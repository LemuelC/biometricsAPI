using System.Security.Cryptography;
using System.Text;

namespace biometricsAPI.Security
{
    public static class ApiKeyHasher
    {
        // Keys are 32 random bytes, so a plain SHA-256 is enough: nobody can brute-force
        // 256 bits of randomness. (Slow hashes like bcrypt are only needed for human passwords.)
        public static byte[] Hash(string apiKey) => SHA256.HashData(Encoding.UTF8.GetBytes(apiKey));

        public static string NewKey() =>
            Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
                .TrimEnd('=').Replace('+', '-').Replace('/', '_');

        /// <summary>
        /// Handles: dotnet run -- genkey &lt;BranchGUID&gt; "&lt;Branch name&gt;"
        /// Prints a new API key (give it to the branch) and the INSERT to run on the central DB.
        /// </summary>
        public static int RunGenKeyCommand(string[] args)
        {
            if (args.Length < 3 || !Guid.TryParse(args[1], out var branchGuid))
            {
                Console.WriteLine("usage: dotnet run -- genkey <BranchGUID> \"<Branch name>\"");
                return 1;
            }

            var key = NewKey();
            var hashHex = Convert.ToHexString(Hash(key));
            var name = args[2].Replace("'", "''");

            Console.WriteLine($"API key (give to the branch, store it nowhere else): {key}");
            Console.WriteLine($"Swagger Authorize value:                              {branchGuid}:{key}");
            Console.WriteLine();
            Console.WriteLine("Run on the central database:");
            // Update-or-insert, so re-running genkey for a branch replaces its old key.
            Console.WriteLine($"IF EXISTS (SELECT 1 FROM dbo.api_client WHERE BranchGUID = '{branchGuid}')");
            Console.WriteLine($"    UPDATE dbo.api_client SET BranchName = N'{name}', ApiKeyHash = 0x{hashHex}, IsActive = 1 WHERE BranchGUID = '{branchGuid}';");
            Console.WriteLine("ELSE");
            Console.WriteLine($"    INSERT INTO dbo.api_client (BranchGUID, BranchName, ApiKeyHash) VALUES ('{branchGuid}', N'{name}', 0x{hashHex});");
            return 0;
        }
    }
}
