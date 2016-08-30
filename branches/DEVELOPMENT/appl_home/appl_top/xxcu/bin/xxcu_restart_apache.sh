#!/bin/bash

. $XXCU_TOP/bin/xxcu_scriptutil.sh
. $XXCU_TOP/bin/xxcu_logutil.sh

# ASK_PASSWORD is set to Y to enforce password prompt for this script
# Use that in environment calling this script if you want only DBA authorized calls of this

if [ "$ASK_PASSWORD" = "Y" ]; then
	do_login apps
fi
	
function check_retval
{
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		error "Command failed (Returned: $RETVAL) Aborting..."
		exit 1
	fi
}

if [ "$CLEAR_CACHE" = "Y" ]; then
	info "Clearing Cache"
	cd $FND_TOP/patch/115/bin/
	perl ojspCompile.pl --compile --flush -p 5
fi

# Recompile recently changed jsps
FILES_TO_RECOMPILE="$(find $OA_HTML -type f -name '*.jsp' -mtime -3 -exec basename {} \;)"

NUM_FILES=$(echo "$FILES_TO_RECOMPILE" | wc -l)

info "Recompiling $NUM_FILES recently changed jsp: $jsp_file"
COUNTER=1
for jsp_file in $FILES_TO_RECOMPILE; do
	info "Compiling $COUNTER / $NUM_FILES [$jsp_file]...."
	cd $FND_TOP/patch/115/bin/
	perl ojspCompile.pl --flush --compile -s "$jsp_file"
	COUNTER=$(expr $COUNTER + 1)
done

info "Stopping Apache"
$ADMIN_SCRIPTS_HOME/adapcctl.sh stop

info "Stopping OA Core Services"
$ADMIN_SCRIPTS_HOME/adoacorectl.sh stop

info "Sleeping 10 seconds"
sleep 10
info "Starting OA Core Services"
$ADMIN_SCRIPTS_HOME/adoacorectl.sh start
check_retval
info "Starting Apache"
$ADMIN_SCRIPTS_HOME/adapcctl.sh start
check_retval

