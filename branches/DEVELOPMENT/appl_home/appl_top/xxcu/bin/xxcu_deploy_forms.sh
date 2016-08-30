#!/bin/bash
##########################################
# Author: Bjørn Erik Hoel, Accenture     #
# Date:   11.Oct.2011                    #
# Name:   xxcu_deploy_forms.sh          #
##########################################
. $XXCU_TOP/bin/xxcu_installutil.sh

do_login apps

# Will control FORMS_PATH structure
set_forms_language "US"

#####################################################
# Example - Add PLL libraries to this section 
#####################################################
#processLibrary "../resource/CUSTOM.pll"


#####################################################
# Example - Add FMB libraries to this section 
#####################################################
#processForm "../forms/US/XXCU_AVAIL_CAPACITY.fmb"
#processForm "../forms/US/XXCU_CAPACITY_RESRV.fmb"
#processForm "../forms/US/XXCU_CAP_RESV_QUOTE.fmb"
#processForm "../forms/US/XXCU_APPTINQ.fmb"
