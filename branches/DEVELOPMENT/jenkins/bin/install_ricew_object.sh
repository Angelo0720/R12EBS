#!/bin/bash
# Author: Bjorn Erik Hoel, Accenture
# Date: 2014-May-27
# Purpose: Dynamically construct the installation entries for the system


#########################################################################
# CONFIGURABLE PARAMETERS
#########################################################################
# Pointer to the file holding all RICEW
RICEW_MASTER_LIST=${RICEW_MASTER_LIST:-scripts/RICEW_MASTER_LIST.dat}
RICEW_TO_INSTALL=${RICEW_TO_INSTALL}
TYPES_TO_PROCESS=""
FAIL_ON_MISSING_FILE="${FAIL_ON_MISSING_FILE:-N}"
PROTOCOL="${PROTOCOL:-https}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
USE_RICEW_MANAGER="${USE_RICEW_MANAGER:-false}"
STOP_ON_MISSING_SCM_FILE="${STOP_ON_MISSING_SCM_FILE:-false}"
ERP_MANAGER_DB_HOST="${ERP_MANAGER_DB_HOST:-localhost}"
ERP_MANAGER_DB_PORT="${ERP_MANAGER_DB_PORT:-5432}"
#########################################################################
function info
{
  logutil_log_file="${LOG_FILE:-/dev/null}"
  echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][INFO] $*" | tee -a "$logutil_log_file"
}

function warning
{
  logutil_log_file="${LOG_FILE:-/dev/null}"
  # Logging to logfile, standard err and SYSLOG whenever errors occur
  LOG_LINE="$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][WARNING] $*"
  echo "$LOG_LINE" >> $logutil_log_file

  if [ ! $TERM ] || [ "$TERM" = "dumb" ]; then
    echo "$LOG_LINE" >&2
    if [ "$LOG_TO_SYSLOG" = "Y" ]; then
      logger -t $PROGNAME -p warn "$*"
    fi
  else
    if [ $(basename $SHELL) = "bash" ] || [ $(basename $SHELL) = "ksh" ]; then
      printf '\033[1;33;40m%s\033[0m\n' "$LOG_LINE" >&2
    else
      echo "$LOG_LINE" >&2
    fi
  fi
}

function error
{
  logutil_log_file="${LOG_FILE:-/dev/null}"
  # Logging to logfile, standard err and SYSLOG whenever errors occur
  LOG_LINE="$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][ERROR] $*"
  echo "$LOG_LINE" >> $logutil_log_file

  if [ ! $TERM ] || [ "$TERM" = "dumb" ]; then
    echo "$LOG_LINE" >&2
    if [ "$LOG_TO_SYSLOG" = "Y" ]; then
      logger -t $PROGNAME -p err "$*"
    fi
  else
    if [ $(basename $SHELL) = "bash" ] || [ $(basename $SHELL) = "ksh" ]; then
      printf '\033[1;31;40m%s\033[0m\n' "$LOG_LINE" >&2
    else
      echo "$LOG_LINE" >&2
    fi
  fi
}

function debug
{
  logutil_log_file="${LOG_FILE:-/dev/null}"
  if [ "$LOG_LEVEL" = "DEBUG" ]; then
      echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][DEBUG] $*" | tee -a "$logutil_log_file"
  fi

}


function check_retval
{
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		echo "CRITICAL ERROR: ABORTING"
		exit $RETVAL
	fi
}

function generate_header
{
	HEADER_TYPE=$1

	####################################
	# Section for generating FND
	####################################
	if [ "${HEADER_TYPE}" = "FND" ]; then
		if [ ${FND_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '#!/bin/bash
PROGRAM_NAME="xxcu_upload_dynamic_fnd"
. xxcu_fndutil.sh
set_fnd_direction UPLOAD
set_nls_languages "US"
do_login apps

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export FND_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating XDO
	####################################
	if [ "${HEADER_TYPE}" = "XDO" ]; then
		if [ ${XDO_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '#!/bin/bash
PROGRAM_NAME="xxcu_upload_dynamic_xdo"

. $XXCU_TOP/bin/xxcu_xdoutil.sh      # Basic xdoload functionality
. $XXCU_TOP/bin/xxcu_fndutil.sh      # Basic fndload functionality

########################################################################################
#                               CONFIGURE THIS RUN                           	       #
########################################################################################
# Always force user to specify password
export ASK_PASSWORD="N"
# Require either UPLOAD or DOWNLOAD of files in the below load-statements

# Verify parameter
if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]
then
	export XXCU_DIRECTION="$1"
else
	verify_direction
fi

# Configure XDOLOAD utility
if [ "$UTIL_DIRECTION" = "" ]; then
	set_fnd_direction $XXCU_DIRECTION
	set_xdo_direction $XXCU_DIRECTION
fi

# Calling this function will extract both US version of setup respectively
set_nls_languages "US"
# Can be a list of languages too, in which case it will generate ldt files for any list of languages, ie:
# set_nls_languages "D NL CHS US"
########################################################################################

# Verify apps login
do_login apps

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export XDO_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating FORM
	####################################
	if [ "${HEADER_TYPE}" = "FORM" ]; then
		if [ ${FORM_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '#!/bin/bash
. $XXCU_TOP/bin/xxcu_installutil.sh

do_login apps

# Will control FORMS_PATH structure
set_forms_language "US"

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export FORM_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating WORKFLOW
	####################################
	if [ "${HEADER_TYPE}" = "WORKFLOW" ]; then
		if [ ${WORKFLOW_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '#!/bin/bash
. $XXCU_TOP/bin/xxcu_installutil.sh
do_login apps

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			debug "1: WORKFLOW_GENERATED_FLAG=${WORKFLOW_GENERATED_FLAG}"
			export WORKFLOW_GENERATED_FLAG=1
			debug "2: WORKFLOW_GENERATED_FLAG=${WORKFLOW_GENERATED_FLAG}"

		fi
	fi

	####################################
	# Section for generating DB
	####################################
	if [ "${HEADER_TYPE}" = "DB" ]; then
		if [ ${DB_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			> ${DYNAMIC_SCRIPT_NAME}

			export DB_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating OAF
	####################################
	if [ "${HEADER_TYPE}" = "OAF" ]; then
		if [ ${OAF_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '#!/bin/bash
PROGRAM_NAME=xxcu_install_dynamic_oaf

export DATA_STAGING_DIR="${XXCU_TOP}/admin/config/OAF/"

. ${XXCU_TOP}/bin/xxcu_oafutil.sh
. ${XXCU_TOP}/bin/xxcu_mdsutil.sh

export JDEV_TOP=${XXCU_TOP}/jdev
export OAFUTILTOP=${XXCU_TOP}/jdev

export OAF_JAVAC=javac
export OAF_JAVAC_OPTIONS="-encoding iso-8859-1 -cp ${JDEV_TOP}/myprojects:${JAVA_TOP}:${CLASSPATH} -d ${JAVA_TOP}"

########################################################################################
#                               CONFIGURE THIS RUN                           	       #
########################################################################################
# Require either UPLOAD or DOWNLOAD of files in the below load-statements
set_mds_direction $1

# Verify apps login
do_login apps


' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export OAF_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating REPORT
	####################################
	if [ "${HEADER_TYPE}" = "REPORT" ]; then
		if [ ${REPORT_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export REPORT_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating CUSTOM_TOP
	####################################
	if [ "${HEADER_TYPE}" = "CUSTOM_TOP" ]; then
		if [ ${CUSTOM_TOP_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export CUSTOM_TOP_GENERATED_FLAG=1

		fi
	fi

	####################################
	# Section for generating COMMON_TOP
	####################################
	if [ "${HEADER_TYPE}" = "COMMON_TOP" ]; then
		if [ ${COMMON_TOP_GENERATED_FLAG} -eq 0 ]; then
			info "Creating ${DYNAMIC_SCRIPT_NAME}"

			echo '

' > "${DYNAMIC_SCRIPT_NAME}"
			chmod u+x "${DYNAMIC_SCRIPT_NAME}"
			export COMMON_TOP_GENERATED_FLAG=1

		fi
	fi
	####################################

}

function set_file_name
{
	TYPE=$1
	RICEW_ID=$2

	if [ "${TYPE}" = "FND" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_upload_dynamic_fnd.sh.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "XDO" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_upload_dynamic_xdo.sh.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "DB" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_upload_dynamic.aifo.${RICEW_ID}"
	fi
	if [ "${TYPE}" = "FORM" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_forms.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "COMMON_TOP" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_files.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "CUSTOM_TOP" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_files.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "OAF" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_oaf.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "WORKFLOW" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_workflow.${RICEW_ID}"
	fi

	if [ "${TYPE}" = "REPORT" ]; then
		DYNAMIC_SCRIPT_NAME="xxcu_install_dynamic_reports.${RICEW_ID}"
	fi

	debug "DYNAMIC_SCRIPT_NAME=${DYNAMIC_SCRIPT_NAME}"
} # set_file_name

LAST_PRE_COMMAND=""

function append_entry
{

	R_ID="$1"
	TYPE="$2"
	INST_CMD="$3"
	PRE_CMD="$4"

	set_file_name ${TYPE} ${DYNAMIC_FILE_EXTENSION}
	generate_header $TYPE
	if [ "${LAST_PRE_COMMAND}" != "${PRE_CMD}" ]; then
		echo "$PRE_CMD" >> ${DYNAMIC_SCRIPT_NAME}
		LAST_PRE_COMMAND=$PRE_CMD
	fi
	echo "$INST_CMD" >> ${DYNAMIC_SCRIPT_NAME}

} # append_entry

# One code block per RICEW type
# Set COPY_FILE=1 if you need to move a file to app server (Not relevant for DB objects)
function transfer_files
{
	TYPE="$1"
	R_ID="$2"
	COPY_FILE=0
	RUN_JOB=0
	set_file_name "${TYPE}" "${DYNAMIC_FILE_EXTENSION}"

	###########################################################################
	# DEFAULT LOCATION (Change in below sections for custom source location
	###########################################################################
	TARGET_LOCATION="${XXCU_TOP}/bin/"

	##################################
	# FND SECTION
	##################################
	if [ "${TYPE}" = "FND" ]; then
		if [ -f "${DYNAMIC_SCRIPT_NAME}" ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"

			debug "Appending tail of file"
			echo '
############################
# Framework Exit
############################
exit $FND_ERROR_FLAG
' >> $DYNAMIC_SCRIPT_NAME


			COPY_FILE=1
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 FND Files"
		fi
	fi

	##################################
	# OAF SECTION
	##################################
	if [ "${TYPE}" = "OAF" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=1
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 OAF Files"
		fi
	fi

	##################################
	# WORKFLOW SECTION
	##################################
	if [ "${TYPE}" = "WORKFLOW" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=1
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 Workflows"
		fi
	fi
	##################################
	# REPORT SECTION
	##################################
	if [ "${TYPE}" = "REPORT" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=0
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 Reports"
		fi
	fi
	##################################
	# CUSTOM_TOP SECTION
	##################################
	if [ "${TYPE}" = "CUSTOM_TOP" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=0
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install XXCU_TOP Files"
		fi
	fi
	##################################
	# COMMON_TOP SECTION
	##################################
	if [ "${TYPE}" = "COMMON_TOP" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=0
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install COMMON_TOP files"
		fi
	fi
	##################################
	# FORM SECTION
	##################################
	if [ "${TYPE}" = "FORM" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=1
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 Forms and libraries"
		fi
	fi
	##################################
	# XDO SECTION
	##################################
	if [ "${TYPE}" = "XDO" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			COPY_FILE=1
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 XDO Files"
		fi
	fi
	##################################
	# DB SECTION
	##################################
	if [ "${TYPE}" = "DB" ]; then
		if [ -f ${DYNAMIC_SCRIPT_NAME} ]; then
			debug "Found ${DYNAMIC_SCRIPT_NAME} to transfer"
			RUN_JOB=1
			JOB_NAME="${DATABASE_NAME} - Install R12 Database Objects"

			# DB AIFO files are also staged on a common location on Jenkins server
			mkdir -p ${JENKINS_HOME}/install
			cp "${DYNAMIC_SCRIPT_NAME}" ${JENKINS_HOME}/install/
		fi
	fi
	##################################

	if [ $COPY_FILE -eq 1 ]; then
		debug "Synchronizing ${DYNAMIC_SCRIPT_NAME} -> ${SHELL_TARGET}:${TARGET_LOCATION}"
		info "Synchronizing ${DYNAMIC_SCRIPT_NAME}"
		rsync -a "${DYNAMIC_SCRIPT_NAME}" "${SHELL_TARGET}:$TARGET_LOCATION"
	fi

	debug "GENERATE_MASTER_FILES_ONLY=${GENERATE_MASTER_FILES_ONLY}"
	if [ "${GENERATE_MASTER_FILES_ONLY}" = "false" ]; then
		if [ $RUN_JOB -eq 1 ]; then
			run_job "${JOB_NAME}"
		fi
	fi
} # transfer_files

function install_ricew
{

	DB_GENERATED_FLAG=0
	FND_GENERATED_FLAG=0
	FORM_GENERATED_FLAG=0
	WORKFLOW_GENERATED_FLAG=0
	XDO_GENERATED_FLAG=0
	OAF_GENERATED_FLAG=0
	REPORT_GENERATED_FLAG=0
	CUSTOM_TOP_GENERATED_FLAG=0
	COMMON_TOP_GENERATED_FLAG=0


	CURRENT_RICEW="$1"
	info "Processing $CURRENT_RICEW"

	GREP_STRING="^$CURRENT_RICEW"
	DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.$CURRENT_RICEW"
	if [ "$CURRENT_RICEW" = "ALL" ]; then
		GREP_STRING="~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_DB" ]; then
		GREP_STRING="~DB~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_FND" ]; then
		GREP_STRING="~FND~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_XDO" ]; then
		GREP_STRING="~XDO~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_FORM" ]; then
		GREP_STRING="~FORM~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_REPORT" ]; then
		GREP_STRING="~REPORT~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_OAF" ]; then
		GREP_STRING="~OAF~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_WORKFLOW" ]; then
		GREP_STRING="~WORKFLOW~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_COMMON_TOP" ]; then
		GREP_STRING="~COMMON_TOP~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

	if [ "$CURRENT_RICEW" = "ALL_CUSTOM_TOP" ]; then
		GREP_STRING="~CUSTOM_TOP~"
		DYNAMIC_FILE_EXTENSION="${RICEW_APPLICATION}.ALL"
	fi

    if [ "$USE_RICEW_MANAGER" = "true" ]; then
        info "Connecting to database and fetching RICEW master"
        RICEW_MASTER_LIST="acn_erp_manager_ricew_master.dat"
        echo "
select r.ricew_name,rt.type_master_name
,rt.directory_name||'/'||rc.file_name
,rc.install_command,rc.pre_install_command
from ricew r
, ricewcomponent rc
, erpapplication a
, ricewcomponent_type rt
where r.id = rc.ricew_id
and r.erp_app_id = a.id
and rc.component_type_id = rt.id
and a.application_name = '${RICEW_APPLICATION}'
and rc.enabled = true
and r.enabled = true
and rt.enabled = true
order by CASE
	WHEN rc.file_name LIKE '%LOOKUP%' THEN 1
	WHEN rc.file_name LIKE '%VALUESET%' THEN 2
	WHEN rc.file_name LIKE '%DESCFLEX%' THEN 3
	WHEN rc.file_name LIKE '%FORMFUNCTION%' THEN 4
	WHEN rc.file_name LIKE '%MESSAGE%' THEN 5
	WHEN rc.file_name LIKE '%MENU%' THEN 6
	WHEN rc.file_name LIKE '%RESP%' THEN 7
	WHEN rc.file_name LIKE '%FRMPER%' THEN 8
	WHEN rc.file_name LIKE '%PROFOPT%' THEN 9
	WHEN rc.file_name LIKE '%PRNT%' THEN 10
	WHEN rc.file_name LIKE '%CP%' THEN 11
	WHEN rc.file_name LIKE '%REQSETS%' THEN 12
	WHEN rc.file_name LIKE '%REQGROUP%' THEN 13
	WHEN rc.file_name LIKE '%ALERT%' THEN 14
	WHEN rc.file_name LIKE '%AUDGRP%' THEN 15
	ELSE 100 END,
rc.sequence_number, rc.id
;
" | psql -h ${ERP_MANAGER_DB_HOST} -p ${ERP_MANAGER_DB_PORT} -U acn_erp_manager --no-align -t -F '~' > $RICEW_MASTER_LIST
        info "Completed"
    fi

	debug "DOS2UNIX: ${RICEW_MASTER_LIST}"
	awk '{ sub("\r$", ""); print }' ${RICEW_MASTER_LIST} > ${RICEW_MASTER_LIST}.unix


	TYPES_TO_PROCESS=$(cat "${RICEW_MASTER_LIST}.unix" | sed 's/\\/\//g' | grep -v '^#' | grep "${GREP_STRING}" | cut -d~ -f2 | sort -u)
	debug "TYPES_TO_PROCESS: $TYPES_TO_PROCESS"

	cat "${RICEW_MASTER_LIST}.unix" | sed 's/\\/\//g' | grep "${GREP_STRING}" | grep -v '^#' |  while read file_line
	do

		RICEW_ID="$(echo $file_line | cut -d~ -f1)"
		check_retval
		RICEW_TYPE="$(echo $file_line | cut -d~ -f2)"
		check_retval
		SCM_PATH="$(echo $file_line | cut -d~ -f3)"
		check_retval
		INSTALL_COMMAND="$(echo $file_line | cut -d~ -f4)"
		check_retval
		PRE_COMMAND="$(echo $file_line | cut -d~ -f5)"
		check_retval

		if [ ! -f "./$SCM_PATH" ]; then
            if [ "${STOP_ON_MISSING_SCM_FILE}" == "false" ]; then
                warning "Unable to find: '$SCM_PATH' Skipping...."
            else
                debug "STOP_ON_MISSING_SCM_FILE=true change it to alter this behavior"
                error "Unable to find: '$SCM_PATH' Aborting."
                exit 1
            fi
		else
			debug "RICEW ID:			${RICEW_ID}"
			debug "RICEW_TYPE:			${RICEW_TYPE}"
			debug "SCM_PATH:			${SCM_PATH}"
			debug "Install Command:		${INSTALL_COMMAND}"
			debug "Pre Command:			${PRE_COMMAND}"
			debug "-------------------------------------------------------------------------------------"

			append_entry "${RICEW_ID}" "${RICEW_TYPE}" "${INSTALL_COMMAND}" "${PRE_COMMAND}"
		fi

	done

	for R_TYPE in $TYPES_TO_PROCESS; do
		transfer_files "${R_TYPE}" "${RICEW_TO_INSTALL}"
	done

} # install_ricew


function run_job
{
	info "Submitting $1 for script: $DYNAMIC_SCRIPT_NAME"
	# Replace spaces with %20 for HTTP request
	#JOB_NAME=$(echo "$1" | sed 's/ /%20/g')
	debug "JOB_NAME=${JOB_NAME}"

	if [ "$TYPE" = "FND" ]; then
		PARAMS="buildWithParameters?EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
        NPARAMS="-p EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
	fi

	if [ "$TYPE" = "XDO" ]; then
		PARAMS="buildWithParameters?EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
		NPARAMS="-p EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
	fi

	if [ "$TYPE" = "FORM" ]; then
		PARAMS="buildWithParameters?EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
		NPARAMS="-p EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
	fi

	if [ "$TYPE" = "DB" ]; then
		PARAMS="buildWithParameters?TARGET_AIFO_FILE=${JENKINS_HOME}/install/${DYNAMIC_SCRIPT_NAME}"
		NPARAMS="-p TARGET_AIFO_FILE=${JENKINS_HOME}/install/${DYNAMIC_SCRIPT_NAME}"
	fi

	if [ "$TYPE" = "WORKFLOW" ]; then
		PARAMS="buildWithParameters?EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
		NPARAMS="-p EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
	fi

	if [ "$TYPE" = "OAF" ]; then
		PARAMS="buildWithParameters?EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
		NPARAMS="-p EXECUTION_SCRIPTNAME=\"${DYNAMIC_SCRIPT_NAME}\""
	fi

	if [ "$TYPE" = "REPORT" ]; then
		PARAMS="build"
		NPARAMS=""
	fi

	if [ "$TYPE" = "COMMON_TOP" ]; then
		PARAMS="build"
		NPARAMS=""
	fi
	if [ "$TYPE" = "CUSTOM_TOP" ]; then
		PARAMS="build"
		NPARAMS=""
	fi
	JENKINS_URL="${PROTOCOL}://localhost:${JENKINS_PORT}//job/${JOB_NAME}/${PARAMS}"
	debug "java -jar /var/lib/jenkins/jenkins-cli.jar -f -s ${PROTOCOL}://localhost:${JENKINS_PORT}/ build \"${JOB_NAME}\" ${NPARAMS}"
    CERT_CHECK_STR=""
    if [ "${PROTOCOL}" = "https" ]; then
        CERT_CHECK_STR="-noCertificateCheck"
    fi
    java -jar /var/lib/jenkins/jenkins-cli.jar ${CERT_CHECK_STR} -s ${PROTOCOL}://localhost:${JENKINS_PORT}/ build "${JOB_NAME}" -s ${NPARAMS}
    RETCODE=$?
    info "########################################## CONSOLE OUTPUT BEGIN #######################################################"
    java -jar /var/lib/jenkins/jenkins-cli.jar ${CERT_CHECK_STR} -s ${PROTOCOL}://localhost:${JENKINS_PORT}/ console "${JOB_NAME}" -f
    info "########################################### CONSOLE OUTPUT END ########################################################"

    if [ $RETCODE -eq 0 ]; then
        info "Successful execution"
    else
        error "Failed. Aborting execution"
        exit 1
    fi


    #curl -X POST $JENKINS_URL --insecure --user ${JENKINS_USER}:${JENKINS_API_TOKEN}

} # run_job

install_ricew ${RICEW_TO_INSTALL}

# OBJECTS_TO_INSTALL="$(cat ${RICEW_MASTER_LIST} | grep "^${RICEW_TO_INSTALL}~") | sort -u"
