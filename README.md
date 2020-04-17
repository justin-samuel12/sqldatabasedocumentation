# Documenting SQL Server objects in a bulk manner
SQL file which will allow you to document multiple objects at a time
___
### License
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](License) 
___
### Description
> Procedure that will document multiple objects (on a user database) in bulk fashion.\
Must has SQL Server 2016 or greater.\
Inspiration came from:\
https://www.red-gate.com/simple-talk/sql/sql-tools/towards-the-self-documenting-sql-server-database/ and\
https://www.red-gate.com/simple-talk/sql/database-delivery/scripting-description-database-tables-using-extended-properties/ 

There are 2 params:\
  @Documentation NVARCHAR(MAX)    - Must be in JSON format \
  @Helper				 BIT (DEFAULT 0)	- only call if you want the helper to be visible 

For the Documentation param, the following keys are required: 
- objectname    - what is the name of the object in schema.object format (ie. dbo.patient, dbo.patient.PatientId, dbo.patient.pk_PatientId) 
- hierarchtype  - details in later section 
- property			- what is the property of the object that should be updated. By default, it is set to "MS_Description". 
- function			- update / delete / append. For update and append, if there is no existing text, sp_addextendedproperty will be used instead. 
- commandText		- what is the text to be placed on the object's property

Both Object Name and Hierarchy Type must has equal number of keys.

This procedure can be called outside of the master database BUT will not allow system databases to be documented.
				
