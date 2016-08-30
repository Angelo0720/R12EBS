// Accenture Configuration Manager - Show Report
// Copyright Accenture - 2014
// Author: Bjorn Erik Hoel

import groovy.sql.Sql
import java.sql.SQLException

import javax.mail.internet.*;
import javax.mail.*
import javax.activation.*

// START JENKINS BLOCK

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
}

def patchMgrUser = Globals.resolver.resolve("ACN_CONFIG_MGR_USER")
def patchMgrPassword = Globals.resolver.resolve("ACN_CONFIG_MGR_PASSWORD")
def patchMgrSID = Globals.resolver.resolve("ACN_CONFIG_MGR_SID")
def patchMgrHost = Globals.resolver.resolve("ACN_CONFIG_MGR_HOST")
def patchMgrPort = Globals.resolver.resolve("ACN_CONFIG_MGR_PORT")

def ojdbcLocation    = Globals.resolver.resolve("OJDBC_LOCATION")
debug ("Loading OJDBC Driver from: "+ojdbcLocation)
this.class.classLoader.systemClassLoader.addURL(new URL("file://"+ojdbcLocation))

// END JENKINS BLOCK

void debug(String p)
{
        if ( Globals.logLevel == "DEBUG" ) {
            def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
            println("[${nowDate}][showReport][DEBUG]: ${p}")
        }
}

void info(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][showReport][INFO]: ${p}")
}

void error(String p)
{

    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][showReport][ERROR]: ${p}")
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

// ##########################
// #### END COMMON BLOCK ####
// ##########################

debug ("Processing environments")
def sqlStatement = "SELECT ENVIRONMENT_NAME FROM ACN_CONFIG_ENVIRONMENTS WHERE ENABLED_FLAG = 'Y'"

def sqlEnv = ""
def envName = ""
def entityName = ""
def entityStatus = ""

opdb_dbConn.eachRow(sqlStatement)
{
    envName = it.ENVIRONMENT_NAME
    debug("Environment: "+envName)

    try 
   {
        sqlEnv = "SELECT GLOBAL_NAME FROM GLOBAL_NAME@"+envName
        opdb_dbConn.eachRow(sqlEnv)
        {
            debug("Remote DB Link: "+it.GLOBAL_NAME)
        }
    
        debug "Processing PATCH entities"
        sqlEntities = "SELECT * FROM ACN_CONFIG_ENTITIES WHERE ENTITY_TYPE = 'PATCH' AND ENABLED_FLAG = 'Y'"
        opdb_dbConn.eachRow(sqlEntities)
        {
            entityName = it.ENTITY_NAME
            notifyEmailString = it.NOTIFY_EMAIL
            debug("Entity: "+entityName+" Notify: "+notifyEmailString)
    
            sqlEnv = "SELECT NVL(TO_CHAR(MAX(LAST_UPDATE_DATE),'YYYY-MON-DD'),'NOT APPLIED') as entity_status FROM AD_APPLIED_PATCHES@"+envName+" WHERE patch_name = '"+entityName+"'"
            opdb_dbConn.eachRow(sqlEnv)
            {
                entityStatus = it.entity_status
                debug(envName+": "+entityName+" - "+entityStatus)
            }
    
            // If status table already contains an installed entry for it, we are done
            // Also requires new status to be installed, since a clone can alter statuses
            sqlStmt = "SELECT COUNT(1) AS COUNTER FROM ACN_CONFIG_ENTITY_ENV_STATUS "+
                        "WHERE ENTITY_TYPE = 'PATCH' AND ENTITY_NAME = '"+entityName+"'"+
                        "AND ENVIRONMENT_NAME = '"+envName+"' "+
                        "AND STATUS LIKE '____-___-__'"
                        "AND '"+entityStatus+"' LIKE '____-___-__'"
            opdb_dbConn.eachRow(sqlStmt)
            {
                alreadyUpdated = it.COUNTER
            }
    
            if (alreadyUpdated == 0 ) 
            {
                sqlEnvStatus = "UPDATE ACN_CONFIG_ENTITY_ENV_STATUS SET STATUS = '"+entityStatus+"' "+
                                "WHERE ENTITY_TYPE = 'PATCH' AND ENTITY_NAME = '"+entityName+"'"+
                                "AND ENVIRONMENT_NAME = '"+envName+"'"
                            
                opdb_dbConn.execute(sqlEnvStatus)
                if ( opdb_dbConn.updateCount == 0 )
                {
                    debug "No existing entry found. Creating it"
                    sqlInsert = "INSERT INTO ACN_CONFIG_ENTITY_ENV_STATUS(ENVIRONMENT_NAME, ENTITY_TYPE, ENTITY_NAME, STATUS) "+
                                "VALUES('"+envName+"','PATCH','"+entityName+"','"+entityStatus+"')"
                    opdb_dbConn.execute(sqlInsert)
                } else {
                    debug "Update successful"
                }
                
                if ( entityStatus != "NOT APPLIED" && entityStatus != "PENDING INSTALL" && entityStatus != "PENDING APPROVAL" )
                {
                    // EMAIL BLOCK BEGIN
                    info "SENDING EMAIL FOR "+envName+" - "+entityName+" "+entityStatus+" to "+notifyEmailString
                    try {
						//###################
						//## EMAIL SECTION ##
						//###################
						
						def message = ""
						def subject = ""
						def toAddress = ""
						
						subject = "Patch "+entityName+" installed in "+envName
						message = "The following patch has been installed in "+envName+" on "+entityStatus+": "+entityName+"\n\n"+
								  "- Jenkins"
						
						toAddress = notifyEmailString 
						
						fromAddress = "R12DBAGrp@example.com"
						host = "smtp.example.com"
						port = "25"
						
						Properties mprops = new Properties();
						mprops.setProperty("mail.transport.protocol","smtp");
						mprops.setProperty("mail.host",host);
						mprops.setProperty("mail.smtp.port",port);
						
						Session lSession = Session.getDefaultInstance(mprops,null);
						MimeMessage msg = new MimeMessage(lSession);
						
						//tokenize out the recipients in case they came in as a list
						StringTokenizer tok = new StringTokenizer(toAddress,";");
						ArrayList emailTos = new ArrayList();
						
						while(tok.hasMoreElements())
						{
							recipientString=tok.nextElement().toString()
							emailTos.add(new InternetAddress(recipientString));
							info("Email sent to: "+recipientString)
						}
						
						InternetAddress[] to = new InternetAddress[emailTos.size()];
						to = (InternetAddress[]) emailTos.toArray(to);
						msg.setRecipients(MimeMessage.RecipientType.TO,to);
						InternetAddress fromAddr = new InternetAddress(fromAddress);
						msg.setFrom(fromAddr);
						msg.setFrom(new InternetAddress(fromAddress));
						msg.setSubject(subject);
						msg.setText(message)
						
						Transport transporter = lSession.getTransport("smtp");
						transporter.connect();
						transporter.send(msg);
						
						//#######################
						//## END EMAIL SECTION ##
						//#######################
					} catch (ex) {
						error "Problem seding email"
					}
                    // EMAIL BLOCK END
                } else {
                    debug "Not sending email, not applied yet "+envName+" - "+entityName+" "+entityStatus
                }
            } else {
                debug "Already installed, no update required"
            }
        }
        
    } catch (SQLException se) {

             error "Unable to extract from "+envName
             error se.message
    }

}

debug "Marking pending approval entries"
sqlEnvStatus = "UPDATE ACN_CONFIG_ENTITY_ENV_STATUS SET STATUS = 'PENDING APPROVAL' "+
"WHERE STATUS IN ( 'NOT APPLIED' ) AND REQUESTED_BY IS NOT NULL AND APPROVED_BY IS NULL"

opdb_dbConn.execute(sqlEnvStatus)

debug "Marking pending install entries"
sqlEnvStatus = "UPDATE ACN_CONFIG_ENTITY_ENV_STATUS SET STATUS = 'PENDING INSTALL' "+
"WHERE STATUS IN ( 'NOT APPLIED', 'PENDING APPROVAL') AND REQUESTED_BY IS NOT NULL AND (APPROVED_BY IS NOT NULL "+
" OR ENVIRONMENT_NAME IN (SELECT ENVIRONMENT_NAME FROM ACN_CONFIG_ENVIRONMENTS WHERE APPROVAL_REQUIRED_FLAG = 'N'))"
opdb_dbConn.execute(sqlEnvStatus)

debug "Marking denied entries"
sqlEnvStatus = "UPDATE ACN_CONFIG_ENTITY_ENV_STATUS SET STATUS = 'DO NOT INSTALL' "+
"WHERE STATUS IN  ( 'NOT APPLIED', 'PENDING APPROVAL', 'DBA INSTALL') AND DENIED_BY IS NOT NULL"

opdb_dbConn.execute(sqlEnvStatus)



/* ################
 * PRODUCING OUTPUT
 * ################*/

debug ("Fetching banner/header information")
sqlBannerStmt = "select RPAD('Patch #',(select max(length(entity_name)) as LENGTH from acn_config_entity_env_status "+
"WHERE entity_name IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y')),' ') AS HEADING_TEXT "+
", RPAD('-',(select max(length(entity_name)) as LENGTH from acn_config_entity_env_status "+
"WHERE entity_name IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y')),'-') AS ENTITY_BANNER"+
", RPAD('-',(select max(length(environment_name)) as LENGTH from acn_config_entity_env_status "+
"WHERE entity_name IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y')),'-') AS ENVIRONMENT_BANNER "+
"from dual"

def entityLength = 0

opdb_dbConn.eachRow(sqlBannerStmt)
{
    headingText = "| "+it.HEADING_TEXT+" |"
        bannerText  = "--"+it.ENTITY_BANNER+"--" 
        entityLength = it.ENTITY_BANNER.size()

}
debug ("Processing environments, entityLength is "+entityLength )
sqlStatement = "SELECT RPAD(ENVIRONMENT_NAME,((SELECT MAX(LENGTH(STATUS)) FROM ACN_CONFIG_ENTITY_ENV_STATUS WHERE ENVIRONMENT_NAME = A.ENVIRONMENT_NAME "+
"AND entity_name IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y'))),' ') AS "+ "ENVIRONMENT_NAME_BANNER "+
", ENVIRONMENT_NAME "+
", RPAD('-',((SELECT MAX(LENGTH(STATUS)) FROM ACN_CONFIG_ENTITY_ENV_STATUS WHERE ENVIRONMENT_NAME = A.ENVIRONMENT_NAME "+
"AND entity_name IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y'))),'-') AS STATUS_BANNER "+
"FROM ACN_CONFIG_ENVIRONMENTS A "+
"WHERE ENABLED_FLAG = 'Y' ORDER BY DECODE(ENVIRONMENT_CLASS,'DEVELOPMENT',10,'QA',50,'PROD',100), ENVIRONMENT_NAME"


opdb_dbConn.eachRow(sqlStatement)
{
    bannerText = bannerText + "-"+it.status_banner+"-|"
    headingText = headingText + " "+it.ENVIRONMENT_NAME_BANNER+" |"
}

debug ("Fetching banner trailer")
sqlBannerStmt = "select RPAD('-',(select max(length(entity_reference)) as LENGTH from acn_config_entities WHERE ENABLED_FLAG = 'Y'),'-') AS REFERENCE_BANNER"+
", RPAD('Reference',(select max(length(entity_reference)) as LENGTH from ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y'),' ') AS HEADING_TEXT "+
"from dual"

opdb_dbConn.eachRow(sqlBannerStmt)
{
    headingText = headingText + " "+it.HEADING_TEXT+" |"
        bannerText  = bannerText  + "-"+it.REFERENCE_BANNER+"-|" 
}

debug ("Fetching owner column")
sqlBannerStmt = "select RPAD('-',(select max(length(notify_email)) as LENGTH from acn_config_entities WHERE ENABLED_FLAG = 'Y'),'-') AS OWNER_BANNER"+
", RPAD('Owner',(select max(length(notify_email)) as LENGTH from ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y'),' ') AS HEADING_TEXT "+
"from dual"

opdb_dbConn.eachRow(sqlBannerStmt)
{
    headingText = headingText + " "+it.HEADING_TEXT+" |"
        bannerText  = bannerText  + "-"+it.OWNER_BANNER+"-|" 
}


println bannerText
println headingText
println bannerText

outputText = ""

debug "Processing PATCH entities"
sqlEntities = "SELECT ENTITY_NAME, RPAD(ENTITY_NAME,"+entityLength+",' ') AS ENTITY_FILLER FROM ACN_CONFIG_ENTITIES WHERE ENTITY_TYPE = 'PATCH' AND ENABLED_FLAG = 'Y' ORDER BY ENTITY_NAME"
opdb_dbConn.eachRow(sqlEntities)
{
    entityName = it.ENTITY_NAME
    outputText = "| "+it.ENTITY_FILLER+" |"

    sqlReport =    "select a.environment_name, RPAD(a.status,(SELECT MAX(LENGTH(STATUS)) FROM ACN_CONFIG_ENTITY_ENV_STATUS "+
    "WHERE ENVIRONMENT_NAME = A.ENVIRONMENT_NAME and ENTITY_NAME IN (SELECT ENTITY_NAME FROM ACN_CONFIG_ENTITIES WHERE ENABLED_FLAG = 'Y')),' ') as status "+
                "from acn_config_entity_env_Status a "+
                ", acn_config_environments b "+
                ", acn_config_entities c "+
                "where a.environment_name = b.environment_name "+
                "and b.enabled_flag = 'Y' "+
                "and a.entity_type = c.entity_type "+
                "and a.entity_name = c.entity_name "+
                "and c.enabled_flag = 'Y' "+
                "and a.entity_type = 'PATCH' "+
                "and a.entity_name = '"+entityName+"'"+
                "order by DECODE(ENVIRONMENT_CLASS,'DEVELOPMENT',10,'QA',50,'PROD',100), environment_name"
        debug "Issuing: "+sqlReport

    opdb_dbConn.eachRow(sqlReport)
    {
        envName = it.ENVIRONMENT_NAME
        status = it.STATUS
        outputText = outputText + " "+status+" |"
    }

    debug ("Fetching entity trailer")
    sqlBannerStmt = "select RPAD(NVL(entity_reference,'Unknown'),(select max(length(entity_reference)) as LENGTH from "+
                "acn_config_entities WHERE ENTITY_TYPE = 'PATCH' AND ENABLED_FLAG = 'Y'),' ') AS ENTITY_TEXT "+
    "from acn_config_entities WHERE entity_name = '"+entityName+"' AND ENTITY_TYPE = 'PATCH'"

    opdb_dbConn.eachRow(sqlBannerStmt)
    {
        outputText = outputText + " "+it.ENTITY_TEXT+" |"
    }

    debug ("Fetching owner column")
    sqlBannerStmt = "select RPAD(NVL(notify_email,'Unknown'),(select max(length(notify_email)) as LENGTH from acn_config_entities "+
                "WHERE ENTITY_TYPE = 'PATCH' AND ENABLED_FLAG = 'Y'),' ') AS ENTITY_TEXT "+
    "from acn_config_entities WHERE entity_name = '"+entityName+"' AND ENTITY_TYPE = 'PATCH'"

    opdb_dbConn.eachRow(sqlBannerStmt)
    {
        outputText = outputText + " "+it.ENTITY_TEXT+" |"
    }


    println outputText    
        println bannerText

}

debug ("Closing database connection")
opdb_dbConn.close()

info ("Completed")

return true
