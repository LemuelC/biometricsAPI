using System.ComponentModel.DataAnnotations;

namespace biometricsAPI.Models
{
    /// <summary>
    /// One t_shifting row as the branch sends it.
    /// bioShiftingGUID and BranchGUID are NOT sent: the database generates bioShiftingGUID on
    /// insert and BranchGUID comes from the authenticated API key.
    ///
    /// Property ORDER must match dbo.tt_t_shifting (table-valued parameters bind by position).
    /// </summary>
    public class ShiftingDto
    {
        public int ShiftingID { get; set; }
        public int? EmployeeID { get; set; }
        public DateTime? ShiftDate { get; set; }
        [StringLength(50)] public string? Location { get; set; }
        public DateTime? StartTime { get; set; }
        public DateTime? EndTime { get; set; }
        public int? TotalMinutes { get; set; }
        public bool? IsAugmentation { get; set; }
        public bool? IsOvertime { get; set; }
        public bool? IsRestDay { get; set; }
        public int? EncodedBy { get; set; }
        public DateTime? EncodedOn { get; set; }
        public int? OvertimeMinutes { get; set; }
    }

    /// <summary>A row of the central dbo.t_shifting table.</summary>
    public class Shifting : ShiftingDto
    {
        public Guid bioShiftingGUID { get; set; }
        public Guid BranchGUID { get; set; }
    }
}
