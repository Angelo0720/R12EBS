#!/bin/bash
# $Id: xxcu_fndutil.sh 23041 2008-10-09 13:01:27Z bel $
##########################################
# Author: Bjørn Erik Hoel, Accenture ANS #
# Date:   08.Nov.2007                    #
# Name:   xxcu_fndutil.sh                #
##########################################
#
. $XXCU_TOP/bin/xxcu_logutil.sh      # Basic logging functionality
. $XXCU_TOP/bin/xxcu_scriptutil.sh   # Basic script functionality
. $XXCU_TOP/bin/xxcu_installutil.sh  # Functionality to detect changes

# Configurable parameters
# Number of FNDs to skip before doing any actual work
SKIPCOUNT=${SKIPCOUNT:-0}
DATA_STAGING_DIR=${DATA_STAGING_DIR:-$XXCU_TOP/admin/config/FNDLOAD}
STOP_ON_ERROR=${STOP_ON_ERROR:-"Y"}

# Internal variables
LOADCOUNT=0
SKIP_FLAG="N"

function replace_owner
{
	if [ $# -ne 3 ]; then
		error "replace_owner <file> <OwnerColumnName> <NewOwner>"
		error "Example: replace_owner my_file.ldt OWNER XXFND"
		exit 1
	fi

	REPLACE_FILE="$1"
	REPLACE_OWNER_COLUMN_NAME="$2"
	REPLACE_NEW_OWNER="$3"

	if [ -f $REPLACE_FILE ]; then
		debug "replacing old '$REPLACE_OWNER_COLUMN_NAME' columns with '${REPLACE_NEW_OWNER}'"
		cat $REPLACE_FILE | sed "s/${REPLACE_OWNER_COLUMN_NAME} = \".*\"/${REPLACE_OWNER_COLUMN_NAME} = \"${REPLACE_NEW_OWNER}\"/g" > ${REPLACE_FILE}.replace
		debug "Moving ${REPLACE_FILE}.replace to ${REPLACE_FILE}"
		mv -f ${REPLACE_FILE}.replace ${REPLACE_FILE}
	else
		error "Cannot open find file: $REPLACE_FILE"
		exit 1
	fi
}

function perform_entity_count
{
	ENTITY_COUNT=$(cat $FNDUTIL_FILENAME | grep "BEGIN $ENTITY_NAME " | wc -l)
	debug "Entity Count: $ENTITY_COUNT"
	if [ $ENTITY_COUNT -gt 1 ]; then
		warning "Found $ENTITY_COUNT entries of $ENTITY_NAME in $(basename $FNDUTIL_FILENAME) - Make sure you intentionally extracted this many for upload"
	fi
}

function set_entity
{
	export ENTITY_NAME="$1"
	debug "set_entity: '$ENTITY_NAME'"
}

# Replace all spaces with _ and set FNDUTIL_FILENAME environment
function set_fnd_filename
{
  export FNDUTIL_FILENAME="$DATA_STAGING_DIR/$(echo $1 | sed 's/ /_/g' | sed 's/:/_/g' | sed 's/\//_/g' | sed 's/</_/g' | sed 's/>/_/g' | sed 's/,/_/g' | sed 's/?/_/g' | sed 's/;/_/g')"
  debug "FNDUTIL_FILENAME set to \"$FNDUTIL_FILENAME\""
  mkdir -p $DATA_STAGING_DIR

  # Check for duplicate entities in ldt files
  # Sometimes this can be very bad, other times intentional
  if [ $FNDUTIL_DIRECTION = "UPLOAD" ]; then
	perform_entity_count

	SOURCE_DATABASE=$(cat $FNDUTIL_FILENAME | grep -i 'source database' | awk '{ print $3 }') > /dev/null 2>&1
	if [ "$SOURCE_DATABASE" = "" ]; then
	SOURCE_DATABASE='Unknown'
	fi
	info "Source Database: $SOURCE_DATABASE"
  fi

}

function verify_language
{
  if [ "$FNDUTIL_LANGUAGE" = "" ] && [ "$FNDUTIL_LANGUAGES" = "" ]; then
    debug "FNDUTIL_LANGUAGES=$FNDUTIL_LANGUAGES"
    debug "FNDUTIL_LANGUAGE=$FNDUTIL_LANGUAGE"
    error "-> Set language by calling set_nls_languages with either 'US', 'N' or 'US N'"
	exit 1
  fi
}

function verify_direction
{
  if [ "$FNDUTIL_DIRECTION" = "" ]; then
    error "-> Set direction by calling set_fnd_direction with either 'UPLOAD' or 'DOWNLOAD'"
	exit 1
  fi
}

function set_fnd_direction
{
  if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]; then
   debug "FNDUTIL_DIRECTION set to \"$1\""
	export FNDUTIL_DIRECTION="$1"
  else
	error "Usage: $0 <UPLOAD|DOWNLOAD>"
	exit 1
  fi
}

function set_nls_languages
{
  export FNDUTIL_LANGUAGES="$1"
  RICEW_PRE_INSTALL_COMMAND="set_nls_languages $1"
}

function set_nls_lang
{
  NEW_FNDUTIL_LANGUAGE="$1"
  ORIG_CHARSET=$(echo $NLS_LANG | cut -d. -f 2)
  if [ "$NEW_FNDUTIL_LANGUAGE" = "N" ]; then
	export NLS_LANG="Norwegian_Norway.${ORIG_CHARSET}"
  elif [ "$NEW_FNDUTIL_LANGUAGE" = "US" ]; then
    export NLS_LANG="American_America.${ORIG_CHARSET}"
  elif [ "$NEW_FNDUTIL_LANGUAGE" = "ZHS" ]; then
    export NLS_LANG="Simplified Chinese_China.${ORIG_CHARSET}"
  else
    error "-> Unknown language mapping. Please expand xxcu_fndutil.sh (set_nls_lang function)"
	exit 1
  fi
  debug "-> Set NLS_LANG to: $NLS_LANG"
  export FNDUTIL_LANGUAGE=${NEW_FNDUTIL_LANGUAGE}
  debug "-> Set FNDUTIL_LANGUAGE to: $FNDUTIL_LANGUAGE"
}

function upload_utf8convert
{
  INFILE="$FNDUTIL_FILENAME"

  touch "$INFILE"

  # Check characterset of raw file (Should be ASCII or UTF8 at this point)
  RAWFILE=$(file ${FNDUTIL_FILENAME} | grep -v ASCII | grep -v UTF-8 | wc -l)

  if [ $RAWFILE -gt 0 ]; then
	error "Source file is not UTF8 or pure ASCII:"
	error "$(file ${FNDUTIL_FILENAME})"
	if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	fi
	FND_ERROR_FLAG=1
  fi

  # Check character set
  CHARSET=$(echo $NLS_LANG | cut -d. -f 2)
  OUTFILE="${FNDUTIL_FILENAME}.${CHARSET}"
  debug "FND_CONVERTED_FILENAME set to \"$OUTFILE\""
  export FND_CONVERTED_FILENAME="${OUTFILE}"
  if [ "$CHARSET" != "UTF8" ] && [ "$CHARSET" != "AL32UTF8" ]; then
    adncnv "$INFILE" UTF8 "$OUTFILE" ${CHARSET} > /dev/null 2>&1
    RETVAL=$?
    if [ $RETVAL -eq 0 ]; then
      info "-> Converted from UTF8 file format to $CHARSET"
      # Clean up logfile
      if [ -f adncnv.log ]; then
		rm adncnv.log
	  fi
    else
      error "-> FAILED TO CONVERT $INFILE (To $CHARSET from UTF8)"
      error "-> Command line was: adncnv $INFILE UTF8 $OUTFILE ${CHARSET}"
      error "-> Log in adncnv.log"
	  if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	  fi
	  FND_ERROR_FLAG=1
    fi
  else
    info "-> Current character set is $CHARSET, no need to convert"
	cp -f "$INFILE" "$FND_CONVERTED_FILENAME"
  fi
}

function utf8convert
{
  INFILE="$FNDUTIL_FILENAME"
  # Check character set
  CHARSET=$(echo $NLS_LANG | cut -d. -f 2)
  OUTFILE=$(echo "$1" | sed 's/ /_/g').${CHARSET}

  if [ "$CHARSET" != "UTF8" ] && [ "$CHARSET" != "AL32UTF8" ]; then
    adncnv "$INFILE" ${CHARSET} "$OUTFILE" UTF8 > /dev/null 2>&1
    RETVAL=$?
    if [ $RETVAL -eq 0 ]; then
      info "-> Converted to UTF8 file format from $CHARSET"
      rm -f "$INFILE"
	  mv "$OUTFILE" "$INFILE"
      # Clean up logfile
      if [ -f adncnv.log ]; then
		rm adncnv.log
	  fi
    else
      error "-> FAILED TO CONVERT $INFILE (From $CHARSET to UTF8)"
      error "-> Command line was: adncnv $INFILE ${CHARSET} $OUTFILE UTF8"
      error "-> Log in adncnv.log"
	   if [ "$STOP_ON_ERROR" = "Y" ]; then
		  exit 1
	   fi
	   FND_ERROR_FLAG=1
    fi
  else
    info "-> Current character set is $CHARSET, no need to convert"
  fi
}

function fnd_load_init
{
  set_entity "$1"
  CURRENT_TYPE="$2"
  CURRENT_NAME="$3"
  CURRENT_DESC="$4"
  WHO="$5"
  export LOADCOUNT=$(expr $LOADCOUNT + 1)
  if [ $SKIPCOUNT -gt $LOADCOUNT ]; then
	SKIP_FLAG="Y"
	SKIP_TEXT=" - SKIPPING"
  else
	SKIP_FLAG="N"
	SKIP_TEXT=""
  fi
  info "##############################################"
  info "# [$LOADCOUNT$SKIP_TEXT] $FNDUTIL_DIRECTION $CURRENT_TYPE using FNDLOAD"
  info "##############################################"
  info "# Name: $CURRENT_NAME"
  info "# Desc: $CURRENT_DESC"
  info "# Registered by: $WHO"
  info "##############################################"
  # Make sure logs end up in its own directory
  mkdir -p $XXCU_TOP/install/log
  cd $XXCU_TOP/install/log

  verify_language
  verify_direction

}

function print_logfile
{
	info "################### LOGFILE CONTENT ####################"
	cat $LAST_LOGFILE
	info "########################################################"
}

function fnd_handle_retval
{
  RETVAL=$?
  FAILED_FLAG="N"
  if [ "$1" = "NORETVAL" ]; then
	CHECK_RETVAL=0
  else
	CHECK_RETVAL=1
  fi
  export LAST_LOGFILE_FULLPATH=$(find . -mmin -1 -exec grep -l "$FNDUTIL_FILENAME" {} \; | sort | tail -1)
  debug "LAST_LOGFILE_FULLPATH: $LAST_LOGFILE_FULLPATH"
  export LAST_LOGFILE=$(basename $LAST_LOGFILE_FULLPATH)
  debug "LAST_LOGFILE: $LAST_LOGFILE"
  NUM_ORA_MESSAGES=$(cat $LAST_LOGFILE | grep "^ORA-"  | wc -l)
  CONCURRENT_REQUEST_SUCCESS=$(cat $LAST_LOGFILE | grep "^Concurrent request completed successfully"  | wc -l)
  debug "NUM_ORA_MESSAGES: $NUM_ORA_MESSAGES"
  if [ $CHECK_RETVAL -eq 1 ] && [ $RETVAL -ne 0 ]; then
	FAILED_FLAG="Y"
    error "-> FAILED TO FNDLOAD $FNDUTIL_DIRECTION (FNDLOAD Returned: $RETVAL) check last logfile: \$XXCU_TOP/install/log/$LAST_LOGFILE"
	print_logfile
	if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	fi
	FND_ERROR_FLAG=1
  fi

  if [ $NUM_ORA_MESSAGES -ne 0 ]; then
	FAILED_FLAG="Y"
    error "-> FAILED TO FNDLOAD $FNDUTIL_DIRECTION (ORA MESSAGES FOUND) check last logfile: \$XXCU_TOP/install/log/$LAST_LOGFILE"
	print_logfile
	if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	fi
	FND_ERROR_FLAG=1
  fi

  if [ $FNDUTIL_DIRECTION = "UPLOAD" ] && [ $CONCURRENT_REQUEST_SUCCESS -eq 0 ]; then
	FAILED_FLAG="Y"
    error "-> FAILED TO FNDLOAD $FNDUTIL_DIRECTION (Concurrent Request Did Not Succeed) check last logfile: \$XXCU_TOP/install/log/$LAST_LOGFILE"
	print_logfile
	if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	fi
	FND_ERROR_FLAG=1
  fi

  # Check for empty FND files
  EMPTY_FILE=$(tail -5 $FNDUTIL_FILENAME | grep " End Entity Definitions " | wc -l)
  if [ $EMPTY_FILE -ne 0 ]; then
	FAILED_FLAG="Y"
	error "Error in file: $FNDUTIL_FILENAME"
	error "FATAL: Data file only contains metadata definition, and no actual data related to entity"
	exit 1
  fi

}

function fnd_download_post
{
  fnd_handle_retval
  if [ "$FAILED_FLAG" = "N" ]; then
	  utf8convert
	  perform_entity_count
	  info "-> Extracted to $(basename $FNDUTIL_FILENAME) in $DATA_STAGING_DIR/"
	  info "-> Logfile: \$XXCU_TOP/install/log/$LAST_LOGFILE"

      # If RICEW_APPLICATION and RICEW_TO_EXTRACT is added, this will enrich the file
      add_ricew_manager_metadata "$FNDUTIL_FILENAME" '#' 'XXCU_FND'

  else
	  warning "-> Continuing despite failure."
  fi
}

function fnd_upload_post
{
  rm -f "$FND_CONVERTED_FILENAME"
  fnd_handle_retval $*
  if [ "$FAILED_FLAG" = "N" ]; then
	info "-> uploaded without errors. Logfile: \$XXCU_TOP/install/log/$LAST_LOGFILE"
	registerProcessedChange "$FNDUTIL_FILENAME"
  else
	  warning "-> Continuing despite failure."
  fi
}

#############################
#### Concurrent Programs ####
#############################
#---------------------------
# Uses custom LCT file for upload
# Reason: Conc program upload should not pull associated valuesets along
#         Can have very destructive side-effects.
#---------------------------
function fnd_load_conc_program
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_conc_program \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME=$1
    fnd_load_init "PROGRAM" "Concurrent Program" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
      for lang in $FNDUTIL_LANGUAGES; do
        set_nls_lang $lang
        set_fnd_filename "CP_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
        if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
          fnd_dl_conc_program $*
        else
          fnd_ul_conc_program $*
        fi
      done
    fi
}

function fnd_ul_conc_program
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert
		# Using custom lct file to avoid pulling VALUE SETS
		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$XXCU_TOP/bin/xxcu_afcpprog.lct \
				"$FND_CONVERTED_FILENAME" CUSTOM_MODE=FORCE > /dev/null 2>&1
		fnd_upload_post NORETVAL
	fi
}
function fnd_dl_conc_program
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
	$FND_TOP/patch/115/import/afcpprog.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME APPLICATION_SHORT_NAME=${CURRENT_APPNAME} \
    CONCURRENT_PROGRAM_NAME="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

##################
#### Printers ####
##################
function fnd_load_printer
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_printer \"$1\" \"$2\" \"$3\""
    fnd_load_init "FND_PRINTER" "Printer" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "PRNT_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_printer $*
			else
				fnd_ul_printer $*
			fi
		done
	fi
}

function fnd_ul_printer
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afcppinf.lct \
				"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_printer
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afcppinf.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME PRINTER_NAME=${CURRENT_NAME} > /dev/null 2>&1

  fnd_download_post
}

#########################
#### Printers Styles ####
#########################
function fnd_load_printer_style
{
    EBS_ACCLERATOR_CMDLINE="function fnd_load_printer_style \"$1\" \"$2\" \"$3\""
    fnd_load_init "STYLE" "Printer Style" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "PRNT_STYLE_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_printer_style $*
			else
				fnd_ul_printer_style $*
			fi
		done
	fi
}
#FNDLOAD apps/apps 0 Y DOWNLOAD $FND_TOP/patch/115/import/afcppstl.lct file_name.ldt STYLE PRINTER_STYLE_NAME="printer style name"
function fnd_ul_printer_style
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afcppstl.lct \
				"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_printer_style
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afcppstl.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME PRINTER_STYLE_NAME=${CURRENT_NAME} > /dev/null 2>&1

  fnd_download_post
}

########################
#### Key Flexfields ####
########################
function fnd_load_key_flexfield
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_key_flexfield \"$1\" \"$2\" \"$3\" \"$4\" \"$5\""
    CURRENT_APPNAME="$1"
    CURRENT_FLEXCODE="$2"
	fnd_load_init "KEY_FLEX" "Key Flexfield" "$3" "$4" "$5"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "KEYFLEX_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_key_flexfield $*
			else
				fnd_ul_key_flexfield $*
			fi
		done
	fi
}
function fnd_ul_key_flexfield
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afffload.lct \
				"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_key_flexfield
{
  #    $FND_TOP/patch/115/import/afffload.lct
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afffload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME P_LEVEL=?COL_ALL:FQL_ALL:SQL_ALL:STR_ONE:WFP_ALL:SHA_ALL:CVR_ALL:SEG_ALL? \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" ID_FLEX_CODE="$CURRENT_FLEXCODE" \
    P_STRUCTURE_CODE="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

################################
#### Descriptive Flexfields ####
################################
function fnd_load_desc_flexfield
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_desc_flexfield \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    CURRENT_CONTEXT="$3"
    fnd_load_init "DESC_FLEX" "Descriptive Flexfield" "$2" "$CURRENT_CONTEXT" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "DESCFLEX_${CURRENT_APPNAME}_${CURRENT_NAME}_${CURRENT_CONTEXT}_${FNDUTIL_LANGUAGE}.ldt"

			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_desc_flexfield $*
			else
				fnd_ul_desc_flexfield $*
			fi
		done
	fi
}
function fnd_ul_desc_flexfield
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afffload.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_desc_flexfield
{
  #    $FND_TOP/patch/115/import/afffload.lct

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afffload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME P_LEVEL=?COL_ALL:REF_ALL:CTX_ONE:SEG_ALL? \
    DESCRIPTIVE_FLEXFIELD_NAME="$CURRENT_NAME" \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    DESCRIPTIVE_FLEX_CONTEXT_CODE="$CURRENT_CONTEXT" > /dev/null 2>&1

  fnd_download_post
}

function fnd_load_desc_flexfield_full
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_desc_flexfield_full \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    fnd_load_init "Descriptive Flexfield" "$2" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "DESCFLEX_${CURRENT_APPNAME}_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"

			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_desc_flexfield_full $*
			else
				fnd_ul_desc_flexfield $*
			fi
		done
	fi
}

function fnd_dl_desc_flexfield_full
{
  #    $FND_TOP/patch/115/import/afffload.lct

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afffload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME P_LEVEL=?COL_ALL:REF_ALL:CTX_ALL:SEG_ALL? \
    DESCRIPTIVE_FLEXFIELD_NAME="$CURRENT_NAME" \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" > /dev/null 2>&1

  fnd_download_post
}

########################
#### Responsibility ####
########################
function fnd_load_responsibility
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_responsibility \"$1\" \"$2\" \"$3\""
    fnd_load_init "FND_RESPONSIBILITY" "Responsibility" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "RESP_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_responsibility $*
			else
				fnd_ul_responsibility $*
			fi
		done
	fi
}
function fnd_ul_responsibility
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afscursp.lct \
			"$FND_CONVERTED_FILENAME"  \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}

function fnd_dl_responsibility
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afscursp.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME DATA_GROUP_NAME="%" RESP_KEY="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post
}

########################
#### Profile Option ####
########################
function fnd_load_profile_option
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_profile_option \"$1\" \"$2\" \"$3\""
    fnd_load_init "PROFILE" "Profile Option" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "PROFOPT_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_profile_option $*
			else
				fnd_ul_profile_option $*
			fi
		done
	fi
}
function fnd_ul_profile_option
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afscprof.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_profile_option
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afscprof.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME PROFILE_VALUES="Y" PROFILE_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

######################
#### Lookup codes ####
######################
function fnd_load_lookups
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_lookups \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    fnd_load_init "FND_LOOKUP_TYPE" "Lookup" "$2" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "LOOKUP_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_lookups $*
			else
				fnd_ul_lookups $*
			fi
		done
	fi
}
function fnd_ul_lookups
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/aflvmlu.lct \
			"$FND_CONVERTED_FILENAME" > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_lookups
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/aflvmlu.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    LOOKUP_TYPE="$CURRENT_NAME" > /dev/null 2>&1
	fnd_download_post
}

###############
#### Menus ####
###############
function fnd_load_menus
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_menus \"$1\" \"$2\" \"$3\""
    fnd_load_init "MENU" "Menu" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "MENU_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_menus $*
			else
				fnd_ul_menus $*
			fi
		done
	fi
}
function fnd_ul_menus
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afsload.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_menus
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afsload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME MENU_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

###############################
#### Forms personalization ####
###############################
function fnd_load_forms_pers
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_forms_pers \"$1\" \"$2\" \"$3\""
    fnd_load_init "FND_FORM_CUSTOM_RULES" "Forms Personalization" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "FRMPER_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_forms_pers $*
			else
				fnd_ul_forms_pers $*
			fi
		done
	fi
}
function fnd_ul_forms_pers
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/affrmcus.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_forms_pers
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/affrmcus.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME FUNCTION_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

####################
#### Value Sets ####
####################
function fnd_load_value_set
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_value_set \"$1\" \"$2\" \"$3\""
    fnd_load_init "VALUE_SET" "Value Set" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then

		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "VALUESET_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_value_set $*
			else
				fnd_ul_value_set $*
			fi
		done
	fi
}
function fnd_ul_value_set
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afffload.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_value_set
{

  #
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afffload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME \
    FLEX_VALUE_SET_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

##################
#### Messages ####
##################
# Sample Syntax:
# fnd_load_messages <ShortName> <FND_MESSAGES.MESSAGE_NAME> <Description> <Who>
# Input file: DATA_STAGING_DIR/MESSAGE_<AppName>_<Message_Name>_<Language>.ldt
function fnd_load_messages
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_messages \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    fnd_load_init "FND_NEW_MESSAGES" "Messages" "$2" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "MESSAGE_${CURRENT_APPNAME}_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_messages $*
			else
				fnd_ul_messages $*
			fi
		done
	fi
}
function fnd_ul_messages
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afmdmsg.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_messages
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afmdmsg.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    MESSAGE_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post

}


#############################
#### XML Publisher setup ####
#############################
# Sample Syntax:
# fnd_load_xdosetup_template <AppShortName> <XDO_TEMPLATES_B.DATA_SOURCE_CODE> <XDO_TEMPLATES_B.Template Code> <Who>
# Input file: DATA_STAGING_DIR/XDO_TEMPLATE_<DATA_SOURCE_CODE>_<TEMPLATE_CODE>_<Language>.ldt
function fnd_load_xdosetup_template
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_xdosetup_template \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
	CURR_TEMPLATE_CODE="$3"
    fnd_load_init "XDO_DS_DEFINITIONS" "XML Publisher Template Setup" "$2" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "XDO_TEMPLATE_${CURRENT_NAME}_${CURR_TEMPLATE_CODE}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_xdo_template $*
			else
				fnd_ul_xdo $*
			fi
		done
	fi
}

function fnd_dl_xdo_template
{

   debug "$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
           $XDO_TOP/patch/115/import/xdotmpl.lct \
           $FNDUTIL_FILENAME\
           $ENTITY_NAME APPLICATION_SHORT_NAME=$CURRENT_APPNAME \
           DATA_SOURCE_CODE=$CURRENT_NAME \
		   X_TEMPLATES TMPL_APP_SHORT_NAME=$CURRENT_APPNAME\
		   TEMPLATE_CODE=$CURR_TEMPLATE_CODE"

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $XDO_TOP/patch/115/import/xdotmpl.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    DATA_SOURCE_CODE="$CURRENT_NAME" \
		X_TEMPLATES TMPL_APP_SHORT_NAME="$CURRENT_APPNAME" \
		TEMPLATE_CODE="$CURR_TEMPLATE_CODE" > /dev/null 2>&1
	fnd_download_post
}

#############################
#### XML Publisher setup ####
#############################
# DATA SOURCE DEFINITIONS
#############################
# Sample Syntax:
# fnd_load_xdosetup <AppShortName> <XDO_LOBS.DATA_SOURCE_CODE> <Description> <Who>
# Input file: DATA_STAGING_DIR/XDO_<DATA_SOURCE_CODE>_<Language>.ldt
function fnd_load_xdosetup
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_xdosetup \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    fnd_load_init "XDO_DS_DEFINITIONS" "XML Publisher Setup" "$2" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "XDO_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_xdo $*
			else
				fnd_ul_xdo $*
			fi
		done
	fi
}
function fnd_ul_xdo
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$XDO_TOP/patch/115/import/xdotmpl.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}

function fnd_dl_xdo
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $XDO_TOP/patch/115/import/xdotmpl.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    DATA_SOURCE_CODE="$CURRENT_NAME" > /dev/null 2>&1
	fnd_download_post
}


############################
# Currencies
############################
# Sample Syntax:
# fnd_load_currencies <FND_CURRENCY.CURR_CODE|"ALL"> <Description> <Who>
# Input file: DATA_STAGING_DIR/CURR_<Message_Name>_<Language>.ldt
function fnd_load_currencies
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_currencies \"$1\" \"$2\" \"$3\""
    #type, name, desc, who
    fnd_load_init "FND_CURRENCY" "Currencies" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "CURR_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_currencies $*
			else
				fnd_ul_currencies $*
			fi
		done
	fi
}
function fnd_ul_currencies
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afnls.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi

}
function fnd_dl_currencies
{
	# Check if it is all codes
	if [ $CURRENT_NAME == "ALL" ]; then
	  C_CODE=""
  else
    C_CODE=$CURRENT_NAME
	fi
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afnls.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME CURR_CODE=${C_CODE} > /dev/null 2>&1

  fnd_download_post

}

############################
# FND Folders
############################
# Sample Syntax:
# fnd_load_folders <FND_FOLDER.NAME> <Description> <Who>
# Input file: DATA_STAGING_DIR/FOLDER_<FND_FOLDER.NAME>_<Language>.ldt
#---------------------------
# Custom LCT file: If folder owner does not exist in target, default it to XXFND user
# If XXFND user does not exist in target, then the load will fail.
#---------------------------
function fnd_load_folders
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_folders \"$1\" \"$2\" \"$3\""
    #type, name, desc, who
    fnd_load_init "FND_FOLDERS" "Folders" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "FOLDER_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_folders $*
			else
				fnd_ul_folders $*
			fi
		done
	fi
}
function fnd_ul_folders
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$XXCU_TOP/bin/xxcu_fndfold.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_folders
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/fndfold.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME NAME="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}


########################
#### Request Groups ####
########################
# Sample Syntax:
# fnd_load_request_group <FND_REQUEST_GROUPS.REQUEST_GROUP_NAME> <Description> <Who>
# Input file: DATA_STAGING_DIR/REQGROUP_<Request Group>_<Language>.ldt
function fnd_load_request_group
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_request_group \"$1\" \"$2\" \"$3\""

    #type, name, desc, who
    fnd_load_init "REQUEST_GROUP" "Request Group" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "REQGROUP_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_request_group $*
			else
				fnd_ul_request_group $*
			fi
		done
	fi
}
function fnd_ul_request_group
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afcpreqg.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_request_group
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afcpreqg.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME REQUEST_GROUP_NAME="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

############################
#### XLA Configurations ####
############################
# Sample Syntax:
# fnd_load_xla_configs DEFAULT 555 Mike
# Input file: DATA_STAGING_DIR/REQGROUP_<Request Group>_<Language>.ldt
function fnd_load_xla_configs
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_xla_configs \"$1\" \"$2\" \"$3\""
    CURRENT_APP_ID="$2"

    #type, name, desc, who
    fnd_load_init "XLA_AAD" "XLA Configurations" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "XLA_CONFIGS_${CURRENT_NAME}_${CURRENT_APP_ID}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_xla_configs $*
			else
				fnd_ul_xla_configs $*
			fi
		done
	fi
}

function fnd_ul_xla_configs
{
	warning "Not implemented for XLA Upload"
}

function fnd_dl_xla_configs
{
  debug "Issuing:
$FND_TOP/bin/FNDLOAD apps/**** 0 Y DOWNLOAD \
$XLA_TOP/patch/115/import/xlaaadrule.lct \
$FNDUTIL_FILENAME \
$ENTITY_NAME APPLICATION_ID=${CURRENT_APP_ID} AMB_CONTEXT_CODE=${CURRENT_NAME}
"

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
	$XLA_TOP/patch/115/import/xlaaadrule.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME APPLICATION_ID=${CURRENT_APP_ID} AMB_CONTEXT_CODE="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

#######################
#### Request Sets ####
#######################
# Sample Syntax:
# fnd_load_request_sets <AppShortName> <FND_REQUEST_SET.REQUEST_SET_NAME> <Description> <Who>
# Input file: DATA_STAGING_DIR/REQSETS_<Request_Set_Name>_<Language>.ldt
# Input file: DATA_STAGING_DIR/REQ_SET_LINKS_<Request_Set_Name>_<Language>.ldt
# NOTE: This also handles the associated request set links
function fnd_load_request_sets
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_request_sets \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    fnd_load_init "REQ_SET" "Request Sets" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "REQSETS_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			set_entity "REQ_SET"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_request_sets $*
			else
				fnd_ul_request_sets $*
			fi

			set_fnd_filename "REQ_SET_LINK_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			set_entity "REQ_SET_LINKS"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_request_set_links $*
			else
				fnd_ul_request_set_links $*
			fi

		done
	fi
}
function fnd_ul_request_sets
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afcprset.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_request_sets
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afcprset.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
	REQUEST_SET_NAME="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

function fnd_ul_request_set_links
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afcprset.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_request_set_links
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afcprset.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
	REQUEST_SET_NAME="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

#######################################
#### Profile Option without values ####
#######################################
function fnd_load_profile_option_no_values
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_profile_option_no_values \"$1\" \"$2\" \"$3\""
    fnd_load_init "PROFILE" "Profile Option without values" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then

		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "PROFOPT_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_profile_option_no_values $*
			else
				fnd_ul_profile_option $*
			fi
		done
	fi
}
function fnd_dl_profile_option_no_values
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afscprof.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME PROFILE_VALUES="N" PROFILE_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

###############
#### USERS ####
###############
function fnd_load_users
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_users \"$1\" \"$2\" \"$3\""
    #type, name, desc, who
    fnd_load_init "FND_USER" "Users" "$1" "$2" "$3"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "USER_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_users $*
			else
				fnd_ul_users $*
			fi
		done
	fi
}
function fnd_ul_users
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
		  $FND_TOP/patch/115/import/afscursp.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE

	   #Notes for using FNDLOAD against FND_USER:-
	   #1. After uploading using FNDLOAD, user will be promoted to change their password again during their next signon attempt.
	   #2. All the responsibilities will be extracted by FNDLOAD alongwith User Definition in FND_USER
	   #3. In the Target Environment , make sure that you have done FNDLOAD for new responsibilities prior to running FNDLOAD on users.

		fnd_upload_post
	fi
}
function fnd_dl_users
{
   $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
      $FND_TOP/patch/115/import/afscursp.lct \
      "$FNDUTIL_FILENAME" \
      $ENTITY_NAME USER_NAME="${CURRENT_NAME}" # > /dev/null 2>&1
   #Do not worry about your password being extracted, it will be encrypted as below in ldt file

  fnd_download_post

}

###########################################################
#### PO Document Types /                               ####
#### Severely bad implementation by Oracle /           ####
#### No update feature, only first time load will work ####
###########################################################
function fnd_load_po_document_types_org
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_po_document_types_org \"$1\" \"$2\""
    fnd_load_init "PO_DOCUMENT_TYPES" "PO Document Types / Supports Create Only" "$1" "$2"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "PO_DOC_TYPES_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_po_doc_types_org $*
			else
				fnd_ul_po_doc_types_org $*
			fi
		done
	fi
}
function fnd_dl_po_doc_types_org
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $PO_TOP/patch/115/import/podoctyp.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME ORG_ID="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

function fnd_ul_po_doc_types_org
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$PO_TOP/patch/115/import/podoctyp.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE
			#> /dev/null 2>&1

		fnd_upload_post
	fi
}

################
#### Alerts ####
################
function fnd_load_alert
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_alert \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    CURRENT_ALERT="$2"
    fnd_load_init "ALR_ALERTS" "Alert" "$CURRENT_ALERT" "$3" "$4"

    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "ALERT_${CURRENT_ALERT}_${FNDUTIL_LANGUAGE}.ldt"

			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_alert $*
			else
				fnd_ul_alert $*
			fi
		done
	fi
}
function fnd_ul_alert
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
            $ALR_TOP/patch/115/import/alr.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}

function fnd_dl_alert
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $ALR_TOP/patch/115/import/alr.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    ALERT_NAME="${CURRENT_ALERT}" > /dev/null 2>&1

  fnd_download_post
}

########################
#### Form Functions ####
########################
function fnd_load_form_function
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_form_function \"$1\" \"$2\" \"$3\""
    fnd_load_init "FUNCTION" "Form Functions" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			set_fnd_filename "FORMFUNCTION_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_form_function $*
			else
				fnd_ul_form_function $*
			fi
		done
	fi
}

function fnd_ul_form_function
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/afsload.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}

function fnd_dl_form_function
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $FND_TOP/patch/115/import/afsload.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME FUNCTION_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}

####################################
#### QA Plans (Collection Plans ####
####################################
# Sample Syntax:
# fnd_load_qa_plan <QA Plan ID> <Description> <Who>
# Input file: DATA_STAGING_DIR/QA_PLAN_<QA_PLANS.PLAN_ID>.ldt
function fnd_load_qa_plan
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_qa_plan \"$1\" \"$2\" \"$3\""
    #type, name, desc, who
    fnd_load_init "QA_PLANS" "QA Plan" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		set_fnd_filename "QA_PLAN_${CURRENT_NAME}.ldt"
		if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
			fnd_dl_qa_plan $*
		else
			fnd_ul_qa_plan $*
		fi
	fi
}
function fnd_ul_qa_plan
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$QA_TOP/patch/115/import/qltplans.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_qa_plan
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $QA_TOP/patch/115/import/qltplans.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME PLAN_ID="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}

####################################
#### Advanced Pricing Contexts  ####
####################################
# Sample Syntax:
# fnd_load_qp_prc_contexts <Context_Code> <Description> <Who>
# Input file: DATA_STAGING_DIR/QP_PRC_CONTEXT_<qp_prc_contexts_v.PRC_CONTEXT_CODE>.ldt
#---------------------------
# Custom lct file:
# Apply USER-columns in both SEEDED and USER columns if set
# Standard lct file does not replicate USER-columns, and thus
# fails with "cannot insert NULL into column" as these are NOT NULL columns.
#---------------------------

function fnd_load_qp_prc_contexts
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_qp_prc_contexts \"$1\" \"$2\" \"$3\""
    #type, name, desc, who
    fnd_load_init "QP_PRC_CONTEXTS" "Advanved Pricing Contexts" "$1" "$2" "$3"
    if [ $SKIP_FLAG = "N" ]; then
		set_fnd_filename "QP_PRC_CONTEXT_${CURRENT_NAME}.ldt"
		if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
			fnd_dl_qp_prc_contexts $*
		else
			fnd_ul_qp_prc_contexts $*
		fi
	fi
}
function fnd_ul_qp_prc_contexts
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$XXCU_TOP/bin/XXCU_QPXPATMD.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_qp_prc_contexts
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $XXCU_TOP/bin/XXCU_QPXPATMD.lct \
    "$FNDUTIL_FILENAME" \
	$ENTITY_NAME PRC_CONTEXT_CODE="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}


#######################
#### AME Attribute ####
#######################
# Also pulls conditions
#######################
function fnd_load_ame_attribute
{
    EBS_ACCLERATOR_CMDLINE="fnd_load_ame_attribute \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"
    CURRENT_TRANSACTION_TYPE="$3"
    if [ $SKIP_FLAG = "N" ]; then
		for lang in $FNDUTIL_LANGUAGES; do
			set_nls_lang $lang
			fnd_load_init "AME_ATTRIBUTES" "AME Attribute" "$2" "$CURRENT_TRANSACTION_TYPE" "$4"
			set_fnd_filename "AME_ATTR_${CURRENT_APPNAME}_${CURRENT_NAME}_${CURRENT_TRANSACTION_TYPE}_${FNDUTIL_LANGUAGE}.ldt"
			set_entity "AME_ATTRIBUTES"

			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_ame_attr $*
			else
				fnd_ul_ame_attr $*
			fi

			set_fnd_filename "AME_COND_${CURRENT_APPNAME}_${CURRENT_NAME}_${CURRENT_TRANSACTION_TYPE}_${FNDUTIL_LANGUAGE}.ldt"
			set_entity "AME_CONDITIONS"

			if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
				fnd_dl_ame_cond $*
			else
				fnd_ul_ame_cond $*
			fi
		done
	fi
}
function fnd_ul_ame_attr
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$AME_TOP/patch/115/import/amesmatt.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_ame_attr
{
  #    $AME_TOP/patch/115/import/amesmatt.lct

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
    $AME_TOP/patch/115/import/amesmatt.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME \
    ATTRIBUTE_NAME="$CURRENT_NAME" \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    TRANSACTION_TYPE_ID="$CURRENT_TRANSACTION_TYPE" > /dev/null 2>&1

  fnd_download_post
}
function fnd_ul_ame_cond
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$AME_TOP/patch/115/import/amesconk.lct \
			"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_ame_cond
{

  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
	$AME_TOP/patch/115/import/amesconk.lct \
    "$FNDUTIL_FILENAME" \
    AME_CONDITIONS \
    APPLICATION_SHORT_NAME="$CURRENT_APPNAME" \
    TRANSACTION_TYPE_ID="$CURRENT_TRANSACTION_TYPE" \
    ATTRIBUTE_NAME="$CURRENT_NAME" > /dev/null 2>&1

  fnd_download_post
}


######################
#### Audit Groups ####
######################
function fnd_load_audit_group
{
  CURRENT_APPNAME=$1
  EBS_ACCLERATOR_CMDLINE="fnd_load_audit_group \"$1\" \"$2\" \"$3\" \"$4\""
  fnd_load_init "FND_AUDIT_GROUPS" "Audit Group" "$2" "$3" "$4"
  if [ $SKIP_FLAG = "N" ]; then
	  for lang in $FNDUTIL_LANGUAGES; do
		set_nls_lang $lang
		set_fnd_filename "AUDGRP_${CURRENT_NAME}_${FNDUTIL_LANGUAGE}.ldt"
		if [ "$FNDUTIL_DIRECTION" = "DOWNLOAD" ]; then
		  fnd_dl_audit_group $*
		else
		  fnd_ul_audit_group $*
		fi
	  done
  fi
}

function fnd_ul_audit_group
{
	detectChange "$FNDUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then
		upload_utf8convert

		$FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y UPLOAD \
			$FND_TOP/patch/115/import/affaudit.lct \
				"$FND_CONVERTED_FILENAME" \
			CUSTOM_MODE=FORCE > /dev/null 2>&1

		fnd_upload_post
	fi
}
function fnd_dl_audit_group
{
  $FND_TOP/bin/FNDLOAD $APPS_LOGIN 0 Y DOWNLOAD \
	$FND_TOP/patch/115/import/affaudit.lct \
    "$FNDUTIL_FILENAME" \
    $ENTITY_NAME APPLICATION_SHORT_NAME=${CURRENT_APPNAME} \
    AUDIT_GROUP="${CURRENT_NAME}" > /dev/null 2>&1

  fnd_download_post

}
