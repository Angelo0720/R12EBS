#!/bin/bash
##########################################
# Author: Bjørn Erik Hoel, Accenture ANS #
# Date:   09.Nov.2007                    #
# Name:   xxcu_scriptutil.sh             #
##########################################

###########################
# Configurable parameters
###########################
# Will not ask for password if password file exists, and is readable for user
export ASK_PASSWORD=${ASK_PASSWORD:-"N"}

export TWO_TASK=${TWO_TASK:-$ORACLE_SID}

function verify_password
{
    if [ $# -lt 2 ] || [ $# -gt 3 ]; then
		error "Usage: verify_password user password [service]"
		return 2
    fi
    if [ $# -eq 2 ]; then
		RESULT=`echo "" | $ORACLE_HOME/bin/sqlplus -s $1/$2`
    else
		RESULT=`echo "" | $ORACLE_HOME/bin/sqlplus -s $1/$2@$3`
    fi
    if [ "$RESULT" = "" ]; then
		#user logged in with no errors
		return 0
    fi

    # If the supplied password is correct, but insufficient privileges:
    # ERROR: ORA-28009: connection to sys should be as sysdba or sysoper
    # In addition, the following error always occur:
    # ERROR: ORA-01017: invalid username/password; logon denied
    # If any other error occurs, then something else is wrong.
    if [ `echo "$RESULT" | grep -v 'ORA-01017' | grep -v 'ORA-28009' | grep 'ORA-' | wc -l` -ne 0 ]; then
		error "SQL*Plus ERROR: $RESULT"
		return 2
    fi
    if [ `echo "$RESULT" | grep 'ORA-28009' | wc -l` -eq 0 ]; then
		echo "Invalid password, please retry."
		error "Invalid password, please retry."
		sleep 1
		return 1
    fi
    unset RESULT
    return 0
}

function get_password
{
  if [ $# -ne 2 ]; then
    error "Usage: get_password prompt passwordVariable"
    return 1
  fi
  prompt=$1
  passwordVariable=$2
  if (tty > /dev/null); then
    # Prompt user and wait for password
    #      an empty line before the prompt attracts the user :-)
    echo > /dev/tty
    echo -e "${prompt} \c" > /dev/tty
    trap "stty echo > /dev/null; exit 1" HUP INT TERM TSTP 
    stty -echo > /dev/null
    read $passwordVariable
    stty echo > /dev/null
    trap HUP INT TERM TSTP
    echo > /dev/tty
  else
    # Password must be provided on standard input
    read $passwordVariable
  fi
  #echo ${passwordVariable}
  unset passwordVariable
}

function do_login
{
  pwd_username=$(echo $1 | tr '[:upper:]' '[:lower:]')
  PASSWD_FILE="$HOME/.secure/$(hostname).${pwd_username}"
  if [ "$ASK_PASSWORD" = "N" ] && [ -f $PASSWD_FILE ]; then
	password=$(cat $PASSWD_FILE)
	chmod go= ${PASSWD_FILE}
	ASKED_FLAG=0
  else  
	get_password "Enter $pwd_username password for ${TWO_TASK}: " password
	ASKED_FLAG=1
  fi
  bDone=0
  bCounter=0
  while [ $bDone -eq 0 ]; do
    bCounter=$(expr $bCounter + 1)
	if [ $bCounter -gt 3 ]; then
		error "Giving up"
		exit 1
	fi
	
    verify_password $pwd_username "$password" $TWO_TASK
    if [ $? -eq 0 ]; then
      bDone=1
    else
	  sleep 1
	  if [ $ASKED_FLAG -eq 1 ]; then
        get_password "Re-enter $pwd_username password for ${TWO_TASK}: " password
	  else
	    get_password "Enter $pwd_username password for ${TWO_TASK}: " password
	  fi
    fi 
  
  done

  APPS_LOGIN="$pwd_username/$password@${TWO_TASK}"
  APPS_PASSWD="$password"

}

function send_mail
{
	MAIL_TO=${1}
	#echo "$MAIL_TO"
	SUBJECT=${2}
	#echo "$SUBJECT"
	MESSAGE=${3}
  MAIL_FOOTER="${4:-##################################################################

This is an automatically generated e-mail.

##################################################################
}"
  IMPORTANCE_FLAG=${5}
  FROM_NAME="${6:-svn@$(hostname)}"
  
  if [ "$IMPORTANCE_FLAG" = "HIGH" ]; then
    IMPORTANCE_TEXT="X-Priority: 1
Priority: Urgent
Importance: high
"
  elif [ "$IMPORTANCE_FLAG" = "LOW" ]; then
    IMPORTANCE_TEXT="X-Priority: 5 (Lowest)
"
  else
    IMPORTANCE_TEXT=""       
  fi

  TMPFILE=/tmp/xxcu_scriptutil_send_mail.tmp.$$
  SENDMAIL_CMD=/usr/sbin/sendmail
	
	echo "Sending mail"
	if [ "$MAIL_TO" != "" ]; then
    echo "Sending email for $SUBJECT to $MAIL_TO" 
cat >> ${TMPFILE} << EOF
To:${MAIL_TO}
From:${FROM_NAME}
Subject:${SUBJECT}
${IMPORTANCE_TEXT}${MESSAGE}
${MAIL_FOOTER}

EOF

    ${SENDMAIL_CMD} -t < ${TMPFILE}
    rm ${TMPFILE}
  else
  	echo "No recipient found - Email not sent!"
	fi
}


function sqlCommandPipe
{
    connstr=$1

    if [ $# -eq 0 ]; then
        error "sqlCommandPipe: argument missing"
        exit 1
    fi
    #set -e
    result=`(cat <<EOF; cat) | (sqlplus -s $connstr) 2>&1
set echo off
set verify off
set feedback off
set heading  off
set pagesize 0
set linesize 10000
EOF
`
   # Error handling
    status=$?
    echo "$result"
    if [ $status -ne 0 ] || [ "`echo "$result" | grep 'ORA-'`" != "" ]; then
        warning "sqlCommandPipe: Command pipe returned exit code $status and text: $result"
        exit 1
    fi
}
