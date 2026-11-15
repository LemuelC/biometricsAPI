/* =====================================================================
   biometricsAPI - central database schema
   Run against the central (merged) database. Safe to re-run: it creates
   what is missing, upgrades an older m_employee, and always recreates
   the table type + upsert procedure (so changes to them are applied).
   ===================================================================== */

/* ---------------------------------------------------------------------
   api_client: one row per branch allowed to call the API.
   ApiKeyHash = SHA-256 of the branch's API key (the raw key is never stored).
   Generate a key + SQL with:  dotnet run -- genkey <BranchGUID> "<Branch name>"
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.api_client', 'U') IS NULL
CREATE TABLE [dbo].[api_client](
	[BranchGUID] [uniqueidentifier] NOT NULL,
	[BranchName] [nvarchar](100) NOT NULL,
	[ApiKeyHash] [varbinary](32) NOT NULL,
	[IsActive] [bit] NOT NULL CONSTRAINT [DF_api_client_IsActive] DEFAULT (1),
	[CreatedOn] [datetime] NOT NULL CONSTRAINT [DF_api_client_CreatedOn] DEFAULT (GETDATE()),
	CONSTRAINT [PK_api_client] PRIMARY KEY CLUSTERED ([BranchGUID])
);
GO

/* ---------------------------------------------------------------------
   m_employee: the branch's columns, plus
     BioEmployeeGUID - central primary key, generated (NEWID) on insert
     BranchGUID      - which branch the row came from
   (BranchGUID, EmployeeID) is unique and identifies the source row.
   EmployeeGUID belongs to another application: the sync never reads or
   writes it.
   PK is nonclustered (random GUIDs fragment a clustered index);
   the unique key is clustered since every lookup goes through it.
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.m_employee', 'U') IS NULL
CREATE TABLE [dbo].[m_employee](
	[BioEmployeeGUID] [uniqueidentifier] NOT NULL CONSTRAINT [DF_m_employee_BioEmployeeGUID] DEFAULT (NEWID()),
	[EmployeeID] [int] NOT NULL,
	[EmployeeGUID] [uniqueidentifier] NULL,
	[EmployeeCode] [nvarchar](10) NULL,
	[IdCode] [nvarchar](10) NULL,
	[Surname] [nvarchar](50) NULL,
	[FirstName] [nvarchar](50) NULL,
	[MiddleName] [nvarchar](25) NULL,
	[NameExtention] [nvarchar](5) NULL,
	[FullName] [nvarchar](150) NULL,
	[ResidentialAddress] [nvarchar](255) NULL,
	[ResidentialZipCode] [nvarchar](10) NULL,
	[ResidentialTelephone] [nvarchar](50) NULL,
	[EmailAddress] [nvarchar](50) NULL,
	[CellPhone] [nvarchar](50) NULL,
	[DateOfBirth] [datetime] NULL,
	[PlaceOfBirth] [nvarchar](10) NULL,
	[Sex] [nvarchar](10) NULL,
	[CivilStatus] [nvarchar](10) NULL,
	[CivilStatusOther] [nvarchar](10) NULL,
	[Citizenship] [nvarchar](20) NULL,
	[Height] [nvarchar](10) NULL,
	[Weight] [nvarchar](10) NULL,
	[BloodType] [nvarchar](10) NULL,
	[HDMFIdNo] [nvarchar](50) NULL,
	[PHICIdNo] [nvarchar](50) NULL,
	[SSSNo] [nvarchar](50) NULL,
	[TIN] [nvarchar](50) NULL,
	[TaxCodeID] [int] NULL,
	[BankAccountNo] [nvarchar](50) NULL,
	[DepartmentID] [int] NULL,
	[PositionID] [int] NULL,
	[Department] [nvarchar](255) NULL,
	[ShiftID] [int] NOT NULL,
	[HourlyRate] [float] NOT NULL,
	[MonthlyRate] [float] NOT NULL,
	[DailyRate] [float] NOT NULL,
	[DateHired] [datetime] NULL,
	[WorkStatus] [nvarchar](50) NULL,
	[HDMFEmployee] [float] NOT NULL,
	[HDMFEmployer] [float] NOT NULL,
	[DateResigned] [date] NULL,
	[AllowsLate] [bit] NOT NULL,
	[PHICBracketID] [int] NOT NULL,
	[SSSBracketID] [int] NOT NULL,
	[ProbationaryDate] [datetime] NULL,
	[IncludeSSS] [bit] NOT NULL,
	[IncludeHDMF] [bit] NOT NULL,
	[IncludePHIC] [bit] NOT NULL,
	[IncludeTax] [bit] NOT NULL,
	[ReasonforResignation] [nvarchar](255) NULL,
	[FinalPayDate] [datetime] NULL,
	[EmploymentStatus] [nvarchar](50) NULL,
	[AllowsUT] [bit] NOT NULL,
	[Allowance] [float] NOT NULL,
	[AllowsAbsences] [bit] NOT NULL,
	[Remarks] [nvarchar](255) NULL,
	[IsSave] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[EncodedByID] [int] NOT NULL,
	[EncodedOn] [datetime] NULL,
	[IsNoPunch] [bit] NULL,
	[WorkDays] [int] NULL,
	[BranchGUID] [uniqueidentifier] NOT NULL,
	CONSTRAINT [PK_m_employee] PRIMARY KEY NONCLUSTERED ([BioEmployeeGUID]),
	CONSTRAINT [UQ_m_employee_Branch_EmployeeID] UNIQUE CLUSTERED ([BranchGUID], [EmployeeID])
);
GO

/* Upgrade: an earlier version of this script named the primary key column [GUID]. */
IF COL_LENGTH('dbo.m_employee', 'GUID') IS NOT NULL AND COL_LENGTH('dbo.m_employee', 'BioEmployeeGUID') IS NULL
BEGIN
	EXEC sp_rename 'dbo.m_employee.GUID', 'BioEmployeeGUID', 'COLUMN';
	IF OBJECT_ID('dbo.DF_m_employee_GUID', 'D') IS NOT NULL
		EXEC sp_rename 'dbo.DF_m_employee_GUID', 'DF_m_employee_BioEmployeeGUID', 'OBJECT';
END
GO

/* A table created by hand may lack the (BranchGUID, EmployeeID) unique key: add it.
   Fails with a duplicate-key error if the table already holds duplicates. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.m_employee') AND name = 'UQ_m_employee_Branch_EmployeeID')
	CREATE UNIQUE NONCLUSTERED INDEX [UQ_m_employee_Branch_EmployeeID] ON [dbo].[m_employee] ([BranchGUID], [EmployeeID]);
GO

/* ---------------------------------------------------------------------
   Drop the procedure first (it depends on the type), then the type.
   Both are recreated below.
   --------------------------------------------------------------------- */
IF OBJECT_ID('dbo.usp_m_employee_upsert', 'P') IS NOT NULL
	DROP PROCEDURE [dbo].[usp_m_employee_upsert];
IF TYPE_ID('dbo.tt_m_employee') IS NOT NULL
	DROP TYPE [dbo].[tt_m_employee];
GO

/* ---------------------------------------------------------------------
   Table type used to send a batch of employees in one call.
   Column ORDER must match EmployeeDto property order in the API
   (table-valued parameters bind by position).
   No BioEmployeeGUID / BranchGUID (assigned centrally) and no
   EmployeeGUID (owned by another application).
   --------------------------------------------------------------------- */
CREATE TYPE [dbo].[tt_m_employee] AS TABLE(
	[EmployeeID] [int] NOT NULL PRIMARY KEY,
	[EmployeeCode] [nvarchar](10) NULL,
	[IdCode] [nvarchar](10) NULL,
	[Surname] [nvarchar](50) NULL,
	[FirstName] [nvarchar](50) NULL,
	[MiddleName] [nvarchar](25) NULL,
	[NameExtention] [nvarchar](5) NULL,
	[FullName] [nvarchar](150) NULL,
	[ResidentialAddress] [nvarchar](255) NULL,
	[ResidentialZipCode] [nvarchar](10) NULL,
	[ResidentialTelephone] [nvarchar](50) NULL,
	[EmailAddress] [nvarchar](50) NULL,
	[CellPhone] [nvarchar](50) NULL,
	[DateOfBirth] [datetime] NULL,
	[PlaceOfBirth] [nvarchar](10) NULL,
	[Sex] [nvarchar](10) NULL,
	[CivilStatus] [nvarchar](10) NULL,
	[CivilStatusOther] [nvarchar](10) NULL,
	[Citizenship] [nvarchar](20) NULL,
	[Height] [nvarchar](10) NULL,
	[Weight] [nvarchar](10) NULL,
	[BloodType] [nvarchar](10) NULL,
	[HDMFIdNo] [nvarchar](50) NULL,
	[PHICIdNo] [nvarchar](50) NULL,
	[SSSNo] [nvarchar](50) NULL,
	[TIN] [nvarchar](50) NULL,
	[TaxCodeID] [int] NULL,
	[BankAccountNo] [nvarchar](50) NULL,
	[DepartmentID] [int] NULL,
	[PositionID] [int] NULL,
	[Department] [nvarchar](255) NULL,
	[ShiftID] [int] NOT NULL,
	[HourlyRate] [float] NOT NULL,
	[MonthlyRate] [float] NOT NULL,
	[DailyRate] [float] NOT NULL,
	[DateHired] [datetime] NULL,
	[WorkStatus] [nvarchar](50) NULL,
	[HDMFEmployee] [float] NOT NULL,
	[HDMFEmployer] [float] NOT NULL,
	[DateResigned] [date] NULL,
	[AllowsLate] [bit] NOT NULL,
	[PHICBracketID] [int] NOT NULL,
	[SSSBracketID] [int] NOT NULL,
	[ProbationaryDate] [datetime] NULL,
	[IncludeSSS] [bit] NOT NULL,
	[IncludeHDMF] [bit] NOT NULL,
	[IncludePHIC] [bit] NOT NULL,
	[IncludeTax] [bit] NOT NULL,
	[ReasonforResignation] [nvarchar](255) NULL,
	[FinalPayDate] [datetime] NULL,
	[EmploymentStatus] [nvarchar](50) NULL,
	[AllowsUT] [bit] NOT NULL,
	[Allowance] [float] NOT NULL,
	[AllowsAbsences] [bit] NOT NULL,
	[Remarks] [nvarchar](255) NULL,
	[IsSave] [bit] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[EncodedByID] [int] NOT NULL,
	[EncodedOn] [datetime] NULL,
	[IsNoPunch] [bit] NULL,
	[WorkDays] [int] NULL
);
GO

/* ---------------------------------------------------------------------
   UPSERT a batch of employees for one branch.
     - (BranchGUID, EmployeeID) exists and differs  -> UPDATE (BioEmployeeGUID kept)
     - (BranchGUID, EmployeeID) does not exist      -> INSERT with BioEmployeeGUID = NEWID()
     - exists and identical                         -> untouched
   EmployeeGUID is never touched.
   UPDLOCK + HOLDLOCK on the target makes concurrent syncs from the
   same branch safe (no duplicate-key race between UPDATE and INSERT).
   Returns one row: Inserted, Updated, Unchanged.
   --------------------------------------------------------------------- */
CREATE PROCEDURE [dbo].[usp_m_employee_upsert]
	@BranchGUID uniqueidentifier,
	@Rows dbo.tt_m_employee READONLY
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;

	DECLARE @Updated int, @Inserted int, @Total int = (SELECT COUNT(*) FROM @Rows);

	BEGIN TRANSACTION;

	UPDATE t SET
		t.[EmployeeCode] = s.[EmployeeCode],
		t.[IdCode] = s.[IdCode],
		t.[Surname] = s.[Surname],
		t.[FirstName] = s.[FirstName],
		t.[MiddleName] = s.[MiddleName],
		t.[NameExtention] = s.[NameExtention],
		t.[FullName] = s.[FullName],
		t.[ResidentialAddress] = s.[ResidentialAddress],
		t.[ResidentialZipCode] = s.[ResidentialZipCode],
		t.[ResidentialTelephone] = s.[ResidentialTelephone],
		t.[EmailAddress] = s.[EmailAddress],
		t.[CellPhone] = s.[CellPhone],
		t.[DateOfBirth] = s.[DateOfBirth],
		t.[PlaceOfBirth] = s.[PlaceOfBirth],
		t.[Sex] = s.[Sex],
		t.[CivilStatus] = s.[CivilStatus],
		t.[CivilStatusOther] = s.[CivilStatusOther],
		t.[Citizenship] = s.[Citizenship],
		t.[Height] = s.[Height],
		t.[Weight] = s.[Weight],
		t.[BloodType] = s.[BloodType],
		t.[HDMFIdNo] = s.[HDMFIdNo],
		t.[PHICIdNo] = s.[PHICIdNo],
		t.[SSSNo] = s.[SSSNo],
		t.[TIN] = s.[TIN],
		t.[TaxCodeID] = s.[TaxCodeID],
		t.[BankAccountNo] = s.[BankAccountNo],
		t.[DepartmentID] = s.[DepartmentID],
		t.[PositionID] = s.[PositionID],
		t.[Department] = s.[Department],
		t.[ShiftID] = s.[ShiftID],
		t.[HourlyRate] = s.[HourlyRate],
		t.[MonthlyRate] = s.[MonthlyRate],
		t.[DailyRate] = s.[DailyRate],
		t.[DateHired] = s.[DateHired],
		t.[WorkStatus] = s.[WorkStatus],
		t.[HDMFEmployee] = s.[HDMFEmployee],
		t.[HDMFEmployer] = s.[HDMFEmployer],
		t.[DateResigned] = s.[DateResigned],
		t.[AllowsLate] = s.[AllowsLate],
		t.[PHICBracketID] = s.[PHICBracketID],
		t.[SSSBracketID] = s.[SSSBracketID],
		t.[ProbationaryDate] = s.[ProbationaryDate],
		t.[IncludeSSS] = s.[IncludeSSS],
		t.[IncludeHDMF] = s.[IncludeHDMF],
		t.[IncludePHIC] = s.[IncludePHIC],
		t.[IncludeTax] = s.[IncludeTax],
		t.[ReasonforResignation] = s.[ReasonforResignation],
		t.[FinalPayDate] = s.[FinalPayDate],
		t.[EmploymentStatus] = s.[EmploymentStatus],
		t.[AllowsUT] = s.[AllowsUT],
		t.[Allowance] = s.[Allowance],
		t.[AllowsAbsences] = s.[AllowsAbsences],
		t.[Remarks] = s.[Remarks],
		t.[IsSave] = s.[IsSave],
		t.[IsDeleted] = s.[IsDeleted],
		t.[EncodedByID] = s.[EncodedByID],
		t.[EncodedOn] = s.[EncodedOn],
		t.[IsNoPunch] = s.[IsNoPunch],
		t.[WorkDays] = s.[WorkDays]
	FROM dbo.m_employee t WITH (UPDLOCK, HOLDLOCK)
	INNER JOIN @Rows s
		ON t.[BranchGUID] = @BranchGUID AND t.[EmployeeID] = s.[EmployeeID]
	-- only touch rows that actually changed (EXCEPT treats NULL = NULL)
	WHERE EXISTS (
		SELECT s.[EmployeeCode], s.[IdCode], s.[Surname], s.[FirstName], s.[MiddleName],
			s.[NameExtention], s.[FullName], s.[ResidentialAddress], s.[ResidentialZipCode], s.[ResidentialTelephone],
			s.[EmailAddress], s.[CellPhone], s.[DateOfBirth], s.[PlaceOfBirth], s.[Sex], s.[CivilStatus],
			s.[CivilStatusOther], s.[Citizenship], s.[Height], s.[Weight], s.[BloodType], s.[HDMFIdNo], s.[PHICIdNo],
			s.[SSSNo], s.[TIN], s.[TaxCodeID], s.[BankAccountNo], s.[DepartmentID], s.[PositionID], s.[Department],
			s.[ShiftID], s.[HourlyRate], s.[MonthlyRate], s.[DailyRate], s.[DateHired], s.[WorkStatus],
			s.[HDMFEmployee], s.[HDMFEmployer], s.[DateResigned], s.[AllowsLate], s.[PHICBracketID], s.[SSSBracketID],
			s.[ProbationaryDate], s.[IncludeSSS], s.[IncludeHDMF], s.[IncludePHIC], s.[IncludeTax],
			s.[ReasonforResignation], s.[FinalPayDate], s.[EmploymentStatus], s.[AllowsUT], s.[Allowance],
			s.[AllowsAbsences], s.[Remarks], s.[IsSave], s.[IsDeleted], s.[EncodedByID], s.[EncodedOn],
			s.[IsNoPunch], s.[WorkDays]
		EXCEPT
		SELECT t.[EmployeeCode], t.[IdCode], t.[Surname], t.[FirstName], t.[MiddleName],
			t.[NameExtention], t.[FullName], t.[ResidentialAddress], t.[ResidentialZipCode], t.[ResidentialTelephone],
			t.[EmailAddress], t.[CellPhone], t.[DateOfBirth], t.[PlaceOfBirth], t.[Sex], t.[CivilStatus],
			t.[CivilStatusOther], t.[Citizenship], t.[Height], t.[Weight], t.[BloodType], t.[HDMFIdNo], t.[PHICIdNo],
			t.[SSSNo], t.[TIN], t.[TaxCodeID], t.[BankAccountNo], t.[DepartmentID], t.[PositionID], t.[Department],
			t.[ShiftID], t.[HourlyRate], t.[MonthlyRate], t.[DailyRate], t.[DateHired], t.[WorkStatus],
			t.[HDMFEmployee], t.[HDMFEmployer], t.[DateResigned], t.[AllowsLate], t.[PHICBracketID], t.[SSSBracketID],
			t.[ProbationaryDate], t.[IncludeSSS], t.[IncludeHDMF], t.[IncludePHIC], t.[IncludeTax],
			t.[ReasonforResignation], t.[FinalPayDate], t.[EmploymentStatus], t.[AllowsUT], t.[Allowance],
			t.[AllowsAbsences], t.[Remarks], t.[IsSave], t.[IsDeleted], t.[EncodedByID], t.[EncodedOn],
			t.[IsNoPunch], t.[WorkDays]
	);
	SET @Updated = @@ROWCOUNT;

	INSERT INTO dbo.m_employee (
		[BioEmployeeGUID], [BranchGUID],
		[EmployeeID], [EmployeeCode], [IdCode], [Surname], [FirstName], [MiddleName],
		[NameExtention], [FullName], [ResidentialAddress], [ResidentialZipCode], [ResidentialTelephone],
		[EmailAddress], [CellPhone], [DateOfBirth], [PlaceOfBirth], [Sex], [CivilStatus],
		[CivilStatusOther], [Citizenship], [Height], [Weight], [BloodType], [HDMFIdNo], [PHICIdNo],
		[SSSNo], [TIN], [TaxCodeID], [BankAccountNo], [DepartmentID], [PositionID], [Department],
		[ShiftID], [HourlyRate], [MonthlyRate], [DailyRate], [DateHired], [WorkStatus],
		[HDMFEmployee], [HDMFEmployer], [DateResigned], [AllowsLate], [PHICBracketID], [SSSBracketID],
		[ProbationaryDate], [IncludeSSS], [IncludeHDMF], [IncludePHIC], [IncludeTax],
		[ReasonforResignation], [FinalPayDate], [EmploymentStatus], [AllowsUT], [Allowance],
		[AllowsAbsences], [Remarks], [IsSave], [IsDeleted], [EncodedByID], [EncodedOn],
		[IsNoPunch], [WorkDays])
	SELECT
		NEWID(), @BranchGUID,
		s.[EmployeeID], s.[EmployeeCode], s.[IdCode], s.[Surname], s.[FirstName], s.[MiddleName],
		s.[NameExtention], s.[FullName], s.[ResidentialAddress], s.[ResidentialZipCode], s.[ResidentialTelephone],
		s.[EmailAddress], s.[CellPhone], s.[DateOfBirth], s.[PlaceOfBirth], s.[Sex], s.[CivilStatus],
		s.[CivilStatusOther], s.[Citizenship], s.[Height], s.[Weight], s.[BloodType], s.[HDMFIdNo], s.[PHICIdNo],
		s.[SSSNo], s.[TIN], s.[TaxCodeID], s.[BankAccountNo], s.[DepartmentID], s.[PositionID], s.[Department],
		s.[ShiftID], s.[HourlyRate], s.[MonthlyRate], s.[DailyRate], s.[DateHired], s.[WorkStatus],
		s.[HDMFEmployee], s.[HDMFEmployer], s.[DateResigned], s.[AllowsLate], s.[PHICBracketID], s.[SSSBracketID],
		s.[ProbationaryDate], s.[IncludeSSS], s.[IncludeHDMF], s.[IncludePHIC], s.[IncludeTax],
		s.[ReasonforResignation], s.[FinalPayDate], s.[EmploymentStatus], s.[AllowsUT], s.[Allowance],
		s.[AllowsAbsences], s.[Remarks], s.[IsSave], s.[IsDeleted], s.[EncodedByID], s.[EncodedOn],
		s.[IsNoPunch], s.[WorkDays]
	FROM @Rows s
	WHERE NOT EXISTS (
		SELECT 1 FROM dbo.m_employee t WITH (UPDLOCK, HOLDLOCK)
		WHERE t.[BranchGUID] = @BranchGUID AND t.[EmployeeID] = s.[EmployeeID]
	);
	SET @Inserted = @@ROWCOUNT;

	COMMIT TRANSACTION;

	SELECT @Inserted AS Inserted, @Updated AS Updated, @Total - @Inserted - @Updated AS Unchanged;
END
GO
