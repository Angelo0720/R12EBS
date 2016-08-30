{CUSTOM_TOP}/bin
- Main framework directory
	- All shellscripts are located here

#########################################
#####   FRAMEWORK SPECIFIC FILES    #####
#########################################

xxcu_logutil.sh
	- Logging functions (DEBUG/INFO/WARNING/ERROR), Enable DEBUG by setting LOG_LEVEL=DEBUG in environment at runtime

xxcu_scriptutil.sh
	- Utility functions for handling passwords, SQL*Plus pipelines within shellscripts. Used heavily by below scripts

xxcu_installutil.sh
	- Functions for handling compilation of external objects, like forms (fmb) and libraries (pll) as well as handling any external file SHA-1 checksum within the environment repository

xxcu_fndutil.sh
	- Functions for handling FNDLOAD capability. This calls FNDLOAD with the appropriate lct file and handles all file handling mechanisms as well as conversion across multi-byte-characterset

xxcu_xdoutil.sh
	- Functions for handling XDOLoad capability. This calls oracle.apps.xdo.oa.util.XDOLoader

xxcu_akutil.sh
	- Functions for handling AKLoad capability. This calls oracle.apps.ak.akload

xxcu_mdsutil.sh
	- Functions for handling MDS Import capability. This calls oracle.jrad.tools.xml.importer.XMLImporter

xxcu_oafutil.sh
	- Handles OAF Customizations - Might require some changes to suit your chosen structure if you want to deviate from JDEV_TOP/MyProjects/ as the holding area for the OAF files

#########################################
##### IMPLEMENTATION SPECIFIC FILES #####
#########################################
# Add your content here 
#########################################

	
#########################################
#####  CUSTOM LCT FILES FOR FNDLOAD  ####
#########################################
# These are referenced from xxcu_fndutil.sh
#########################################
xxcu_afcpprog.lct
	- Removed the feature that pulls valuesets associated with concurrent programs, as these should be extracted separately, and handled separately
xxcu_fndfold.lct
	- Added better error handling and logging
XXCU_QPXPATMD.lct
	- Added better error handling and logging
