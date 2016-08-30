#!/bin/ksh
##########################################
# Author: Bjørn Erik Hoel, Accenture ANS #
# Date:   09.Nov.2007                    #
# Name:   xxcu_logutil.sh                #
##########################################

LOG_TO_SYSLOG=${LOG_TO_SYSLOG:-N}
PROGNAME=$(basename $0 .sh)

# Initialize the DB_NAME
LOGUTIL_DB_NAME="${TWO_TASK:-$ORACLE_SID}"
if [ "$LOGUTIL_DB_NAME" != "" ]; then
	LOGUTIL_DB_NAME="[$LOGUTIL_DB_NAME]"
else
	LOGUTIL_DB_NAME=""
fi  


function info
{
  logutil_log_file=${LOG_FILE:-/dev/null}
  LOG_UTIL_USE_STDERR=${LOG_UTIL_USE_STDERR:-"N"}
  if [ "$LOG_UTIL_USE_STDERR" = "Y" ]; then
	echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME]${LOGUTIL_DB_NAME}[INFO] $*" | tee -a $logutil_log_file >&2
  else	
    echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME]${LOGUTIL_DB_NAME}[INFO] $*" | tee -a $logutil_log_file
  fi
}

function warning
{
  logutil_log_file=${LOG_FILE:-/dev/null}
  # Logging to logfile, standard err and SYSLOG whenever errors occur
  LOG_LINE="$(date +"%Y%m%d %H:%M:%S") [$PROGNAME]${LOGUTIL_DB_NAME}[WARNING] $*" 
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
  LOG_LINE="$(date +"%Y%m%d %H:%M:%S") [$PROGNAME]${LOGUTIL_DB_NAME}[ERROR] $*" 
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
      echo "$(date +"%Y%m%d %H:%M:%S") [$PROGNAME]${LOGUTIL_DB_NAME}[DEBUG] $*" | tee -a $logutil_log_file
  fi

}

