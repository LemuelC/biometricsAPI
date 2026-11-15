/* =====================================================================
   biometricsAPI - t_attendance_logs
   Run against the central database (after 001_create_schema.sql).
   Safe to re-run: creates the table if missing and always recreates the
   table type + upsert procedure.
   ===================================================================== */

/* ---------------------------------------------------------------------
   t_attendance_logs: the branch's columns, plus
     bioAttendanceLogGUID - central primary key, generated (NEWID) on insert
     BranchGUID           - which branch the row came from
   (BranchGUID, AttendanceLogID) is unique and identifies the source row.
   AttendanceLogID stores the branch's own value (not an identity here).
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.t_attendance_logs', 'U') IS NULL
CREATE TABLE [dbo].[t_attendance_logs](
	[bioAttendanceLogGUID] [uniqueidentifier] NOT NULL CONSTRAINT [DF_t_attendance_logs_bioAttendanceLogGUID] DEFAULT (NEWID()),
	[AttendanceLogID] [int] NOT NULL,
	[LogDate] [datetime] NULL,
	[LogIN] [datetime] NULL,
	[LogOUT] [datetime] NULL,
	[EmployeeID] [int] NULL,
	[TotalMinutes] [int] NULL,
	[ShiftingID] [int] NULL,
	[WorkMinutes] [int] NULL,
	[OTMinutes] [int] NULL,
	[NDMinutes] [int] NULL,
	[PaidLeave] [int] NULL,
	[Leave] [int] NULL,
	[BranchGUID] [uniqueidentifier] NOT NULL,
	CONSTRAINT [PK_t_attendance_logs] PRIMARY KEY NONCLUSTERED ([bioAttendanceLogGUID]),
	CONSTRAINT [UQ_t_attendance_logs_Branch_AttendanceLogID] UNIQUE CLUSTERED ([BranchGUID], [AttendanceLogID])
);
GO

/* A copy of a branch table may have AttendanceLogID as IDENTITY, which blocks storing
   each branch's own AttendanceLogID values. Stop with a clear message. */
IF COLUMNPROPERTY(OBJECT_ID('dbo.t_attendance_logs'), 'AttendanceLogID', 'IsIdentity') = 1
	RAISERROR('dbo.t_attendance_logs.AttendanceLogID is an IDENTITY column. In the central table it must be a plain int (it stores each branch''s AttendanceLogID). Recreate the table without IDENTITY, then run this script again.', 16, 1);
GO

/* A table created by hand may lack the (BranchGUID, AttendanceLogID) unique key: add it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.t_attendance_logs') AND name = 'UQ_t_attendance_logs_Branch_AttendanceLogID')
	CREATE UNIQUE NONCLUSTERED INDEX [UQ_t_attendance_logs_Branch_AttendanceLogID] ON [dbo].[t_attendance_logs] ([BranchGUID], [AttendanceLogID]);
GO

IF OBJECT_ID('dbo.usp_t_attendance_logs_upsert', 'P') IS NOT NULL
	DROP PROCEDURE [dbo].[usp_t_attendance_logs_upsert];
IF TYPE_ID('dbo.tt_t_attendance_logs') IS NOT NULL
	DROP TYPE [dbo].[tt_t_attendance_logs];
GO

/* ---------------------------------------------------------------------
   Table type: column ORDER must match AttendanceLogDto property order in the API.
   No bioAttendanceLogGUID / BranchGUID (assigned centrally).
   --------------------------------------------------------------------- */
CREATE TYPE [dbo].[tt_t_attendance_logs] AS TABLE(
	[AttendanceLogID] [int] NOT NULL PRIMARY KEY,
	[LogDate] [datetime] NULL,
	[LogIN] [datetime] NULL,
	[LogOUT] [datetime] NULL,
	[EmployeeID] [int] NULL,
	[TotalMinutes] [int] NULL,
	[ShiftingID] [int] NULL,
	[WorkMinutes] [int] NULL,
	[OTMinutes] [int] NULL,
	[NDMinutes] [int] NULL,
	[PaidLeave] [int] NULL,
	[Leave] [int] NULL
);
GO

/* ---------------------------------------------------------------------
   UPSERT a batch of attendance log rows for one branch.
     - (BranchGUID, AttendanceLogID) exists and differs  -> UPDATE (bioAttendanceLogGUID kept)
     - (BranchGUID, AttendanceLogID) does not exist      -> INSERT with bioAttendanceLogGUID = NEWID()
     - exists and identical                              -> untouched
   Returns one row: Inserted, Updated, Unchanged.
   --------------------------------------------------------------------- */
CREATE PROCEDURE [dbo].[usp_t_attendance_logs_upsert]
	@BranchGUID uniqueidentifier,
	@Rows dbo.tt_t_attendance_logs READONLY
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @Updated int, @Inserted int, @Total int = (SELECT COUNT(*) FROM @Rows);

	BEGIN TRANSACTION;

	UPDATE t SET
		t.[LogDate] = s.[LogDate],
		t.[LogIN] = s.[LogIN],
		t.[LogOUT] = s.[LogOUT],
		t.[EmployeeID] = s.[EmployeeID],
		t.[TotalMinutes] = s.[TotalMinutes],
		t.[ShiftingID] = s.[ShiftingID],
		t.[WorkMinutes] = s.[WorkMinutes],
		t.[OTMinutes] = s.[OTMinutes],
		t.[NDMinutes] = s.[NDMinutes],
		t.[PaidLeave] = s.[PaidLeave],
		t.[Leave] = s.[Leave]
	FROM dbo.t_attendance_logs t WITH (UPDLOCK, HOLDLOCK)
	INNER JOIN @Rows s
		ON t.[BranchGUID] = @BranchGUID AND t.[AttendanceLogID] = s.[AttendanceLogID]
	-- only touch rows that actually changed (EXCEPT treats NULL = NULL)
	WHERE EXISTS (
		SELECT s.[LogDate], s.[LogIN], s.[LogOUT], s.[EmployeeID], s.[TotalMinutes], s.[ShiftingID],
			s.[WorkMinutes], s.[OTMinutes], s.[NDMinutes], s.[PaidLeave], s.[Leave]
		EXCEPT
		SELECT t.[LogDate], t.[LogIN], t.[LogOUT], t.[EmployeeID], t.[TotalMinutes], t.[ShiftingID],
			t.[WorkMinutes], t.[OTMinutes], t.[NDMinutes], t.[PaidLeave], t.[Leave]
	);
	SET @Updated = @@ROWCOUNT;

	INSERT INTO dbo.t_attendance_logs (
		[bioAttendanceLogGUID], [BranchGUID],
		[AttendanceLogID], [LogDate], [LogIN], [LogOUT], [EmployeeID], [TotalMinutes], [ShiftingID],
		[WorkMinutes], [OTMinutes], [NDMinutes], [PaidLeave], [Leave])
	SELECT
		NEWID(), @BranchGUID,
		s.[AttendanceLogID], s.[LogDate], s.[LogIN], s.[LogOUT], s.[EmployeeID], s.[TotalMinutes], s.[ShiftingID],
		s.[WorkMinutes], s.[OTMinutes], s.[NDMinutes], s.[PaidLeave], s.[Leave]
	FROM @Rows s
	WHERE NOT EXISTS (
		SELECT 1 FROM dbo.t_attendance_logs t WITH (UPDLOCK, HOLDLOCK)
		WHERE t.[BranchGUID] = @BranchGUID AND t.[AttendanceLogID] = s.[AttendanceLogID]
	);
	SET @Inserted = @@ROWCOUNT;

	COMMIT TRANSACTION;

	SELECT @Inserted AS Inserted, @Updated AS Updated, @Total - @Inserted - @Updated AS Unchanged;
END
GO
