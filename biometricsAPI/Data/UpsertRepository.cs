using System.Collections.Concurrent;
using System.Data;
using System.Reflection;
using biometricsAPI.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Data
{
    /// <summary>
    /// Sends a batch to a table's upsert procedure as one table-valued parameter:
    /// one round trip, one transaction, set-based UPDATE + INSERT on the server.
    /// Every table follows the same convention:
    ///   procedure  dbo.usp_&lt;table&gt;_upsert (@BranchGUID, @Rows dbo.tt_&lt;table&gt; READONLY)
    ///   returns    one row: Inserted, Updated, Unchanged
    /// </summary>
    public class UpsertRepository
    {
        // DTO properties in declaration order = table type column order.
        private static readonly ConcurrentDictionary<Type, PropertyInfo[]> ColumnsByType = new();

        private readonly AppDbContext _db;

        public UpsertRepository(AppDbContext db)
        {
            _db = db;
        }

        public async Task<UpsertResult> UpsertAsync<TDto>(string table, Guid branchGuid, IReadOnlyList<TDto> rows, CancellationToken ct)
        {
            var conn = (SqlConnection)_db.Database.GetDbConnection();
            await _db.Database.OpenConnectionAsync(ct);
            try
            {
                await using var cmd = new SqlCommand($"dbo.usp_{table}_upsert", conn)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 120,
                };
                cmd.Parameters.Add(new SqlParameter("@BranchGUID", SqlDbType.UniqueIdentifier) { Value = branchGuid });
                cmd.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured)
                {
                    TypeName = $"dbo.tt_{table}",
                    Value = ToDataTable(rows),
                });

                await using var reader = await cmd.ExecuteReaderAsync(ct);
                await reader.ReadAsync(ct);
                return new UpsertResult(rows.Count, reader.GetInt32(0), reader.GetInt32(1), reader.GetInt32(2));
            }
            finally
            {
                await _db.Database.CloseConnectionAsync();
            }
        }

        private static DataTable ToDataTable<TDto>(IEnumerable<TDto> rows)
        {
            var columns = ColumnsByType.GetOrAdd(typeof(TDto), t => t
                .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                .OrderBy(p => p.MetadataToken)
                .ToArray());

            var table = new DataTable();
            foreach (var p in columns)
                table.Columns.Add(p.Name, Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType);

            foreach (var row in rows)
            {
                var values = new object[columns.Length];
                for (var i = 0; i < columns.Length; i++)
                    values[i] = columns[i].GetValue(row) ?? DBNull.Value;
                table.Rows.Add(values);
            }
            return table;
        }
    }
}
