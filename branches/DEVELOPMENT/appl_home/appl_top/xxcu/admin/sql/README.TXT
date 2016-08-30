{CUSTOM_TOP}/admin/sql
- This is typically where all DDL / DML statement scripts are stored (One time run / compilable objects)
	- Package specifications: .pks
	- Package bodies: .pkb
	- General table / index scripts: .sql

- Files here are typically referenced from the $CUSTOM_TOP/install/*.aifo files containing the Installation Framework for Oracle DB 
  master control file, specifying the order and user in which the objects are processed

Got you