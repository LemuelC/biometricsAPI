using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Encodings.Web;
using biometricsAPI.Data;
using Microsoft.AspNetCore.Authentication;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace biometricsAPI.Security
{
    /// <summary>
    /// Authenticates a branch. Two accepted forms:
    ///   X-Branch-Id: &lt;BranchGUID&gt;  +  X-Api-Key: &lt;API key&gt;      (branch sync client)
    ///   X-Api-Key: &lt;BranchGUID&gt;:&lt;API key&gt;                       (Swagger: one field)
    /// The key is hashed and compared to dbo.api_client.ApiKeyHash in constant time.
    /// </summary>
    public class ApiKeyAuthenticationHandler : AuthenticationHandler<AuthenticationSchemeOptions>
    {
        public const string SchemeName = "ApiKey";
        public const string BranchHeader = "X-Branch-Id";
        public const string KeyHeader = "X-Api-Key";
        public const string BranchClaim = "branch_guid";

        private readonly AppDbContext _db;

        public ApiKeyAuthenticationHandler(
            IOptionsMonitor<AuthenticationSchemeOptions> options,
            ILoggerFactory logger,
            UrlEncoder encoder,
            AppDbContext db)
            : base(options, logger, encoder)
        {
            _db = db;
        }

        protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            var keyValue = Request.Headers[KeyHeader].ToString().Trim();
            var branchValue = Request.Headers[BranchHeader].ToString().Trim();

            if (keyValue.Length == 0)
                return AuthenticateResult.Fail($"Missing {KeyHeader} header.");

            // Combined form "<BranchGUID>:<key>" (keys are base64url, so they never contain ':').
            var separator = keyValue.IndexOf(':');
            if (separator > 0)
            {
                branchValue = keyValue[..separator].Trim();
                keyValue = keyValue[(separator + 1)..].Trim();
            }

            if (branchValue.Length == 0)
                return AuthenticateResult.Fail($"Missing branch: send {BranchHeader}, or {KeyHeader} as \"<BranchGUID>:<key>\".");
            if (!Guid.TryParse(branchValue, out var branchGuid))
                return AuthenticateResult.Fail($"\"{branchValue}\" is not a valid BranchGUID.");

            var client = await _db.ApiClients.AsNoTracking()
                .FirstOrDefaultAsync(c => c.BranchGUID == branchGuid);

            if (client is null || !client.IsActive)
            {
                Logger.LogWarning("Branch {Branch} not registered or inactive ({Ip})", branchGuid, Context.Connection.RemoteIpAddress);
                return AuthenticateResult.Fail($"Branch {branchGuid} is not registered in dbo.api_client or is inactive.");
            }

            if (!CryptographicOperations.FixedTimeEquals(ApiKeyHasher.Hash(keyValue), client.ApiKeyHash))
            {
                Logger.LogWarning("Wrong API key for branch {Branch} ({Ip})", branchGuid, Context.Connection.RemoteIpAddress);
                return AuthenticateResult.Fail($"API key does not match branch {branchGuid}.");
            }

            var identity = new ClaimsIdentity(new[]
            {
                new Claim(BranchClaim, client.BranchGUID.ToString()),
                new Claim(ClaimTypes.Name, client.BranchName),
            }, SchemeName);

            return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
        }

        // 401 body says why, so a bad header or unregistered branch is obvious from Swagger/logs.
        protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
        {
            var result = await HandleAuthenticateOnceSafeAsync();
            Response.StatusCode = StatusCodes.Status401Unauthorized;
            await Response.WriteAsJsonAsync(new
            {
                status = 401,
                error = result.Failure?.Message ?? "Not authenticated.",
            });
        }
    }
}
