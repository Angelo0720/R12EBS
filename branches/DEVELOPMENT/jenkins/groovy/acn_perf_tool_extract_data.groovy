import groovy.sql.Sql
import java.sql.SQLException

errorLoc = ""

class Globals {
   static def build = Thread.currentThread().executable
   static def resolver = build.buildVariableResolver
   static String logLevel = resolver.resolve("LOG_LEVEL")
   static String workspace = build.workspace.toString()
   static String dataFileName = resolver.resolve("DATA_FILE")
   static String dictReadUser = resolver.resolve("DICTIONARY_READ_USER")
   static String dictReadPassword = resolver.resolve("DICTIONARY_READ_PASSWORD")
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
this.class.classLoader.systemClassLoader.addURL(new URL("file:///var/lib/jenkins/apache-maven-2.2.1/lib/ojdbc6.jar"))

//jdbcStr = getJDBCString(Globals.databaseName)
  
opdb_dbConn = Sql.newInstance(
   "jdbc:postgresql://localhost/postgres",
   "acn_perf_tool","welcome1","org.postgresql.Driver")

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
			info "Processing: "+databaseName
			def TARGET_CONNECTION_URL      = "jdbc:oracle:thin:"+Globals.dictReadUser+"/"+Globals.dictReadPassword+"@"+jdbcStr
			debug("Setting up connection to Database: "+jdbcStr) 
			Properties props = new Properties();
			props.setProperty("LoginTimeout","2");
			props.setProperty("oracle.jdbc.ReadTimeout","10000");
			
			target_dbConn = Sql.newInstance(TARGET_CONNECTION_URL, props, "oracle.jdbc.OracleDriver");
			
			target_dbConn.withStatement { 
			   stmt -> stmt.queryTimeout = 10 
			} 			
			def userDBNameStmt = "SELECT USER AS USER_NAME, GLOBAL_NAME as GLOBAL_NAME from GLOBAL_NAME"
			target_dbConn.eachRow(userDBNameStmt)
			{
				info("Connected to "+it.USER_NAME+"@"+it.GLOBAL_NAME)
			}

			
			info "-> Mark old SQLTEXT for purge"
			opdb_dbConn.executeUpdate("Update ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT SET PURGE_FLAG = 'Y' WHERE DATABASE_NAME = ?", [databaseName])
			
			///////////////////
			// Generate Files
			///////////////////
			// Main Statistics
			info "-> Generate Main Statistics"
			myList = []
			sqlStmt = "select database_name||'~'||delta_time||'~'||metric_name||'~'||average||'~'||metric_unit as FILE_LINE"+
						" from ( "+
						"  SELECT database_name"+
						"  ,(select TO_CHAR(begin_interval_time ,'YYYYMMDDHH24MISS') from ACN_PERF_TOOL.acn_perf_hist_snapshot B where snap_id = A.snap_id AND a.database_name = database_name) as delta_time"+
						"  ,metric_name, case when metric_name = 'Library Cache Hit Ratio' then least(round( average ,1),100) else round( average ,1) end as average, metric_unit"+
						"  from ACN_PERF_TOOL.acn_perf_hist_sysmetric_summary A"+
						"  where metric_name IN ("+
						"   'Current Logons Count'"+
						"  ,'Library Cache Hit Ratio'"+
						"  ,'Buffer Cache Hit Ratio'"+
						"  , 'Host CPU Utilization (%)'"+
						"  )"+
						"  and database_name = ?"+
						"  order by snap_id"+
						") X";
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add it.FILE_LINE
			}
			
			writeToFile(Globals.workspace,databaseName+"-Key-Statistics",".dat",myList)



			info "-> Generate CPU Trend (AutoTune)"
			// CPU Time Autotuning
			sqlStmt = "select DATABASE_NAME||'~'||delta_time||'~'||case when prev_sekunder_cpu = 0 then 0 else TRUNC(sekunder_cpu - prev_sekunder_cpu) end AS FILE_LINE "+
					"from ( "+
					"select * "+
					"from   "+
					"(   "+
					"  select database_name,   "+
					"    (select TO_CHAR(MAX(begin_interval_time),'YYYYMMDDHH24MISS') from ACN_PERF_TOOL.acn_perf_hist_snapshot where snap_id = A.snap_id and database_name = a.database_name) as delta_time   "+
					"  , stat_name, value as sekunder_cpu    "+
					"  , lag(value,1) over (order by snap_id) as prev_sekunder_cpu   "+
					"  from (  "+
					"    select database_name,snap_id,stat_name, SUM(value) as value   "+
					"    from ACN_PERF_TOOL.acn_perf_hist_sysstat a   "+
					"    where a.stat_name in ('DBMS_AUTO_TASK_ADMIN SQL Seconds')  "+
					"    and a.database_name = ? "+
					"    and snap_id >= (select max(snap_id) from ACN_PERF_TOOL.acn_perf_hist_snapshot) - 200  "+
					"    group by database_name,snap_id, stat_name  "+
					"    ) a  "+
					"  order by snap_id   "+
					") a  "+
					"where sekunder_cpu - prev_sekunder_cpu >= 0"+
					"order by delta_time "+
					") a"
			myList = []
			
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add it.FILE_LINE
			}
			
			writeToFile(Globals.workspace,databaseName+"-CPU-Trend-Autotune",".dat",myList)
			

			info "-> Generate CPU Trend (Parse)"
			// CPU Time Parse
			sqlStmt = "select DATABASE_NAME||'~'||delta_time||'~'||TRUNC(sekunder_parse - prev_sekunder_parse) AS FILE_LINE "+
					"from ( "+
					"select * "+
					"from   "+
					"(   "+
					"  select database_name,   "+
					"    (select TO_CHAR(begin_interval_time,'YYYYMMDDHH24MISS') from ACN_PERF_TOOL.acn_perf_hist_snapshot where snap_id = A.snap_id and database_name = a.database_name) as delta_time   "+
					"  , stat_name, value/100 as sekunder_parse    "+
					"  , lag(value,1) over (order by snap_id)/100 as prev_sekunder_parse   "+
					"  from (  "+
					"    select database_name,snap_id,stat_name, SUM(value) as value   "+
					"    from ACN_PERF_TOOL.acn_perf_hist_sysstat a   "+
					"    where a.stat_name in ('parse time cpu')  "+
					"    and a.database_name = ? "+
					"    and snap_id >= (select max(snap_id) from ACN_PERF_TOOL.acn_perf_hist_snapshot where database_name = a.database_name) - 200  "+
					"    group by database_name,snap_id, stat_name  "+
					"    ) a  "+
					"  order by snap_id   "+
					") a  "+
					"where sekunder_parse - prev_sekunder_parse > 0 and prev_sekunder_parse > 0"+
					"order by delta_time "+
					") a"
			
			myList = []
			
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add it.FILE_LINE
			}
			
			writeToFile(Globals.workspace,databaseName+"-CPU-Trend-Parse",".dat",myList)
			
			info "-> Generate CPU Trend (SQL)"
			// CPU Time SQL
			sqlStmt = "select database_name||'~'||delta_time||'~'||sekunder_cpu_session as file_line "+
			"from ( "+
			"select database_name,delta_time, TRUNC(sekunder_SESSION - prev_sekunder_SESSION) AS SEKUNDER_CPU_SESSION, prev_sekunder_SESSION "+
			"from   "+
			"(   "+
			"select database_name,  "+
			"  (select TO_CHAR(begin_interval_time,'YYYYMMDDHH24MISS')     "+
			"   from ACN_PERF_TOOL.acn_perf_hist_snapshot where database_name = a.database_name "+
			"   and snap_id = A.snap_id "+ 
			"   ) as delta_time   "+
			", stat_name, value/100 as sekunder_SESSION    "+
			", lag(value,1) over (order by snap_id)/100 as prev_sekunder_SESSION   "+
			"from (  "+
			"  select database_name,snap_id, stat_name,sum(value) as value from ACN_PERF_TOOL.acn_perf_hist_sysstat a   "+
			"  where a.stat_name in ( 'CPU used by this session' )   "+
			"  and a.database_name = ? "+
			"  and snap_id >= (select max(snap_id) from ACN_PERF_TOOL.acn_perf_hist_snapshot where database_name = a.database_name) - 200  "+
			"  group by database_name,snap_id,stat_name  "+
			"  ) a  "+
			"order by snap_id   "+
			") a  "+
			") a "+
			"where sekunder_cpu_session > 0 and prev_sekunder_SESSION > 0 "+
			"order by delta_time"
			
			myList = []
			
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add it.FILE_LINE
			}
			
			writeToFile(Globals.workspace,databaseName+"-CPU-Trend-SQL",".dat",myList)
			

			// Library Cache Trend
			info "-> Generate CPU Trend (Library Cache)"
			sqlStmt = "select database_name||'~'||delta_time||'~'||cachehit_pct AS FILE_LINE from "+
						"( "+
						"select database_name,   "+
						"(select TO_CHAR(begin_interval_time,'YYYYMMDDHH24MISS') from ACN_PERF_TOOL.acn_perf_hist_snapshot where snap_id = a.snap_id and database_name = a.database_name) as delta_time  "+
						", gets - prev_gets as delta_gets  "+
						", gethits - prev_gethits delta_gethits  "+
						", round(100*(gethits - prev_gethits) / GREATEST(gets - prev_gets , 1),2) as cachehit_pct  "+
						"from (  "+
						"  select   "+
						"  lag(gets,1) over (order by snap_id) PREV_GETS  "+
						"  ,lag(gethits,1) over (order by snap_id) PREV_GETHITS  "+
						"  , a.*  "+
						"  from   "+
						"    (  "+
						"      SELECT database_name,snap_id,sum(gets) as gets,sum(gethits) as gethits  "+
						"      from ACN_PERF_TOOL.acn_perf_hist_LIBRARYCACHE A  "+
						"      where namespace = 'SQL AREA'  "+
						"      and snap_id >= (select max(snap_id) from ACN_PERF_TOOL.acn_perf_hist_snapshot where database_name = a.database_name) - 200  "+
						"      and a.database_name = ?  "+
						"      group by snap_id, database_name  "+
						"    ) a  "+
						"  order by snap_id desc  "+
						"  ) a  "+
						") a "+
						"where delta_time is not null "+
						"and cachehit_pct > 0 order by delta_time"

			myList = []
			
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add it.FILE_LINE
			}
			
			writeToFile(Globals.workspace,databaseName+"-CPU-Trend-LibCache",".dat",myList)


		// Top 15 CPU Queries
		info "-> Generating CPU SQL"
		sqlStmt = "select a.rownum as ENTRYID, a.sql_id "+
				", a.cpu_seconds_last_week, a.cpu_seconds_today, a.cpu_seconds_yesterday, executions "+
				"from ( "+
				"select rownum, sql_id, cpu_seconds_last_week, cpu_seconds_today, cpu_seconds_yesterday,executions "+
				"from ( "+
				"select row_number() over () as rownum, sql_id, cpu_seconds_last_week, cpu_seconds_today, cpu_seconds_yesterday,executions "+
				"from ( "+
				"select sql_id "+
				", sum(executions_delta) as executions "+
				", trunc(sum(cpu_time_delta) / 1000000 ) as cpu_seconds_last_week "+
				", trunc(sum(case when date_trunc('day',b.begin_interval_time) = date_trunc('day',NOW()) then cpu_time_delta else 0 end ) / 1000000) as cpu_seconds_today  "+
				", trunc(sum(case when date_trunc('day',b.begin_interval_time) = date_trunc('day',NOW()) - interval '1 day' then cpu_time_delta else 0 end ) / 1000000) as cpu_seconds_yesterday  "+
				"from acn_perf_tool.acn_perf_hist_sqlstat a "+
				", acn_perf_tool.acn_perf_hist_snapshot b "+
				"where a.database_name = ? "+
				"and a.snap_id = b.snap_id "+
				"and a.database_name = b.database_name "+
				"and b.begin_interval_time > NOW() - interval '7 days' "+
				"and a.snap_id >= (select max(snap_id) from acn_perf_tool.acn_perf_hist_snapshot WHERE database_name = ?) - 200  "+
				"group by sql_id "+
				"order by 3 desc "+
				") a "+
				") a "+
				" where rownum <= 15 "+
				") a"

			myList = []
						
			opdb_dbConn.eachRow(sqlStmt, [databaseName,databaseName])
			{
							
				sSQLID = it.SQL_ID
				
				String v_sql_text = ""
				String v_module = ""
				String v_action = ""
				def v_program_id = 0
				def v_line = 0
				def v_program = ""
				
				insert_flag = true
				debug "Checking for existing entry for SQL_ID: "+sSQLID
				// SELECT SQL_TEXT, MODULE, ACTION, PROGRAM, PROGRAM_LINE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT WHERE DATABASE_NAME = 'MDMTST2' AND SQL_ID = '7jh143gdfnpgu'
				sqlStmt = "SELECT SQL_TEXT, MODULE, ACTION, PROGRAM, PROGRAM_LINE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT WHERE DATABASE_NAME = ? AND SQL_ID = ?"
				opdb_dbConn.eachRow(sqlStmt,[databaseName,sSQLID])
				{
					debug "Found existing entry for SQL_ID: "+sSQLID
					insert_flag = false
					v_sql_text = it.sql_text
					v_module = it.module
					v_action = it.action
					v_program = it.program
					v_line = it.program_line
					
				}
				
							
				if (insert_flag) 
				{
					debug "Inserting SQL_ID: "+sSQLID
					// Fetch SQL ID from source DB
					info "Inserting sqltext"
					target_dbConn.eachRow ( "SELECT replace(sql_text,CHR(0),' ') AS SQL_TEXT "+
											",'['||parsing_schema_name||'] '||module as module "+
											", action, program_id "+
											", program_line# as program_line "+
											" FROM V\$SQLAREA a WHERE SQL_ID = ?", [ sSQLID ] )
					{
						
						v_sql_text = it.sql_text
						v_module = it.module
						v_action = it.action
						v_program_id = it.program_id
						v_line = it.program_line
					
						v_program = ""
						pgmStmt = "select owner||'.'||object_name as program from dba_objects where object_id = ?"
						target_dbConn.eachRow(pgmStmt,[v_program_id])
						{
							v_program = it.program
						}
					
						sqlStmt = "insert into ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT( database_name,sql_id,sql_text,module,action,program,program_line) values(?,?,?,?,?,?,?)"
						opdb_dbConn.execute(sqlStmt,[databaseName, sSQLID, v_sql_text,v_module,v_action,v_program,v_line])
					}
					
					
				}

				debug "Added to file: "+it.ENTRYID
				myList.add (it.ENTRYID+"~"+sSQLID+"~"+
							it.EXECUTIONS+"~"+it.CPU_SECONDS_LAST_WEEK+"~"+
							it.CPU_SECONDS_TODAY+"~"+it.CPU_SECONDS_YESTERDAY+"~"+
							v_module+"~"+v_action+"~"+v_program+"~"+v_line+"~"+v_sql_text )
						
				debug "Clear purge flag: "+sSQLID
				opdb_dbConn.executeUpdate("Update ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT SET PURGE_FLAG = 'N' WHERE SQL_ID = ? AND DATABASE_NAME = ?", [sSQLID, databaseName])
							
			}
			
			writeToFile(Globals.workspace,databaseName+"-CPU-SQL",".dat",myList)

			// IO Trend
			
			info "-> Generating IO Trend"
			sqlStmt = "select * from (select database_name "+
				",(select TO_CHAR(begin_interval_time ,'YYYYMMDDHH24MISS') from ACN_PERF_TOOL.acn_perf_hist_snapshot where snap_id = A.snap_id and database_name = a.database_name) as delta_time "+
				", a.*  "+
				", ROUND((a.delta_block_gets + a.delta_consistent_gets - a.delta_physical_reads) / greatest(1,(a.delta_block_gets + a.delta_consistent_gets),4)*100) as BufferCacheHitRate "+
				"from ( "+
				"select a.database_name, a.snap_id,max(case when stat_name = 'physical reads' then value - delta_value else 0 end ) as delta_physical_reads "+
				",      max(case when stat_name = 'consistent gets' then value - delta_value else 0 end ) as delta_consistent_gets "+
				",      max(case when stat_name = 'db block gets' then value - delta_value else 0 end) as delta_block_gets "+
				",      trunc(max(case when stat_name = 'physical write bytes' then value - delta_value else 0 end )/1000000000) as delta_write_gb "+
				",      trunc(max(case when stat_name = 'physical read bytes' then value - delta_value else 0 end )/1000000000) as delta_read_gb "+
				"from ( "+
				"select snap_id,stat_name,database_name, value, "+
				" (select value from ACN_PERF_TOOL.acn_perf_hist_sysstat where database_name = a.database_name and snap_id = a.snap_id - 1 and stat_name = a.stat_name) as delta_value "+
				"from ACN_PERF_TOOL.acn_perf_hist_sysstat a "+
				"where 1 = 1 "+
				"and stat_name in ('physical reads','consistent gets','db block gets','physical read bytes','physical write bytes') "+
				"and database_name = ? "+
				") a  "+
				"group by a.snap_id, database_name "+
				") a "+
				"where delta_read_gb is not null "+
				"and delta_read_gb >= 0) a "+
				"where delta_time is not null order by 2"

			debug sqlStmt
			myList = []
						
			opdb_dbConn.eachRow(sqlStmt, [databaseName])
			{
				myList.add (it.database_name+"~"+it.delta_time+"~"+
							it.snap_id+"~"+it.delta_physical_reads+"~"+
							it.delta_write_gb+"~"+it.delta_read_gb+"~"+
							it.delta_consistent_gets+"~"+it.delta_block_gets+"~"+it.buffercachehitrate )
			}
			
			writeToFile(Globals.workspace,databaseName+"-IO-Trend",".dat",myList)
		
			// Top 15 IO Queries
			info "-> Generating IO SQL"
			sqlStmt = "select a.rownum as ENTRYID, a.sql_id  "+
				", a.buffer_gets_last_week, a.buffer_gets_today, a.buffer_gets_yesterday, a.executions  "+
				"from (  "+
				"select rownum, sql_id, buffer_gets_last_week, buffer_gets_today, buffer_gets_yesterday,executions  "+
				"from (  "+
				"select row_number() over () as rownum, sql_id, buffer_gets_last_week, buffer_gets_today, buffer_gets_yesterday,executions  "+
				"from (  "+
				"select sql_id  "+
				", sum(executions_delta) as executions  "+
				", trunc(sum(buffer_gets_delta) ) as buffer_gets_last_week  "+
				", trunc(sum(case when date_trunc('day',b.begin_interval_time) = date_trunc('day',NOW()) then buffer_gets_delta else 0 end ) ) as buffer_gets_today   "+
				", trunc(sum(case when date_trunc('day',b.begin_interval_time) = date_trunc('day',NOW()) - interval '1 day' then buffer_gets_delta else 0 end ) ) as buffer_gets_yesterday   "+
				"from acn_perf_tool.acn_perf_hist_sqlstat a  "+
				", acn_perf_tool.acn_perf_hist_snapshot b  "+
				"where a.database_name = ? "+
				"and a.snap_id = b.snap_id  "+
				"and a.database_name = b.database_name  "+
				"and b.begin_interval_time > NOW() - interval '7 days'  "+
				"and a.snap_id >= (select max(snap_id) from acn_perf_tool.acn_perf_hist_snapshot WHERE database_name = ?) - 200   "+
				"group by sql_id  "+
				"order by 3 desc  "+
				") a  "+
				") a  "+
				" where rownum <= 15 "+
				") a"

			myList = []
						
			opdb_dbConn.eachRow(sqlStmt, [databaseName,databaseName])
			{
				sSQLID = it.SQL_ID
				
				String v_sql_text = ""
				String v_module = ""
				String v_action = ""
				def v_program_id = 0
				def v_line = 0
				def v_program = ""
				insert_flag = true
				sqlStmt = "SELECT SQL_TEXT, MODULE, ACTION, PROGRAM, PROGRAM_LINE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT WHERE DATABASE_NAME = ? AND SQL_ID = ?"
				debug "Checking for existing entry for SQL_ID: "+sSQLID
				opdb_dbConn.eachRow(sqlStmt,[databaseName,sSQLID])
				{
					debug "Found for existing entry for SQL_ID: "+sSQLID
					insert_flag = false
					v_sql_text = it.sql_text
					v_module = it.module
					v_action = it.action
					v_program = it.program
					v_line = it.program_line
				}
				
							
				if (insert_flag) 
				{
					// Fetch SQL ID from source DB
					debug "Inserting sqltext"
					target_dbConn.eachRow ( "SELECT replace(sql_text,CHR(0),' ') AS SQL_TEXT "+
											",'['||parsing_schema_name||'] '||module as module "+
											", action, program_id "+
											", program_line# as program_line "+
											" FROM V\$SQLAREA a WHERE SQL_ID = ?", [ sSQLID ] )
					{
						
						v_sql_text = it.sql_text
						v_module = it.module
						v_action = it.action
						v_program_id = it.program_id
						v_line = it.program_line
					
						v_program = ""
						pgmStmt = "select owner||'.'||object_name as program from dba_objects where object_id = ?"
						target_dbConn.eachRow(pgmStmt,[v_program_id])
						{
							v_program = it.program
						}
					
						sqlStmt = "insert into ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT( database_name,sql_id,sql_text,module,action,program,program_line) values(?,?,?,?,?,?,?)"
						opdb_dbConn.execute(sqlStmt,[databaseName, sSQLID, v_sql_text,v_module,v_action,v_program,v_line])
					}
					
					
				}
						
				myList.add (it.ENTRYID+"~"+sSQLID+"~"+
							it.EXECUTIONS+"~"+it.BUFFER_GETS_LAST_WEEK+"~"+
							it.BUFFER_GETS_TODAY+"~"+it.BUFFER_GETS_YESTERDAY+"~"+
							v_module+"~"+v_action+"~"+v_program+"~"+v_line+"~"+v_sql_text )
						
				opdb_dbConn.executeUpdate("Update ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT SET PURGE_FLAG = 'N' WHERE SQL_ID = ? AND DATABASE_NAME = ?", [sSQLID, databaseName])

			}
			
			writeToFile(Globals.workspace,databaseName+"-IO-SQL",".dat",myList)

			// PURGE SECTION
			info "-> Purge SNAPSHOT"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT "+
			"WHERE SNAP_ID <= (SELECT MAX(SNAP_ID) FROM  ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?) - 200 AND DATABASE_NAME = ?",[ databaseName, databaseName])

			info "-> Purge SYSMETRIC_SUMMARY"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SYSMETRIC_SUMMARY "+
			"WHERE SNAP_ID NOT IN (SELECT SNAP_ID FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?)AND DATABASE_NAME = ?",[ databaseName, databaseName])

			info "-> Purge SQLSTAT"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SQLSTAT "+
			"WHERE SNAP_ID NOT IN (SELECT SNAP_ID FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?) AND DATABASE_NAME = ?",[ databaseName, databaseName])

			info "-> Purge SQLTEXT"
			opdb_dbConn.executeUpdate("delete from ACN_PERF_TOOL.ACN_PERF_HIST_SQLTEXT where database_name = ? and purge_flag = 'Y'",[ databaseName ]);

			info "-> Purge SYSSTAT"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_SYSSTAT "+
			"WHERE SNAP_ID NOT IN (SELECT SNAP_ID FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?)AND DATABASE_NAME = ?",[ databaseName, databaseName])

			info "-> Purge LIBRARYCACHE"
			opdb_dbConn.executeUpdate("DELETE FROM ACN_PERF_TOOL.ACN_PERF_HIST_LIBRARYCACHE "+
			"WHERE SNAP_ID NOT IN (SELECT SNAP_ID FROM ACN_PERF_TOOL.ACN_PERF_HIST_SNAPSHOT WHERE DATABASE_NAME = ?)AND DATABASE_NAME = ?",[ databaseName, databaseName])
		
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
