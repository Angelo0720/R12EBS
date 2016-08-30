import groovy.sql.Sql
import java.sql.SQLException

class Globals 
{
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String appsPassword = resolver.resolve("APPS_PASSWORD")
   static String tnsString = resolver.resolve("TNS_STRING")
   static String userListFile = resolver.resolve("USER_LIST_FILE")   
   static String ojdbcLocation = resolver.resolve("OJDBC_LOCATION")
}

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
            def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
            println("[${nowDate}][assign_responsibilities][DEBUG]: ${p}")
        }
}

void info(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][assign_responsibilities][INFO]: ${p}")
}

void error(String p)
{

    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][assign_responsibilities][ERROR]: ${p}")
}



String getRespApp(String pKeyString)
{

      // Check which app owns a resp
     def sqlStmt =  "select b.application_short_name "+
				    "from fnd_Responsibility a "+
					", fnd_application b "+
					"where responsibility_key = '"+pKeyString+"' "+
					"and a.application_id = b.application_id "

    bRespHasApp = false;
	String retVal = "<NULL>"
    opdb_dbConn.eachRow(sqlStmt)
    {
        bRespHasApp = true;
		retVal = it.APPLICATION_SHORT_NAME
    }

	return retVal
}

void assignResp(String pUserName, String pApp, String pKey)
{

	def endDateStr = "fnd_user_pkg.null_date"
	
	if ( pKey.equals("SAMPLEOPM_USER") || 
		 pKey.equals("SAMPLE_OPM_INQUIRY") ||
		 pKey.equals("SAMPLE_WHS_MNGR") ||
		 pKey.equals("SAMPLE_QA_USER") ||
		 pKey.equals("SAMPLE_QC_USER") ||
		 pKey.equals("SAMPLE_SCM_OPM_INQUIRY") ||
		 pKey.equals("SAMPLE_SCM_OPM_USER") ||
		 pKey.equals("SAMPLE_SCM_PLANNING") ||
		 pKey.equals("SAMPLE_APCC_DASHBOARD") ||
		 pKey.equals("SAMPLE_OPM_ADMN") ||
		 pKey.equals("SAMPLE_OPM_FINANCIAL_USER") ||
		 pKey.equals("SAMPLE_OPM_FINANCIAL_INQ_USER") ||
		 pKey.equals("SAMPLE_RS_USER") ||
		 pKey.equals("SAMPLE_RS_INQ") 
		 )
	{
		endDateStr = "TRUNC(SYSDATE)"	
	};


	
      // Check if user exists
	def sqlStmt = "select 1 "+
		"from fnd_user a "+
		"where a.user_name = '"+pUserName+"' "

    bUserExists = false;

    opdb_dbConn.eachRow(sqlStmt)
    {
        bUserExists = true;
    }

    if ( bUserExists ) {

		  // Check if user already has responsibility
		 def assignStmt = "select 1 "+
			"from fnd_user_resp_groups_all a "+
			", fnd_user b "+
			", fnd_responsibility c "+
			", fnd_application d "+
			"where b.user_id = a.user_id "+
			"and b.user_name = '"+pUserName+"' "+
			"and c.application_id = a.responsibility_application_id "+
			"and c.responsibility_id = a.responsibility_id "+
			"and c.responsibility_key = '"+pKey+"' "+
			"and d.application_id = c.application_id "+
			"and d.application_short_name = '"+pApp+"' "

		bUserHasAssignment = false;

		opdb_dbConn.eachRow(assignStmt)
		{
			bUserHasAssignment = true;
		}

		if ( ! bUserHasAssignment ) {

		  info ("Assigning user "+pApp+"."+pKey)
		  try {
			  opdb_dbConn.call("{call "+
				  "fnd_user_pkg.addresp(username => ? "+
				   "                       ,resp_app=> ? "+
				   "                       ,resp_key=> ? "+
				   "                       ,security_group => 'STANDARD' "+
				   "                       ,description => 'Added via Jenkins' "+
				   "                       ,end_date => "+endDateStr+
				   "                       ,start_date => SYSDATE - 1) }",
													[ pUserName
													, pApp
													, pKey
													])
			} catch (SQLException se) {

				 error "Unable to assign: "+pUserName+" with: "+pKey
				 error se.message
			}

		}
		
	} else {
		error "User "+pUserName+" does not exist! Skipping."	
	}
}

this.class.classLoader.systemClassLoader.addURL(new URL("file://"+Globals.ojdbcLocation))

def OPDB_CONNECTION_URL      = "jdbc:oracle:thin:apps/"+Globals.appsPassword+"@"+Globals.tnsString
info("Setting up connection to Database") 
opdb_dbConn = Sql.newInstance(OPDB_CONNECTION_URL, "oracle.jdbc.OracleDriver");

def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
opdb_dbConn.eachRow(userDBNameStmt)
{
    info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
}

// Get binds in all queries, so we can hardcode literals and make teststeps simpler to code
opdb_dbConn.execute("ALTER SESSION SET CURSOR_SHARING=SIMILAR")

fileLines = new File(Globals.userListFile).readLines()

fileLines.each {
	try {
		lineString = it
		debug ("Line: "+lineString)
			
		if (! lineString[0].equals("#")) {
			arr = lineString.split(":")
			
			userNameString = arr[0].toUpperCase()
			respAppString = ""
			respKeyString = arr[1].toUpperCase()
			bProcess = false;
			
			if (arr.size() == 3) {
				respAppString = arr[1].toUpperCase()
				respKeyString = arr[2].toUpperCase()
				info ("Processing: "+userNameString+" ("+respAppString+" - "+respKeyString+")")
				bProcess = true;
			} else {
			
				respAppString = getRespApp(respKeyString)
			
				if (respAppString == "<NULL>")
				{
					error "Responsibility "+respKeyString+" does not exist! Skipping."
				}
				else
				{
					info ("Processing: "+userNameString+" ("+respAppString+" - "+respKeyString+")")
					bProcess = true;
				}		
			}
			if ( bProcess )
			{
				assignResp(userNameString, respAppString, respKeyString )
			}
		}
    }
    catch (e) { 
       println e
       error "Skipping"
    }
	
}

info "Closing connection to database"
opdb_dbConn.close()

return true
