{CUSTOM_TOP}/install
- Used by AFPO Installation Framework for Oracle DB
	- This directory typically holds the install master files (.aifo) and the custom pom.xml file 
	- An .aifo file contains the order in which files are processed when evaluating whether or not they should have DDL/DML executed
	- The custom .pom file contains several mandatory environment variables which are used to handle multiple environments and allows for 
	  a single pom-file for all your installations across environments. Just set the environment variables accordingly during runtime in your
	  continous integration tool (Jenkins / Hudson or similar)



