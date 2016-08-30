#!/bin/bash
##########################################
# Author: Bjorn Erik Hoel, Accenture     #
# Date:   02.May.2012                    #
# Name:   xxcu_deploy_ak_objects.sh      #
##########################################
PROGRAM_NAME=`basename $0 .sh`

. $XXCU_TOP/bin/xxcu_akutil.sh

########################################################################################
#                               CONFIGURE THIS RUN                                       #
########################################################################################
# Require either UPLOAD or DOWNLOAD of files in the below load-statements
set_ak_direction $1
########################################################################################

# Verify apps login
do_login apps

# Region AKLoad
#ak_load_regions "IBE" "SAMPLE_IBE_ORD_DTL_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_INV_SUM_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_SHP_DTL_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_DLY_DTL_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_DLY_HDR_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_SHP_HDR_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_INV_DTL_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_INV_HDR_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_PMT_DTL_R" "Used in iStore - Telukunta"
#ak_load_regions "IBE" "SAMPLE_IBE_INV_SUM_R" "Used in iStore - Telukunta"


