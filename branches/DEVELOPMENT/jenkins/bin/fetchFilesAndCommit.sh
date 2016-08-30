#!/bin/bash

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

--target <user@host>
  Is the username and host/IP address the files will be distributed to.
  Remember the target host already has to be set up with the correct public
  key.
  Alternative: Use environment variable PF_TARGET

--target-dir <absolute path on target server>
  Absolute root path on source.
  Alternative: Use environment variable PF_TARGET_DIR

--commit-target <Full SVN URL for folder to commit files to>
  Note: This folder will be checked out
  Alternative: Use environment variable PF_COMMIT_TARGET

--commit-comment <Comment associated with the commit>
  Alternative: Use environment variable PF_COMMIT_COMMENT

Usage example
   fetchFilesAndCommit \\
      --target <user>@<hostname> \\
      --target-dir \"/tmp/jenkins_build_10\" \\
      --commit-target \"https://hostname/svn/repo/OEBS/branches/DEVELOPMENT/appl_home/appl_top/xxcu/admin/config/FNDLOAD/\" \\
      --commit-comment \"Some comment about the files being added\"
"
}

# If any remaining arguments remain, exit 1
if [ $# -eq 0 ] ; then
   usage
   exit 1
fi


# Short parameters list for getopt
# Not in use in this script
SHORTOPTS="vh"

# Long/named parameters list for getopt
LONGOPTS="help,target:,target-dir:,commit-target:,commit-comment:"

# getopt is uses for long named parameters
ARGS=$(getopt -s bash -o $SHORTOPTS --long $LONGOPTS --name $PROGNAME -- "$@" )

eval set -- "$ARGS"

debug "Environment variable: PF_TARGET='${PF_TARGET}'"
debug "Environment variable: PF_TARGET_DIR='${PF_TARGET_DIR}'"
debug "Environment variable: PF_COMMIT_TARGET='${PF_COMMIT_TARGET}'"
debug "Environment variable: PF_COMMIT_COMMENT='${PF_COMMIT_COMMENT}'"
debug "Environment variable: PF_APPS_PASSWORD='"`echo $PF_APPS_PASSWORD|wc -w`"'"

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
      --target)
         shift
         PF_TARGET="$1"
         debug "Command line argument --target '$PF_TARGET' assigned to variable PF_TARGET"
         ;;
      --target-dir)
         shift
         PF_TARGET_DIR="$1"
         debug "Command line argument --target-dir '${PF_TARGET_DIR}' assigned to variable PF_TARGET_DIR"
         ;;
      --commit-target)
         shift
         PF_COMMIT_TARGET="$1"
         debug "Command line argument --commit-target '$PF_COMMIT_TARGET' assigned to variable PF_COMMIT_TARGET"
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
       exit 1
         ;;
   esac
   shift
done

# If any remaining arguments remain, exit 1
if [ "$*" ] ; then
   error "$PROGNAME: remaining unknown argument '$*'"
   exit 1
fi

# Check all mandatory arguments.
MISSING_ARGUMENT=false
if [ -z $PF_TARGET ] ; then
   error "$PROGNAME: variable PF_TARGET not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ -z ${PF_TARGET_DIR} ] ; then
   error "$PROGNAME: variable PF_TARGET_DIR not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ -z $PF_COMMIT_TARGET ] ; then
   error "$PROGNAME: variable PF_COMMIT_TARGET not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi
if [ "$PF_COMMIT_COMMENT" = "" ] ; then
   error "$PROGNAME: variable PF_COMMIT_COMMENT not set, please set environment variable or add argument to script"
   MISSING_ARGUMENT=true
fi

if $MISSING_ARGUMENT ; then
   error "$PROGNAME: one or more arguments are missing"
   exit 1
fi

debug "Clean up from previous runs and ensure an empty directory is ready to receive files"

WORKSPACE_DIR="$(pwd)"
debug "Workspace Directory: ${WORKSPACE_DIR}"
LOCAL_WORK_DIRECTORY="/tmp/ebs_accelerator_fetchedFiles_$$"
debug "Local Working Directory: ${LOCAL_WORK_DIRECTORY}"

debug "Cleaning out $LOCAL_WORK_DIRECTORY"
mkdir -p ${LOCAL_WORK_DIRECTORY}
rm -rf ${LOCAL_WORK_DIRECTORY}
mkdir -p ${LOCAL_WORK_DIRECTORY}

info "Fetching Files from $PF_TARGET:${PF_TARGET_DIR}"
rsync -mr "$PF_TARGET:${PF_TARGET_DIR}/*" "${LOCAL_WORK_DIRECTORY}/"

info "Adding file metadata to RICEW Manager if applicable"
cd "${LOCAL_WORK_DIRECTORY}"
FILES="$(find . -type f)"
for f in $FILES; do
    info "Processing '$f'"
    # Look for metadata tags
    METADATA_APPLICATION=$(cat "$f" | grep '~RICEW_APPLICATION~' | cut -d~ -f3)
    METADATA_RICEW=$(cat "$f" | grep '~RICEW_EXTRACTED~' | cut -d~ -f3)
    METADATA_CMDLINE=$(cat "$f" | grep '~RICEW_CMDLINE~' | cut -d~ -f3)
    METADATA_PRE_CMDLINE=$(cat "$f" | grep '~RICEW_PRE_INSTALL_COMMAND~' | cut -d~ -f3)
    METADATA_COMPONENT_TYPE=$(cat "$f" | grep '~RICEW_COMPONENT_TYPE~' | cut -d~ -f3)
    debug "METADATA_APPLICATION: $METADATA_APPLICATION"
    debug "METADATA_RICEW: $METADATA_RICEW"
    debug "METADATA_CMDLINE: $METADATA_CMDLINE"
    debug "METADATA_PRE_CMDLINE: $METADATA_PRE_CMDLINE"
    debug "METADATA_COMPONENT_TYPE: $METADATA_COMPONENT_TYPE"

    echo "
insert into ricewcomponent(id, version, component_type_id,enabled,file_name,install_command,last_updated_by,ricew_id,sequence_number,pre_install_command)
select nextval('hibernate_sequence')
, 0
, (select id from ricewcomponent_type where type_name = '${METADATA_COMPONENT_TYPE}')
, true
, '$f'
, '$METADATA_CMDLINE'
, 'jenkins'
, (select id from ricew where ricew_name = '${METADATA_RICEW}' and erp_app_id = (select id from erpapplication where application_name = '${METADATA_APPLICATION}'))
, (select coalesce(max(sequence_number),0) + 10 from ricewcomponent where component_type_id = (select id from ricewcomponent_type where type_name = '${METADATA_COMPONENT_TYPE}'))
, '${METADATA_PRE_CMDLINE}'
 where not exists (select 'x' from ricewcomponent where file_name = '$f' and ricew_id = (select id from ricew where ricew_name = '${METADATA_RICEW}' and erp_app_id = (select id from erpapplication where application_name = '${METADATA_APPLICATION}')));
    "| psql --user acn_erp_manager

    debug "Removing ~RICEW metadata entries from file"
    cat "$f" | grep -v '# ~RICEW_' > "$f.new"
    mv "$f.new" "$f"
    info "Done processing $f"

done

cd "${WORKSPACE_DIR}"

debug "Copying from staging to final area"
rsync -mr "${LOCAL_WORK_DIRECTORY}/" "${PF_COMMIT_TARGET}"

info "Add new directories and files in ${PF_COMMIT_TARGET}"
cd "${PF_COMMIT_TARGET}/"
ITEMS_TO_ADD="$(scm_status | grep ^? | cut -d' ' -f2-)"

for i in $ITEMS_TO_ADD; do
    scm_add "$i"
done

cd "${WORKSPACE_DIR}"
scm_commit "${PF_COMMIT_TARGET}" "${PF_COMMIT_COMMENT}"

info "Completed"
