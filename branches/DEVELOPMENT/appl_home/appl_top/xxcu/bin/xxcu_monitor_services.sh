#!/bin/bash

. $XXCU_TOP/bin/xxcu_scriptutil.sh
. $XXCU_TOP/bin/xxcu_logutil.sh

# ASK_PASSWORD is set to Y to enforce password prompt for this script
# Use that in environment calling this script if you want only DBA authorized calls of this
do_login apps

function check_retval
{
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		error "Command failed (Returned: $RETVAL) Aborting..."
		exit 1
	fi
}

GLOBAL_RETCODE=0
MAIL_BODY=""

function check_service_components
{
	FIND_SERVICE_COMPONENT_STATUS=$(echo "
	set pages 1000
	set lines 400
	set trimspool on
	set heading off
	set feedback off
	select RPAD(COMPONENT_NAME,50,' ')||COMPONENT_STATUS from FND_SVC_COMPONENTS
	WHERE COMPONENT_STATUS NOT IN ('RUNNING','NOT_CONFIGURED');

	" | sqlCommandPipe $APPS_LOGIN)

	WC=$(echo $FIND_SERVICE_COMPONENT_STATUS | wc -c)
	debug "WC for FIND_SERVICE_COMPONENT_STATUS is: $WC"
	if [ $WC -gt 10 ]; then
		MSG="One or more configured service components are down, please ensure they are running"
		MAIL_BODY="${MAIL_BODY}
$MSG
${FIND_SERVICE_COMPONENT_STATUS}
---------------------------------------------
	"
		error "${MSG}"
		echo "${FIND_SERVICE_COMPONENT_STATUS}"
		GLOBAL_RETCODE=1
	fi

}

function check_tablespaces
{

	DB_STATUS=$(echo "
	set pages 1000
	set lines 400
	set trimspool on
	set heading off
	set feedback off
		select RPAD(tablespace_name,50,' ')||MB_USED||'MB used - '||MB_ALLOCATED||'MB allocated' 
		from (
		select a.tablespace_name, MB_USED, MB_ALLOCATED
		from (
		select tablespace_name, sum(bytes/(1024*1024) ) as MB_USED
		from dba_segments
		group by tablespace_name
		) a
		, 
		( select tablespace_name, ROUND(sum(DECODE(autoextensible,'YES',maxbytes,bytes)/(1024*1024) ),1) as MB_ALLOCATED
		from dba_data_files
		group by tablespace_name
		) b
		, dba_tablespaces c
		where a.tablespace_name = b.tablespace_name
		and a.tablespace_name = c.tablespace_name
		and c.contents = 'PERMANENT'
		)
		where (mb_allocated - mb_used) / mb_allocated < 0.05 ;

	" | sqlCommandPipe $APPS_LOGIN)

	WC=$(echo $DB_STATUS | wc -c)
	debug "WC for DB_STATUS is: $WC"
	if [ $WC -gt 10 ]; then
		MSG="One or more tablespaces are approaching full state"
		MAIL_BODY="${MAIL_BODY}
$MSG
${DB_STATUS}
---------------------------------------------
	"
		error "${MSG}"
		echo "${DB_STATUS}"
		GLOBAL_RETCODE=1
	fi



}

function check_processes
{

	DB_STATUS=$(echo "
	set pages 1000
	set lines 400
	set trimspool on
	set heading off
	set feedback off
SELECT 'Warning: Number of processes in INST_ID: '||inst_id||' is '||proc_count||' (Max: '||value||') Have DBA team increase processes init parameter'
from (
SELECT CURR_PROC.inst_id, proc_count, MAX_PROC.value
from (
select inst_id, count(1) proc_count from gv\$process
group by inst_id
) CURR_PROC
, (
select inst_id, value 
from gv\$parameter
where name = 'processes'
) MAX_PROC
WHERE CURR_PROC.INST_ID = MAX_PROC.INST_ID
AND PROC_COUNT > MAX_PROC.VALUE * 0.8
);

	" | sqlCommandPipe $APPS_LOGIN)

	WC=$(echo $DB_STATUS | wc -c)
	debug "WC for DB_STATUS is: $WC"
	if [ $WC -gt 10 ]; then
		MSG="Processes is running high"
		MAIL_BODY="${MAIL_BODY}
$MSG
${DB_STATUS}
---------------------------------------------
	"
		error "${MSG}"
		echo "${DB_STATUS}"
		GLOBAL_RETCODE=1
	fi

}

function check_flashback
{

	DB_STATUS=$(echo "
	set pages 1000
	set lines 400
	set trimspool on
	set heading off
	set feedback off
select 'Oldest Flashback Point is less than 0.5 days, it might not be functioning properly'
from (
select sysdate - OLDEST_FLASHBACK_TIME as retention_days FROM V\$FLASHBACK_DATABASE_LOG
)
where retention_days < 0.5
UNION ALL
select 'Flashback database is off' FROM V\$DATABASE WHERE FLASHBACK_ON = 'NO';

	" | sqlCommandPipe $APPS_LOGIN)

	WC=$(echo $DB_STATUS | wc -c)
	debug "WC for DB_STATUS is: $WC"
	if [ $WC -gt 10 ]; then
		MSG="Issue with Flashback Mechanism"
		MAIL_BODY="${MAIL_BODY}
$MSG
${DB_STATUS}
---------------------------------------------
	"
		error "${MSG}"
		echo "${DB_STATUS}"
		GLOBAL_RETCODE=1
	fi





}

function check_parameters 
{


	DB_STATUS=$(echo "
	set pages 1000
	set lines 400
	set trimspool on
	set heading off
	set feedback off
	select 'Instance started without spfile' from v\$parameter where name = 'spfile' and value is null;
	" | sqlCommandPipe $APPS_LOGIN)

	WC=$(echo $DB_STATUS | wc -c)
	debug "WC for DB_STATUS is: $WC"
	if [ $WC -gt 10 ]; then
		MSG="Issue with parameters"
		MAIL_BODY="${MAIL_BODY}
$MSG
${DB_STATUS}
---------------------------------------------
	"
		error "${MSG}"
		echo "${DB_STATUS}"
		GLOBAL_RETCODE=1
	fi

}


check_service_components

check_tablespaces

check_processes

check_parameters

check_flashback

if [ $GLOBAL_RETCODE -ne 0 ]; then
	MSG="One or more monitoring checks failed. Please review"	
	error "${MSG}"
	MAIL_BODY="$MAIL_BODY
$MSG
---------------------------------------------
"

	if [ "$NOTIFY_MAIL" != "" ]; then
		info "Sending mail to $NOTIFY_MAIL"
		echo "$MAIL_BODY" | mailx -s "Monitoring failed for $TWO_TASK" "$NOTIFY_MAIL"
	fi
fi

exit $GLOBAL_RETCODE
