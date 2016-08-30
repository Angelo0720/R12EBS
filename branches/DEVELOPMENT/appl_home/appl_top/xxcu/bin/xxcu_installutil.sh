#!/bin/ksh
##########################################
# Author: Bj�rn Erik Hoel, Accenture     #
# Date:   11.Oct.2011                    #
# Name:   xxcu_installutil.sh            #
##########################################
# $Id: $
#
. $XXCU_TOP/bin/xxcu_logutil.sh      # Basic logging functionality
. $XXCU_TOP/bin/xxcu_scriptutil.sh   # Basic script functionality

CHECKSUM_EXPORTED='N'
CHECKSUM_FILE="/tmp/$0.${TWO_TASK}.checksum"
ORIG_FORMS_PATH=${FORMS_PATH}
# Default language
FORMS_LANGUAGE=${FORMS_LANGUAGE:-US}
# Default Workflow upload mode
WF_UPLOAD_MODE=${WF_UPLOAD_MODE:-UPGRADE}
# Remove compilation result before compilation
PURGE_FLAG=${PURGE_FLAG:-"N"}
# Do we stop on error?
STOP_ON_ERROR=${STOP_ON_ERROR:-"Y"}

function add_ricew_manager_metadata
{
    TARGET_FILE="$1"
    FILE_COMMENT="$2"
    COMPONENT_TYPE="$3"

    if [ "$RICEW_APPLICATION" != "" ] && [ "${RICEW_TO_EXTRACT}" != "" ]; then
        debug "Adding metadata to file: $TARGET_FILE - Application: $RICEW_APPLICATION RICEW: $RICEW_TO_EXTRACT"
        echo "" >> "$TARGET_FILE" 
        echo "${FILE_COMMENT} ~RICEW_APPLICATION~$RICEW_APPLICATION~" >> "$TARGET_FILE"
        echo "${FILE_COMMENT} ~RICEW_EXTRACTED~$RICEW_TO_EXTRACT~" >> "$TARGET_FILE"
        echo "${FILE_COMMENT} ~RICEW_COMPONENT_TYPE~${COMPONENT_TYPE}~" >> "$TARGET_FILE"
        echo "${FILE_COMMENT} ~RICEW_CMDLINE~${EBS_ACCLERATOR_CMDLINE}~" >> "$TARGET_FILE"
        echo "${FILE_COMMENT} ~RICEW_PRE_INSTALL_COMMAND~${RICEW_PRE_INSTALL_COMMAND}~" >> "$TARGET_FILE"

        debug "Metadata added:
$(tail -5 "$TARGET_FILE")"
    fi
}

function compile_java_file
{
	obj_name="$1"
	info "Processing '$obj_name'"
	if [ ! -f "$obj_name" ]; then
		error "Unable to locate file: $obj_name"
		exit 1
	fi

	if [ $PURGE_FLAG = "Y" ]; then
		CLASSFILE_NAME="$(dirname $obj_name)/$(basename $obj_name .java).class"
		debug "Classfile: $CLASSFILE_NAME"
		if [ -f "$CLASSFILE_NAME" ]; then
			debug "purging $CLASSFILE_NAME"
			rm -f "$CLASSFILE_NAME"
		fi
	else

		debug "javac -Xlint:unchecked -Xlint:deprecation $obj_name"
		javac -Xlint:unchecked -Xlint:deprecation "$obj_name" 2> compile_result.$$
		RETVAL=$?

		if [ -s compile_result.$$ ]; then
			if [ $RETVAL -eq 0 ]; then
				warning "############################################################################"
				warning "COMPILATION WARNINGS:"
				warning "############################################################################"
				cat compile_result.$$
				rm compile_result.$$
				warning "############################################################################"
			fi
		fi

		if [ $RETVAL -ne 0 ]; then
			error "############################################################################"
			error "COMPILATION ERRORS:"
			error "############################################################################"
			cat compile_result.$$
			rm compile_result.$$
			error "############################################################################"
			error "Failed to compile $obj_name - Exiting...."
			exit 1
		fi
	fi
}

function set_forms_language
{
	FORMS_LANGUAGE="$1"
	debug "FORMS_LANGUAGE set to $FORMS_LANGUAGE"
}

function detectChangedFolder
{

	if [ $# -ne 2 ]; then
		error "Usage: detectChangedFolder \"<step name prefix>\" \"<path to folder>\""
		exit 1
	fi

	debug "detectChangedFolder.argument1: $1"
	debug "detectChangedFolder.argument2: $2"

	if [ "$1" = "" ]; then
		error "detectChangedFolder must have argument 1 set"
		exit 1
	fi
	if [ "$2" = "" ]; then
		error "detectChangedFolder must have argument 2 set"
		exit 1
	fi

	FILE_NAMES="$(find $2 -type f|sort)"
    NEW_CHECKSUM=$(for FILE_NAME in $FILE_NAMES; do echo $FILE_NAME; cat $FILE_NAME ;done | sha1sum | awk '{ print $1 }')
	debug "detectChangedFolder.New Checksum: $NEW_CHECKSUM"

	CURR_CHECKSUM=$(echo "
set serverout on
BEGIN
	ACN_ORA_INSTALL_PKG.PRINT_STEP_CHECKSUM(
			p_username  => 'external'
		  , p_step_name => '$1.$2'
		  );
END;
/
" | sqlCommandPipe $APPS_LOGIN)

	debug "detectChangedFolder.Previous checksum: $CURR_CHECKSUM"

	if [ "$CURR_CHECKSUM" = "" ]; then
		info "New change detected - Processing - $1"
		DETECT_FLAG=1
	elif [ "$NEW_CHECKSUM" != "$CURR_CHECKSUM" ]; then
		info "Change detected - Processing - $1"
		DETECT_FLAG=1
	else
		info "No change detected - Skipping - $1"
		DETECT_FLAG=0
	fi

}

function getCheckSumList
{


	if [ "$CHECKSUM_EXPORTED" = "N" ]; then
		info "Extracting current checksums in environment"
		SPOOL_RETVAL=$(echo "
set serverout on
set pages 10000
set lines 400
set trimspool on
spool $CHECKSUM_FILE
set heading off
set feedback off
select step_name||':'||checksum
from acn_ora_install_control
where checksum is not null;

" | sqlCommandPipe $APPS_LOGIN)

		CHECKSUM_EXPORTED='Y'
	fi

}

function detectChange
{

	if [ $# -ne 1 ]; then
		error "Usage: detectChange <fileName>"
		exit 1
	fi

	change_filename=$(basename $1)
	if [ ! -f "$1" ]; then
		error "Unable to locate file: $1"
		exit 1
	fi

    NEW_CHECKSUM=$(sha1sum $1 | awk '{ print $1 }')
	debug "detectChange.New Checksum: $NEW_CHECKSUM"

	getCheckSumList

	CHECKSUM_HIT=$(grep "$NEW_CHECKSUM" "$CHECKSUM_FILE" | wc -l)
	if [ "$CHECKSUM_HIT" = "0" ]; then

		CURR_CHECKSUM=$(echo "
set serverout on
BEGIN
	ACN_ORA_INSTALL_PKG.PRINT_STEP_CHECKSUM(
			p_username  => 'external'
		  , p_step_name => '$1'
		  );
END;
/
" | sqlCommandPipe $APPS_LOGIN)

		debug "detectChange.Previous checksum: $CURR_CHECKSUM"

		if [ "$CURR_CHECKSUM" = "" ]; then
			info "New change detected - Processing - $change_filename"
			DETECT_FLAG=1
		elif [ "$NEW_CHECKSUM" != "$CURR_CHECKSUM" ]; then
			info "Change detected - Processing - $change_filename"
			DETECT_FLAG=1
		else
			info "No change detected - Skipping - $change_filename"
			DETECT_FLAG=0
		fi
	else
		debug "detectChange.Found existing checksum in extracted list"
		info "No change detected - Skipping - $change_filename"
		DETECT_FLAG=0
	fi

}

function registerProcessedChangeFolder
{
	if [ $# -ne 2 ]; then
		error "Usage: registerProcessedChangeFolder \"<step name prefix>\" \"<path to folder>\""
		return -1
	fi

	debug "detectChangedFolder.argument1: $1"
	debug "detectChangedFolder.argument2: $2"
    NEW_CHECKSUM=$(for FILE_NAME in `find $2 -type f|sort`; do echo $FILE_NAME; cat $FILE_NAME ;done | sha1sum | awk '{ print $1 }')
	debug "registerProcessedChangeFolder.New Checksum: $NEW_CHECKSUM"

RETVAL=$(echo "
set serverout on
BEGIN
	ACN_ORA_INSTALL_PKG.REGISTER_STEP_OBJECT_CHECKSUM(
			p_username  => 'external'
		  , p_step_name => '$1.$2'
		  , p_checksum  => '$NEW_CHECKSUM'
		  );

	COMMIT;
END;
/
" | sqlCommandPipe $APPS_LOGIN)

	debug "RegisterStep Result: $RETVAL"

}

function registerProcessedChange
{
	if [ $# -ne 1 ]; then
		error "Usage: registerProcessedChange <fileName>"
		return -1
	fi

	NEW_CHECKSUM=$(sha1sum $1 | awk '{ print $1 }')
	debug "registeredProcessedChange.New Checksum: $NEW_CHECKSUM"

RETVAL=$(echo "
set serverout on
BEGIN
	ACN_ORA_INSTALL_PKG.REGISTER_STEP_OBJECT_CHECKSUM(
			p_username  => 'external'
		  , p_step_name => '$1'
		  , p_checksum  => '$NEW_CHECKSUM'
		  );

	COMMIT;
END;
/
" | sqlCommandPipe $APPS_LOGIN)

	debug "RegisterStep Result: $RETVAL"

}

function compileForm
{
	form_name=$1
	optional_top="$2"
	dir_name=$(dirname $form_name)
	fmx_name=${dir_name}/$(basename $form_name .fmb)".fmx"
	COMPILE_LOG=/tmp/compilation_$$.log
	debug "Temporary place fmb in AU_TOP and compile"
	export FORMS_PATH="$XXCU_TOP/resource/$FORMS_LANGUAGE:$AU_TOP/resource:$AU_TOP/resource/stub:$XXCU_TOP/forms/$FORMS_LANGUAGE:$AU_TOP/forms/$FORMS_LANGUAGE"
	cp --force ${form_name} $AU_TOP/bin/${dir_name} # Assume relative path on this
	debug "frmcmp_batch $AU_TOP/bin/${form_name} userid=apps/****** output_file=$fmx_name module_type=form compile_all=special"
	frmcmp_batch $AU_TOP/bin/${form_name} userid=$APPS_LOGIN output_file=$fmx_name batch=no module_type=form compile_all=special | tee $COMPILE_LOG
	RETVAL=$?
    debug "frmcmp_batch returned $RETVAL"
	# Check that COMPILE_LOG created the form file
	COMPILE_RESULT=$( cat $COMPILE_LOG | grep "Created form file $fmx_name" | wc -l)
	debug "COMPILE_RESULT for $fmx_name=$COMPILE_RESULT"
	if [ $COMPILE_RESULT -ne 0 ]; then
		SUCCESS_FLAG=1
		debug "Copying ${fmx_name} to AU_TOP/bin/${dir_name}"
		cp --force ${fmx_name} $AU_TOP/bin/${dir_name} # Assume relative path on thiss

		if [ "$optional_top" != "" ]; then
			info "Copying to Optional Destination ${optional_top}/forms/${FORMS_LANGUAGE}/"
			cp --force ${fmx_name} ${optional_top}/forms/${FORMS_LANGUAGE}/
		fi

	else
		SUCCESS_FLAG=0
	fi
	rm $COMPILE_LOG
	export FORMS_PATH=$ORIG_FORMS_PATH
}

function compileLibrary
{
	obj_name=$1
	dir_name=$(dirname $obj_name)
	compiled_name=${dir_name}/$(basename $obj_name .pll)".plx"
	COMPILE_LOG=/tmp/compilation_$$.log
	debug "Temporary place pll in AU_TOP and compile"
	export FORMS_PATH="$XXCU_TOP/resource/$FORMS_LANGUAGE:$AU_TOP/resource:$AU_TOP/resource/stub:$XXCU_TOP/forms/$FORMS_LANGUAGE:$AU_TOP/forms/$FORMS_LANGUAGE"
	cp --force ${obj_name} $AU_TOP/bin/${dir_name} # Assume relative path on this
	debug "frmcmp_batch $AU_TOP/bin/${obj_name} userid=apps/******** output_file=$compiled_name batch=no module_type=library compile_all=special"
	frmcmp_batch $AU_TOP/bin/${obj_name} userid=$APPS_LOGIN output_file=$compiled_name batch=no module_type=library compile_all=special | tee $COMPILE_LOG
	RETVAL=$?
        debug "frmcmp_batch returned $RETVAL"
	# Check that COMPILE_LOG created the file
	COMPILE_RESULT=$( cat $COMPILE_LOG | tail -1 | grep "Done" | wc -l)
	debug "COMPILE_RESULT for $compiled_name=$COMPILE_RESULT"
	if [ $COMPILE_RESULT -ne 0 ]; then
		SUCCESS_FLAG=1
		debug "Copying ${compiled_name} to AU_TOP/bin/${dir_name}"
		cp --force ${compiled_name} $AU_TOP/bin/${dir_name} # Assume relative path on this
	else
		SUCCESS_FLAG=0
	fi
	rm $COMPILE_LOG
	export FORMS_PATH=$ORIG_FORMS_PATH
}

function processForm
{

	form_name=$1
	opt_top=$2
	# This will set $DETECT_FLAG
	detectChange $form_name

	if [ $DETECT_FLAG -eq 1 ]; then
		info "PROCESSING THE FORM"
		compileForm $form_name $opt_top
		if [ $SUCCESS_FLAG -eq 1 ]; then
			registerProcessedChange $form_name
		else
			error "Failed to compile $form_name"
			if [ "$STOP_ON_ERROR" = "Y" ]; then
				exit 1
			fi
		fi
	fi

}

function set_wf_upload_mode
{
	WF_UPLOAD_MODE=$1
	debug "WF_UPLOAD_MODE=$1"
}

function uploadWorkflow
{
	obj_name=$1
	dir_name=$(dirname $obj_name)
	debug "WFLOAD apps/******** 0 Y $WF_UPLOAD_MODE $obj_name"
	WFLOAD $APPS_LOGIN 0 Y $WF_UPLOAD_MODE $obj_name
	RETVAL=$?
	debug "WFLOAD returned $RETVAL"
	if [ $RETVAL -eq 0 ]; then
		SUCCESS_FLAG=1
	else
		SUCCESS_FLAG=0
	fi

}

function processLibrary
{

	obj_name=$1
	# This will set $DETECT_FLAG
	detectChange $obj_name

	if [ $DETECT_FLAG -eq 1 ]; then
		info "PROCESSING THE LIBRARY"
		compileLibrary $obj_name
		if [ $SUCCESS_FLAG -eq 1 ]; then
			registerProcessedChange $obj_name
		else
			error "Failed to compile $obj_name"
			if [ "$STOP_ON_ERROR" = "Y" ]; then
				exit 1
			fi
		fi
	fi

}

function processWorkflow
{

	obj_name=$1
	# This will set $DETECT_FLAG
	WF_FILE_NAME=$XXCU_TOP/admin/config/WFLOAD/$obj_name
	detectChange $WF_FILE_NAME

	if [ $DETECT_FLAG -eq 1 ]; then
		info "PROCESSING THE WORKFLOW IN ${WF_UPLOAD_MODE} MODE"
		uploadWorkflow $WF_FILE_NAME
		if [ $SUCCESS_FLAG -eq 1 ]; then
			registerProcessedChange $WF_FILE_NAME
		else
			error "Failed to upload $obj_name"
			if [ "$STOP_ON_ERROR" = "Y" ]; then
				exit 1
			fi
		fi
	fi

}
