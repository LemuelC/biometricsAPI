using biometricsAPI.Data;
using biometricsAPI.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Controllers
{
    [Route("api/employees")]
    public class EmployeesController : BranchControllerBase
    {
        private readonly AppDbContext _db;
        private readonly UpsertRepository _repo;

        public EmployeesController(AppDbContext db, UpsertRepository repo)
        {
            _db = db;
            _repo = repo;
        }

        /// <summary>
        /// UPSERT a batch of employees for the calling branch.
        /// Matches on (BranchGUID, EmployeeID): existing rows are updated if changed, new rows inserted.
        /// </summary>
        [HttpPost("upsert")]
        [RequestSizeLimit(50_000_000)]
        public Task<ActionResult<UpsertResult>> Upsert([FromBody] List<EmployeeDto> employees, CancellationToken ct) =>
            UpsertBatch(_repo, "m_employee", employees, e => e.EmployeeID, ct);

        /// <summary>Employees already stored for the calling branch.</summary>
        [HttpGet]
        public async Task<ActionResult<List<Employee>>> List([FromQuery] int page = 1, [FromQuery] int pageSize = 100, CancellationToken ct = default)
        {
            page = Math.Max(page, 1);
            pageSize = Math.Clamp(pageSize, 1, 1000);
            var branch = BranchGuid;

            return await _db.Employees.AsNoTracking()
                .Where(e => e.BranchGUID == branch)
                .OrderBy(e => e.EmployeeID)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync(ct);
        }

        [HttpGet("{employeeId:int}")]
        public async Task<ActionResult<Employee>> Get(int employeeId, CancellationToken ct)
        {
            var branch = BranchGuid;
            var employee = await _db.Employees.AsNoTracking()
                .FirstOrDefaultAsync(e => e.BranchGUID == branch && e.EmployeeID == employeeId, ct);
            return employee is null ? NotFound() : employee;
        }
    }
}
