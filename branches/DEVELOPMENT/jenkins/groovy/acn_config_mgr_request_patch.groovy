// Accenture Configuration Manager - Request Patch
// Copyright Accenture - 2014
// Author: Bjorn Erik Hoel
import groovy.sql.Sql
import java.sql.SQLException

String approvalRequiredFlag = "N"

// START JENKINS BLOCK

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
}

def envNameString         = Globals.resolver.resolve("REQUEST_TO_ENVIRONMENT")

def enabledFlag           = Globals.resolver.resolve("ENABLED_FLAG")   
def entityTypeString      = Globals.resolver.resolve("ENTITY_TYPE")
def entityFullString      = Globals.resolver.resolve("ENTITY_NAME")
def userNameString        = Globals.resolver.resolve("BUILD_USER_ID")
def entityReferenceString = Globals.resolver.resolve("ENTITY_REFERENCE")
def entityNoteString      = Globals.resolver.resolve("ENTITY_NOTE")

def installerEmailString = Globals.resolver.resolve("INSTALLER_EMAIL")
def approverEmailString = Globals.resolver.resolve("APPROVER_EMAIL")
def notifyEmailString = Globals.resolver.resolve("NOTIFY_EMAIL")

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
            println("[${nowDate}][requestPatch][DEBUG]: ${p}")
        }
}

void info(String p)
{
    def nowDate = new Date().format("yyyy-MM-dd HH:mm:ss z")
    println("[${nowDate}][requestPatch][INFO]: ${p}")
}


if ( enabledFlag == "true" )
{
  enabledFlag = "Y"
} else {
  enabledFlag = "N"
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

assert entityReferenceString != null, 'Reference must be set'
assert entityFullString != null, 'Entity name must be set'

entityReferenceString = entityReferenceString.trim()
entityFullString = entityFullString.trim()

info ("Adding "+entityTypeString+" request to "+envNameString+
    "\nEntity: "+entityFullString+
    "\nReference: "+entityReferenceString+
    "\nNote: "+entityNoteString+
    "\nEnabledFlag: "+enabledFlag)
def sqlStmt = ""

info "Verifying numeric only PATCH number"
sqlStmt = "SELECT trim(regexp_replace('"+entityFullString+"','[A-Z]|[a-z]|[:delimiter:]','')) AS REAL_PATCH_NO FROM DUAL"
debug sqlStmt
opdb_dbConn.eachRow(sqlStmt)
{
    testString = it.REAL_PATCH_NO
    assert testString == entityFullString, 'Alphanumeric characters or delimiters are not allowed. Numeric only'
}

auditUserString = userNameString

try {
	sqlStmt = "SELECT MAX(USER_NAME||' - '||DESCRIPTION||' ('||email_Address||')') as AUDIT_WHO "+
	"FROM FND_USER@"+envNameString +" "+
	"WHERE USER_NAME = UPPER('"+userNameString+"') OR USER_NAME = UPPER('CONT-'||'"+userNameString+"')"
	
	debug sqlStmt
	def auditUserString = ""

	opdb_dbConn.eachRow(sqlStmt)
	{
		auditUserString = it.AUDIT_WHO
	}
} catch (ex) {
	info "Unable to connect to FND_USER@"+envNameString+" - Defaulting user"
}

if (auditUserString)
{
    userNameString = auditUserString
    info "Real User Name of requestor: "+userNameString
}


sqlStmt = "DELETE FROM ACN_CONFIG_ENTITIES WHERE ENTITY_TYPE = '"+entityTypeString+"' AND ENTITY_NAME = '"+entityFullString+"'"
debug sqlStmt
opdb_dbConn.execute(sqlStmt)

sqlStmt = "INSERT INTO ACN_CONFIG_ENTITIES(ENTITY_TYPE, ENTITY_NAME, ENABLED_FLAG, OWNER_NAME, ENTITY_REFERENCE, ENTITY_NOTES,NOTIFY_EMAIL) VALUES ('"+
          entityTypeString+"','"+
          entityFullString+"','"+
          enabledFlag+"','"+
          userNameString+"','"+
          entityReferenceString+"','"+
          entityNoteString+"','"+
          notifyEmailString+
          "')"

debug sqlStmt
opdb_dbConn.execute(sqlStmt)
          
sqlStmt = "INSERT INTO ACN_CONFIG_ENTITIES_HIST(ENTITY_ACTION, ENTITY_DATE, "+
              "ENTITY_TYPE, ENTITY_NAME, ENABLED_FLAG, OWNER_NAME, ENTITY_REFERENCE, ENTITY_NOTES,NOTIFY_EMAIL) VALUES ('"+
              "REQUEST',SYSDATE,'"+
              entityTypeString+"','"+
              entityFullString+"','"+
              enabledFlag+"','"+
              userNameString+"','"+
              entityReferenceString+"','"+
              entityNoteString+"',REPLACE('"+
              notifyEmailString+"',';') "+
              ")"

debug sqlStmt
opdb_dbConn.execute(sqlStmt)


sqlStmt = "UPDATE ACN_CONFIG_ENTITY_ENV_STATUS SET REQUESTED_BY = '"+userNameString+"', REQUESTED_DATE = LEAST(NVL(REQUESTED_DATE,SYSDATE),SYSDATE) "+
"WHERE ENTITY_TYPE = '"+entityTypeString+"' AND ENTITY_NAME = '"+entityFullString+"' "+
"AND ENVIRONMENT_NAME = '"+envNameString+"'"

debug sqlStmt
opdb_dbConn.execute(sqlStmt)
if ( opdb_dbConn.updateCount == 0 )
{
    info "Making ACN_CONFIG_ENTITY_ENV_STATUS entry for "+envNameString
    sqlStmt = "INSERT INTO ACN_CONFIG_ENTITY_ENV_STATUS(ENVIRONMENT_NAME, ENTITY_TYPE, ENTITY_NAME, STATUS, REQUESTED_BY, REQUESTED_DATE) "+
    "VALUES('"+envNameString+"','"+entityTypeString+"','"+entityFullString+"','REQUESTED','"+userNameString+"',SYSDATE)"
    debug sqlStmt
    opdb_dbConn.execute(sqlStmt)        
}

debug ("Determine Approval_Required_Flag for target environment")
sqlStmt = "SELECT APPROVAL_REQUIRED_FLAG FROM ACN_CONFIG_ENVIRONMENTS WHERE ENVIRONMENT_NAME = '"+envNameString+"'"
opdb_dbConn.eachRow(sqlStmt)
{
  approvalRequiredFlag = it.APPROVAL_REQUIRED_FLAG
  info "Approval required: "+approvalRequiredFlag
}

debug "Closing connection to database"
opdb_dbConn.close()

import javax.mail.internet.*;
import javax.mail.*
import javax.activation.*


//################
//## EMAIL SECTION ##
//################

if (enabledFlag == "Y" )
{

    def message = ""
    def subject = ""
    def toAddress = ""
    
    if ( approvalRequiredFlag == "Y")
    {
        subject = "Approval Required for "+entityTypeString  +": "+entityFullString+" in "+envNameString
        message = "Approval Required for "+entityTypeString  +": "+entityFullString+" in "+envNameString+"\n"+
              "Requested by: "+userNameString+"\n"+
              "Reference: "+entityReferenceString+"\n\n"+
              "Notes: "+entityNoteString+"\n\n"+
			  "Please go to: https://jenkins.example.com:8080/job/Accenture%20Patch%20Tracker%20-%20Approve%20Patch/build?delay=0sec to approve it\n\n"+
              "- Jenkins"
    
        toAddress = approverEmailString 
    
    } else {
    
        subject = "Installation Requested for "+entityTypeString  +": "+entityFullString+" in "+envNameString
        message = "Installation Requested for "+entityTypeString  +": "+entityFullString+" in "+envNameString+"\n"+
              "Requested by: "+userNameString+"\n"+
              "Reference: "+entityReferenceString+"\n\n"+
              "Notes: "+entityNoteString+"\n\n"+
              "- Jenkins"
    
        toAddress = installerEmailString 
    
    }
    
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


}

//#######################
//## END EMAIL SECTION ##
//#######################

info ("Success")

return true