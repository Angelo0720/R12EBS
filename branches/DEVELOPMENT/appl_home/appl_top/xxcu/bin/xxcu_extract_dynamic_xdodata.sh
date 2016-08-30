#!/bin/bash
############################################
# Author: Bjørn Erik Hoel, Accenture       #
# Date:   2012-MAY-03                      #
# Name:   xxcu_extract_dynamic_xdodata.sh  #
############################################

PROGRAM_NAME=`basename $0 .sh`

if [ $# -ne 3 ]; then
	echo "Usage: $0 <Shell Script Entry> <Data Staging Directory> <XDO_LANGUAGE>" 
	exit 1
fi

########################################################################################
#                               CONFIGURE THIS RUN                           	         #
########################################################################################
# Dynamically place files extracted for this job in a unique folder
export SCRIPT_ENTRY="$1"
export XDO_STAGING_DIR="$2"
export P_XDO_LANGUAGES="$3"

. xxcu_logutil.sh      # Basic logging functionality
. xxcu_scriptutil.sh   # Basic script functionality
. xxcu_xdoutil.sh      # Basic xdoload functionality

# Verify apps login
if [ "$APPS_PASSWD" = "" ]
then
	do_login apps
	APPS_PASSWD=$APPS_PASSWD
fi
set_xdo_direction DOWNLOAD

info "Files for this run will be placed in: $DATA_STAGING_DIR"

set_xdo_languages "$P_XDO_LANGUAGES"

info "Executing: $SCRIPT_ENTRY"
eval $SCRIPT_ENTRY

