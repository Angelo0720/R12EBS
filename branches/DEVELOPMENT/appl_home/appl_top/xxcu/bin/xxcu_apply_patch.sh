#!/bin/bash

. $XXCU_TOP/bin/xxcu_scriptutil.sh
. $XXCU_TOP/bin/xxcu_logutil.sh

function check_retval
{
        RETVAL=$?
        if [ $RETVAL -ne 0 ]; then
				cat $APPL_TOP/admin/$TWO_TASK/log/$LOG_FILE
                error "Command failed (Returned: $RETVAL) Aborting..."
                exit 1
        fi
}

BASE_URL="https://getupdates.oracle.com/all_unsigned"

if [ $# -ne 1 ]; then
        error "Usage: $0 <Patch-ZipFile-Name>"
        error "Example: $0 p17675571_R12.GME.B_R12_GENERIC.zip"
        exit 1
fi

ZIP_FILENAME="$1"

if [ "$APPLY_PATCH" = "true" ]; then
	APPLY_TEXT=""
else
	APPLY_TEXT="apply=no"
fi 

if [ "$MOS_HTTP_USER" = "" ]; then
        error "MOS_HTTP_USER environment variable is not set"
        exit 1
fi

if [ "$MOS_HTTP_PASSWORD" = "" ]; then
        error "MOS_HTTP_PASSWORD environment variable is not set"
        exit 1
fi

mkdir -p "$XXCU_TOP/patch"
cd "$XXCU_TOP/patch"

wget --no-check-certificate --http-user="$MOS_HTTP_USER" --http-passwd="$MOS_HTTP_PASSWORD" "${BASE_URL}/${ZIP_FILENAME}" -O "${ZIP_FILENAME}"

BASE_NAME=$(basename ${ZIP_FILENAME} .zip)
unzip -o ${ZIP_FILENAME} -d ${BASE_NAME}

cd ${BASE_NAME}
cd *

pwd

DRIVER_FILE=$(basename $(find . -name "*.drv" | head -1) )

LOG_FILE="$(basename $(find . -name "*.drv") .drv).log"

> $APPL_TOP/admin/$TWO_TASK/log/$LOG_FILE

adpatch ${APPLY_TEXT} workers=48 defaultsfile=$APPL_TOP/admin/$TWO_TASK/adalldefaults.txt  logfile=$LOG_FILE restart=n patchtop=$(pwd) driver=$DRIVER_FILE options=hotpatch
check_retval
