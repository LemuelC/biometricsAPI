# Tables synced to the central biometricsAPI, in sync order. Shared by sync.ps1 and test-connection.ps1.
#   Name     - branch table (dbo.<Name>)
#   Endpoint - API path that upserts it
#   Key      - the branch's ID column; together with BranchGUID it identifies the row centrally
#   Columns  - columns sent. Central-only columns (GUID / BioEmployeeGUID / BranchGUID) are never sent.
#   Required - NOT NULL centrally: the sync stops if the branch table lacks one.
#              Any other column the branch table lacks is sent as null.
#   DateColumn - (optional) date column for the date filter (-Days / -From / -To).
#              Without it the table is always sent in full (every row, every run).
$SyncTables = @(
    [pscustomobject]@{
        Name     = 'm_employee'
        Endpoint = 'api/employees/upsert'
        Key      = 'EmployeeID'
        # No DateColumn: always a full upsert.
        # EmployeeGUID is owned by another application: not synced.
        Columns  = @(
            'EmployeeID', 'EmployeeCode', 'IdCode', 'Surname', 'FirstName', 'MiddleName',
            'NameExtention', 'FullName', 'ResidentialAddress', 'ResidentialZipCode', 'ResidentialTelephone',
            'EmailAddress', 'CellPhone', 'DateOfBirth', 'PlaceOfBirth', 'Sex', 'CivilStatus',
            'CivilStatusOther', 'Citizenship', 'Height', 'Weight', 'BloodType', 'HDMFIdNo', 'PHICIdNo',
            'SSSNo', 'TIN', 'TaxCodeID', 'BankAccountNo', 'DepartmentID', 'PositionID', 'Department',
            'ShiftID', 'HourlyRate', 'MonthlyRate', 'DailyRate', 'DateHired', 'WorkStatus',
            'HDMFEmployee', 'HDMFEmployer', 'DateResigned', 'AllowsLate', 'PHICBracketID', 'SSSBracketID',
            'ProbationaryDate', 'IncludeSSS', 'IncludeHDMF', 'IncludePHIC', 'IncludeTax',
            'ReasonforResignation', 'FinalPayDate', 'EmploymentStatus', 'AllowsUT', 'Allowance',
            'AllowsAbsences', 'Remarks', 'IsSave', 'IsDeleted', 'EncodedByID', 'EncodedOn',
            'IsNoPunch', 'WorkDays'
        )
        Required = @(
            'EmployeeID', 'ShiftID', 'HourlyRate', 'MonthlyRate', 'DailyRate', 'HDMFEmployee', 'HDMFEmployer',
            'AllowsLate', 'PHICBracketID', 'SSSBracketID', 'IncludeSSS', 'IncludeHDMF', 'IncludePHIC', 'IncludeTax',
            'AllowsUT', 'Allowance', 'AllowsAbsences', 'IsSave', 'IsDeleted', 'EncodedByID'
        )
    },
    [pscustomobject]@{
        Name     = 't_shifting'
        Endpoint = 'api/shifting/upsert'
        Key      = 'ShiftingID'
        DateColumn = 'ShiftDate'
        Columns  = @(
            'ShiftingID', 'EmployeeID', 'ShiftDate', 'Location', 'StartTime', 'EndTime', 'TotalMinutes',
            'IsAugmentation', 'IsOvertime', 'IsRestDay', 'EncodedBy', 'EncodedOn', 'OvertimeMinutes'
        )
        Required = @('ShiftingID')
    }
)
