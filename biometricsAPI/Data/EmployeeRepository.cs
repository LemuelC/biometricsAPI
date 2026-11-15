using System.Data;
using System.Reflection;
using biometricsAPI.Models;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Data
{
    public class EmployeeRepository
    {
        // EmployeeDto properties in declaration order = dbo.tt_m_employee column order.
        private static readonly PropertyInfo[] DtoColumns = typeof(EmployeeDto)
            .GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .OrderBy(p => p.MetadataToken)
            .ToArray();

        private readonly AppDbContext _db;

        public EmployeeRepository(AppDbContext db)
        {
            _db = db;
        }

        /// <summary>
        /// Sends the whole batch to dbo.usp_m_employee_upsert as one table-valued parameter:
        /// one round trip, one transaction, set-based UPDATE + INSERT on the server.
        /// </summary>
        public async Task<UpsertResult> UpsertAsync(Guid branchGuid, IReadOnlyList<EmployeeDto> rows, CancellationToken ct)
        {
            var conn = (SqlConnection)_db.Database.GetDbConnection();
            await _db.Database.OpenConnectionAsync(ct);
            try
            {
                await using var cmd = new SqlCommand("dbo.usp_m_employee_upsert", conn)
                {
                    CommandType = CommandType.StoredProcedure,
                    CommandTimeout = 120,
                };
                cmd.Parameters.Add(new SqlParameter("@BranchGUID", SqlDbType.UniqueIdentifier) { Value = branchGuid });
                cmd.Parameters.Add(new SqlParameter("@Rows", SqlDbType.Structured)
                {
                    TypeName = "dbo.tt_m_employee",
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

        private static DataTable ToDataTable(IEnumerable<EmployeeDto> rows)
        {
            var table = new DataTable();
            foreach (var p in DtoColumns)
                table.Columns.Add(p.Name, Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType);

            foreach (var row in rows)
            {
                var values = new object[DtoColumns.Length];
                for (var i = 0; i < DtoColumns.Length; i++)
                    values[i] = DtoColumns[i].GetValue(row) ?? DBNull.Value;
                table.Rows.Add(values);
            }
            return table;
        }
    }
}
