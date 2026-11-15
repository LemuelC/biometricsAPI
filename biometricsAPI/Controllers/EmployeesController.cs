using System.Security.Claims;
using biometricsAPI.Data;
using biometricsAPI.Models;
using biometricsAPI.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Controllers
{
    [ApiController]
    [Route("api/employees")]
    [Authorize]
    public class EmployeesController : ControllerBase
    {
        private const int MaxBatchSize = 5000;

        private readonly AppDbContext _db;
        private readonly EmployeeRepository _repo;

        public EmployeesController(AppDbContext db, EmployeeRepository repo)
        {
            _db = db;
            _repo = repo;
        }

        // Set by ApiKeyAuthenticationHandler from the caller's API key.
        private Guid BranchGuid => Guid.Parse(User.FindFirstValue(ApiKeyAuthenticationHandler.BranchClaim)!);

        /// <summary>
        /// UPSERT a batch of employees for the calling branch.
        /// Matches on (BranchGUID, EmployeeID): existing rows are updated if changed, new rows inserted.
        /// </summary>
        [HttpPost("upsert")]
        [RequestSizeLimit(50_000_000)]
        public async Task<ActionResult<UpsertResult>> Upsert([FromBody] List<EmployeeDto> employees, CancellationToken ct)
        {
            if (employees.Count == 0)
                return BadRequest("No employees sent.");
            if (employees.Count > MaxBatchSize)
                return BadRequest($"Send at most {MaxBatchSize} employees per request.");

            var duplicates = employees.GroupBy(e => e.EmployeeID).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
            if (duplicates.Count > 0)
                return BadRequest($"Duplicate EmployeeID in batch: {string.Join(", ", duplicates)}");

            return await _repo.UpsertAsync(BranchGuid, employees, ct);
        }

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
