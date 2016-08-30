#!/bin/bash
##########################################
# Author: Bjørn Erik Hoel, Accenture     #
# Date:   14.Dec.2011                    #
# Name:   xxcu_deploy_fnd_objects.sh     #
##########################################
PROGRAM_NAME=`basename $0 .sh`

. $XXCU_TOP/bin/xxcu_fndutil.sh

########################################################################################
#                               CONFIGURE THIS RUN                           	       #
########################################################################################
# Require either UPLOAD or DOWNLOAD of files in the below load-statements
set_fnd_direction $1

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

# Verify apps login
do_login apps

#####################################
#### BLOCK SPECIFIC INSTRUCTIONS ####
#####################################
# Each of the below blocks is reserved for each type of entity
# The order in which these are listed is recommended, as it correlates to the typical dependency order in which 
# the FNDLOAD scripts are typically run. (Used in multiple implementations with thousands of FNDLOAD entities)
# The mandatory parameters have sample values in them, whilst purely freetext (cosmetic) parameters have <> in them
# These freetext parameters simply provide better description during runtime.
# It is always a good idea to put a persons name in the contact parameter, as the DBA will have a point of contact in
# the event that a .ldt file fails for some reason.
# If there is doubt as to what the parameters refer to, please look in xxcu_fndutil.sh
#####################################

######################
#### Lookup Types ####    
######################
#fnd_load_lookups "XXCU" "XXCU_CH_ITEM_CAT_QTY_CHECK" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

###################
#### Valuesets ####
###################
#fnd_load_value_set "XXCU_NON_MET_PO_FROM" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

###################################
#### Advanced Pricing Contexts ####
###################################
#fnd_load_qp_prc_contexts "FIRM" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

################################
#### Descriptive Flexfields ####
################################
#fnd_load_desc_flexfield "PO" "PO_LINES" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# fnd Folders 
# NOT PROPERLY SUPPORTED BY ORACLE USE WITH EXTREME CAUTION!
############################
#fnd_load_folders  "US AP Invoice Batch Folder"  "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Form Functions
############################
#fnd_load_form_function "XXCU_MOB_MOVEB_SA" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Messages
############################
#fnd_load_messages "XXCU" "XXCU_PO_WF_NOTIF_SUPPLIER" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Menus
############################
#fnd_load_menus "XXCU_PO_APPROVER" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"


############################
# Responsibility
############################
#fnd_load_responsibility "XXCU_IBE_SALESREP" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

###############################
#### Forms personalization ####
###############################
#fnd_load_forms_pers "XXCU_SCALE_RECEIPTS" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Profile Options
############################
#fnd_load_profile_option "XXCU_READ_ONLY" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

##########################################
####   Printers (Used for interfaces  ####
##########################################
#fnd_load_printer "XXCU_SALES_ORDER_EXTRACT" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

#############################
#### Concurrent Programs ####
#############################
#fnd_load_conc_program "XXCU" "XXCU_00030_XML" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
#Request Sets
############################
#fnd_load_request_sets "XXCU" "XXCU_AR_AUTOINV_CANADA" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Request Groups
############################
#fnd_load_request_group "XXCU SA Settlement Reports" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

############################
# Alerts
############################
#fnd_load_alert "XXCU" "MXN_CURR_DAILYRATE_VAL" "<Insert description here (Freetext)>" "<Insert Contact Person Name (FreeText)>"

