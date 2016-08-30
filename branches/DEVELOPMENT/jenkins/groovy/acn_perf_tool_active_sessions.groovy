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
   static String dataFileName = resolver.resolve("DATA_FILE")
   static String DATABASE = resolver.resolve("DATABASE")
   static String includeBackgroundFlag = resolver.resolve("INCLUDE_BACKGROUND_PROCESSES")
   static String INST_ID = resolver.resolve("INST_ID")
   static String SID = resolver.resolve("SID")
   static String SAMPLE_COUNT = resolver.resolve("SAMPLE_COUNT")
   static String NUMBER_TO_REPORT = resolver.resolve("NUMBER_TO_REPORT")
   
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
	locStr = ""
	if ( ! errorLoc.equals("") ) { locStr = "(Location: "+errorLoc+") " }
	println("["+(today)+"][ERROR]: "+locStr+p)
	errorLoc = ""
}

/* MAIN SCRIPT SECTION */

this.class.classLoader.systemClassLoader.addURL(new URL("file:///usr/share/java/postgresql-jdbc.jar"))
this.class.classLoader.systemClassLoader.addURL(new URL("file:///var/lib/jenkins/mvn/apache-maven-2.2.1/lib/ojdbc6.jar"))

/*
opdb_dbConn = Sql.newInstance(
   "jdbc:postgresql://localhost/postgres",
   "acn_perf_tool",Globals.opDBPassword,"org.postgresql.Driver")

info "Connected to Operational DB"
opdb_dbConn.connection.autoCommit = false
*/

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

		if ( databaseName.equals(Globals.DATABASE) ) {
			try {
			
				def TARGET_CONNECTION_URL      = "jdbc:oracle:thin:"+Globals.dictReadUser+"/"+Globals.dictReadPassword+"@"+jdbcStr
				debug("Setting up connection to Database: "+jdbcStr) 
				target_dbConn = Sql.newInstance(TARGET_CONNECTION_URL, "oracle.jdbc.OracleDriver");
				def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
				target_dbConn.eachRow(userDBNameStmt)
				{
					info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
				}

				if ( Globals.SID.equals("") ) 
				{
					// Display all active sesssions at the moment in HTML table format
					info ("Current Active Sessions")
					sqlStmt = "  WITH  "+
					"  gvsession AS ( "+
					"    SELECT * FROM GV\$SESSION), "+
					"  gvsesstat AS ( "+
					"    SELECT * FROM GV\$SESSTAT "+
					"    where statistic# IN (select statistic#  from v\$statname where name IN(  "+
					"        'CPU used by this session' "+
					"      , 'physical read total bytes' "+
					"      , 'physical write total bytes' "+
					"      , 'db block gets' "+
					"      , 'consistent gets' "+
					"      , 'physical reads'     "+  
					"          ) "+
					"      ) "+
					"    ), "+
					"  gvsqlarea AS ( "+
					"    SELECT inst_id, sql_id, executions, buffer_gets, disk_reads,sql_text FROM GV\$SQLAREA "+
					"    WHERE SQL_ID IN (SELECT SQL_ID FROM GV\$SESSION)), "+
					"  gvprocess AS ( "+
					"    SELECT * FROM GV\$PROCESS), "+
					"  vstatname AS ( "+
					"    SELECT * FROM v\$statname "+
					"    where name IN(  "+
					"        'CPU used by this session' "+
					"      , 'physical read total bytes' "+
					"      , 'physical write total bytes' "+
					"      , 'db block gets' "+
					"      , 'consistent gets' "+
					"      , 'physical reads'     "+  
					"          )), "+
					"  dbaprocedures AS ( "+
					"    SELECT * FROM dba_procedures  "+
					"    WHERE object_id IN (select plsql_entry_object_id FROM GV\$SESSION) "+
					"    ), "+
					"  gvsession_longops AS ( "+
					"    SELECT * FROM gv\$session_longops) "+
					"select rownum as EntryID, a.* from ( "+
					"select * from ( "+
					"select * from ( "+
					"select USERNAME,blocking_session,sid "+
					"      ,Trunc((Sysdate - Logon_Time) * 24 * 60 * 60) As Connected_Seconds,Module,Sql_Id "+
					",(select TRUNC((value/100)/GREATEST((sysdate - a.logon_time),1/8640)) from gvsesstat a1 "+
					"where a1.statistic# = (select statistic#  from vstatname where name = 'CPU used by this session') "+
					"and a1.inst_id = a.inst_id "+
					"and a1.sid = a.sid) est_sess_cpu_seconds_per_day "+
					",(select trunc(value/100) from gvsesstat a2 "+
					"where a2.statistic# = (select statistic#  from vstatname where name = 'CPU used by this session') "+
					"and a2.inst_id = a.inst_id  "+
					"and a2.sid = a.sid) sess_cpu_seconds "+
					",logon_time "+
					",(select executions  "+
					"  from gvsqlarea a3 "+
					"  where a3.sql_id = a.sql_id and a3.inst_id = a.inst_id)  as sql_global_execs "+
					",(select sum(time_remaining) "+
					"  from gvsession_longops a4 "+
					"  where 1 = 1 "+
					"  and a4.sid = a.sid "+
					"  and a4.inst_id = a.inst_id "+
					"  and a4.serial# = a.serial#) as time_remaining "+
					",(select buffer_gets from gvsqlarea a5 where a5.sql_id = a.sql_id and a5.inst_id = a.inst_id)  as sql_global_bufget "+
					",(select TRUNC(value/1000000) "+
					"from gvsesstat a6 "+
					"where a6.statistic# = (select statistic# from vstatname where name = 'physical read total bytes') "+
					"and a6.sid = a.sid "+
					"and a6.inst_id = a.inst_id "+
					") as sess_mb_read "+
					",(select TRUNC(value/1000000) "+
					"from gvsesstat a7 "+
					"where a7.statistic# = (select statistic# from vstatname where name = 'physical write total bytes') "+
					"and a7.sid = a.sid "+
					"and a7.inst_id = a.inst_id "+
					") as sess_mb_written "+
					",round((select 100*(p1.value + p2.value - p3.value) / GREATEST((p1.value + p2.value),1) "+
					"from gvsesstat p1, gvsesstat p2, gvsesstat p3 "+
					"where 1 = 1 "+
					"and p1.statistic# = (select statistic# from vstatname where name = 'db block gets') "+
					"and p2.statistic# = (select statistic# from vstatname where name = 'consistent gets') "+
					"and p3.statistic# = (select statistic# from vstatname where name = 'physical reads') "+
					"and p1.sid = a.sid "+
					"and p2.sid = a.sid "+
					"and p3.sid = a.sid "+
					"and p1.inst_id = a.inst_id "+
					"and p2.inst_id = a.inst_id "+
					"and p3.inst_id = a.inst_id "+
					"),2) as sess_cachehit_pct "+
					",(select sql_text from gvsqlarea a8 where a8.sql_id = a.sql_id and a8.inst_id = a.inst_id)  as sql_text "+
					",(select disk_reads from gvsqlarea a9 where a9.sql_id = a.sql_id and a9.inst_id = a.inst_id)  as sql_global_diskread "+
					",(select spid from gvprocess a10 where a10.addr = a.paddr and a10.inst_id = a.inst_id) as unix_pid "+
					",(select owner||'.'||object_name||'.'||procedure_name||'()' "+
					"from dbaprocedures a11 "+
					"where a11.object_id = a.plsql_entry_object_id "+
					"and a11.subprogram_id = a.plsql_entry_subprogram_id "+
					") as top_level_proc "+
					",(select owner||'.'||object_name||'.'||procedure_name||'()'  "+
					"    from dbaprocedures x "+
					"    where x.object_id = a.plsql_object_id  "+
					"    and x.subprogram_id = a.plsql_subprogram_id "+
					" ) as executing_proc "+
					", osuser "+
					", action "+
					", program "+
					", inst_id "+
					", client_identifier "+
					", event "+
					", 100 - round ((select value from gvsesstat a12 where a12.statistic# = 574 and a12.sid = a.sid and a12.inst_id = a.inst_id) / (select greatest(value,1) from gvsesstat a13 where a13.statistic# = 573 and a13.sid = a.sid and a13.inst_id = a.inst_id),2) as PARSE_HIT_PCT "+
					"from gvsession a "+
					"where 1 = 1 "+
					"and status = 'ACTIVE' "+
					"and (decode(username,null,'Y','N') = ? or username is not null) "+
					"and sid != USERENV('SID') "+
					"ORDER BY sql_global_bufget DESC "+
					") A "+
					"where sess_cpu_seconds >= 0 "+
					") A order by 7 desc "+
					") A "
					debug "Fetching active sessions: "+sqlStmt
					target_dbConn.eachRow(sqlStmt, [ Globals.includeBackgroundFlag ])
					{
						println "+------+-----+----------+----------+---------+------------+-----------+---------------+----------+-----------------------+----------+"
						println "| INST | SID | UserName |CPU/Day(s)|Block SID|Connected(s)|Sess CPU(s)| SQL ID        | Unix PID |      Logon Time       | OS User  |"
						println "+------+-----+----------+----------+---------+------------+-----------+---------------+----------+-----------------------+----------+"
						println "|"+(it.INST_ID).toString().padLeft(6)+
						        "|"+(it.SID).toString().padLeft(5)+
								"|"+(it.USERNAME).padRight(10)+
						        "|"+(it.est_sess_cpu_seconds_per_day).toString().padLeft(10)+
						        "|"+(it.blocking_session).toString().padLeft(9)+
						        "|"+(it.connected_seconds).toString().padLeft(12)+
						        "|"+(it.sess_cpu_seconds).toString().padLeft(11)+
						        "|"+(it.SQL_ID).padRight(15)+
						        "|"+(it.unix_pid).toString().padLeft(10)+
						        "|"+(it.logon_time).toString().padRight(23)+
								"|"+(it.OSUSER).padRight(10)+"|"
						println "+------+-----+----------+----------+---------+------------+-----------+---------------+----------+-----------------------+----------+"
						println "| Time remaining               | "+it.time_remaining+" (s)"
						println "| Session read                 | "+it.sess_mb_read+" mb"
						println "| Session Write                | "+it.sess_mb_written+" mb"
						println "| Session Buffer Cache Hit Rate| "+it.sess_cachehit_pct+"%"
						println "| Parse hit                    | "+it.PARSE_HIT_PCT+"%"
						println "| Module                       | "+it.module
						println "| Top Level Proc               | "+it.top_level_proc
						println "| Executing Proc               | "+it.executing_proc
						println "| Action                       | "+it.action
						println "| Program                      | "+it.program
						println "| Client  Identifier           | "+it.client_identifier
						println "| Event                        | "+it.event
						println "| SQL Text                     | "+it.sql_text
						
					}
					println "+----------------------------------+-------------------------------------------------------------------------------------------------"

									
				} else {
					// Run profiler query and display results as well as pivot results
					sqlStmt = "select EntryID,TRUNC(sample_msec) sample_msec,status,execution_event,executing_Statement,sql_id "+
					", delta_exec "+
					", ROUND(sample_msec * 100 / sum(sample_msec) over (partition by 1),2) as PCT_TOTAL "+
					",sql_text  "+
					"from ( "+
					"SELECT rownum as EntryID, a.sample_msec, a.distcount, a.status, event as execution_event "+
					",nvl(a.plsql_executing,SUBSTR(a.sql_text,1,50)) as executing_statement,a.sql_id "+
					",a.execs_last - a.exec_count_min as delta_exec "+
					",a.sql_text  "+
					"FROM ( "+
					"WITH  "+
					"    t1 AS (SELECT hsecs FROM v\$timer), "+
					"    q AS ( "+
					"        select /*+ opt_param('_optimizer_sortmerge_join_enabled','false') opt_param('hash_join_enabled','false') ordered use_nl(t) */  "+
					"            status,plsql_object_id,plsql_subprogram_id,sql_id, event  "+
					"            , min((select sum(executions) from gv\$sqlarea where INST_ID = ? AND sql_id = t.sql_id)) as exec_count_min "+
					"            , count(*) as ANTALL, count(distinct r.rn) DISTCOUNT "+
					"        from "+
					"            (select /*+ no_unnest */ rownum rn from dual connect by level <= ?) r "+
					"          , gv\$session t "+
					"        where inst_id = ? "+
					"        and sid = ? "+
					"        group by status, plsql_object_id, plsql_subprogram_id, sql_id, event "+
					"        order by "+
					"            ANTALL desc, status,plsql_object_id,plsql_subprogram_id,sql_id, event "+
					"    ), "+
					"    t2 AS (SELECT hsecs FROM v\$timer) "+
					"SELECT /*+ ORDERED */ "+
					"    trunc((t2.hsecs - t1.hsecs) * 10 * q.distcount / ?, 2) sample_msec "+
					"  , exec_count_min "+
					"  , distcount "+
					"  , q.status "+
					"  ,(select owner||'.'||object_name||'.'||procedure_name  "+
					"    from dba_procedures  "+
					"    where object_id = q.plsql_object_id  "+
					"    and subprogram_id = q.plsql_subprogram_id) as plsql_executing "+
					"  , q.sql_id "+
					"  , event "+
					"  , (select sql_text from gv\$sqlarea  where inst_id = ? and sql_id = q.sql_id) as SQL_TEXT "+
					"  , (select executions from gv\$sqlarea  where inst_id = ? and sql_id = q.sql_id) as EXECS_LAST "+
					"FROM "+
					"     t1, "+
					"     q, "+
					"     t2 "+
					") a "+
					") "+
					"where rownum <= ? "
					debug "Profiling: "+sqlStmt

					println "+--------+--------+--------+---------------+----------+------------+-----------+---------------+----------+-----------------------+----------+"
					println "|Sample %|Time(ms)| Status | SQL_ID        |Executions|Event  "
					println "+--------+--------+--------+---------------+----------+------------+-----------+---------------+----------+-----------------------+----------+"
					target_dbConn.eachRow(sqlStmt, [ Globals.INST_ID, Globals.SAMPLE_COUNT, Globals.INST_ID, Globals.SID, Globals.SAMPLE_COUNT, Globals.INST_ID, Globals.INST_ID, Globals.NUMBER_TO_REPORT ] )
					{
						println "|"+(it.PCT_TOTAL).toString().padLeft(8)+
								"|"+(it.sample_msec).toString().padLeft(8)+
						        "|"+(it.STATUS).toString().padLeft(8)+
								"|"+(it.SQL_ID).toString().padLeft(15)+
								"|"+(it.DELTA_EXEC).toString().padLeft(10)+
								"|"+(it.EXECUTION_EVENT)
						println("|        | SQL Text -> "+it.SQL_TEXT)
						println "+--------+--------+--------+---------------+----------+------------+-----------+---------------+----------+-----------------------+----------+"
					}
					
				}
				
				myList = []
				
				debug "Closing connection to database"
				target_dbConn.close()

			} catch (SQLException se) {
				 error "Unable to process: "+databaseName+"@"+arr[2]
				 error se.message
			} // try/catch block
		} // if DatabaseName = Globals.database
	} // Non-comment
} // Looping databases in file

return bSuccess
