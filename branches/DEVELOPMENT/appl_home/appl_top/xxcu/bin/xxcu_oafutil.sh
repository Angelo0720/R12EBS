#!/bin/bash
# $Id: xxcu_oafutil.sh 2227 2014-02-28 16:10:57Z johan.almqvist $
##########################################
# Author: Johan Almqvist, Accenture ANS  #
# Date:   20.Feb.2008                    #
# Name:   xxcu_oafutil.sh                #
# Changelog:                             #
# March 7, 2016: Bjorn Hoel, rewritten   #
##########################################
. $XXCU_TOP/bin/xxcu_logutil.sh      # Basic logging functionality
. $XXCU_TOP/bin/xxcu_scriptutil.sh   # Basic script functionality
. $XXCU_TOP/bin/xxcu_installutil.sh  # Functionality to detect changes

function oaf_init
{
  CURRENT_TYPE="$1"
  CURRENT_NAME="$2"
  CURRENT_DESC="$3"
  WHO="$4"
  export OAF_UTIL_FILE="${CURRENT_NAME}"
  export OAF_UTIL_DIRECTORY="$(dirname "${OAF_UTIL_FILE}")"

  info "##############################################"
  info "# OAF Util $CURRENT_TYPE"
  info "##############################################"
  info "# Name: $CURRENT_NAME"
  info "# Desc: $CURRENT_DESC"
  info "# Registered by: $WHO"

  cd "${XXCU_TOP}/admin/config/OAF/"
}

function oaf_handle_retval
{
  if [ $? -ne 0 ]; then
    error "-> OAF UTIL STEP FAILED, output of last command is:"
    error "${DEBUG_OUTPUT}"
    exit 1
  else
    debug "${DEBUG_OUTPUT}"
    registerProcessedChange "$MDSUTIL_FILENAME"
  fi
}

#############################
#### Java                ####
#############################
function oaf_compilejava
{
	oaf_init "Compile Java" "$1" "$2" "$3"
	# Compile Java files to a separate folder structure under $JDEV_TOP
    debug "Creating directory: ${JAVA_TOP}/${OAF_UTIL_DIRECTORY}"
    mkdir -p "${JAVA_TOP}/${OAF_UTIL_DIRECTORY}"

    detectChange "${OAF_UTIL_FILE}"
    if [ $DETECT_FLAG -eq 1 ]; then

        # Temporary fix for .class files
        # If a .class file is sent to this function, just copy it to the target instead of compiling it
        BN_CLASS=$(basename "${OAF_UTIL_FILE}" .class)
        BN=$(basename "${OAF_UTIL_FILE}")
        if [ "${BN}" == "${BN_CLASS}" ]; then
            # We don't ahve a classfile, compile it:
            info "javac -d '${JAVA_TOP}' '${OAF_UTIL_FILE}'"
        	DEBUG_OUTPUT="$(javac -d "${JAVA_TOP}" "$OAF_UTIL_FILE")"
        else
            # We have a .class file copy it
            info "Copying .class file to JAVA_TOP directory: $OAF_UTIL_DIRECTORY"
            cp -f "$XXCU_TOP/admin/config/OAF/$OAF_UTIL_FILE" "$JAVA_TOP/$OAF_UTIL_DIRECTORY"
        fi
        oaf_handle_retval
    	info "##############################################"
    fi
}
