SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO
USE [MASTER]
GO
IF (@@microsoftversion / POWER(2, 24)) >=13
BEGIN
-- add custom message
DECLARE @message_id	INT;				

-- adding "not allowed documentation on system database"
SET @message_id = 64500;
EXEC sp_addmessage 
	@msgnum = @message_id, 
	@severity = 1, 
	@msgtext = 'System databases are not allowed to be documented! Current database is (%s)',
	@replace = 'replace';

-- adding "not allowed documentation on system database"
SET @message_id = 64501;
EXEC sp_addmessage 
	@msgnum = @message_id, 
	@severity = 1, 
	@msgtext = 'Documented value is not in JSON format!',
	@replace = 'replace';																				

EXEC ('DROP PROCEDURE IF EXISTS sp_DBDocumentation;')
EXEC ('CREATE PROCEDURE sp_DBDocumentation AS SELECT DB_Name()');				
EXEC sys.sp_MS_marksystemobject 'sp_DBDocumentation';

EXEC('ALTER PROCEDURE sp_DBDocumentation
(
	@Documentation	NVARCHAR(MAX)='''',
	@Helper			BIT	=0		
)
AS
SET NOCOUNT ON; SET XACT_ABORT ON;

/*------------------------ INITIAL VARIABLES ------------------------*/
DECLARE @DBName		SYSNAME = DB_NAME(),
		@Message	VARCHAR(MAX);

-- Not allowing documentation on system databases
IF (@Helper = 0 AND @DBName IN (''master'',''msdb'',''model'',''tempdb'',''resource''))
BEGIN												
	RAISERROR (64500,1,1,@DBName)
	RETURN
END

-- make sure that the Documentation variable is in JSON format
IF (@Helper = 0 AND ISJSON(@Documentation) =0)
BEGIN												
	RAISERROR (64501,1,1)
	RETURN;
END


IF (@Helper = 1)
BEGIN
SET @Message=''
<* 
DESCRIPTION:
Procedure that will document multiple objects (on a user database) in bulk fashion.
Must has SQL Server 2016 or greater.

Inspiration came from:
https://www.red-gate.com/simple-talk/sql/sql-tools/towards-the-self-documenting-sql-server-database/ and
https://www.red-gate.com/simple-talk/sql/database-delivery/scripting-description-database-tables-using-extended-properties/

There are 2 params:
@Documentation	NVARCHAR(MAX)	- Must be in JSON format
@Helper			BIT (DEFAULT 0)	- only call if you want the helper to be visible

For the Documentation param, the following keys are required:
	objectname		- what is the name of the object in schema.object format (ie. dbo.patient, dbo.patient.PatientId, dbo.patient.pk_PatientId)
	hierarchtype	- details in later section
	property		- what is the property of the object that should be updated. By default, it is set to "MS_Description".
	function		- update / delete / append. For update and append, if there is no existing text, sp_addextendedproperty will be used instead.
	commandText		- what is the text to be placed on the object''''s property

Both Object Name and Hierarchy Type must has equal number of keys.

This procedure can be called outside of the master database BUT will not allow system databases to be documented.

HIERARCH TYPE:
The following keys will be considered to be used:
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

EXAMPLES:
	-- to view documentation helper
	EXECUTE sp_DBDocumentation @helper = 1

-- passing values directly 
	EXECUTE sp_DBDocumentation ''''[
	{"objectname":"dbo.Response","hierarchtype":"schema.table","property":"MS_Description","function":"update","commandText":"new comment"},
	{"objectname":"dbo.ResponseToHealthEval","hierarchtype":"schema.table","property":"MS_Description","function":"delete","commandText":""},
	{"objectname":"dbo.ConnectionManager","hierarchtype":"schema.table","property":"MS_Description","function":"append","commandText":"adding another comment"}
	]''''

-- creating variable and then passing
	DECLARE @value NVARCHAR(MAX)=''''[
		{"objectname":"dbo.Response","hierarchtype":"schema.table","property":"MS_Description","function":"update","commandText":"new comment"},
		{"objectname":"dbo.ResponseToHealthEval","hierarchtype":"schema.table","property":"MS_Description","function":"delete","commandText":""},
		{"objectname":"dbo.ConnectionManager","hierarchtype":"schema.table","property":"MS_Description","function":"append","commandText":"adding another comment"}
		]''''

	EXECUTE sp_DBDocumentation @Value


CHANGE LOG:
	04/16/2020: initial release [Justin S.]				
*>
''
PRINT @Message
RETURN;
END
/*------------------------ VARIABLES -------------------------------*/
DECLARE @ObjectName    	SYSNAME,
		@HierarchyType 	SYSNAME,
		@Hierarchy     	SYSNAME,
		@Level0        	VARCHAR(256),
		@Level1        	VARCHAR(256),
		@Level2        	VARCHAR(256),
		@Name0         	VARCHAR(256),
		@Name1         	VARCHAR(256),
		@Name2         	VARCHAR(256),
		@CommandText   	SQL_VARIANT,
		@Value			SQL_VARIANT,
		@Property      	SYSNAME,
		@Function      	VARCHAR(10),
		@ObjectId		INT,
		@Return			INT,
		@Object_Cursor 	CURSOR;

DECLARE @Keys AS TABLE
(
	[Hierarchy]      VARCHAR(40) UNIQUE,
	[Level0]         VARCHAR(40),
	[Level1]         VARCHAR(40),
	[Level2]         VARCHAR(40)
);

DECLARE @Tabledefinition AS TABLE
(
	[pkid]         INT IDENTITY(1, 1) NOT NULL,
	[objectname]   SYSNAME NOT NULL,
	[hierarchtype] SYSNAME NOT NULL,
	[property]     SYSNAME NOT NULL	DEFAULT ''MS_Description'',
	[function]     VARCHAR(10) NOT NULL DEFAULT ''update'',
	[commandText]  SQL_VARIANT NOT NULL,
	CHECK([function] IN(''update'', ''delete'',	''append''))
);

DECLARE @Result					TABLE
(
	ObjectName	SYSNAME,
	[Hierarchy]	VARCHAR(40),
	[Function]	VARCHAR(10),
	Result		VARCHAR(256)
);
/*------------------------END VARIABLES -------------------------------*/

INSERT INTO @Keys
SELECT TheHierarchies.[Key], 
	REVERSE(PARSENAME(REVERSE(TheHierarchies.[Key]),1)),
	REVERSE(PARSENAME(REVERSE(TheHierarchies.[Key]),2)),
	REVERSE(PARSENAME(REVERSE(TheHierarchies.[Key]),3))
FROM
	(VALUES(''database''),
	(''asymmetric key''),
	(''certificate''),
	(''plan guide''),
	(''synonym''),
	(''schema.aggregate''),
	(''contract''),
	(''assembly''),
	(''schema.default''),
	(''event notification''),
	(''filegroup''),
	(''filegroup.logical file name''),
	(''schema.function''),
	(''schema.function.column''),
	(''schema.function.constraint''),
	(''schema.function.parameter''),
	(''message type''),
	(''partition function''),
	(''partition scheme''),
	(''schema.procedure''),
	(''schema.procedure.parameter''),
	(''schema.queue''),
	(''schema.queue.event notification''),
	(''remote service binding''),
	(''route''),
	(''schema.rule''),
	(''schema''),
	(''service''),
	(''schema.service''),
	(''schema.synonym''),
	(''schema.table''),
	(''schema.table.column''),
	(''schema.table.constraint''),
	(''schema.table.index''),
	(''schema.table.trigger''),
	(''symmetric key''),
	(''trigger''),
	(''type''),
	(''schema.type''),
	(''schema.view''),
	(''schema.view.column''),
	(''schema.view.index''),
	(''schema.view.trigger''),
	(''schema.xml schema collection'')
	) TheHierarchies([Key]);

INSERT INTO @Tabledefinition
SELECT	*
FROM OPENJSON(@Documentation)
WITH
(
	[objectname]	SYSNAME			''$.objectname'',
	[hierarchtype]	SYSNAME			''$.hierarchtype'', 
	[property]		SYSNAME			''$.property'',
	[function]		VARCHAR(10)		''$.function'',
	[commandText]	VARCHAR(4000)	''$.commandText''
)
BEGIN TRY

DECLARE Object_Cursor CURSOR FAST_FORWARD FOR  
	SELECT [td].[objectName],
		REVERSE(PARSENAME(REVERSE([td].[objectName]), 1)),
		REVERSE(PARSENAME(REVERSE([td].[objectName]), 2)),
		REVERSE(PARSENAME(REVERSE([td].[objectName]), 3)),
		[td].[hierarchtype],
		[td].[property],
		[td].[function],
		[td].[commandtext],
		[h].Hierarchy,
		[h].[Level0],
		[h].[Level1],
		[h].[Level2],
		OBJECT_Id([td].[objectName]) 
		FROM   @TableDefinition [td]
	LEFT JOIN @Keys [h] ON [h].[Hierarchy]=[td].[hierarchtype]
	ORDER BY [td].[pkid];

OPEN Object_Cursor;
FETCH NEXT FROM Object_Cursor INTO @objectName,@Name0, @Name1, @Name2, @HierarchyType, @Property, @Function, @CommandText, @Hierarchy, @Level0, @Level1, @Level2, @ObjectId
WHILE @@FETCH_STATUS = 0
BEGIN
IF @HierarchyType =''database'' 
	BEGIN
		SET @Level0 = NULL;
		SET @Name0  = NULL;
		SET @Level1 = NULL;
		SET @Name1 = NULL;
		SET @Level2 = NULL;
		SET @Name2 = NULL;
		SET @ObjectId = 0;
	END;

SET @Message = CASE WHEN @Hierarchy IS NULL THEN FORMATMESSAGE(''hierarchy type of %s does not exist'',@HierarchyType)
	ELSE ''missing object information. try again!''
END

-- check if there''s value betwenn level and it''s associated name																
IF (@Level0 IS NOT NULL AND @Name0 IS NULL) OR (@Level0 IS NULL AND @Name0 IS NOT NULL) goto complete;
IF (@Level1 IS NOT NULL AND @Name1 IS NULL) OR (@Level1 IS NULL AND @Name1 IS NOT NULL) goto complete;
IF (@Level2 IS NOT NULL AND @Name2 IS NULL) OR (@Level2 IS NULL AND @Name2 IS NOT NULL) goto complete;

-- check if object exists
IF @Hierarchy <>''database''
BEGIN
	IF @ObjectId IS NULL
	BEGIN
		SET @message = FORMATMESSAGE(''%s does not exists. Please try again!'',@objectName);																			
		goto complete;
	END
END

-- check if there''s any text to be added
IF @Function<>''delete'' AND (@CommandText IS NULL OR LEN( CAST(@CommandText AS VARCHAR(8000)) ) = 0 )
BEGIN
	SET @message = FORMATMESSAGE(''%s has no value to upsert. moving to next object.'',@objectName);																			
	goto complete;
END

SET @Value = NULL;
SELECT @Value = [value] FROM sys.extended_properties WHERE major_id = @ObjectId AND minor_id = 0 AND [name] = @Property;

IF @Function = ''delete''
BEGIN
	SET @Message = FORMATMESSAGE(''There is no value on %s for %s'',@objectname, @HierarchyType);

	IF @Value IS NULL goto complete;

	EXECUTE sys.sp_dropextendedproperty @Property, @Level0, @Name0, @Level1, @Name1, @Level2, @Name2;
	SET @Message =FORMATMESSAGE(''%s has their %s property deleted successfully.'',@objectname, @HierarchyType);
	END
ELSE
	BEGIN
		IF @Value IS NULL -- there''s no existing value
		BEGIN
			EXECUTE sys.sp_addextendedproperty @Property, @CommandText, @Level0, @Name0, @Level1, @Name1, @Level2, @Name2;
			SET @Message =FORMATMESSAGE(''%s has their %s property inserted successfully.'',@objectname, @HierarchyType);
		END
		ELSE
		BEGIN
			IF @Function=''append'' SET @CommandText = cast(@Value as VARCHAR(8000)) +'','' + cast(@CommandText as VARCHAR(8000))
			EXECUTE	@Return = sys.sp_updateextendedproperty @Property, @CommandText, @Level0, @Name0, @Level1, @Name1, @Level2, @Name2;
			
			SET @Message =FORMATMESSAGE(''%s has their %s property upserted successfully.'',@objectname, @HierarchyType);
		END
	END

complete:
-- enter results for that object
	INSERT @Result 
	VALUES (@objectName,@HierarchyType,@Function,@Message)

FETCH NEXT FROM Object_Cursor INTO @objectName,@Name0, @Name1, @Name2, @HierarchyType, @Property, @Function, @CommandText, @Hierarchy, @Level0, @Level1, @Level2, @ObjectId
END
CLOSE Object_Cursor;
DEALLOCATE Object_Cursor;

	SELECT * FROM @Result

END TRY
BEGIN CATCH
	IF CURSOR_STATUS(''global'',''Object_Cursor'') >= 0 
	BEGIN
		CLOSE Object_Cursor;
		DEALLOCATE Object_Cursor ;
	END

	SELECT
		ERROR_NUMBER() AS ErrorNumber,
		ERROR_STATE() AS ErrorState,
		ERROR_SEVERITY() AS ErrorSeverity,
		QUOTENAME(OBJECT_SCHEMA_NAME(@@PROCID)) +''.'' + QUOTENAME(object_name(@@PROCID)) AS ErrorProcedure,
		ERROR_LINE() AS ErrorLine,
		ERROR_MESSAGE() AS ErrorMessage;

	THROW

END CATCH   
')
END
