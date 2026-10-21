using Microsoft.EntityFrameworkCore;

namespace vo_hoang_phuc_0118_nhom01.model;

public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : DbContext(options)
{
    public DbSet<AppUser> Users => Set<AppUser>();
    public DbSet<OtpCode> OtpCodes => Set<OtpCode>();
    public DbSet<Subject> Subjects => Set<Subject>();
    public DbSet<ClassRoom> ClassRooms => Set<ClassRoom>();
    public DbSet<Enrollment> Enrollments => Set<Enrollment>();
    public DbSet<ClassSession> ClassSessions => Set<ClassSession>();
    public DbSet<Attendance> Attendances => Set<Attendance>();
    public DbSet<LeaveRequest> LeaveRequests => Set<LeaveRequest>();

    // Trả về false nếu lưu bị trùng khoá hoặc xoá dữ liệu đang được tham chiếu.
    public async Task<bool> TrySaveAsync()
    {
        try
        {
            await SaveChangesAsync();
            return true;
        }
        catch (DbUpdateException)
        {
            return false;
        }
    }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<AppUser>(e =>
        {
            e.HasIndex(x => x.Username).IsUnique();
            e.HasIndex(x => x.Email).IsUnique();
            e.Property(x => x.Role).HasConversion<string>().HasMaxLength(20);
        });
        b.Entity<OtpCode>(e => e.Property(x => x.Purpose).HasConversion<string>().HasMaxLength(20));
        b.Entity<LeaveRequest>(e =>
        {
            e.Property(x => x.Status).HasConversion<string>().HasMaxLength(20);
            e.Property(x => x.Reason).HasMaxLength(1000);
            e.HasIndex(x => new { x.ClassSessionId, x.StudentId }).IsUnique();
        });
        b.Entity<Subject>(e => e.HasIndex(x => x.Code).IsUnique());
        b.Entity<Enrollment>(e => e.HasIndex(x => new { x.ClassRoomId, x.StudentId }).IsUnique());
        b.Entity<Attendance>(e => e.HasIndex(x => new { x.ClassSessionId, x.StudentId }).IsUnique());

        // SQL Server không index được cột nvarchar(max), nên đặt độ dài mặc định cho mọi cột chuỗi.
        foreach (var p in b.Model.GetEntityTypes().SelectMany(t => t.GetProperties())
                     .Where(p => p.ClrType == typeof(string) && p.GetMaxLength() == null))
            p.SetMaxLength(255);

        // Tránh lỗi "multiple cascade paths" trên SQL Server.
        foreach (var fk in b.Model.GetEntityTypes().SelectMany(t => t.GetForeignKeys()))
            fk.DeleteBehavior = DeleteBehavior.Restrict;
    }
}
