using System.Security.Claims;
using biometricsAPI.Data;
using biometricsAPI.Models;
using biometricsAPI.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace biometricsAPI.Controllers
{
    /// <summary>Shared plumbing for the per-table sync controllers.</summary>
    [ApiController]
    [Authorize]
    public abstract class BranchControllerBase : ControllerBase
    {
        protected const int MaxBatchSize = 5000;

        // Set by ApiKeyAuthenticationHandler from the caller's API key.
        protected Guid BranchGuid => Guid.Parse(User.FindFirstValue(ApiKeyAuthenticationHandler.BranchClaim)!);

        /// <summary>Validates a batch and sends it to dbo.usp_&lt;table&gt;_upsert for the calling branch.</summary>
        protected async Task<ActionResult<UpsertResult>> UpsertBatch<TDto>(
            UpsertRepository repo, string table, List<TDto> rows, Func<TDto, int> key, CancellationToken ct)
        {
            if (rows.Count == 0)
                return BadRequest("No rows sent.");
            if (rows.Count > MaxBatchSize)
                return BadRequest($"Send at most {MaxBatchSize} rows per request.");

            var duplicates = rows.GroupBy(key).Where(g => g.Count() > 1).Select(g => g.Key).ToList();
            if (duplicates.Count > 0)
                return BadRequest($"Duplicate key in batch: {string.Join(", ", duplicates)}");

            return await repo.UpsertAsync(table, BranchGuid, rows, ct);
        }
    }
}
