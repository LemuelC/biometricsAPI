using biometricsAPI.Data;
using biometricsAPI.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Controllers
{
    [Route("api/shifting")]
    public class ShiftingController : BranchControllerBase
    {
        private readonly AppDbContext _db;
        private readonly UpsertRepository _repo;

        public ShiftingController(AppDbContext db, UpsertRepository repo)
        {
            _db = db;
            _repo = repo;
        }

        /// <summary>
        /// UPSERT a batch of shifting rows for the calling branch.
        /// Matches on (BranchGUID, ShiftingID): existing rows are updated if changed, new rows inserted.
        /// </summary>
        [HttpPost("upsert")]
        [RequestSizeLimit(50_000_000)]
        public Task<ActionResult<UpsertResult>> Upsert([FromBody] List<ShiftingDto> rows, CancellationToken ct) =>
            UpsertBatch(_repo, "t_shifting", rows, s => s.ShiftingID, ct);

        /// <summary>
        /// Shifting rows already stored for the calling branch, newest shift first.
        /// Optional from / to (yyyy-MM-dd, both inclusive) filter on ShiftDate.
        /// </summary>
        [HttpGet]
        public async Task<ActionResult<List<Shifting>>> List([FromQuery] DateTime? from, [FromQuery] DateTime? to,
            [FromQuery] int page = 1, [FromQuery] int pageSize = 100, CancellationToken ct = default)
        {
            page = Math.Max(page, 1);
            pageSize = Math.Clamp(pageSize, 1, 1000);
            var branch = BranchGuid;

            var query = _db.Shifting.AsNoTracking().Where(s => s.BranchGUID == branch);
            if (from is not null) query = query.Where(s => s.ShiftDate >= from.Value.Date);
            if (to is not null)
            {
                var toExclusive = to.Value.Date.AddDays(1);
                query = query.Where(s => s.ShiftDate < toExclusive);
            }

            return await query
                .OrderByDescending(s => s.ShiftDate).ThenByDescending(s => s.ShiftingID)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync(ct);
        }

        [HttpGet("{shiftingId:int}")]
        public async Task<ActionResult<Shifting>> Get(int shiftingId, CancellationToken ct)
        {
            var branch = BranchGuid;
            var row = await _db.Shifting.AsNoTracking()
                .FirstOrDefaultAsync(s => s.BranchGUID == branch && s.ShiftingID == shiftingId, ct);
            return row is null ? NotFound() : row;
        }
    }
}
