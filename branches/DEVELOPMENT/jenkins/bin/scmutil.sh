#!/bin/bash
# The purpose of this script utility is to abstract the chosen SCM tool of
# a client, so that any need to interact with files via source code control
# tool command line client happens via this utility
#

# Currently implemented types: SVN, MERCURIAL
export EBS_ACCELERATOR_SCM_TOOL="${EBS_ACCELERATOR_SCM_TOOL:-"SVN"}"

export SCM_USER="${SCM_USER:-oebs_r12_extract}"
export SCM_PASSWORD="${SCM_PASSWORD:-oebs_r12_extract}"
export SCM_NEEDS_LOCK="${SCM_NEEDS_LOCK:-'false'}"

LOG_TO_SYSLOG=${LOG_TO_SYSLOG:-"N"}
PROGNAME="scmutil"
PROGVERSION=0.1

function info
{
  logutil_log_file=${LOG_FILE:-/dev/null}
  echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][INFO] $*" | tee -a $logutil_log_file
}

function warning
{
  logutil_log_file=${LOG_FILE:-/dev/null}
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
  logutil_log_file=${LOG_FILE:-/dev/null}
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
  logutil_log_file=${LOG_FILE:-/dev/null}
  if [ "$LOG_LEVEL" = "DEBUG" ]; then
      echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME][DEBUG] $*" | tee -a $logutil_log_file
  fi

}

debug "EBS_ACCELERATOR_SCM_TOOL=${EBS_ACCELERATOR_SCM_TOOL}"
if [ "${EBS_ACCELERATOR_SCM_TOOL}" == "SVN" ]; then
    debug "Setting up SCM commands for Subversion"
    export SCM_BASE_CMD="svn"
    export SCM_CMD="${SCM_BASE_CMD} --username $SCM_USER --password $SCM_PASSWORD --no-auth-cache"
    export SCM_DEBUG_CMD="${SCM_BASE_CMD} --username $SCM_USER --password ******* --no-auth-cache"
    export SCM_PATH=${SCM_PATH:-""}
    export SCM_PUSH_COMMAND=""
    export SCM_ADD_COMMAND="${SCM_BASE_CMD} add"
    export SCM_STATUS_COMMAND="${SCM_BASE_CMD} status"

elif [ "${EBS_ACCELERATOR_SCM_TOOL}" == "MERCURIAL" ]; then
    debug "Setting up SCM commands for Mercurial"
    export HGUSER=${SCM_USER}
    export SCM_BASE_CMD="hg"
    export SCM_CMD="${SCM_BASE_CMD} --verbose"
    export SCM_DEBUG_CMD="${SCM_BASE_CMD} --verbose"
    export SCM_PATH=${SCM_PATH:-""}
    export SCM_PUSH_COMMAND="$SCM_CMD push ${SCM_PROTOCOL}://${SCM_USER}:${SCM_PASSWORD}@${SCM_HOST}:${SCM_PORT}"
    export SCM_ADD_COMMAND="${SCM_BASE_CMD} add"
    export SCM_STATUS_COMMAND="${SCM_BASE_CMD} status"

fi

function scm_status
{
    ${SCM_STATUS_COMMAND} $*
}

# Add SCM specific variations to allow the commit of a change to the repo
function scm_commit
{

    SCM_LOCAL_DIR="$1"
    SCM_COMMIT_COMMENT="$2"
    debug "scm_commit: Committing $SCM_LOCAL_DIR"
    SCM_CURR_DIR="$(pwd)"
    cd "${SCM_LOCAL_DIR}"

    info "Commit files back with $SCM_COMMIT_COMMENT"
    debug "${SCM_DEBUG_CMD} commit -m '${SCM_COMMIT_COMMENT}'"
    ${SCM_CMD} commit -m "${SCM_COMMIT_COMMENT}"

    if [ "${SCM_PUSH_COMMAND}" != "" ]; then
        info "Pushing files back to source repository"
        ${SCM_PUSH_COMMAND}
    fi

    cd "${SCM_CURR_DIR}"
}

# Add SCM specific variations to allow the ADD of a file to the repo
function scm_add
{
    debug "Adding $*"
    ${SCM_ADD_COMMAND} $* 2>/dev/null

    if [ "${SCM_NEEDS_LOCK}" == "true" ]; then
        if [ "${EBS_ACCELERATOR_SCM_TOOL}" == "SVN" ]; then
            info "Adding svn:needs-lock to file"
            svn propset svn:needs-lock '*' $* >/dev/null 2>&1
        fi
        if [ "${EBS_ACCELERATOR_SCM_TOOL}" == "MERCURIAL" ]; then
            warn "Pessimistic locking not implemented for ${EBS_ACCELERATOR_SCM_TOOL}"
        fi
    fi
}

function scm_set_file_executable
{
    filename=$1
    debug "scm_set_file_executable: $filename"
    if [ "${EBS_ACCELERATOR_SCM_TOOL}" == "SVN" ]; then
        info "Adding svn:executable to file"
        svn propset svn:executable '*' $* >/dev/null 2>&1
    elif [ "${EBS_ACCELERATOR_SCM_TOOL}" == "MERCURIAL" ]; then
        chmod $filename +x
    fi
}
