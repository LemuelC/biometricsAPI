using System.ComponentModel.DataAnnotations;

namespace biometricsAPI.Models
{
    /// <summary>
    /// One t_biometric_logs row as the branch sends it.
    /// bioBiometricLogGUID and BranchGUID are NOT sent: the database generates bioBiometricLogGUID
    /// on insert and BranchGUID comes from the authenticated API key.
    ///
    /// Property ORDER must match dbo.tt_t_biometric_logs (table-valued parameters bind by position).
    /// </summary>
    public class BiometricLogDto
    {
        public int BiometricLogID { get; set; }
        public int? EmployeeID { get; set; }
        [StringLength(50)] public string? LogType { get; set; }
        public DateTime? LogDateTime { get; set; }
    }

    /// <summary>A row of the central dbo.t_biometric_logs table.</summary>
    public class BiometricLog : BiometricLogDto
    {
        public Guid bioBiometricLogGUID { get; set; }
        public Guid BranchGUID { get; set; }
    }
}
