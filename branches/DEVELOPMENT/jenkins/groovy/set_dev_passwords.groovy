import groovy.sql.Sql
import java.sql.SQLException
import java.util.regex.Matcher
import java.util.regex.Pattern

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String systemPassword = resolver.resolve("SYSTEM_PASSWORD")
   static String tnsString = resolver.resolve("TNS_STRING")
}

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
        println("[DEBUG]: "+p);
        }
}

void info(String p)
{

    println("[INFO]: "+p)
}

void warning(String p)
{

    println("[WARNING]: "+p)
}

String getUserName(String pKeyString)
{

      // Check which app owns a resp
     def sqlStmt =  "select user_id "+
				    "from dba_users a "+
					"where a.username  = '"+pKeyString+"' "

    bUserExists = false;
	String retVal = ""
    opdb_dbConn.eachRow(sqlStmt)
    {
        bUserExists = true;
		retVal = it.user_id
    }

	return retVal
}

this.class.classLoader.systemClassLoader.addURL(new URL("file:///home/jenkins/mvn/apache-maven-2.2.1/lib/ojdbc6.jar"))

def OPDB_CONNECTION_URL      = "jdbc:oracle:thin:system/"+Globals.systemPassword+"@"+Globals.tnsString
info("Setting up connection to Database") 
opdb_dbConn = Sql.newInstance(OPDB_CONNECTION_URL, "oracle.jdbc.OracleDriver");

def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
opdb_dbConn.eachRow(userDBNameStmt)
{
    info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
}

def thr = Thread.currentThread()
def build = thr?.executable
String pattern = ""
String userName = ""

envVars = build.getEnvVars()

envVars.each {  
  
  pattern = (String)it.key

  pwCount = ( ( pattern =~ /_PASSWORD/).count )

  if ( pwCount > 0 && it.key != "SYSTEM_PASSWORD" ) 
  { 
    
	userName = (it.key =~ /_PASSWORD/).replaceFirst("")    
	String user_id = ""
	user_id = getUserName(userName)
	
	if (bUserExists)
		{
		debug("---> Setting profile")
		opdb_dbConn.execute("ALTER USER "+userName+" PROFILE XXCU_PROFILE")
		
		info ("---> Setting "+userName+" Password")
		opdb_dbConn.execute("ALTER USER "+userName+" IDENTIFIED BY \""+it.value+"\"")
		}
	else 
		{
		warning ("---> User "+userName+" does not exists, skipping.")
		}
        
  }
}

info "Closing connection to database"
opdb_dbConn.close()

return true
