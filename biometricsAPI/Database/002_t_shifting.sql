/* =====================================================================
   biometricsAPI - t_shifting
   Run against the central database (after 001_create_schema.sql).
   Safe to re-run: creates the table if missing and always recreates the
   table type + upsert procedure.
   ===================================================================== */

/* ---------------------------------------------------------------------
   t_shifting: the branch's columns, plus
     bioShiftingGUID - central primary key, generated (NEWID) on insert
     BranchGUID      - which branch the row came from
   (BranchGUID, ShiftingID) is unique and identifies the source row.
   ShiftingID stores the branch's own value (not an identity here).
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.t_shifting', 'U') IS NULL
CREATE TABLE [dbo].[t_shifting](
	[bioShiftingGUID] [uniqueidentifier] NOT NULL CONSTRAINT [DF_t_shifting_bioShiftingGUID] DEFAULT (NEWID()),
	[ShiftingID] [int] NOT NULL,
	[EmployeeID] [int] NULL,
	[ShiftDate] [datetime] NULL,
	[Location] [nvarchar](50) NULL,
	[StartTime] [datetime] NULL,
	[EndTime] [datetime] NULL,
	[TotalMinutes] [int] NULL,
	[IsAugmentation] [bit] NULL,
	[IsOvertime] [bit] NULL,
	[IsRestDay] [bit] NULL,
	[EncodedBy] [int] NULL,
	[EncodedOn] [datetime] NULL,
	[OvertimeMinutes] [int] NULL,
	[BranchGUID] [uniqueidentifier] NOT NULL,
	CONSTRAINT [PK_t_shifting] PRIMARY KEY NONCLUSTERED ([bioShiftingGUID]),
	CONSTRAINT [UQ_t_shifting_Branch_ShiftingID] UNIQUE CLUSTERED ([BranchGUID], [ShiftingID])
);
GO

/* A copy of a branch table may have ShiftingID as IDENTITY, which blocks storing
   each branch's own ShiftingID values. Stop with a clear message. */
IF COLUMNPROPERTY(OBJECT_ID('dbo.t_shifting'), 'ShiftingID', 'IsIdentity') = 1
	RAISERROR('dbo.t_shifting.ShiftingID is an IDENTITY column. In the central table it must be a plain int (it stores each branch''s ShiftingID). Recreate the table without IDENTITY, then run this script again.', 16, 1);
GO

/* A table created by hand may lack the (BranchGUID, ShiftingID) unique key: add it. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.t_shifting') AND name = 'UQ_t_shifting_Branch_ShiftingID')
	CREATE UNIQUE NONCLUSTERED INDEX [UQ_t_shifting_Branch_ShiftingID] ON [dbo].[t_shifting] ([BranchGUID], [ShiftingID]);
GO

IF OBJECT_ID('dbo.usp_t_shifting_upsert', 'P') IS NOT NULL
	DROP PROCEDURE [dbo].[usp_t_shifting_upsert];
IF TYPE_ID('dbo.tt_t_shifting') IS NOT NULL
	DROP TYPE [dbo].[tt_t_shifting];
GO

/* ---------------------------------------------------------------------
   Table type: column ORDER must match ShiftingDto property order in the API.
   No bioShiftingGUID / BranchGUID (assigned centrally).
   --------------------------------------------------------------------- */
CREATE TYPE [dbo].[tt_t_shifting] AS TABLE(
	[ShiftingID] [int] NOT NULL PRIMARY KEY,
	[EmployeeID] [int] NULL,
	[ShiftDate] [datetime] NULL,
	[Location] [nvarchar](50) NULL,
	[StartTime] [datetime] NULL,
	[EndTime] [datetime] NULL,
	[TotalMinutes] [int] NULL,
	[IsAugmentation] [bit] NULL,
	[IsOvertime] [bit] NULL,
	[IsRestDay] [bit] NULL,
	[EncodedBy] [int] NULL,
	[EncodedOn] [datetime] NULL,
	[OvertimeMinutes] [int] NULL
);
GO

/* ---------------------------------------------------------------------
   UPSERT a batch of shifting rows for one branch.
     - (BranchGUID, ShiftingID) exists and differs  -> UPDATE (bioShiftingGUID kept)
     - (BranchGUID, ShiftingID) does not exist      -> INSERT with bioShiftingGUID = NEWID()
     - exists and identical                         -> untouched
   Returns one row: Inserted, Updated, Unchanged.
   --------------------------------------------------------------------- */
CREATE PROCEDURE [dbo].[usp_t_shifting_upsert]
	@BranchGUID uniqueidentifier,
	@Rows dbo.tt_t_shifting READONLY
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @Updated int, @Inserted int, @Total int = (SELECT COUNT(*) FROM @Rows);

	BEGIN TRANSACTION;

	UPDATE t SET
		t.[EmployeeID] = s.[EmployeeID],
		t.[ShiftDate] = s.[ShiftDate],
		t.[Location] = s.[Location],
		t.[StartTime] = s.[StartTime],
		t.[EndTime] = s.[EndTime],
		t.[TotalMinutes] = s.[TotalMinutes],
		t.[IsAugmentation] = s.[IsAugmentation],
		t.[IsOvertime] = s.[IsOvertime],
		t.[IsRestDay] = s.[IsRestDay],
		t.[EncodedBy] = s.[EncodedBy],
		t.[EncodedOn] = s.[EncodedOn],
		t.[OvertimeMinutes] = s.[OvertimeMinutes]
	FROM dbo.t_shifting t WITH (UPDLOCK, HOLDLOCK)
	INNER JOIN @Rows s
		ON t.[BranchGUID] = @BranchGUID AND t.[ShiftingID] = s.[ShiftingID]
	-- only touch rows that actually changed (EXCEPT treats NULL = NULL)
	WHERE EXISTS (
		SELECT s.[EmployeeID], s.[ShiftDate], s.[Location], s.[StartTime], s.[EndTime], s.[TotalMinutes],
			s.[IsAugmentation], s.[IsOvertime], s.[IsRestDay], s.[EncodedBy], s.[EncodedOn], s.[OvertimeMinutes]
		EXCEPT
		SELECT t.[EmployeeID], t.[ShiftDate], t.[Location], t.[StartTime], t.[EndTime], t.[TotalMinutes],
			t.[IsAugmentation], t.[IsOvertime], t.[IsRestDay], t.[EncodedBy], t.[EncodedOn], t.[OvertimeMinutes]
	);
	SET @Updated = @@ROWCOUNT;

	INSERT INTO dbo.t_shifting (
		[bioShiftingGUID], [BranchGUID],
		[ShiftingID], [EmployeeID], [ShiftDate], [Location], [StartTime], [EndTime], [TotalMinutes],
		[IsAugmentation], [IsOvertime], [IsRestDay], [EncodedBy], [EncodedOn], [OvertimeMinutes])
	SELECT
		NEWID(), @BranchGUID,
		s.[ShiftingID], s.[EmployeeID], s.[ShiftDate], s.[Location], s.[StartTime], s.[EndTime], s.[TotalMinutes],
		s.[IsAugmentation], s.[IsOvertime], s.[IsRestDay], s.[EncodedBy], s.[EncodedOn], s.[OvertimeMinutes]
	FROM @Rows s
	WHERE NOT EXISTS (
		SELECT 1 FROM dbo.t_shifting t WITH (UPDLOCK, HOLDLOCK)
		WHERE t.[BranchGUID] = @BranchGUID AND t.[ShiftingID] = s.[ShiftingID]
	);
	SET @Inserted = @@ROWCOUNT;

	COMMIT TRANSACTION;

	SELECT @Inserted AS Inserted, @Updated AS Updated, @Total - @Inserted - @Updated AS Unchanged;
END
GO
