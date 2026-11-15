using biometricsAPI.Models;
using Microsoft.EntityFrameworkCore;

namespace biometricsAPI.Data
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

        public DbSet<ApiClient> ApiClients => Set<ApiClient>();
        public DbSet<Employee> Employees => Set<Employee>();
        public DbSet<Shifting> Shifting => Set<Shifting>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<ApiClient>(e =>
            {
                e.ToTable("api_client");
                e.HasKey(x => x.BranchGUID);
            });

            modelBuilder.Entity<Employee>(e =>
            {
                e.ToTable("m_employee");
                e.HasKey(x => x.BioEmployeeGUID);
                e.HasIndex(x => new { x.BranchGUID, x.EmployeeID }).IsUnique();
                e.Property(x => x.DateResigned).HasColumnType("date");
            });

            modelBuilder.Entity<Shifting>(e =>
            {
                e.ToTable("t_shifting");
                e.HasKey(x => x.bioShiftingGUID);
                e.HasIndex(x => new { x.BranchGUID, x.ShiftingID }).IsUnique();
            });
        }
    }
}
