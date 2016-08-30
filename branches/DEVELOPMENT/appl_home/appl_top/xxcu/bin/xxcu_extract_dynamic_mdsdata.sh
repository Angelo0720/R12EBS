#!/bin/bash
############################################
# Author: Bjørn Erik Hoel, Accenture       #
# Date:   2016-FEB-08                      #
# Name:   xxcu_extract_dynamic_mdsdata.sh  #
############################################


PROGRAM_NAME=`basename $0 .sh`

if [ $# -lt 2 ]; then
	echo "Usage: $0 <Data Staging Directory> <Shell Script Entry 1>" 
	exit 1
fi

########################################################################################
#                               CONFIGURE THIS RUN                           	         #
########################################################################################
# Dynamically place files extracted for this job in a unique folder
export DATA_STAGING_DIR="$1"
export SCRIPT_ENTRY_1="$2"

# Source after setting DATA_STAGING_DIR
. $XXCU_TOP/bin/xxcu_mdsutil.sh

# Require either UPLOAD or DOWNLOAD of files in the below load-statements
set_mds_direction DOWNLOAD

# Verify apps login
do_login apps

info "Files for this run will be placed in: $DATA_STAGING_DIR"

TMP_FLAG=$(echo "${DATA_STAGING_DIR}" | cut -d/ -f2)
debug "TMP_FLAG=$TMP_FLAG"
if [ "$TMP_FLAG" = "tmp" ]; then
	if [ -d "$DATA_STAGING_DIR" ]; then
		debug "Cleaning up temporary directory"
		find "$DATA_STAGING_DIR/" -name "*.ldt" -type f -exec rm {} \; 
	fi
fi

info "Executing: $SCRIPT_ENTRY_1"
eval $SCRIPT_ENTRY_1
