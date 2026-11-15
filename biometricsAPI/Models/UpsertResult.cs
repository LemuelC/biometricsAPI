namespace biometricsAPI.Models
{
    /// <summary>What an upsert did with the rows a branch sent.</summary>
    public record UpsertResult(int Received, int Inserted, int Updated, int Unchanged);
}
