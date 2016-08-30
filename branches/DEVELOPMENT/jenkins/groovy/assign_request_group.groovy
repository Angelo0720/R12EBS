import groovy.sql.Sql
import java.sql.SQLException

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String appsPassword = resolver.resolve("APPS_PASSWORD")
   static String tnsString = resolver.resolve("TNS_STRING")

}

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
            println("[Assign XXCU Request Group][DEBUG]: "+p);
        }
}

void info(String p)
{
    println("[setupSysadmins][INFO]: "+p)
}

void assignReqGrpSet(String pSetName, String pApp)
{

      // Check if request group already has request set
     def assignStmt = "select 1 "+
                "from fnd_request_group_units "+
                "where request_group_id = (select request_group_id from fnd_request_groups where request_group_name = 'XXCU_Request_Group') "+
                "and request_unit_id = (select request_set_id from fnd_request_sets where request_set_name = '"+pSetName+"') "

     bGroupHasAssignment = false;

     opdb_dbConn.eachRow(assignStmt)
    {
        bGroupHasAssignment = true;
    }

    if ( ! bGroupHasAssignment ) {

        info ("Assigning request group "+pApp+"."+pSetName)

        opdb_dbConn.call("{call "+
               "FND_SET.add_set_to_group( "+
               "     REQUEST_SET  => ? "+
               "    ,SET_APPLICATION => ? "+
               "    ,REQUEST_GROUP       => 'XXCU_Request_Group' "+
               "    ,GROUP_APPLICATION   =>'XXCU' "+
               "    ) }", 
               [ pSetName, pApp ])
    }

}


void assignReqGrp(String pConcName, String pApp)
{

      // Check if request group already has program
     def assignStmt = "select 1 "+
                "from fnd_request_group_units "+
                "where request_group_id = (select request_group_id from fnd_request_groups where request_group_name = 'XXCU_Request_Group') "+
                "and request_unit_id = (select concurrent_program_id from fnd_concurrent_programs where concurrent_program_name = '"+pConcName+"') "

     bGroupHasAssignment = false;

     opdb_dbConn.eachRow(assignStmt)
    {
        bGroupHasAssignment = true;
    }

    if ( ! bGroupHasAssignment ) {

        info ("Assigning request group "+pApp+"."+pConcName)

        opdb_dbConn.call("{call "+
               "FND_PROGRAM.add_to_group( "+
               "     PROGRAM_SHORT_NAME  => ? "+
               "    ,PROGRAM_APPLICATION => ? "+
               "    ,REQUEST_GROUP       => 'XXCU_Request_Group' "+
               "    ,GROUP_APPLICATION   =>'XXCU' "+
               "    ) }", 
               [ pConcName, pApp ])
    }

}

this.class.classLoader.systemClassLoader.addURL(new URL("file:///home/jenkins/mvn/apache-maven-2.2.1/lib/ojdbc6.jar"))

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


def sqlStmt = "select (select application_short_name from fnd_application where application_id = a.application_id) as conc_app_name, concurrent_program_name "+
" from fnd_concurrent_programs a "+
" where concurrent_program_name like 'XX%' "+
" and concurrent_program_name not like 'XXCU%CNV0%' "

opdb_dbConn.eachRow(sqlStmt)
{
    info("Processing "+it.conc_app_name+"."+it.concurrent_program_name)
    assignReqGrp(it.concurrent_program_name, it.conc_app_name )
}

sqlStmt = "select (select application_short_name from fnd_application where application_id = a.application_id) as app_name "+
", request_set_name "+
"from fnd_request_sets a "+
"where request_set_name like 'XXCU%' " 

opdb_dbConn.eachRow(sqlStmt)
{
    info("Processing "+it.app_name+"."+it.request_set_name)
    assignReqGrpSet(it.request_set_name, it.app_name )
}

info "Closing connection to database"
opdb_dbConn.close()

return true
