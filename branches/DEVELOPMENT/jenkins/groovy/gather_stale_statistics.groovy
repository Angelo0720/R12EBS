import groovy.sql.Sql
import java.sql.SQLException

class Globals 
{
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String scriptName = "gather_stale_statistics"
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String appsPassword = resolver.resolve("APPS_PASSWORD")
   static String tnsString = resolver.resolve("TNS_STRING")
   static String ojdbcLocation = resolver.resolve("OJDBC_LOCATION")
}

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
            def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
            println("[${nowDate}]["+Globals.scriptName+"][DEBUG]: ${p}")
        }
}

void info(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}]["+Globals.scriptName+"][INFO]: ${p}")
}

void error(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}]["+Globals.scriptName+"][ERROR]: ${p}")
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
	
// List Schemas that have stale stats
def sqlStmt = "select owner,count(1) " +
"from dba_tab_modifications a "+
", dba_tables b "+
"where a.table_owner = b.owner "+
"and a.table_name = b.table_name "+
"and greatest( ((a.inserts + a.updates - a.deletes) - num_rows),0) > (num_rows / 10) "+
"and table_owner not in ('SYS') "+
"and b.table_name not like 'MLOG\$%' "+
"and b.table_name not like 'DR\$%' "+
"group by owner "+
"order by owner"

bSuccess = true

opdb_dbConn.eachRow(sqlStmt)
{	
	sOwner = it.OWNER

	info ("Generating SCHEMA stats for user "+sOwner)
	try {
	  opdb_dbConn.call("{call "+
		  "dbms_stats.gather_schema_stats(ownname => ? "+
		  "                       ,options => 'GATHER AUTO' ) } ",
											[ sOwner ])

	} catch (SQLException se) {
		 error "Unable to process: "+sOwner
		 error se.message
		 bSuccess = false
	}

}


info "Closing connection to database"
opdb_dbConn.close()

return bSuccess
