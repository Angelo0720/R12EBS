#!/bin/ksh
# $Id:  $
##########################################
# Author: Bjorn Erik Hoel, Accenture     #
# Date:   02.May.2012                    #
# Name:   xxcu_akutil.sh                 #
##########################################

. $XXCU_TOP/bin/xxcu_installutil.sh  # Functionality to detect changes

DATA_STAGING_DIR=${DATA_STAGING_DIR:-$XXCU_TOP/admin/config/AKLOAD}

function get_ak_tnsstring
{
	AK_TNS_STRING=`perl -e 'my $read = undef;
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

function verify_ak_direction
{
  if [ "$AKUTIL_DIRECTION" = "" ]; then
    error "-> Set direction by calling set_ak_direction with either 'UPLOAD' or 'DOWNLOAD'"
	exit 1
  fi
}

function set_ak_direction
{
  if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]; then
	export AKUTIL_DIRECTION="$1"
  else
	error "Usage: $0 <UPLOAD|DOWNLOAD>"
	exit 1	
  fi
}

function ak_load_init
{
  CURRENT_TYPE="$1"
  CURRENT_NAME="$2"
  CURRENT_DESC="$3"
  WHO="$4"
  info "##############################################"
  info "# $AKUTIL_DIRECTION $CURRENT_TYPE using oracle.apps.ak.akload"
  info "##############################################"
  info "# Name: $CURRENT_NAME"
  info "# Desc: $CURRENT_DESC"
  info "# Registered by: $WHO"  
  info "##############################################"
  # Make sure logs end up in its own directory
  mkdir -p $XXCU_TOP/install/log
  mkdir -p ${DATA_STAGING_DIR}
  cd $XXCU_TOP/install/log
  
  verify_ak_direction
  get_ak_tnsstring
}

function ak_handle_retval
{
  RETVAL=$?
  if [ $RETVAL -ne 0 ]; then
    error "-> FAILED TO AKLOAD $AKUTIL_DIRECTION check last logfile."
    exit 1
  fi
}

function ak_download_post
{
  ak_handle_retval

  info "-> Extracted to $(basename $AKUTIL_FILENAME)"
}

function ak_upload_post
{
  ak_handle_retval
  registerProcessedChange "$AKUTIL_FILENAME"
  info "-> uploaded without errors, cleaning up tmp-file"
}

function set_ak_filename
{
  export AKUTIL_FILENAME=$(echo "$1" | sed 's/ /_/g')
}


######################
#### Regions      ####
######################
function ak_load_regions
{
	CURRENT_APPNAME=$1
	ak_load_init "Regions" "$2" "$3" "$4"
	set_ak_filename "${DATA_STAGING_DIR}/REGION_${CURRENT_APPNAME}_${CURRENT_NAME}.ldt"
		if [ "$AKUTIL_DIRECTION" = "DOWNLOAD" ]; then
			ak_dl_region $*
		else
			ak_ul_region $*		
		fi
}

function ak_ul_region
{
	detectChange "$AKUTIL_FILENAME"

	if [ $DETECT_FLAG -eq 1 ]; then	

		debug "
			java oracle.apps.ak.akload apps <hidden> 
				THIN \"$AK_TNS_STRING\"				
				UPLOAD $AKUTIL_FILENAME 
				UPDATE $NLS_LANG
		"

		java oracle.apps.ak.akload apps $APPS_PASSWD \
				THIN "$AK_TNS_STRING" \
				UPLOAD $AKUTIL_FILENAME \
				UPDATE $NLS_LANG
		ak_upload_post
	fi
}

function ak_dl_region
{
	debug "
		java oracle.apps.ak.akload apps <hidden> 
			THIN \"$AK_TNS_STRING\"
			DOWNLOAD $AKUTIL_FILENAME
			GET CUSTOM_REGION $CURRENT_APPNAME 
			$CURRENT_NAME
	"
	java oracle.apps.ak.akload apps $APPS_PASSWD \
			THIN "$AK_TNS_STRING" \
			DOWNLOAD $AKUTIL_FILENAME \
			GET CUSTOM_REGION $CURRENT_APPNAME \
				$CURRENT_NAME
				
	ak_handle_retval	
	ak_download_post		
}

