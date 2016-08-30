#!/bin/bash

. $XXCU_TOP/bin/xxcu_scriptutil.sh
. $XXCU_TOP/bin/xxcu_logutil.sh

do_login apps
	
function check_retval
{
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		error "Command failed (Returned: $RETVAL) Aborting..."
		exit 1
	fi
}

info "Stopping Appstier"
$ADMIN_SCRIPTS_HOME/adstpall.sh $APPS_LOGIN

info "Waiting for processes to be stopped"
USER_ID=$(id | cut -d"(" -f1 | cut -d"=" -f2)

bWaiting="TRUE"
while [ $bWaiting = "TRUE" ]; do
	NUM_PROCS=$(ps -ef | grep ^${USER_ID} | grep -v xxcu | grep -v CLONE | grep -v sshd | grep -v "ps -ef" | grep -v "grep" | grep -v " sh" | grep -v "bash" | grep -v Xvnc | grep -v vncconfig | grep -v ' ssh ' | grep -v ' twm'| grep -v xterm | grep -v sleep | grep -v '/ccr/bin/nmz' | wc -l)
	
	if [ $NUM_PROCS -lt 2 ]; then
		bWaiting="FALSE"
	else
		info "Still $NUM_PROCS processes running."
		sleep 10
	fi
done



