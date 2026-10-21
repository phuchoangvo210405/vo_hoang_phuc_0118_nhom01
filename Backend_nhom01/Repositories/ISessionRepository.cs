using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public interface ISessionRepository
{
    IQueryable<ClassSession> Sessions();
    IQueryable<Attendance> Attendances();
    void AddSession(ClassSession session);
    void RemoveSession(ClassSession session);
    void AddAttendance(Attendance attendance);
    Task<bool> SaveAsync();
}
