#!/bin/bash

# SVN Command
export SCRIPT_DIR="$(pwd)"

export FAILED_FLAG=0

# Source the SCM utility depending on where we are running from
if [ -f ./scmutil.sh ]; then
    . scmutil.sh
elif [ -f ./jenkins/bin/scmutil.sh ]; then
    . ./jenkins/bin/scmutil.sh
elif [ -f ./jenkins/scmutil.sh ]; then
    . ./jenkins/scmutil.sh
elif [ -f ./scripts/scmutil.sh ]; then
    . ./scripts/scmutil.sh
fi

# on any returned errors exit
set -o errexit

PROGNAME=${0##*/}
PROGVERSION=0.1

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
  echo "$LOG_LINE" >> "$logutil_log_file"

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
  echo "$LOG_LINE" >> "$logutil_log_file"

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

function promote_file
{
	promote_file_name=$(echo "$1" | sed 's/\\/\//g')
	# Remove trailing and leading spaces
	promote_file_name=$(echo "$promote_file_name" | sed 's/ *$//g')
	promote_file_name=$(echo "$promote_file_name" | sed 's/^ *//g')
	info "Promoting [${promote_file_name}]"
	debug "Issuing: cp -rf '$SOURCE_BASE_NAME/${promote_file_name}' '$TARGET_BASE_NAME/${promote_file_name}'"
	cp -f "$SOURCE_BASE_NAME/${promote_file_name}" "$TARGET_BASE_NAME/${promote_file_name}"
	if [ $? -ne 0 ]; then
		error "Promotion failed... exiting"
		FAILED_FLAG=1
		exit 1
	fi

	debug "Add new files"
	debug "$SVN_CMD_DEBUG add '$TARGET_BASE_NAME/${promote_file_name}'"
	$SVN_CMD add "$TARGET_BASE_NAME/${promote_file_name}" 2>/dev/null
	debug "Adding svn:needs-lock to file"
	svn propset svn:needs-lock '*' "$TARGET_BASE_NAME/${promote_file_name}" >/dev/null 2>&1
	# See if the executable property is set for this file, and if so set it on the target file as well
	EXEC_FLAG=$(svn propget svn:executable "$SOURCE_BASE_NAME/${promote_file_name}")
	if [ "$EXEC_FLAG" != "" ]; then
		debug "Adding svn:executable to files"
		svn propset svn:executable '*' "$TARGET_BASE_NAME/${promote_file_name}" >/dev/null 2>&1
	fi

}

echo "##############################################################################"
echo "# $PROGNAME Started"
echo "##############################################################################"



usage()
{
echo "Usage: $PROGNAME [options]

Options:

 -h
--help
  Gives this helping text.

-v
--version
  Gives script version.

--source-dir <BASE DIR TO BRANCH>

--target-dir <BASE DIR TO BRANCH>

--commit-comment <Comment associated with the commit>
  Alternative: Use environment variable PF_COMMIT_COMMENT

Usage example
   promoteFilesAndCommit.sh \\
      --source-dir dev_branch_dir \\
      --target-dir qa_branch_dir \\
      --promote-ricew ricewname \\
      --commit-comment \"Some comment about the files being added\"
"
}

# If any remaining arguments remain, exit 1
if [ $# -eq 0 ] ; then
   usage
   FAILED_FLAG=1
   exit 1
fi


# Short parameters list for getopt
# Not in use in this script
SHORTOPTS="vh"

# Long/named parameters list for getopt
LONGOPTS="version,help,source-dir:,target-dir:,promote-ricew:,commit-comment:"

# getopt is uses for long named parameters
ARGS=$(getopt -s bash -o $SHORTOPTS --long $LONGOPTS --name $PROGNAME -- "$@" )

eval set -- "$ARGS"

# Test for parameters and set argument
while true; do
   case $1 in
      -v|--version)
         echo "$PROGVERSION"
         exit 0
         ;;
      -h|--help)
         usage
         exit 0
         ;;
      --source-dir)
         shift
         PF_SOURCE_DIR="$1"
         debug "Command line argument --source-dir '$PF_SOURCE_DIR' assigned to variable PF_SOURCE_DIR"
         ;;
      --target-dir)
         shift
         PF_TARGET_DIR="$1"
         debug "Command line argument --target-dir '$PF_TARGET_DIR' assigned to variable PF_TARGET_DIR"
         ;;
      --promote-ricew)
         shift
         PF_PROMOTE_RICEW="$1"
         debug "Command line argument --promote-ricew '$PF_PROMOTE_RICEW' assigned to variable PF_PROMOTE_RICEW"
         ;;
      --commit-comment)
         shift
         PF_COMMIT_COMMENT="$1"
         debug "Command line argument --commit-comment '$PF_COMMIT_COMMENT' assigned to variable PF_COMMIT_COMMENT"
         ;;
      --)
         shift
         break
         ;;
      *)
         shift
         error "$PROGNAME: unknown argument '$1'"
		 FAILED_FLAG=1
       exit 1
         ;;
   esac
   shift
done

# If any remaining arguments remain, exit 1
if [ "$*" ] ; then
   error "$PROGNAME: remaining unknown argument '$*'"
   FAILED_FLAG=1
   exit 1
fi

# Check all mandatory arguments.
debug "PF_PROMOTE_RICEW=$PF_PROMOTE_RICEW"

MISSING_ARGUMENT=false
if [ "$PF_PROMOTE_RICEW" = "" ]; then
   error "$PROGNAME: variable PF_PROMOTE_RICEW must be set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ "$PF_SOURCE_DIR" = "" ] ; then
   error "$PROGNAME: variable PF_SOURCE_DIR not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ "$PF_TARGET_DIR" = "" ] ; then
   error "$PROGNAME: variable PF_TARGET_DIR not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ "$PF_COMMIT_COMMENT" = "" ] ; then
   error "$PROGNAME: variable PF_COMMIT_COMMENT not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if $MISSING_ARGUMENT ; then
   error "$PROGNAME: one or more arguments are missing"
   FAILED_FLAG=1
   exit 1
fi

GREP_STRING="${PF_PROMOTE_RICEW}"

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
WHEN rc.file_name LIKE 'LOOKUP%' THEN 1
WHEN rc.file_name LIKE 'VALUESET%' THEN 2
WHEN rc.file_name LIKE 'DESCFLEX%' THEN 3
WHEN rc.file_name LIKE 'FORMFUNCTION%' THEN 4
WHEN rc.file_name LIKE 'MESSAGE%' THEN 5
WHEN rc.file_name LIKE 'MENU%' THEN 6
WHEN rc.file_name LIKE 'RESP%' THEN 7
WHEN rc.file_name LIKE 'FRMPER%' THEN 8
WHEN rc.file_name LIKE 'PROFOPT%' THEN 9
WHEN rc.file_name LIKE 'PRNT%' THEN 10
WHEN rc.file_name LIKE 'CP%' THEN 11
WHEN rc.file_name LIKE 'REQSETS%' THEN 12
WHEN rc.file_name LIKE 'REQGROUP%' THEN 13
WHEN rc.file_name LIKE 'ALERT%' THEN 14
WHEN rc.file_name LIKE 'AUDGRP%' THEN 15
ELSE 100 END,
rc.sequence_number, rc.id
;
" | psql --user acn_erp_manager --no-align -t -F '~' > $RICEW_MASTER_LIST
info "Completed"

debug "DOS2UNIX: ${RICEW_MASTER_LIST}"
awk '{ sub("\r$", ""); print }' ${RICEW_MASTER_LIST} > ${RICEW_MASTER_LIST}.unix


TYPES_TO_PROCESS=$(cat "${RICEW_MASTER_LIST}.unix" | sed 's/\\/\//g' | grep -v '^#' | grep "${GREP_STRING}" | cut -d~ -f2 | sort -u)
debug "TYPES_TO_PROCESS: $TYPES_TO_PROCESS"
info "-------------------------------------------------------------------------------------"
cat "${RICEW_MASTER_LIST}.unix" | sed 's/\\/\//g' | grep "${GREP_STRING}" | grep -v '^#' |  while read file_line
do

    SCM_PATH="$(echo $file_line | cut -d~ -f3)"

    if [ ! -f "${PF_SOURCE_DIR}/${SCM_PATH}" ]; then
        if [ "${STOP_ON_MISSING_SCM_FILE}" == "false" ]; then
            warning "Unable to find: '$SCM_PATH' Skipping...."
        else
            debug "STOP_ON_MISSING_SCM_FILE=true change it to alter this behavior"
            error "Unable to find: '$SCM_PATH' Aborting."
            exit 1
        fi
    else
        info "Promoting: ${SCM_PATH}"

        DIR_NAME="$(dirname "$SCM_PATH")"
        mkdir -p "${PF_TARGET_DIR}/${DIR_NAME}"
        cp -f "${PF_SOURCE_DIR}/${SCM_PATH}" "${PF_TARGET_DIR}/${SCM_PATH}"
        scm_add "${PF_TARGET_DIR}/${SCM_PATH}"
    fi

done
info "-------------------------------------------------------------------------------------"
scm_commit "${PF_TARGET_DIR}" "${PF_COMMIT_COMMENT}"
