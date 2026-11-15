using System.ComponentModel.DataAnnotations;

namespace biometricsAPI.Models
{
    /// <summary>
    /// One employee row as the branch sends it (the branch's m_employee columns).
    /// BioEmployeeGUID and BranchGUID are NOT sent: the database generates BioEmployeeGUID on
    /// insert and BranchGUID comes from the authenticated API key, so a branch can only write
    /// its own rows. EmployeeGUID belongs to another application and is not synced.
    ///
    /// Property ORDER must match dbo.tt_m_employee (table-valued parameters bind by position).
    /// </summary>
    public class EmployeeDto
    {
        public int EmployeeID { get; set; }
        [StringLength(10)] public string? EmployeeCode { get; set; }
        [StringLength(10)] public string? IdCode { get; set; }
        [StringLength(50)] public string? Surname { get; set; }
        [StringLength(50)] public string? FirstName { get; set; }
        [StringLength(25)] public string? MiddleName { get; set; }
        [StringLength(5)] public string? NameExtention { get; set; }
        [StringLength(150)] public string? FullName { get; set; }
        [StringLength(255)] public string? ResidentialAddress { get; set; }
        [StringLength(10)] public string? ResidentialZipCode { get; set; }
        [StringLength(50)] public string? ResidentialTelephone { get; set; }
        [StringLength(50)] public string? EmailAddress { get; set; }
        [StringLength(50)] public string? CellPhone { get; set; }
        public DateTime? DateOfBirth { get; set; }
        [StringLength(10)] public string? PlaceOfBirth { get; set; }
        [StringLength(10)] public string? Sex { get; set; }
        [StringLength(10)] public string? CivilStatus { get; set; }
        [StringLength(10)] public string? CivilStatusOther { get; set; }
        [StringLength(20)] public string? Citizenship { get; set; }
        [StringLength(10)] public string? Height { get; set; }
        [StringLength(10)] public string? Weight { get; set; }
        [StringLength(10)] public string? BloodType { get; set; }
        [StringLength(50)] public string? HDMFIdNo { get; set; }
        [StringLength(50)] public string? PHICIdNo { get; set; }
        [StringLength(50)] public string? SSSNo { get; set; }
        [StringLength(50)] public string? TIN { get; set; }
        public int? TaxCodeID { get; set; }
        [StringLength(50)] public string? BankAccountNo { get; set; }
        public int? DepartmentID { get; set; }
        public int? PositionID { get; set; }
        [StringLength(255)] public string? Department { get; set; }
        public int ShiftID { get; set; }
        public double HourlyRate { get; set; }
        public double MonthlyRate { get; set; }
        public double DailyRate { get; set; }
        public DateTime? DateHired { get; set; }
        [StringLength(50)] public string? WorkStatus { get; set; }
        public double HDMFEmployee { get; set; }
        public double HDMFEmployer { get; set; }
        public DateTime? DateResigned { get; set; }
        public bool AllowsLate { get; set; }
        public int PHICBracketID { get; set; }
        public int SSSBracketID { get; set; }
        public DateTime? ProbationaryDate { get; set; }
        public bool IncludeSSS { get; set; }
        public bool IncludeHDMF { get; set; }
        public bool IncludePHIC { get; set; }
        public bool IncludeTax { get; set; }
        [StringLength(255)] public string? ReasonforResignation { get; set; }
        public DateTime? FinalPayDate { get; set; }
        [StringLength(50)] public string? EmploymentStatus { get; set; }
        public bool AllowsUT { get; set; }
        public double Allowance { get; set; }
        public bool AllowsAbsences { get; set; }
        [StringLength(255)] public string? Remarks { get; set; }
        public bool IsSave { get; set; }
        public bool IsDeleted { get; set; }
        public int EncodedByID { get; set; }
        public DateTime? EncodedOn { get; set; }
        public bool? IsNoPunch { get; set; }
        public int? WorkDays { get; set; }
    }

    /// <summary>A row of the central dbo.m_employee table.</summary>
    public class Employee : EmployeeDto
    {
        public Guid BioEmployeeGUID { get; set; }
        public Guid BranchGUID { get; set; }
    }
}
