// Accenture Configuration Manager - Add Environment
// Copyright Accenture - 2014
// Author: Bjorn Erik Hoel

import groovy.sql.Sql
import java.sql.SQLException

// START JENKINS BLOCK

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static def logLevel = resolver.resolve("LOG_LEVEL")
}

def envNameString  = Globals.resolver.resolve("ENVIRONMENT_NAME")
def envClassString = Globals.resolver.resolve("ENVIRONMENT_CLASS")
def sidString      = Globals.resolver.resolve("ENVIRONMENT_NAME")      
def portNumber     = Globals.resolver.resolve("ENVIRONMENT_PORT")
def passwordString = Globals.resolver.resolve("REMOTE_PASSWORD")
def userNameString = Globals.resolver.resolve("REMOTE_USERNAME")
def hostNameString = Globals.resolver.resolve("REMOTE_HOSTNAME")
def enabledFlag    = Globals.resolver.resolve("ENABLED_FLAG")   
def approvalFlag    = Globals.resolver.resolve("APPROVAL_REQUIRED_FLAG")
def ojdbcLocation    = Globals.resolver.resolve("OJDBC_LOCATION")

def patchMgrUser = Globals.resolver.resolve("ACN_CONFIG_MGR_USER")
def patchMgrPassword = Globals.resolver.resolve("ACN_CONFIG_MGR_PASSWORD")
def patchMgrSID = Globals.resolver.resolve("ACN_CONFIG_MGR_SID")
def patchMgrHost = Globals.resolver.resolve("ACN_CONFIG_MGR_HOST")
def patchMgrPort = Globals.resolver.resolve("ACN_CONFIG_MGR_PORT")

debug ("envNameString    : "+envNameString)
debug ("portNumber       : "+portNumber       )
debug ("passwordString   : <hidden>")
debug ("userNameString   : "+userNameString )
debug ("hostNameString   : "+hostNameString )
debug ("enabledFlag      : "+enabledFlag )
debug ("envClassString   : "+envClassString )
debug ("Loading OJDBC Driver from: "+ojdbcLocation)

this.class.classLoader.systemClassLoader.addURL(new URL("file://"+ojdbcLocation))

// END JENKINS BLOCK

/*
// BEGIN NON JENKINS BLOCK

class Globals 
{
    static String logLevel       = "DEBUG"
}
def envNameString  = "TESTING"
def envClassString = "DEVELOPMENT"
def sidString      = "XE"
def portNumber     = 1521
def passwordString = "apps"
def userNameString = "apps"
def hostNameString = "localhost"
def enabledFlag    = "Y"

// END NON JENKINS BLOCK
*/

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
            def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
            println("[${nowDate}][AddEnvironment][DEBUG]: ${p}")
        }
}

void info(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][AddEnvironment][INFO]: ${p}")
}


if ( enabledFlag == "true" )
{
  enabledFlag = "Y"
} else {
  enabledFlag = "N"
}


if ( approvalFlag == "true" )
{
  approvalFlag = "Y"
} else {
  approvalFlag = "N"
}

def OPDB_CONNECTION_URL      = "jdbc:oracle:thin:"+patchMgrUser+"/"+patchMgrPassword+"@"+patchMgrHost+":"+patchMgrPort+"/"+patchMgrSID
info("Setting up connection to Database ("+patchMgrUser+"@"+patchMgrHost+":"+patchMgrPort+"/"+patchMgrSID+") ")
opdb_dbConn = Sql.newInstance(OPDB_CONNECTION_URL, "oracle.jdbc.OracleDriver");

def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
opdb_dbConn.eachRow(userDBNameStmt)
{
    info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
}

// Get binds in all queries, so we can hardcode literals and make teststeps simpler to code
opdb_dbConn.execute("ALTER SESSION SET CURSOR_SHARING=SIMILAR")

try 
{
    debug("Creating table: ACN_CONFIG_ENVIRONMENTS")
    def CreateTableStmt = "CREATE TABLE ACN_CONFIG_ENVIRONMENTS(ENVIRONMENT_NAME  VARCHAR2(100),ENABLED_FLAG VARCHAR2(1) DEFAULT 'Y' NOT NULL, APPROVAL_REQUIRED_FLAG VARCHAR2(1) DEFAULT 'N' NOT NULL, "+
                          "ENVIRONMENT_CLASS VARCHAR2(100) DEFAULT 'DEVELOPMENT' NOT NULL)"
    opdb_dbConn.execute(CreateTableStmt)
} catch (SQLException se) {
    assert se.message.contains('ORA-00955')
    debug("Table already exists: ACN_CONFIG_ENVIRONMENTS")            
}

try 
{
    debug("Creating table: ACN_CONFIG_ENTITIES")            
    def CreateTableStmt = "CREATE TABLE ACN_CONFIG_ENTITIES("+
"  ENTITY_TYPE   VARCHAR2(100) NOT NULL"+
", ENTITY_NAME   VARCHAR2(100) NOT NULL"+
", ENABLED_FLAG  VARCHAR2(1) DEFAULT 'Y' NOT NULL"+
", OWNER_NAME    VARCHAR2(100) NOT NULL"+
", ENTITY_REFERENCE VARCHAR2(1000)"+
", ENTITY_NOTES VARCHAR2(4000)"+
", NOTIFY_EMAIL VARCHAR2(1000)"+
")"

    opdb_dbConn.execute(CreateTableStmt)
} catch (SQLException se) {
    assert se.message.contains('ORA-00955')
    debug("Table already exists: ACN_CONFIG_ENTITIES")            
}

try 
{
    debug("Creating table: ACN_CONFIG_ENTITIES_HIST")            
    def CreateTableStmt = "CREATE TABLE ACN_CONFIG_ENTITIES_HIST("+
"  ENTITY_ACTION VARCHAR2(100) NOT NULL"+
", ENTITY_DATE   DATE DEFAULT SYSDATE NOT NULL"+
", ENTITY_TYPE   VARCHAR2(100) NOT NULL"+
", ENTITY_NAME   VARCHAR2(100) NOT NULL"+
", ENABLED_FLAG  VARCHAR2(1) DEFAULT 'Y' NOT NULL"+
", OWNER_NAME    VARCHAR2(100) NOT NULL"+
", ENTITY_REFERENCE VARCHAR2(1000)"+
", ENTITY_NOTES VARCHAR2(4000)"+
", NOTIFY_EMAIL VARCHAR2(1000)"+
")"

    opdb_dbConn.execute(CreateTableStmt)
} catch (SQLException se) {
    assert se.message.contains('ORA-00955')
    debug("Table already exists: ACN_CONFIG_ENTITIES_HIST")            
}

try 
{
    debug("Creating table: ACN_CONFIG_ENTITY_ENV_STATUS")
    def CreateTableStmt = "CREATE TABLE ACN_CONFIG_ENTITY_ENV_STATUS"+
"("+
"  ENTITY_TYPE       VARCHAR2(100) NOT NULL"+
", ENTITY_NAME       VARCHAR2(100) NOT NULL"+
", ENVIRONMENT_NAME  VARCHAR2(100) NOT NULL"+
", REQUESTED_BY      VARCHAR2(100) NULL"+
", REQUESTED_DATE    DATE NULL"+
", APPROVED_BY       VARCHAR2(100) NULL"+
", APPROVED_DATE     DATE NULL"+
", DENIED_BY         VARCHAR2(100) NULL"+
", DENIED_DATE       DATE NULL"+
", STATUS            VARCHAR2(100) DEFAULT 'NOT INSTALLED' NOT NULL"+
")"

    opdb_dbConn.execute(CreateTableStmt)
} catch (SQLException se) {
    assert se.message.contains('ORA-00955')
    debug("Table already exists: ACN_CONFIG_ENTITY_ENV_STATUS")            
}

info "Deleting ACN_CONFIG_ENVIRONMENTS entry for "+envNameString
deleteStmt = "DELETE FROM ACN_CONFIG_ENVIRONMENTS WHERE environment_name = '"+envNameString+"'"
opdb_dbConn.execute(deleteStmt)

info "Inserting ACN_CONFIG_ENVIRONMENTS entry for "+envNameString
insertStmt = "INSERT INTO ACN_CONFIG_ENVIRONMENTS(environment_name,enabled_flag,environment_class, approval_required_flag) "+
" VALUES('"+envNameString+"','"+enabledFlag+"','"+envClassString+"','"+approvalFlag+"')"
opdb_dbConn.execute(insertStmt)

info ("Adding environment "+envNameString+" on port "+portNumber+" Connect to: "+userNameString+" On Host: "+hostNameString)

try 
{
    def DBLinkStmt = "DROP DATABASE LINK "+envNameString
    opdb_dbConn.execute(DBLinkStmt)
} catch (SQLException se) {
    assert se.message.contains('ORA-02024')
    debug("No database link to drop with name: "+envNameString)            
}

try 
{
    info "Creating database link"
    def DBLinkStmt = "CREATE DATABASE LINK "+envNameString+" CONNECT TO "+userNameString+" IDENTIFIED BY "+passwordString+
        " USING '(description=(address=(protocol=TCP)(host="+hostNameString+")(port="+portNumber+"))(connect_data=(service_name="+sidString+")))'"
    opdb_dbConn.execute(DBLinkStmt)
        
} catch (SQLException se) {
    assert se.message.contains('ORA-02011')
    debug("Database Link already exists: "+envNameString)            
}

userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME@"+envNameString
opdb_dbConn.eachRow(userDBNameStmt)
{
    info("DB Link connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
}

info "Closing connection to database"
opdb_dbConn.close()

return true