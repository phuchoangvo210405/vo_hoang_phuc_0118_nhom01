using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public interface ILeaveRequestRepository
{
    IQueryable<LeaveRequest> LeaveRequests();
    void Add(LeaveRequest leaveRequest);
    Task<bool> SaveAsync();
}
