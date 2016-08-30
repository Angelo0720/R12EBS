#!/bin/bash
############################################
# Author: Bj�rn Erik Hoel, Accenture       #
# Date:   2012-APR-07                      #
# Name:   xxcu_extract_dynamic_fnddata.sh  #
############################################

PROGRAM_NAME=`basename $0 .sh`
EXPORT_LANGUAGE="${EXPORT_LANGUAGE:-US}"

if [ $# -lt 2 ]; then
	echo "Usage: $0 <Data Staging Directory> <Shell Script Entry 1> [Shell Script Entry 2] [Shell Script Entry 3] [Shell Script Entry 4] [Shell Script Entry 5] "
	exit 1
fi

########################################################################################
#                               CONFIGURE THIS RUN                           	         #
########################################################################################
# Dynamically place files extracted for this job in a unique folder
export DATA_STAGING_DIR="$1"
export SCRIPT_ENTRY_1="$2"
export SCRIPT_ENTRY_2="$3"
export SCRIPT_ENTRY_3="$4"
export SCRIPT_ENTRY_4="$5"
export SCRIPT_ENTRY_5="$6"

. xxcu_fndutil.sh

# Require either UPLOAD or DOWNLOAD of files in the below load-statements
set_fnd_direction DOWNLOAD

# Calling this function will extract both US version of setup respectively
set_nls_languages "${EXPORT_LANGUAGE}"
# Can be a list of languages too, in which case it will generate any list of languages, ie:
# set_nls_languages "D NL ZHS US"
########################################################################################

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
info "Executing: $SCRIPT_ENTRY_2"
eval $SCRIPT_ENTRY_2
info "Executing: $SCRIPT_ENTRY_3"
eval $SCRIPT_ENTRY_3
info "Executing: $SCRIPT_ENTRY_4"
eval $SCRIPT_ENTRY_4
info "Executing: $SCRIPT_ENTRY_5"
eval $SCRIPT_ENTRY_5
