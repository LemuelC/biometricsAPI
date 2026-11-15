using biometricsAPI.Data;
using biometricsAPI.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Controllers
{
    [Route("api/biometric-logs")]
    public class BiometricLogsController : BranchControllerBase
    {
        private readonly AppDbContext _db;
        private readonly UpsertRepository _repo;

        public BiometricLogsController(AppDbContext db, UpsertRepository repo)
        {
            _db = db;
            _repo = repo;
        }

        /// <summary>
        /// UPSERT a batch of biometric log rows for the calling branch.
        /// Matches on (BranchGUID, BiometricLogID): existing rows are updated if changed, new rows inserted.
        /// </summary>
        [HttpPost("upsert")]
        [RequestSizeLimit(50_000_000)]
        public Task<ActionResult<UpsertResult>> Upsert([FromBody] List<BiometricLogDto> rows, CancellationToken ct) =>
            UpsertBatch(_repo, "t_biometric_logs", rows, l => l.BiometricLogID, ct);

        /// <summary>
        /// Biometric logs already stored for the calling branch, newest first.
        /// Optional from / to (yyyy-MM-dd, both inclusive) filter on LogDateTime.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<BiometricLog>>> List([FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int? employeeId, [FromQuery] int page = 1, [FromQuery] int pageSize = 100, CancellationToken ct = default)
        {
            page = Math.Max(page, 1);
            pageSize = Math.Clamp(pageSize, 1, 1000);
            var branch = BranchGuid;

            var query = _db.BiometricLogs.AsNoTracking().Where(l => l.BranchGUID == branch);
            if (employeeId is not null) query = query.Where(l => l.EmployeeID == employeeId);
            if (from is not null) query = query.Where(l => l.LogDateTime >= from.Value.Date);
            if (to is not null)
            {
                var toExclusive = to.Value.Date.AddDays(1);
                query = query.Where(l => l.LogDateTime < toExclusive);
            }

            return await query
                .OrderByDescending(l => l.LogDateTime).ThenByDescending(l => l.BiometricLogID)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync(ct);
        }

        [HttpGet("{biometricLogId:int}")]
        public async Task<ActionResult<BiometricLog>> Get(int biometricLogId, CancellationToken ct)
        {
            var branch = BranchGuid;
            var row = await _db.BiometricLogs.AsNoTracking()
                .FirstOrDefaultAsync(l => l.BranchGUID == branch && l.BiometricLogID == biometricLogId, ct);
            return row is null ? NotFound() : row;
        }
    }
}
