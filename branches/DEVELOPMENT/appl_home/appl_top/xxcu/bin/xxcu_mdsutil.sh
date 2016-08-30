#!/bin/bash
# $Id: xxcu_mdsutil.sh 2227 2014-02-28 16:10:57Z johan.almqvist $
##########################################
# Author: Johan Almqvist, Accenture ANS  #
# Date:   12.Feb.2008                    #
# Name:   xxcu_mdsutil.sh                #
##########################################
. $XXCU_TOP/bin/xxcu_logutil.sh      # Basic logging functionality
. $XXCU_TOP/bin/xxcu_scriptutil.sh   # Basic script functionality
. $XXCU_TOP/bin/xxcu_installutil.sh  # Functionality to detect changes

#-----------------------------------------------------------------------------
# Changelog:
# 2012-03-12 - Stian Indal Haugseth
#   - Added debug statements
# 16-Mar-2014 : Daniel Rodil
#   - modified function mds_ul_pers to use JDEV_TOP/myprojects
#
#-----------------------------------------------------------------------------
# When DOWNLOADING this is set to something else, when UPLOADING it is fetched relative to $JAVA_TOP
DATA_STAGING_DIR=${DATA_STAGING_DIR:-$XXCU_TOP/admin/config/OAF}
RICEW_COMPONENT_TYPE=${RICEW_COMPONENT_TYPE:-"OAFLOAD"}
SKIP_NEXT_MAPPING="false"

function get_mds_tnsstring
{
        MDS_TNS_STRING=`perl -e 'my $read = undef;
                my $parcount = 0;
                my $string = "";
                my $twotask = $ENV{"TWO_TASK"};

                die "TWO_TASK not set" unless (defined $twotask);

                open TNSNAMES, $ENV{"TNS_ADMIN"}."/tnsnames.ora" || die "Could not open tnsnames.ora";

                while (<TNSNAMES>) {
                        if (/(\s*$twotask\s*=)(.*)$/ || $read) {
                                if ($2 && !$read) {$_ = $2;}
                                elsif ($1 && !$read) {$_ = "";};
                                foreach $char (split //) {
                                        if ($char =~ /\s/) {next;};
                                        if ($char eq "(") {$parcount++;};
                                        if ($char eq ")") {$parcount--;};
                                        # if ($char eq "=") {next;};
                                        $string = $string . $char;
                                        if (1 > $parcount && $read) {print $string; close TNSNAMES; exit;}
                                }
                                # There is no true in perl :-)
                                $read = 1==1;
                        }
                }

                die "No entry matching $twotask found in tnsnames.ora"'`
}

function verify_mds_direction
{
  if [ "$MDSUTIL_DIRECTION" = "" ]; then
    error "-> Set direction by calling set_mds_direction with either 'UPLOAD' or 'DOWNLOAD'"
        exit 1
  fi
}

function set_mds_direction
{
  if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]; then
        export MDSUTIL_DIRECTION="$1"
  else
        error "Usage: $0 <UPLOAD|DOWNLOAD>"
        exit 1
  fi
}

function skip_next_mapping
{
    info "Skipping mapping of ID's for this specific run"
    SKIP_NEXT_MAPPING="true"
}

function map_internal_user
{
  USER_NAME="$1"
  FULL_PATH="$2"
  debug "Attempting to map USER: $USER_NAME"
  INTERNAL_ID=$(echo "
SELECT USER_ID FROM FND_USER WHERE USER_NAME = '$USER_NAME';
" | sqlCommandPipe $APPS_LOGIN)

  debug "Internal ID: '$INTERNAL_ID'"
  if [ "$INTERNAL_ID" != "" ]; then
    INTERNAL_ID=$(expr $INTERNAL_ID + 0)
    export CURRENT_NAME_INTERNAL="$(echo "${CURRENT_NAME}" | sed "s/${USER_NAME}/${INTERNAL_ID}/")"
  else
    error "Unable to map user: $USER_NAME in this database. Please ensure it exists before attempting to load this MDS"
    exit 1
  fi
}

function map_internal_org
{
    ORG_CODE="$1"
    FULL_PATH="$2"
    debug "Attempting to map ORG: $ORG_CODE"
    INTERNAL_ID=$(echo "
        select ORGANIZATION_ID from HR_OPERATING_UNITS WHERE SHORT_CODE='$ORG_CODE';
  " | sqlCommandPipe $APPS_LOGIN)

    debug "Internal ID: '$INTERNAL_ID'"
    if [ "$INTERNAL_ID" != "" ]; then
      INTERNAL_ID=$(expr $INTERNAL_ID + 0)
      export CURRENT_NAME_INTERNAL="$(echo "${CURRENT_NAME}" | sed "s/${ORG_CODE}/${INTERNAL_ID}/")"
    else
      error "Unable to map ORG: $ORG_CODE in this database. Please ensure it exists before attempting to load this MDS"
      exit 1
    fi

}

function map_internal_resp
{
  RESP_KEY="$1"
  FULL_PATH="$2"
  debug "Attempting to map RESP: $RESP_KEY"
  INTERNAL_ID=$(echo "
SELECT RESPONSIBILITY_ID FROM FND_RESPONSIBILITY WHERE RESPONSIBILITY_KEY = '$1';
" | sqlCommandPipe $APPS_LOGIN)

  debug "Internal ID: '$INTERNAL_ID'"
  if [ "$INTERNAL_ID" != "" ]; then
    INTERNAL_ID=$(expr $INTERNAL_ID + 0)
    export CURRENT_NAME_INTERNAL="$(echo "${CURRENT_NAME}" | sed "s/${RESP_KEY}/${INTERNAL_ID}/")"
  else
    error "Unable to map responsibilty: $RESP_KEY in this database. Please ensure it exists before attempting to load this MDS"
    exit 1
  fi
}

function mds_load_init
{
  # mds_load_init "Personalization - USER" "/oracle/apps/eam/asset/webui/customizations/user/ISILVA/EAM_AD_ADVSEARCH_PAGE" "ISILVA"
  CURRENT_TYPE="$1"
  CURRENT_NAME="$2"
  CURRENT_DESC="$3"

  CURRENT_NAME_INTERNAL="${CURRENT_NAME}"
  debug "CURRENT_TYPE: ${CURRENT_TYPE}"
  if [ $SKIP_NEXT_MAPPING == "false" ]; then
      if [ "${CURRENT_TYPE}" == "Personalization - USER" ]; then
        map_internal_user "$CURRENT_DESC" "${CURRENT_NAME}"
      fi

      if [ "${CURRENT_TYPE}" == "Personalization - RESP" ]; then
        map_internal_resp "$CURRENT_DESC" "${CURRENT_NAME}"
      fi

      if [ "${CURRENT_TYPE}" == "Personalization - ORG" ]; then
        map_internal_org "$CURRENT_DESC" "${CURRENT_NAME}"
      fi
  fi
  SKIP_NEXT_MAPPING="false"

  info "##############################################"
  info "# $MDSUTIL_DIRECTION $CURRENT_TYPE using oracle.jrad.tools.xml.importer.XMLImporter"
  info "##############################################"
  info "# Name: $CURRENT_NAME"
  debug "# Internal Name: ${CURRENT_NAME_INTERNAL}"
  info "# Desc: $CURRENT_DESC"
  info "# Registered by: $WHO"
  info "##############################################"
  # Make sure logs end up in its own directory
  mkdir -p $XXCU_TOP/install/log
  cd $XXCU_TOP/install/log

  verify_mds_direction
  get_mds_tnsstring
}

function mds_handle_retval
{
  RETVAL=$?
  if [ $RETVAL -ne 0 ]; then
    error "-> FAILED TO PROCESS $MDSUTIL_DIRECTION check last logfile.Content of DEBUG_OUTPUT is:"
    error "$DEBUG_OUTPUT"
    exit 1
  fi

  WARNING_FLAG=$(echo "$DEBUG_OUTPUT" | grep "^Warning" | wc -l)
  ERROR_FLAG=$(echo "$DEBUG_OUTPUT" | grep "^Error" | wc -l)
  ORA_FLAG=$(echo "$DEBUG_OUTPUT" | grep "^ORA-" | wc -l)

  if [ ${WARNING_FLAG} -ne 0 ] || [ ${ERROR_FLAG} -ne 0 ] || [ ${ORA_FLAG} -ne 0 ]; then
    error "Problems detected in output during run, output from run:
$DEBUG_OUTPUT"

    if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
        info "Removing file: $MDSUTIL_FILENAME"
        rm -f "$MDSUTIL_FILENAME"
    fi
    exit 1
  else
    debug "Output from run:
$DEBUG_OUTPUT"
    if [ "$MDSUTIL_DIRECTION" = "UPLOAD" ]; then
        registerProcessedChange "$MDSUTIL_FILENAME"
    fi
  fi
}

function mds_download_post
{
  mds_handle_retval

  mkdir -p "$MDSUTIL_DIRNAME"

  debug "Moving file to ${MDSUTIL_DIRNAME}:
$(find "$DATA_STAGING_DIR" ! -name "${CURRENT_DESC}" -name "*.xml" -exec mv "{}" "${MDSUTIL_DIRNAME}" \; -print)"

  add_ricew_manager_metadata "$MDSUTIL_FILENAME" '#' "${RICEW_COMPONENT_TYPE}"

  info "-> Extracted to $(basename $MDSUTIL_FILENAME) in $MDSUTIL_DIRNAME"

}

function mds_upload_post
{
  mds_handle_retval
  info "-> Uploaded without errors, cleaning up tmp-file"
}

function set_mds_filename
{
  export MDSUTIL_FILENAME="$DATA_STAGING_DIR/$(echo "$1" | sed 's/ /_/g').xml"
  debug "MDSUTIL_FILENAME=$MDSUTIL_FILENAME"
  export MDSUTIL_RELATIVE_FILENAME="$(echo ${1}.xml | cut -d/ -f2- | sed 's/ /_/g')"
  export MDSUTIL_DIRNAME="$(dirname $MDSUTIL_FILENAME)"
  debug "MDSUTIL_DIRNAME=$MDSUTIL_DIRNAME"
  mkdir -p "$MDSUTIL_DIRNAME"

}

#############################
#### Pages               ####
#############################
function mds_load_pg
{
        mds_load_init "Page" "$1" "$2" "$3"
        set_mds_filename "$CURRENT_NAME"
        if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
                mds_dl_pg $*
        else
                mds_ul_pg $*
        fi
}

function mds_ul_pg
{
    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
        debug "java oracle.jrad.tools.xml.importer.XMLImporter \\
                '${MDSUTIL_FILENAME}' \\
                -username APPS -password ***** \\
                -dbconnection $MDS_TNS_STRING \\
                -rootdir $DATA_STAGING_DIR"

        # Store current dir
        MY_PWD=$(pwd)
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"
        DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.importer.XMLImporter \
                "${MDSUTIL_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING \
                -rootdir $DATA_STAGING_DIR)
        mds_upload_post
        debug "cd $MY_PWD"
        cd $MY_PWD
    fi
}

function mds_dl_pg
{
        error "Page download not implemented"
}

#############################
#### Regions             ####
#############################
function mds_load_rn
{
        mds_load_init "Region" "$1" "$2" "$3"
        set_mds_filename "$CURRENT_NAME"
        if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
                mds_dl_pg $*
        else
                mds_ul_pg $*
        fi
}

function mds_ul_rn
{
    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then

        debug "java oracle.jrad.tools.xml.importer.XMLImporter \\
                '${MDSUTIL_FILENAME}' \\
                -username APPS -password ***** \\
                -dbconnection $MDS_TNS_STRING \\
                -rootdir $DATA_STAGING_DIR"

        # Store current dir
        PWD=$(pwd)
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"
        DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.importer.XMLImporter \
                "${MDSUTIL_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING \
                -rootdir $DATA_STAGING_DIR)
        mds_upload_post
        debug "cd $PWD"
        cd $PWD
    fi
}

function mds_dl_rn
{
        error "Region download not implemented"
}

#############################
#### Attribute Sets      ####
#############################
function mds_load_attr
{
        mds_load_init "Attribute set" "$1" "$2" "$3"
        set_mds_filename "$CURRENT_NAME"
        if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
                mds_dl_attr $*
        else
                mds_ul_attr $*
        fi
}

function mds_ul_attr
{
    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then

        debug "java oracle.jrad.tools.xml.importer.XMLImporter \\
                '${MDSUTIL_FILENAME}' \\
                -username APPS -password ***** \\
                -dbconnection $MDS_TNS_STRING \\
                -rootdir $DATA_STAGING_DIR"

        # Store current dir
        PWD=$(pwd)
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"
        DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.importer.XMLImporter \
                "${MDSUTIL_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING \
                -rootdir $DATA_STAGING_DIR)
        mds_upload_post
        debug "cd $PWD"
        cd $PWD
    fi
}

function mds_dl_attr
{
        error "Attribute set download not implemented"
}

#############################
#### Personalizations    ####
#############################

function mds_load_pers
{
    if [ $# -lt 3 ]; then
        error "Only got $# parameters"
        error "Param 1: $1"
        error "Param 2: $2"
        error "Param 3: $3"
        error "Usage: mds_load_pers <jdr_path> <USER|RESP|ORG|SITE> <shortname>"
        exit 1
    fi
    # mds_load_pers "/oracle/apps/eam/asset/webui/customizations/user/ISILVA/EAM_AD_ADVSEARCH_PAGE" "USER" "ISILVA"
	EBS_ACCLERATOR_CMDLINE="mds_load_pers \"$1\" \"$2\" \"$3\""
    mds_load_init "Personalization - $2" "$1" "$3"
    set_mds_filename "${CURRENT_NAME}"
    if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
            mds_dl_pers $*
    else
            mds_ul_pers $*
    fi
}

function mds_ul_pers
{

    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then

        debug "java oracle.jrad.tools.xml.importer.XMLImporter \
                '${MDSUTIL_RELATIVE_FILENAME}' \
                -username APPS -password ******* \
                -dbconnection $MDS_TNS_STRING \
                -validate \
                -rootdir $DATA_STAGING_DIR \
                -mmddir $OA_HTML/jrad \
                -jdk13"

        # Store current dir
        PWD=$(pwd)
        # dani modified to use JDEV_TOP/myprojects
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"

        DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.importer.XMLImporter \
                "${MDSUTIL_RELATIVE_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING \
                -validate \
                -rootdir $DATA_STAGING_DIR \
                -mmddir $OA_HTML/jrad \
                -jdk13)
        mds_upload_post
        debug "cd $PWD"
        cd $PWD
    fi
}

function mds_dl_pers
{

    # dani modified to use JDEV_TOP/myprojects
    debug "java oracle.jrad.tools.xml.exporter.XMLExporter \
                '${CURRENT_NAME_INTERNAL}' \
                -username APPS -password ******* \
                -dbconnection $MDS_TNS_STRING \
                -rootdir $DATA_STAGING_DIR \
                -mmddir $OA_HTML/jrad \
                -jdk13"

    info "Downloading to file: $MDSUTIL_FILENAME"

    DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.exporter.XMLExporter \
                "${CURRENT_NAME_INTERNAL}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING \
                -rootdir $DATA_STAGING_DIR \
                -mmddir $OA_HTML/jrad \
                -jdk13)

    mds_download_post

}


#############################
#### JPX files           ####
#############################

function mds_load_jpx
{
        mds_load_init "JPX" "$1" "$2" "$3"
        set_mds_filename "$CURRENT_NAME"
        if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
                mds_dl_jpx $*
        else
                mds_ul_jpx $*
        fi
}

function mds_ul_jpx
{
    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
        debug "java oracle.jrad.tools.xml.importer.JPXImporter \
                '${MDSUTIL_FILENAME}' \
                -username APPS -password ******* \
                -dbconnection $MDS_TNS_STRING"

        # Store current dir
        PWD=$(pwd)
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"
        DEBUG_OUTPUT=$(java oracle.jrad.tools.xml.importer.JPXImporter \
                "${MDSUTIL_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING)
        mds_upload_post
        debug "cd $PWD"
        cd "${PWD}"
    fi
}

function mds_dl_jpx
{
        error "Personalization download not implemented"
}

######################
### XLIFF Files    ###
######################

function mds_load_xlf
{
        mds_load_init "XLF" "$1" "$2" "$3"
        set_mds_filename "$CURRENT_NAME"
        if [ "$MDSUTIL_DIRECTION" = "DOWNLOAD" ]; then
                mds_dl_xlf $*
        else
                mds_ul_xlf $*
        fi
}

function mds_ul_xlf
{
    detectChange "$MDSUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
        debug "java oracle.jrad.tools.trans.imp.XLIFFImporter \
                '${MDSUTIL_FILENAME}' \
                -username APPS -password ******* \
                -dbconnection $MDS_TNS_STRING"

        # Store current dir
        PWD=$(pwd)
        debug "cd $DATA_STAGING_DIR"
        cd "${DATA_STAGING_DIR}"
        DEBUG_OUTPUT=$(java oracle.jrad.tools.trans.imp.XLIFFImporter \
                "${MDSUTIL_FILENAME}" \
                -username APPS -password $APPS_PASSWD \
                -dbconnection $MDS_TNS_STRING)
        mds_upload_post
        debug "cd $PWD"
        cd $PWD
    fi
}

function mds_dl_xlf
{
        error "XLIFF download not implemented"
}
