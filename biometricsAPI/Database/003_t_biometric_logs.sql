/* =====================================================================
   biometricsAPI - t_biometric_logs
   Run against the central database (after 001_create_schema.sql).
   Safe to re-run: creates the table if missing and always recreates the
   table type + upsert procedure.
   ===================================================================== */

/* ---------------------------------------------------------------------
   t_biometric_logs: the branch's columns, plus
     bioBiometricLogGUID - central primary key, generated (NEWID) on insert
     BranchGUID          - which branch the row came from
   (BranchGUID, BiometricLogID) is unique and identifies the source row.
   BiometricLogID stores the branch's own value (not an identity here).
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.t_biometric_logs', 'U') IS NULL
CREATE TABLE [dbo].[t_biometric_logs](
	[bioBiometricLogGUID] [uniqueidentifier] NOT NULL CONSTRAINT [DF_t_biometric_logs_bioBiometricLogGUID] DEFAULT (NEWID()),
	[BiometricLogID] [int] NOT NULL,
	[EmployeeID] [int] NULL,
	[LogType] [nvarchar](50) NULL,
	[LogDateTime] [datetime] NULL,
	[BranchGUID] [uniqueidentifier] NOT NULL,
	CONSTRAINT [PK_t_biometric_logs] PRIMARY KEY NONCLUSTERED ([bioBiometricLogGUID]),
	CONSTRAINT [UQ_t_biometric_logs_Branch_BiometricLogID] UNIQUE CLUSTERED ([BranchGUID], [BiometricLogID])
);
GO

/* A copy of a branch table may have BiometricLogID as IDENTITY, which blocks storing
   each branch's own BiometricLogID values. Stop with a clear message. */
IF COLUMNPROPERTY(OBJECT_ID('dbo.t_biometric_logs'), 'BiometricLogID', 'IsIdentity') = 1
	RAISERROR('dbo.t_biometric_logs.BiometricLogID is an IDENTITY column. In the central table it must be a plain int (it stores each branch''s BiometricLogID). Recreate the table without IDENTITY, then run this script again.', 16, 1);
GO

/* A table created by hand may lack the (BranchGUID, BiometricLogID) unique key: add it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.t_biometric_logs') AND name = 'UQ_t_biometric_logs_Branch_BiometricLogID')
	CREATE UNIQUE NONCLUSTERED INDEX [UQ_t_biometric_logs_Branch_BiometricLogID] ON [dbo].[t_biometric_logs] ([BranchGUID], [BiometricLogID]);
GO

IF OBJECT_ID('dbo.usp_t_biometric_logs_upsert', 'P') IS NOT NULL
	DROP PROCEDURE [dbo].[usp_t_biometric_logs_upsert];
IF TYPE_ID('dbo.tt_t_biometric_logs') IS NOT NULL
	DROP TYPE [dbo].[tt_t_biometric_logs];
GO

/* ---------------------------------------------------------------------
   Table type: column ORDER must match BiometricLogDto property order in the API.
   No bioBiometricLogGUID / BranchGUID (assigned centrally).
   --------------------------------------------------------------------- */
CREATE TYPE [dbo].[tt_t_biometric_logs] AS TABLE(
	[BiometricLogID] [int] NOT NULL PRIMARY KEY,
	[EmployeeID] [int] NULL,
	[LogType] [nvarchar](50) NULL,
	[LogDateTime] [datetime] NULL
);
GO

/* ---------------------------------------------------------------------
   UPSERT a batch of biometric log rows for one branch.
     - (BranchGUID, BiometricLogID) exists and differs  -> UPDATE (bioBiometricLogGUID kept)
     - (BranchGUID, BiometricLogID) does not exist      -> INSERT with bioBiometricLogGUID = NEWID()
     - exists and identical                             -> untouched
   Returns one row: Inserted, Updated, Unchanged.
   --------------------------------------------------------------------- */
CREATE PROCEDURE [dbo].[usp_t_biometric_logs_upsert]
	@BranchGUID uniqueidentifier,
	@Rows dbo.tt_t_biometric_logs READONLY
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @Updated int, @Inserted int, @Total int = (SELECT COUNT(*) FROM @Rows);

	BEGIN TRANSACTION;

	UPDATE t SET
		t.[EmployeeID] = s.[EmployeeID],
		t.[LogType] = s.[LogType],
		t.[LogDateTime] = s.[LogDateTime]
	FROM dbo.t_biometric_logs t WITH (UPDLOCK, HOLDLOCK)
	INNER JOIN @Rows s
		ON t.[BranchGUID] = @BranchGUID AND t.[BiometricLogID] = s.[BiometricLogID]
	-- only touch rows that actually changed (EXCEPT treats NULL = NULL)
	WHERE EXISTS (
		SELECT s.[EmployeeID], s.[LogType], s.[LogDateTime]
		EXCEPT
		SELECT t.[EmployeeID], t.[LogType], t.[LogDateTime]
	);
	SET @Updated = @@ROWCOUNT;

	INSERT INTO dbo.t_biometric_logs (
		[bioBiometricLogGUID], [BranchGUID],
		[BiometricLogID], [EmployeeID], [LogType], [LogDateTime])
	SELECT
		NEWID(), @BranchGUID,
		s.[BiometricLogID], s.[EmployeeID], s.[LogType], s.[LogDateTime]
	FROM @Rows s
	WHERE NOT EXISTS (
		SELECT 1 FROM dbo.t_biometric_logs t WITH (UPDLOCK, HOLDLOCK)
		WHERE t.[BranchGUID] = @BranchGUID AND t.[BiometricLogID] = s.[BiometricLogID]
	);
	SET @Inserted = @@ROWCOUNT;

	COMMIT TRANSACTION;

	SELECT @Inserted AS Inserted, @Updated AS Updated, @Total - @Inserted - @Updated AS Unchanged;
END
GO
