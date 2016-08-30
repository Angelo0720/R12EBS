#!/bin/bash
##########################################
# @author Bjørn Erik Hoel, Accenture
# $Id:  $
# @version $Revision: 57373 $
# Date:   14.Dec.2011
# Name:   xxcu_deploy_xdo_objects.sh
##########################################
PROGRAM_NAME=`basename $0 .sh`

. $XXCU_TOP/bin/xxcu_xdoutil.sh      # Basic xdoload functionality
. $XXCU_TOP/bin/xxcu_fndutil.sh      # Basic fndload functionality

########################################################################################
#                               CONFIGURE THIS RUN                           	       #
########################################################################################
# Always force user to specify password
export ASK_PASSWORD="N"
# Require either UPLOAD or DOWNLOAD of files in the below load-statements

# Verify parameter
if [ "$1" = "UPLOAD" ] || [ "$1" = "DOWNLOAD" ]
then
	export XXCU_DIRECTION="$1"
else
	verify_direction
fi

# Configure XDOLOAD utility
if [ "$UTIL_DIRECTION" = "" ]; then
	set_fnd_direction $XXCU_DIRECTION
	set_xdo_direction $XXCU_DIRECTION
fi

# Calling this function will extract both US version of setup respectively
set_nls_languages "US"
# Can be a list of languages too, in which case it will generate ldt files for any list of languages, ie:
# set_nls_languages "D NL CHS US"
########################################################################################

########################################################################################
###### Variables configured by setting environment variables in calling shell #######
########################################################################################
# The below variables are initialized in xxcu_fndutil.sh, and will affect how processing is done
# SKIPCOUNT: 0-n
# DATA_STAGING_DIR: <directory of .ldt>
# STOP_ON_ERROR: Y|N
########################################################################################

################################
#set_xdo_languages "en_US" 
#fnd_load_conc_program "XXCU" "XXCU_00039_XML" "<Insert description here>" "<Insert Contact Person here>"
#fnd_load_xdosetup     "XXCU" "XXCU_00039_XML" "<Insert description here>" "<Insert Contact Person here>"
#xdo_load_rtf_templ    "XXCU" "XXCU_00039_XML" "<Insert description here>" "<Insert Contact Person here>"
################################
#set_xdo_languages "en_US"
#fnd_load_conc_program "XXCU" "XXCU_00125" "<Insert description here>" "<Insert Contact Person here>"
#fnd_load_xdosetup     "XXCU" "XXCU_00125" "<Insert description here>" "<Insert Contact Person here>"
#xdo_load_rtf_templ    "XXCU" "XXCU_00125" "<Insert description here>" "<Insert Contact Person here>"
#xdo_load_data_templ   "XXCU" "XXCU_00125" "<Insert description here>" "<Insert Contact Person here>"
################################

################################
# MLS BLOCK
################################
#set_nls_languages "ZHS"
#set_xdo_languages "zh_CN"
#xdo_load_mls_templ  "XXCU" "XXCU_CONTLIST_RT" "<Insert description here>" "<Insert Contact Person here>"

#set_nls_languages "ZHS"
#set_xdo_languages "zh_CN"
#xdo_load_mls_templ  "XXCU" "XXCU_CH_PAY_NOTICE" "<Insert description here>" "<Insert Contact Person here>"

