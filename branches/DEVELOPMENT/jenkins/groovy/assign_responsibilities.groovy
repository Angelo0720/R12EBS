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
	if ( Globals.logLevel == "DEBUG" ) 
	{
		println("[assign_responsibilities][DEBUG]: "+p);
	}
}

void info(String p)
{

    println("[assign_responsibilities][INFO]: "+p)
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
	String retVal = ""
    opdb_dbConn.eachRow(sqlStmt)
    {
        bRespHasApp = true;
		retVal = it.APPLICATION_SHORT_NAME
    }

	return retVal
}

void assignResp(String pUserName, String pApp, String pKey)
{
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

      opdb_dbConn.call("{call "+
          "fnd_user_pkg.addresp(username => ? "+
           "                       ,resp_app=> ? "+
           "                       ,resp_key=> ? "+
           "                       ,security_group => 'STANDARD' "+
           "                       ,description => 'Added via Jenkins' "+
           "                       ,end_date => SYSDATE + 10000 "+
           "                       ,start_date => SYSDATE - 1) }",
                                            [ pUserName
                                            , pApp
                                            , pKey
                                            ])

    };

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
		
		if (arr.size() == 3) {
			respAppString = arr[1].toUpperCase()
			respKeyString = arr[2].toUpperCase()
			info ("Processing: "+userNameString+" ("+respAppString+" - "+respKeyString+")")
		} else {
		
			respAppString = getRespApp(respKeyString)
		
			info ("Processing: "+userNameString+" ("+respAppString+" - "+respKeyString+")")
		
		
		}
		    
        
        def userFound = false
        def userFax = "NONE"
        def sqlStmt = "SELECT USER_NAME, FAX FROM FND_USER WHERE USER_NAME = '"+userNameString+"'"
        opdb_dbConn.eachRow(sqlStmt)
        {
            userFound = true
            userFax = it.FAX
        }

        if (! userFax.equals("IT-EXTERNAL SYSADMIN")) {
            if (userFound) {
                // println
                info ("---> Deleting old password history for user "+userNameString)
                opdb_dbConn.execute("delete from fnd_user_preferences where user_name = '"+userNameString+"' and module_name ='PWDVALREUSE'")
                
                info ("---> Calling FND_USER_PKG.UPDATEUSER")
                opdb_dbConn.call("{call fnd_user_pkg.updateuser("+
                                    "  x_user_name => ? "+
                                    ", x_owner => '' "+
                                    ", x_password_date => SYSDATE "+
                                    ", x_password_accesses_left => fnd_user_pkg.null_number "+
                                    ", x_password_lifespan_accesses => fnd_user_pkg.null_number "+
                                    ", x_password_lifespan_days => fnd_user_pkg.null_number "+
                                    ", x_fax                        => 'IT-EXTERNAL SYSADMIN' ) } ",
                                    [ userNameString
                                    ])
                
            } else {
                info ("---> Calling FND_USER_PKG.CREATEUSER")
                passWordString = 'welcome1'
                opdb_dbConn.call("{call "+
                    "fnd_user_pkg.createuser(x_user_name                  => ?                                             "+
                    "                       ,x_owner                      => ''                                            "+
                    "                       ,x_unencrypted_password       => ?                                             "+
                    "                       ,x_session_number             => userenv('sessionid')                          "+
                    "                       ,x_start_date                 => TRUNC(SYSDATE)                                "+
                    "                       ,x_end_date                   => fnd_user_pkg.null_date                        "+
                    "                       ,x_last_logon_date            => fnd_user_pkg.null_date                        "+
                    "                       ,x_description                => ?                                             "+
                    "                       ,x_password_date              => fnd_user_pkg.null_date                        "+
                    "                       ,x_password_accesses_left     => fnd_user_pkg.null_number                      "+
                    "                       ,x_password_lifespan_accesses => fnd_user_pkg.null_number                      "+
                    "                       ,x_password_lifespan_days     => 90                                            "+
                    "                       ,x_employee_id                => NULL                                          "+
                    "                       ,x_email_address              => 'notdefined@xxcu_noemail.org'                 "+
                    "                       ,x_fax                        => 'IT-EXTERNAL SYSADMIN'                                 "+
                    "                       ,x_customer_id                => ''                                            "+
                    "                       ,x_supplier_id                => '') }",
                                            [ userNameString
                                            , passWordString 
                                            , userNameString
                                            ])
                        
                }
    
        } else {
            debug ( "User "+userNameString+" is already existing")
        }

        assignResp(userNameString, respAppString, respKeyString )
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
