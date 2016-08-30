#!/bin/bash
##########################################
# Author: Bjørn Erik Hoel, Accenture     #
# Date:   11.Oct.2011                    #
# Name:   xxcu_deploy_workflow.sh       #
##########################################
. $XXCU_TOP/bin/xxcu_installutil.sh

do_login apps

#####################################################
# Add Workflows to this section. Fetched form XXCU_TOP/admin/config/WFLOAD
#####################################################
# FORCE UPLOAD THE FOLLOWING WORKFLOWS
########
set_wf_upload_mode "FORCE"
#processWorkflow "POWFPOAG.wft"
#processWorkflow "POAPPRV.wft"
#processWorkflow "POWFRQAG.wft"
########
# "UPGRADE" UPLOAD THE FOLLOWING WORKFLOWS
########
set_wf_upload_mode "UPGRADE"
#processWorkflow "PAAPINVW.wft"
