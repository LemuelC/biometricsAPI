using biometricsAPI.Data;
using biometricsAPI.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Controllers
{
    [Route("api/attendance-logs")]
    public class AttendanceLogsController : BranchControllerBase
    {
        private readonly AppDbContext _db;
        private readonly UpsertRepository _repo;

        public AttendanceLogsController(AppDbContext db, UpsertRepository repo)
        {
            _db = db;
            _repo = repo;
        }

        /// <summary>
        /// UPSERT a batch of attendance log rows for the calling branch.
        /// Matches on (BranchGUID, AttendanceLogID): existing rows are updated if changed, new rows inserted.
        /// </summary>
        [HttpPost("upsert")]
        [RequestSizeLimit(50_000_000)]
        public Task<ActionResult<UpsertResult>> Upsert([FromBody] List<AttendanceLogDto> rows, CancellationToken ct) =>
            UpsertBatch(_repo, "t_attendance_logs", rows, a => a.AttendanceLogID, ct);

        /// <summary>
        /// Attendance logs already stored for the calling branch, newest first.
        /// Optional from / to (yyyy-MM-dd, both inclusive) filter on LogDate.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<AttendanceLog>>> List([FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? employeeId, [FromQuery] int page = 1, [FromQuery] int pageSize = 100, CancellationToken ct = default)
        {
            page = Math.Max(page, 1);
            pageSize = Math.Clamp(pageSize, 1, 1000);
            var branch = BranchGuid;

            var query = _db.AttendanceLogs.AsNoTracking().Where(a => a.BranchGUID == branch);
            if (employeeId is not null) query = query.Where(a => a.EmployeeID == employeeId);
            if (from is not null) query = query.Where(a => a.LogDate >= from.Value.Date);
            if (to is not null)
            {
                var toExclusive = to.Value.Date.AddDays(1);
                query = query.Where(a => a.LogDate < toExclusive);
            }

            return await query
                .OrderByDescending(a => a.LogDate).ThenByDescending(a => a.AttendanceLogID)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync(ct);
        }

        [HttpGet("{attendanceLogId:int}")]
        public async Task<ActionResult<AttendanceLog>> Get(int attendanceLogId, CancellationToken ct)
        {
            var branch = BranchGuid;
            var row = await _db.AttendanceLogs.AsNoTracking()
                .FirstOrDefaultAsync(a => a.BranchGUID == branch && a.AttendanceLogID == attendanceLogId, ct);
            return row is null ? NotFound() : row;
        }
    }
}
