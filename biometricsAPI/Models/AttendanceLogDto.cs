namespace biometricsAPI.Models
{
    /// <summary>
    /// One t_attendance_logs row as the branch sends it.
    /// bioAttendanceLogGUID and BranchGUID are NOT sent: the database generates bioAttendanceLogGUID
    /// on insert and BranchGUID comes from the authenticated API key.
    ///
    /// Property ORDER must match dbo.tt_t_attendance_logs (table-valued parameters bind by position).
    /// </summary>
    public class AttendanceLogDto
    {
        public int AttendanceLogID { get; set; }
        public DateTime? LogDate { get; set; }
        public DateTime? LogIN { get; set; }
        public DateTime? LogOUT { get; set; }
        public int? EmployeeID { get; set; }
        public int? TotalMinutes { get; set; }
        public int? ShiftingID { get; set; }
        public int? WorkMinutes { get; set; }
        public int? OTMinutes { get; set; }
        public int? NDMinutes { get; set; }
        public int? PaidLeave { get; set; }
        public int? Leave { get; set; }
    }

    /// <summary>A row of the central dbo.t_attendance_logs table.</summary>
    public class AttendanceLog : AttendanceLogDto
    {
        public Guid bioAttendanceLogGUID { get; set; }
        public Guid BranchGUID { get; set; }
    }
}
