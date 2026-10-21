using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public class LeaveRequestRepository(ApplicationDbContext db) : ILeaveRequestRepository
{
    public IQueryable<LeaveRequest> LeaveRequests() => db.LeaveRequests;

    public void Add(LeaveRequest leaveRequest) => db.LeaveRequests.Add(leaveRequest);

    public Task<bool> SaveAsync() => db.TrySaveAsync();
}
