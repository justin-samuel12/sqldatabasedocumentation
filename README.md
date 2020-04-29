# Documenting SQL Server objects in a bulk manner
SQL file which will allow you to document multiple objects at a time.

Please download and install on your SQL Server. 

### License
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](License) 
******
### Description
> Procedure that will document multiple objects (on a user database) in bulk fashion.\
**MUST HAVE SQL Server 2016 or greater.**

Inspiration came from:

https://www.red-gate.com/simple-talk/sql/sql-tools/towards-the-self-documenting-sql-server-database/ 
and https://www.red-gate.com/simple-talk/sql/database-delivery/scripting-description-database-tables-using-extended-properties/ 

There are 2 params:
- **@Documentation** NVARCHAR(MAX)   - Must be in JSON format 
- **@OutputResults** BIT (DEFAULT 0) - only call if you want the results to be visible
- **@Helper**	   BIT (DEFAULT 0) - only call if you want the helper to be visible 

For the Documentation param, the following keys are required: 
- **objectname**    - what is the name of the object in schema.object format (ie. dbo.patient, dbo.patient.PatientId, dbo.patient.pk_PatientId) 
- **hierarchtype**  - details in later section 
- **property**			- what is the property of the object that should be updated. By default, it is set to `MS_Description`. 
- **function**			- update / delete / append. For update and append, if there is no existing text, `sp_addextendedproperty` will be used instead. 
- **commandText**		- what is the text to be placed on the object's property

Both Object Name and Hierarchy Type must has equal number of keys.

This procedure can be called outside of the master database BUT will not allow system databases to be documented.

### Hierarch Type				
> The following keys will be considered to be used:

      - database
      - asymmetric key
      - certificate
      - plan guide
      - synonym
      - schema.aggregate
      - contract
      - assembly
      - schema.default
      - event notification
      - filegroup
      - filegroup.logical file name
      - schema.function
      - schema.function.column
      - schema.function.constraint
      - schema.function.parameter
      - message type
      - partition function
      - partition scheme
      - schema.procedure
      - schema.procedure.parameter
      - schema.queue
      - schema.queue.event notification
      - remote service binding
      - route
      - schema.rule
      - schema
      - service
      - schema.service
      - schema.synonym
      - schema.table
      - schema.table.column
      - schema.table.constraint
      - schema.table.index
      - schema.table.trigger
      - symmetric key
      - trigger
      - type
      - schema.type
      - schema.view
      - schema.view.column
      - schema.view.index
      - schema.view.trigger
      - schema.xml schema collection

### Examples
```
-- to view documentation helper
EXECUTE sp_DBDocumentation @helper = 1

-- passing values directly 
EXECUTE sp_DBDocumentation '[
{"objectname":"dbo.Response","hierarchtype":"schema.table","property":"MS_Description","function":"update","commandText":"new comment"},
{"objectname":"dbo.ResponseToHealthEval","hierarchtype":"schema.table","property":"MS_Description","function":"delete","commandText":""},
{"objectname":"dbo.ConnectionManager","hierarchtype":"schema.table","property":"MS_Description","function":"append","commandText":"adding another comment"}
]'

-- creating variable and then passing
DECLARE @value NVARCHAR(MAX)='[
{"objectname":"dbo.Response","hierarchtype":"schema.table","property":"MS_Description","function":"update","commandText":"new comment"},
{"objectname":"dbo.ResponseToHealthEval","hierarchtype":"schema.table","property":"MS_Description","function":"delete","commandText":""},
{"objectname":"dbo.ConnectionManager","hierarchtype":"schema.table","property":"MS_Description","function":"append","commandText":"adding another comment"}
]'

EXECUTE sp_DBDocumentation @Value
```
