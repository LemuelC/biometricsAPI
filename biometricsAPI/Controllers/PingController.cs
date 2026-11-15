using System.Security.Claims;
using biometricsAPI.Security;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace biometricsAPI.Controllers
{
    /// <summary>Lets a branch check that its URL and API key work.</summary>
    [ApiController]
    [Route("api/ping")]
    [Authorize]
    public class PingController : ControllerBase
    {
        [HttpGet]
        public IActionResult Get() => Ok(new
        {
            branchGuid = User.FindFirstValue(ApiKeyAuthenticationHandler.BranchClaim),
            branchName = User.Identity?.Name,
            serverTime = DateTime.Now,
        });
    }
}
