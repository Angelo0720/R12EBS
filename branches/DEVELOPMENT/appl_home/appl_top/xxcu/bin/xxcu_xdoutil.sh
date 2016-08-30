#!/bin/ksh
# $Id:  $
############################################################
# Author: Johan Almqvist, Accenture ANS                    #
# Date:   12.Feb.2008                                      #
# Name:   xxcu_xdoutil.sh                                  #
#                                                          #
# Modification History                                     #
# Date          Name             Description               #
# 28-Mar-2014   Daniel Rodil     Added XDO_FILE_TYPE = XLS #
############################################################

. $XXCU_TOP/bin/xxcu_logutil.sh      # Basic logging functionality
. $XXCU_TOP/bin/xxcu_scriptutil.sh   # Basic script functionality
. $XXCU_TOP/bin/xxcu_installutil.sh  # Functionality to detect changes

# Configurable parameters
# Number of FNDs to skip before doing any actual work
SKIPCOUNT=${SKIPCOUNT:-0}
XDO_STAGING_DIR=${XDO_STAGING_DIR:-$XXCU_TOP/admin/config/XDOLOAD}
STOP_ON_ERROR=${STOP_ON_ERROR:-"Y"}

# Internal variables
LOADCOUNT=0
SKIP_FLAG="N"

function get_xdo_tnsstring
{
	XDO_TNS_STRING=`perl -e 'my $read = undef;
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

function verify_xdo_direction
{
  if [ "$XDOUTIL_DIRECTION" = "" ]; then
    error "-> Set direction by calling set_xdo_direction with either 'UPLOAD' or 'DOWNLOAD'"
	exit 1
  fi
}

function set_xdo_direction
{
  if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]; then
	export XDOUTIL_DIRECTION="$1"
  else
	error "Usage: $0 <UPLOAD|DOWNLOAD>"
	exit 1	
  fi
}

function xdo_load_init
{
  CURRENT_TYPE="$1"
  CURRENT_NAME="$2"
  CURRENT_DESC="$3"
  WHO="$4"
  
  if [ $SKIPCOUNT -gt $LOADCOUNT ]; then
	SKIP_FLAG="Y"
	SKIP_TEXT=" - SKIPPING"
  else
	SKIP_FLAG="N"
	SKIP_TEXT=""
  fi
  info "##############################################"
  info "# [$LOADCOUNT$SKIP_TEXT] $XDOUTIL_DIRECTION $CURRENT_TYPE using oracle.apps.xdo.oa.util.XDOLoader"
  info "##############################################"
  info "# Name: $CURRENT_NAME"
  info "# Desc: $CURRENT_DESC"
  info "# Registered by: $WHO"  
  info "##############################################"
  # Make sure logs end up in its own directory
  mkdir -p $XXCU_TOP/install/log
  mkdir -p $XDO_STAGING_DIR
  cd $XXCU_TOP/install/log
  XDO_LOGFILE="xdo_$$.log"
  
  verify_xdo_direction
  get_xdo_tnsstring
}

function xdo_handle_retval
{
  RETVAL=$?
  FAILED_FLAG="N"
  if [ $RETVAL -ne 0 ]; then
    error "-> FAILED TO XDOLOAD $XDOUTIL_DIRECTION."
	if [ -f $XDO_LOGFILE ]; then
	  error "Output of $XDO_LOGFILE:"
	  cat $XDO_LOGFILE
	fi
    error "Aborting...."
	FAILED_FLAG="Y"
	if [ "$STOP_ON_ERROR" = "Y" ]; then
		exit 1
	fi
  fi
  if [ -f $XDO_LOGFILE ]; then
	debug "Content of logfile: $(cat $XDO_LOGFILE)"
	rm -f $XDO_LOGFILE
  fi
}

function xdo_download_post
{
  xdo_handle_retval
  info "-> Extracted to $(basename $XDOUTIL_FILENAME)"
 
}

function xdo_upload_post
{
  xdo_handle_retval
  if [ "$FAILED_FLAG" = "N" ]; then
	  registerProcessedChange "$XDOUTIL_FILENAME"
	  info "-> uploaded without errors, cleaning up tmp-file"
  else
	  warning "-> Continuing despite failure."
  fi
}

function set_xdo_filename
{
  export XDOUTIL_FILENAME=$(echo "$1" | sed 's/ /_/g')
}


function set_xdo_languages
{
  export XDOUTIL_LANGUAGES="$1"
  RICEW_PRE_INSTALL_COMMAND="set_xdo_languages $1"
}

function set_xdo_long_lang
{
  if [ "$XDOUTIL_TERRITORY" = "00" ]; then
	export XDOUTIL_LONG_LANG="${XDOUTIL_LANGUAGE}"
  else
	export XDOUTIL_LONG_LANG="${XDOUTIL_LANGUAGE}_${XDOUTIL_TERRITORY}"
  fi
  debug "-> Set XDO_LONG_LANG to: $XDOUTIL_LONG_LANG"
}

function set_xdo_territory
{
  NEW_XDOUTIL_TERRITORY="$1"
  debug "-> Set XDO_TERRITORY to: $NEW_XDOUTIL_TERRITORY"
  export XDOUTIL_TERRITORY=${NEW_XDOUTIL_TERRITORY}
}

function set_xdo_lang
{
  NEW_XDOUTIL_LANGUAGE="$1"
  debug "-> Set XDO_LANGUAGE to: $NEW_XDOUTIL_LANGUAGE"
  export XDOUTIL_LANGUAGE=${NEW_XDOUTIL_LANGUAGE}
}

#############################
#### Data Templates      ####
#############################
function xdo_load_data_templ
{
    EBS_ACCLERATOR_CMDLINE="xdo_load_data_templ \"$1\" \"$2\" \"$3\" \"$4\""
	CURRENT_APPNAME=$1
	xdo_load_init "Data Template" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang ${long_lang}
			set_xdo_filename "${XDO_STAGING_DIR}/DATA_TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.xml"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_data_templ $*
			else
				xdo_ul_data_templ $*		
			fi
		done
	fi
}

function xdo_ul_data_templ
{
	detectChange "$XDOUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then	

		debug "
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD <hidden> \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE DATA_TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE 00 \
			-TERRITORY 00 \
			-XDO_FILE_TYPE XML-DATA-TEMPLATE \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		"
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD $APPS_PASSWD \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE DATA_TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE 00 \
			-TERRITORY 00 \
			-XDO_FILE_TYPE XML-DATA-TEMPLATE \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		xdo_upload_post
	fi
}


function xdo_dl_data_templ
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm -f /tmp/xxcu_xdo_util/$$/* > /dev/null 2>&1
	cd /tmp/xxcu_xdo_util/$$
	
	debug "
		java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD 
		-DB_USERNAME apps 
		-DB_PASSWORD <hidden> 
		-JDBC_CONNECTION $XDO_TNS_STRING 
		-LOB_TYPE DATA_TEMPLATE 
		-APPS_SHORT_NAME $1 
		-LOB_CODE $CURRENT_NAME 
		-LANGUAGE 00 
		-TERRITORY 00
		"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE DATA_TEMPLATE \
		-APPS_SHORT_NAME $1 \
		-LOB_CODE $CURRENT_NAME \
		-LANGUAGE 00 \
		-TERRITORY 00 
	xdo_download_post		
	xdo_outfile="DATA_TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}.*"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
  	xdo_handle_retval	
    add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
    
	unset xdo_outfile
	cd -
}
#############################
#### RTF Templates       ####
#############################

function xdo_load_rtf_templ
{
    EBS_ACCLERATOR_CMDLINE="xdo_load_rtf_templ \"$1\" \"$2\" \"$3\" \"$4\""
    CURRENT_APPNAME="$1"  
    xdo_load_init "Template" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang
			set_xdo_filename "${XDO_STAGING_DIR}/TEMPLATE_SOURCE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.rtf"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_rtf_templ $*
			else
				xdo_ul_rtf_templ $*		
			fi
		done
	fi
}

function xdo_ul_rtf_templ
{
	detectChange "$XDOUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then	

		debug "
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD <hidden> \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE $XDOUTIL_LANGUAGE \
			-TERRITORY $XDOUTIL_TERRITORY \
			-XDO_FILE_TYPE RTF \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		"
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD $APPS_PASSWD \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE $XDOUTIL_LANGUAGE \
			-TERRITORY $XDOUTIL_TERRITORY \
			-XDO_FILE_TYPE RTF \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		xdo_upload_post 
	fi
}

function xdo_dl_rtf_templ
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm /tmp/xxcu_xdo_util/$$/* > /dev/null 2>&1
	cd /tmp/xxcu_xdo_util/$$
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'application/rtf' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'application/rtf' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	xdo_download_post
	xdo_outfile="TEMPLATE_SOURCE_${CURRENT_APPNAME}_${CURRENT_NAME}*.*"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
	xdo_handle_retval
    add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
	unset xdo_outfile
	cd -
}


#############################
#### MLS Templates       ####
#############################

function xdo_load_mls_templ
{
    EBS_ACCLERATOR_CMDLINE="xdo_load_mls_templ \"$1\" \"$2\" \"$3\" \"$4\""
	CURRENT_APPNAME="$1"  
    xdo_load_init "MLS Template" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang
			set_xdo_filename "${XDO_STAGING_DIR}/MLS_TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.xsl"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_mls_templ $*
			else
				xdo_ul_mls_templ $*		
			fi
		done
	fi
}

function xdo_ul_mls_templ
{
        detectChange "$XDOUTIL_FILENAME"

        if [ $DETECT_FLAG -eq 1 ]; then

                debug "
                java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
                        -DB_USERNAME apps \
                        -DB_PASSWORD <hidden> \
                        -JDBC_CONNECTION $XDO_TNS_STRING \
                        -LOB_TYPE MLS_TEMPLATE \
                        -APPS_SHORT_NAME $CURRENT_APPNAME \
                        -LOB_CODE $CURRENT_NAME \
                        -LANGUAGE $XDOUTIL_LANGUAGE \
                        -TERRITORY $XDOUTIL_TERRITORY \
                        -XDO_FILE_TYPE XSL-FO \
                        -NLS_LANG $NLS_LANG \
                        -CUSTOM_MODE FORCE \
                        -FILE_NAME $XDOUTIL_FILENAME
                "
                java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
                        -DB_USERNAME apps \
                        -DB_PASSWORD $APPS_PASSWD \
                        -JDBC_CONNECTION $XDO_TNS_STRING \
                        -LOB_TYPE MLS_TEMPLATE \
                        -APPS_SHORT_NAME $CURRENT_APPNAME \
                        -LOB_CODE $CURRENT_NAME \
                        -LANGUAGE $XDOUTIL_LANGUAGE \
                        -TERRITORY $XDOUTIL_TERRITORY \
                        -XDO_FILE_TYPE XSL-FO \
                        -NLS_LANG $NLS_LANG \
                        -CUSTOM_MODE FORCE \
                        -FILE_NAME $XDOUTIL_FILENAME
                xdo_upload_post
        fi
}

function xdo_dl_mls_templ
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm /tmp/xxcu_xdo_util/$$/* > /dev/null 2>&1
	cd /tmp/xxcu_xdo_util/$$
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE MLS_TEMPLATE \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE MLS_TEMPLATE \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	xdo_download_post
	xdo_outfile="MLS_TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}_*.*"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
	xdo_handle_retval
    add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
    
	unset xdo_outfile
	cd -
}


#############################
### BI Publisher Bursting ###
#############################
function xdo_load_bursting_file
{

    EBS_ACCLERATOR_CMDLINE="xdo_load_bursting_file \"$1\" \"$2\" \"$3\" \"$4\""
	CURRENT_APPNAME="$1"  
    xdo_load_init "Bursting File" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang
			set_xdo_filename "${XDO_STAGING_DIR}/BURSTING_FILE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.xsl"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_bursting_file $*
			else
				xdo_ul_bursting_file $*
			fi
		done
	fi

}

function xdo_ul_bursting_file
{

        detectChange "$XDOUTIL_FILENAME"

        if [ $DETECT_FLAG -eq 1 ]; then

                debug "
                java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
                        -DB_USERNAME apps \
                        -DB_PASSWORD <hidden> \
                        -JDBC_CONNECTION $XDO_TNS_STRING \
                        -LOB_TYPE BURSTING_FILE \
						-XDO_FILE_TYPE XML-BURSTING-FILE \
                        -APPS_SHORT_NAME $CURRENT_APPNAME \
                        -LOB_CODE $CURRENT_NAME \
                        -LANGUAGE $XDOUTIL_LANGUAGE \
                        -TERRITORY $XDOUTIL_TERRITORY \
                        -NLS_LANG $NLS_LANG \
                        -CUSTOM_MODE FORCE \
                        -FILE_NAME $XDOUTIL_FILENAME
                "
                java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
                        -DB_USERNAME apps \
                        -DB_PASSWORD $APPS_PASSWD \
                        -JDBC_CONNECTION $XDO_TNS_STRING \
						-LOB_TYPE BURSTING_FILE \
						-XDO_FILE_TYPE XML-BURSTING-FILE \
                        -APPS_SHORT_NAME $CURRENT_APPNAME \
                        -LOB_CODE $CURRENT_NAME \
                        -LANGUAGE $XDOUTIL_LANGUAGE \
                        -TERRITORY $XDOUTIL_TERRITORY \
                        -NLS_LANG $NLS_LANG \
                        -CUSTOM_MODE FORCE \
                        -FILE_NAME $XDOUTIL_FILENAME
                xdo_upload_post
        fi

}		

function xdo_dl_bursting_file
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm -f /tmp/xxcu_xdo_util/$$/* > /dev/null 2>&1
	cd /tmp/xxcu_xdo_util/$$
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE BURSTING_FILE \
		-XDO_FILE_TYPE XML-BURSTING-FILE \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LOB_CODE $CURRENT_NAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-FILE_NAME $XDOUTIL_FILENAME > $XDO_LOGFILE
	"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE BURSTING_FILE \
		-XDO_FILE_TYPE XML-BURSTING-FILE \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LOB_CODE $CURRENT_NAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-FILE_NAME $XDOUTIL_FILENAME > $XDO_LOGFILE
	xdo_download_post
	xdo_outfile="$XDOUTIL_FILENAME"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
	xdo_handle_retval
	add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
	unset xdo_outfile
	cd -
}

#############################
#### XSL Templates       ####
#############################

function xdo_load_xsl_templ
{
    EBS_ACCLERATOR_CMDLINE="xdo_load_xsl_templ \"$1\" \"$2\" \"$3\" \"$4\""
	CURRENT_APPNAME="$1"  
    xdo_load_init "Template" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang

			set_xdo_filename "${XDO_STAGING_DIR}/TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.xsl"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_xsl_templ $*
			else
				xdo_ul_xsl_templ $*		
			fi
		done
	fi
}

function xdo_ul_xsl_templ
{
	detectChange "$XDOUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then	
	
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LOB_CODE $CURRENT_NAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-XDO_FILE_TYPE XSL-FO \
		-NLS_LANG $NLS_LANG \
		-CUSTOM_MODE FORCE \
		-FILE_NAME $XDOUTIL_FILENAME  > /dev/null 2>&1
	"

		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD $APPS_PASSWD \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE $XDOUTIL_LANGUAGE \
			-TERRITORY $XDOUTIL_TERRITORY \
			-XDO_FILE_TYPE XSL-FO \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME > /dev/null 2>&1
		xdo_upload_post 
	fi
}

function xdo_dl_xsl_templ
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm -f /tmp/xxcu_xdo_util/$$/*
	cd /tmp/xxcu_xdo_util/$$
	echo "XDOUTIL_LANGUAGE is" ${XDOUTIL_LANGUAGE}
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'text/xml' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE 2>&1
	"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'text/xml' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE 2>&1
	xdo_download_post
	xdo_outfile="TEMPLATE_${CURRENT_APPNAME}_${CURRENT_NAME}*.xsl"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
	xdo_handle_retval
	add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
	unset xdo_outfile
	cd -
}

#############################
#### XLS Templates       ####
#############################

function xdo_load_xls_templ
{
    EBS_ACCLERATOR_CMDLINE="xdo_load_xls_templ \"$1\" \"$2\" \"$3\" \"$4\""
	CURRENT_APPNAME="$1"  
    xdo_load_init "Template" "$2" "$3" "$4"
    if [ $SKIP_FLAG = "N" ]; then
		for long_lang in $XDOUTIL_LANGUAGES; do
			lang=$(echo $long_lang | cut -d_ -f1)
			territory=$(echo $long_lang | cut -d_ -f2)
			set_xdo_lang $lang
			set_xdo_territory $territory
			set_xdo_long_lang
			set_xdo_filename "${XDO_STAGING_DIR}/TEMPLATE_SOURCE_${CURRENT_APPNAME}_${CURRENT_NAME}_${XDOUTIL_LONG_LANG}.xls"
			if [ "$XDOUTIL_DIRECTION" = "DOWNLOAD" ]; then
				xdo_dl_xls_templ $*
			else
				xdo_ul_xls_templ $*		
			fi
		done
	fi
}

function xdo_ul_xls_templ
{
	detectChange "$XDOUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then	

		debug "
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD <hidden> \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE $XDOUTIL_LANGUAGE \
			-TERRITORY $XDOUTIL_TERRITORY \
			-XDO_FILE_TYPE XLS \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		"
		
		java oracle.apps.xdo.oa.util.XDOLoader UPLOAD \
			-DB_USERNAME apps \
			-DB_PASSWORD $APPS_PASSWD \
			-JDBC_CONNECTION $XDO_TNS_STRING \
			-LOB_TYPE TEMPLATE \
			-APPS_SHORT_NAME $CURRENT_APPNAME \
			-LOB_CODE $CURRENT_NAME \
			-LANGUAGE $XDOUTIL_LANGUAGE \
			-TERRITORY $XDOUTIL_TERRITORY \
			-XDO_FILE_TYPE XLS \
			-NLS_LANG $NLS_LANG \
			-CUSTOM_MODE FORCE \
			-FILE_NAME $XDOUTIL_FILENAME 
		xdo_upload_post 
	fi
}

function xdo_dl_xls_templ
{
	mkdir -p /tmp/xxcu_xdo_util/$$
	rm -f /tmp/xxcu_xdo_util/$$/* > /dev/null 2>&1
	cd /tmp/xxcu_xdo_util/$$
	debug "XDOUTIL_LANGUAGE is" ${XDOUTIL_LONG_LANG}
	debug "
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD <hidden> \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'application/vnd.ms-excel' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	"
	java oracle.apps.xdo.oa.util.XDOLoader DOWNLOAD \
		-DB_USERNAME apps \
		-DB_PASSWORD $APPS_PASSWD \
		-JDBC_CONNECTION $XDO_TNS_STRING \
		-LOB_TYPE TEMPLATE \
		-FILE_CONTENT_TYPE 'application/vnd.ms-excel' \
		-APPS_SHORT_NAME $CURRENT_APPNAME \
		-LANGUAGE $XDOUTIL_LANGUAGE \
		-TERRITORY $XDOUTIL_TERRITORY \
		-LOB_CODE $CURRENT_NAME > $XDO_LOGFILE
	xdo_download_post
	xdo_outfile="TEMPLATE_SOURCE_${CURRENT_APPNAME}_${CURRENT_NAME}_*.*"
	debug "In TEMP /tmp/xxcu_xdo_util/$$ directory- List all Files"
	debug "$(ls -al)"
	mv $xdo_outfile $XDOUTIL_FILENAME
	xdo_handle_retval
	add_ricew_manager_metadata "$XDOUTIL_FILENAME" '#' 'XDOLOAD'
	unset xdo_outfile
	cd -
}
