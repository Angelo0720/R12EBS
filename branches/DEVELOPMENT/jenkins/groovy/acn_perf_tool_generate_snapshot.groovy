import groovy.sql.Sql
import java.sql.SQLException

errorLoc = ""

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String workspace = build.workspace.toString()
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String dictReadUser = resolver.resolve("DICTIONARY_READ_USER")
   static String dictReadPassword = resolver.resolve("DICTIONARY_READ_PASSWORD")
   static String opDBPassword = resolver.resolve("OPDB_PASSWORD")
   static String dataFileName = resolver.resolve("DATA_FILE")
}

public void writeToFile(def directory, def fileName, def extension, def infoList) {
    File file = new File("$directory/$fileName$extension")
	debug "Deleting, then writing "+(infoList.size())+" lines to: "+fileName+extension

	if ( file.exists() ) {
		file.delete()
	}
    infoList.each {
        file << ("${it}\n")
    }
}


void debug(String p)
{
		errorLoc = p
        if ( Globals.logLevel == "DEBUG" ) 
		{
			def today = new Date()
			println("["+(today)+"][DEBUG]: "+p);
        }
}

void info(String p)
{
	def today = new Date()
	println("["+(today)+"][INFO]: "+p);
}

void error(String p)
{
	def today = new Date()
	println("["+(today)+"][ERROR]: (Location: "+errorLoc+") "+p)
}

/* MAIN SCRIPT SECTION */

this.class.classLoader.systemClassLoader.addURL(new URL("file:///usr/share/java/postgresql-jdbc.jar"))
this.class.classLoader.systemClassLoader.addURL(new URL("file:///var/lib/jenkins/mvn/apache-maven-2.2.1/lib/ojdbc6.jar"))

//jdbcStr = getJDBCString(Globals.databaseName)
  
opdb_dbConn = Sql.newInstance(
   "jdbc:postgresql://localhost/postgres",
   "acn_perf_tool",Globals.opDBPassword,"org.postgresql.Driver")

info "Connected to Operational DB"
opdb_dbConn.connection.autoCommit = false

String databaseName = ""
    
fileLines = new File(Globals.workspace+"/"+Globals.dataFileName).readLines()

def bSuccess = true

def myList = []

	
fileLines.each {
	lineString = it
	jdbcStr = ""
		
	if (! lineString[0].equals("#")) {
		arr = lineString.split(":")
		databaseName = arr[1].toUpperCase()
		jdbcStr = arr[2] + ":"+arr[4]+":"+arr[1]

//		if ( databaseName.equals("CCBDEV1") ) {
		try {
		
			def TARGET_CONNECTION_URL      = "jdbc:oracle:thin:"+Globals.dictReadUser+"/"+Globals.dictReadPassword+"@"+jdbcStr
			def v_snap_id
			def v_snap_end
			debug("Setting up connection to Database: "+jdbcStr) 
			target_dbConn = Sql.newInstance(TARGET_CONNECTION_URL, "oracle.jdbc.OracleDriver");
			def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
			target_dbConn.eachRow(userDBNameStmt)
			{
				info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
			}
			
			// Current snapshot and end timestamp
			sqlStmt = 	"SELECT coalesce(MAX(SNAP_ID),0)+1 as snap_id"+
						",	   MAX(END_INTERVAL_TIME) as snap_end "+
						"FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = '"+databaseName+"'";
			
			opdb_dbConn.eachRow(sqlStmt)
			{
				v_snap_id = it.snap_id;
				v_snap_end = it.snap_end;			
			}
            myList = []
			// Fetch current statistics
			info "-> Inserting new snapshot"
			opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_snapshot(DATABASE_NAME, SNAP_ID, BEGIN_INTERVAL_TIME, END_INTERVAL_TIME) "+
					  "values(?,?,?,NOW())",[databaseName,v_snap_id,v_snap_end])

			
			info "-> Inserting librarycache"
			nCounter = 0
			target_dbConn.eachRow ( "SELECT namespace, gets, gethits FROM SYS.V_\$LIBRARYCACHE" )
			{
				nCounter = nCounter + 1
				opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_librarycache( database_name,snap_id,namespace,gets,gethits) "+
					  "values(?,?,?,?,?)",[databaseName,v_snap_id,it.namespace, it.gets, it.gethits])
			}

			info "-> Completed: "+nCounter+" rows inserted"
			info "-> Inserting sysstat"
			nCounter = 0
			target_dbConn.eachRow ( "SELECT statistic# as statistic, name, value FROM V\$SYSSTAT "+
									"WHERE name IN ('parse time cpu','CPU used by this session' "+
									", 'physical reads','consistent gets','db block gets','physical read bytes','physical write bytes') ")
			{
				nCounter = nCounter + 1
				opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_sysstat( database_name,snap_id,statistic,stat_name,value) "+
					  "values(?,?,?,?,?)",[databaseName,v_snap_id,it.statistic, it.name, it.value])
			}

			info "-> Inserting sysstat (ORA\$AT)"
			target_dbConn.eachRow("select TRUNC(sum(cpu_time)/1000000 ) as CPU_SECONDS from v\$sqlarea where action like 'ORA\$AT%' and command_type = 3")
			{
				opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_sysstat( database_name,snap_id,statistic,stat_name,value) "+
					  "values(?,?,?,?,?)",[databaseName,v_snap_id,-20001,"DBMS_AUTO_TASK_ADMIN SQL Seconds", it.cpu_seconds])
				
			}
			
			info "-> Inserting sqlstat"
			nCounter = 0
			target_dbConn.eachRow ( "SELECT sql_id, executions, buffer_gets, cpu_time from V\$SQLAREA A where sql_text not like '% no_monitoring %'" )
			{
				nCounter = nCounter + 1
				opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_sqlstat( database_name,snap_id,sql_id, executions, buffer_gets, cpu_time) "+
					  "values(?,?,?,?,?,?)",[databaseName,v_snap_id,it.sql_id, it.executions, it.buffer_gets, it.cpu_time])
			}
			info "-> Completed: "+nCounter+" rows inserted"


			info "-> Update sqlstat deltas"
			sqlStmt = "UPDATE ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT "+
		"SET BUFFER_GETS_DELTA = GREATEST(0,BUFFER_GETS - COALESCE((SELECT BUFFER_GETS FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT B WHERE ACN_PERF_HIST_SQLSTAT.SQL_ID = B.SQL_ID AND B.SNAP_ID = ? - 1 AND DATABASE_NAME = ?),0)) "+
		",   CPU_TIME_DELTA = GREATEST(CPU_TIME - COALESCE((SELECT CPU_TIME FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT B WHERE ACN_PERF_HIST_SQLSTAT.SQL_ID = B.SQL_ID AND B.SNAP_ID = ? - 1 AND DATABASE_NAME = ?),0)) "+
		",   EXECUTIONS_DELTA = GREATEST(EXECUTIONS - COALESCE((SELECT EXECUTIONS FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT B WHERE ACN_PERF_HIST_SQLSTAT.SQL_ID = B.SQL_ID AND B.SNAP_ID = ? - 1 AND DATABASE_NAME = ?),0)) "+
		"WHERE SNAP_ID = ? AND DATABASE_NAME = ?"
			opdb_dbConn.executeUpdate(sqlStmt,[v_snap_id,databaseName,v_snap_id,databaseName,v_snap_id,databaseName,v_snap_id,databaseName])

			info "-> Select sysmetric_summary"
			nCounter = 0
			sqlStmt = "SELECT metric_name, average, metric_unit from v\$sysmetric_summary where end_time > ?"
			target_dbConn.eachRow ( sqlStmt, [ v_snap_end ])
			{
				nCounter = nCounter + 1
				opdb_dbConn.execute("insert into ACN_PERF_TOOL.acn_perf_hist_sysmetric_summary( database_name,snap_id,metric_name,average,metric_unit) "+
					  "values(?,?,?,?,?)",[databaseName,v_snap_id,it.metric_name, it.average, it.metric_unit])
			}
			info "-> Completed: "+nCounter+" rows inserted"

			// Compress irrelevant SQLSTAT data
			info "-> Purge SQLSTAT Non-Top (Irrelevant Data)"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT X "+
						"WHERE SQL_ID NOT IN ( "+
						"	SELECT SQL_ID "+
						"	FROM ( "+
						"	SELECT SQL_ID, DELTA_CHANGE, ROW_NUMBER() OVER () AS ROWNUM "+
						"	FROM  "+
						"	( "+
						"		SELECT SQL_ID, SUM(BUFFER_GETS_DELTA) AS DELTA_CHANGE "+
						"		FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT A "+
						"		WHERE DATABASE_NAME = ? "+
						"		AND SNAP_ID = (SELECT MAX(SNAP_ID) - 3 FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?) "+
						"		GROUP BY SQL_ID "+
						"		ORDER BY 2 DESC "+
						"	) A "+
						"	) B "+
						"	WHERE ROWNUM <= 30 "+
						"	UNION "+
						"	SELECT SQL_ID "+
						"	FROM ( "+
						"	SELECT SQL_ID, DELTA_CHANGE, ROW_NUMBER() OVER () AS ROWNUM "+
						"	FROM  "+
						"	( "+
						"		SELECT SQL_ID, SUM(CPU_TIME_DELTA) AS DELTA_CHANGE "+
						"		FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT A "+
						"		WHERE DATABASE_NAME = ? "+
						"		AND SNAP_ID = (SELECT MAX(SNAP_ID) - 3 FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?) "+
						"		GROUP BY SQL_ID "+
						"		ORDER BY 2 DESC "+
						"	) A "+
						"	) B "+
						"	WHERE ROWNUM <= 30 "+
						"	 "+
						") "+
						"AND DATABASE_NAME = ? "+
						"AND SNAP_ID = (SELECT MAX(SNAP_ID) - 3 FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?)"
					,[ databaseName, databaseName, databaseName, databaseName, databaseName, databaseName])			

			
			debug "Closing connection to database"
			target_dbConn.close()
			opdb_dbConn.commit()

		} catch (SQLException se) {
			 error "Unable to process: "+databaseName+"@"+arr[2]
			 error se.message
			 opdb_dbConn.rollback()
		}
	//}
	}
			
}

opdb_dbConn.close()
return bSuccess
