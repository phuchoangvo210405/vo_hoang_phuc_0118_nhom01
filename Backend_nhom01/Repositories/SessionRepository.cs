using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public class SessionRepository(ApplicationDbContext db) : ISessionRepository
{
    public IQueryable<ClassSession> Sessions() => db.ClassSessions;
    public IQueryable<Attendance> Attendances() => db.Attendances;

    public void AddSession(ClassSession session) => db.ClassSessions.Add(session);
    public void RemoveSession(ClassSession session) => db.ClassSessions.Remove(session);
    public void AddAttendance(Attendance attendance) => db.Attendances.Add(attendance);

    public Task<bool> SaveAsync() => db.TrySaveAsync();
}
