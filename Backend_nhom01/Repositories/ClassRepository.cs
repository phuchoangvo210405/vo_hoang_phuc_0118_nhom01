using Microsoft.EntityFrameworkCore;
using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public class ClassRepository(ApplicationDbContext db) : IClassRepository
{
    public IQueryable<Subject> Subjects() => db.Subjects;
    public IQueryable<ClassRoom> Classes() => db.ClassRooms;
    public IQueryable<Enrollment> Enrollments() => db.Enrollments;

    // Lớp chỉ được quản lý bởi admin hoặc giảng viên phụ trách lớp đó.
    public async Task<ClassRoom?> FindManagedAsync(int classId, int userId, bool isAdmin)
    {
        var c = await db.ClassRooms.FindAsync(classId);
        return c is not null && (isAdmin || c.TeacherId == userId) ? c : null;
    }

    public Task<bool> IsEnrolledAsync(int classId, int studentId) =>
        db.Enrollments.AnyAsync(e => e.ClassRoomId == classId && e.StudentId == studentId);

    public void AddSubject(Subject subject) => db.Subjects.Add(subject);
    public void RemoveSubject(Subject subject) => db.Subjects.Remove(subject);
    public void AddClass(ClassRoom classRoom) => db.ClassRooms.Add(classRoom);
    public void RemoveClass(ClassRoom classRoom) => db.ClassRooms.Remove(classRoom);
    public void AddEnrollment(Enrollment enrollment) => db.Enrollments.Add(enrollment);
    public void RemoveEnrollment(Enrollment enrollment) => db.Enrollments.Remove(enrollment);

    public Task<bool> SaveAsync() => db.TrySaveAsync();
}
