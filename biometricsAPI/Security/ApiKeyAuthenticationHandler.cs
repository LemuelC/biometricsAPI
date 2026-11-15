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
    /// Authenticates a branch from two headers:
    ///   X-Branch-Id: the branch's BranchGUID
    ///   X-Api-Key:   the branch's secret key
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
            if (!Request.Headers.TryGetValue(BranchHeader, out var branchValue) ||
                !Request.Headers.TryGetValue(KeyHeader, out var keyValue))
                return AuthenticateResult.NoResult();

            var key = keyValue.ToString();
            if (!Guid.TryParse(branchValue, out var branchGuid) || string.IsNullOrWhiteSpace(key))
                return AuthenticateResult.Fail("Invalid credentials.");

            var client = await _db.ApiClients.AsNoTracking()
                .FirstOrDefaultAsync(c => c.BranchGUID == branchGuid && c.IsActive);

            var suppliedHash = ApiKeyHasher.Hash(key);
            if (client is null || !CryptographicOperations.FixedTimeEquals(suppliedHash, client.ApiKeyHash))
            {
                Logger.LogWarning("Rejected API key for branch {Branch} from {Ip}", branchGuid, Context.Connection.RemoteIpAddress);
                return AuthenticateResult.Fail("Invalid credentials.");
            }

            var identity = new ClaimsIdentity(new[]
            {
                new Claim(BranchClaim, client.BranchGUID.ToString()),
                new Claim(ClaimTypes.Name, client.BranchName),
            }, SchemeName);

            return AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName));
        }
    }
}
