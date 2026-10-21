using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using vo_hoang_phuc_0118_nhom01.model;
using vo_hoang_phuc_0118_nhom01.Repositories;
using vo_hoang_phuc_0118_nhom01.Services;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

[ApiController]
[Authorize]
public class LeaveRequestsApiController(
    ILeaveRequestRepository leaves,
    ISessionRepository sessions,
    IClassRepository classes,
    FileStorageService files) : ApiControllerBase
{
    [HttpPost("api/leave-requests")]
    [Authorize(Roles = nameof(UserRole.SinhVien))]
    public async Task<IActionResult> Submit([FromForm] LeaveForm form)
    {
        var s = await sessions.Sessions().FirstOrDefaultAsync(x => x.Id == form.SessionId);
        if (s is null) return NotFound("Buổi học không tồn tại.");
        if (!await classes.IsEnrolledAsync(s.ClassRoomId, CurrentUserId)) return Forbid();
        if (string.IsNullOrWhiteSpace(form.Reason)) return BadRequest("Vui lòng nhập lý do.");
        if (await leaves.LeaveRequests().AnyAsync(l => l.ClassSessionId == s.Id && l.StudentId == CurrentUserId))
            return Conflict("Bạn đã gửi đơn cho buổi này.");

        string? evidence = null;
        if (form.Evidence is { Length: > 0 })
        {
            try
            {
                evidence = await files.SaveAsync(form.Evidence, "leave");
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(ex.Message);
            }
        }

        leaves.Add(new LeaveRequest
        {
            ClassSessionId = s.Id,
            StudentId = CurrentUserId,
            Reason = form.Reason.Trim(),
            EvidencePath = evidence,
            Status = LeaveStatus.Pending,
            CreatedAt = DateTime.UtcNow
        });
        await leaves.SaveAsync();
        return Ok(new { message = "Đã gửi đơn xin nghỉ." });
    }

    [HttpGet("api/leave-requests/mine")]
    [Authorize(Roles = nameof(UserRole.SinhVien))]
    public async Task<IActionResult> Mine()
    {
        var list = await leaves.LeaveRequests().Where(l => l.StudentId == CurrentUserId)
            .OrderByDescending(l => l.CreatedAt)
            .Select(l => new { l.Id, l.ClassSessionId, Session = l.ClassSession.Title, l.Reason, l.Status, l.CreatedAt, l.ReviewedAt })
            .ToListAsync();
        return Ok(list);
    }

    [HttpGet("api/classes/{classId:int}/leave-requests")]
    public async Task<IActionResult> GetByClass(int classId)
    {
        if (await classes.FindManagedAsync(classId, CurrentUserId, IsAdmin) is null)
            return NotFound("Không tìm thấy lớp hoặc bạn không có quyền.");

        var list = await leaves.LeaveRequests().Where(l => l.ClassSession.ClassRoomId == classId)
            .OrderByDescending(l => l.CreatedAt)
            .Select(l => new
            {
                l.Id, l.ClassSessionId, Session = l.ClassSession.Title, l.StudentId, Student = l.Student.FullName,
                l.Reason, HasEvidence = l.EvidencePath != null, l.Status, l.CreatedAt, l.ReviewedAt
            })
            .ToListAsync();
        return Ok(list);
    }

    [HttpGet("api/leave-requests/{id:int}/evidence")]
    public async Task<IActionResult> GetEvidence(int id)
    {
        var l = await leaves.LeaveRequests().Include(x => x.ClassSession).FirstOrDefaultAsync(x => x.Id == id);
        if (l is null || l.EvidencePath is null) return NotFound();
        if (l.StudentId != CurrentUserId && await classes.FindManagedAsync(l.ClassSession.ClassRoomId, CurrentUserId, IsAdmin) is null)
            return NotFound();

        return PhysicalFile(files.FullPath(l.EvidencePath), FileStorageService.MimeOf(l.EvidencePath));
    }

    [HttpPut("api/leave-requests/{id:int}/review")]
    public async Task<IActionResult> Review(int id, ReviewLeaveRequest req)
    {
        var l = await leaves.LeaveRequests().Include(x => x.ClassSession).FirstOrDefaultAsync(x => x.Id == id);
        if (l is null) return NotFound();
        if (await classes.FindManagedAsync(l.ClassSession.ClassRoomId, CurrentUserId, IsAdmin) is null) return NotFound();

        l.Status = req.Approve ? LeaveStatus.Approved : LeaveStatus.Rejected;
        l.ReviewedAt = DateTime.UtcNow;
        await leaves.SaveAsync();
        return Ok(new { l.Id, l.Status });
    }
}
