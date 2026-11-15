namespace biometricsAPI.Models
{
    /// <summary>A branch allowed to call the API (dbo.api_client).</summary>
    public class ApiClient
    {
        public Guid BranchGUID { get; set; }
        public string BranchName { get; set; } = "";
        public byte[] ApiKeyHash { get; set; } = Array.Empty<byte>();
        public bool IsActive { get; set; }
        public DateTime CreatedOn { get; set; }
    }
}
