using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using vo_hoang_phuc_0118_nhom01.model;
using vo_hoang_phuc_0118_nhom01.Repositories;
using vo_hoang_phuc_0118_nhom01.Services;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

[ApiController]
[Route("api/classes")]
[Authorize]
public class ClassesApiController(
    IClassRepository classes,
    ISessionRepository sessions,
    ILeaveRequestRepository leaves,
    IUserRepository users,
    EmailService email,
    IConfiguration config) : ApiControllerBase
{
    private const string NoAccess = "Không tìm thấy lớp hoặc bạn không có quyền.";

    // Admin xem tất cả, giảng viên xem lớp mình dạy, sinh viên xem lớp đã đăng ký.
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var q = classes.Classes().AsQueryable();
        if (User.IsInRole(nameof(UserRole.GiangVien))) q = q.Where(c => c.TeacherId == CurrentUserId);
        else if (!IsAdmin) q = q.Where(c => c.Enrollments.Any(e => e.StudentId == CurrentUserId));

        var list = await q.OrderBy(c => c.Id)
            .Select(c => new { c.Id, c.Name, c.SubjectId, Subject = c.Subject.Name, c.TeacherId, Teacher = c.Teacher.FullName })
            .ToListAsync();
        return Ok(list);
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetOne(int id)
    {
        var c = await classes.Classes()
            .Where(x => x.Id == id)
            .Select(x => new { x.Id, x.Name, x.SubjectId, Subject = x.Subject.Name, x.TeacherId, Teacher = x.Teacher.FullName })
            .FirstOrDefaultAsync();
        if (c is null) return NotFound();
        if (!IsAdmin && c.TeacherId != CurrentUserId && !await classes.IsEnrolledAsync(id, CurrentUserId))
            return NotFound(NoAccess);
        return Ok(c);
    }

    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Create(ClassRequest req)
    {
        if (!await classes.Subjects().AnyAsync(s => s.Id == req.SubjectId)) return BadRequest("Môn học không tồn tại.");
        if (!await users.Users().AnyAsync(u => u.Id == req.TeacherId && u.Role == UserRole.GiangVien))
            return BadRequest("Giảng viên không hợp lệ.");

        var c = new ClassRoom { Name = req.Name.Trim(), SubjectId = req.SubjectId, TeacherId = req.TeacherId };
        classes.AddClass(c);
        await classes.SaveAsync();
        return Ok(new { c.Id, c.Name, c.SubjectId, c.TeacherId });
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Update(int id, ClassRequest req)
    {
        var c = await classes.Classes().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound();
        if (!await classes.Subjects().AnyAsync(s => s.Id == req.SubjectId)) return BadRequest("Môn học không tồn tại.");
        if (!await users.Users().AnyAsync(u => u.Id == req.TeacherId && u.Role == UserRole.GiangVien))
            return BadRequest("Giảng viên không hợp lệ.");

        c.Name = req.Name.Trim();
        c.SubjectId = req.SubjectId;
        c.TeacherId = req.TeacherId;
        await classes.SaveAsync();
        return Ok(new { c.Id, c.Name, c.SubjectId, c.TeacherId });
    }

    [HttpDelete("{id:int}")]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Delete(int id)
    {
        var c = await classes.Classes().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound();

        classes.RemoveClass(c);
        if (!await classes.SaveAsync()) return Conflict("Không thể xoá: lớp đang có buổi học hoặc sinh viên.");
        return NoContent();
    }

    [HttpGet("{id:int}/students")]
    public async Task<IActionResult> GetStudents(int id)
    {
        if (await classes.FindManagedAsync(id, CurrentUserId, IsAdmin) is null) return NotFound(NoAccess);

        var list = await classes.Enrollments().Where(e => e.ClassRoomId == id)
            .Select(e => new { e.StudentId, e.Student.Username, e.Student.FullName, e.Student.Email })
            .ToListAsync();
        return Ok(list);
    }

    [HttpPost("{id:int}/students")]
    public async Task<IActionResult> Enroll(int id, EnrollRequest req)
    {
        if (await classes.FindManagedAsync(id, CurrentUserId, IsAdmin) is null) return NotFound(NoAccess);
        if (!await users.Users().AnyAsync(u => u.Id == req.StudentId && u.Role == UserRole.SinhVien))
            return BadRequest("Sinh viên không hợp lệ.");

        classes.AddEnrollment(new Enrollment { ClassRoomId = id, StudentId = req.StudentId });
        if (!await classes.SaveAsync()) return Conflict("Sinh viên đã có trong lớp.");
        return Ok(new { message = "Đã thêm sinh viên vào lớp." });
    }

    [HttpDelete("{id:int}/students/{studentId:int}")]
    public async Task<IActionResult> Unenroll(int id, int studentId)
    {
        if (await classes.FindManagedAsync(id, CurrentUserId, IsAdmin) is null) return NotFound(NoAccess);

        var e = await classes.Enrollments().FirstOrDefaultAsync(x => x.ClassRoomId == id && x.StudentId == studentId);
        if (e is null) return NotFound();

        classes.RemoveEnrollment(e);
        await classes.SaveAsync();
        return NoContent();
    }

    // Báo cáo vắng: chỉ tính các buổi đã đóng. Vắng = không điểm danh và không có đơn nghỉ được duyệt.
    [HttpGet("{id:int}/absence-report")]
    public async Task<IActionResult> AbsenceReport(int id)
    {
        if (await classes.FindManagedAsync(id, CurrentUserId, IsAdmin) is null) return NotFound(NoAccess);
        return Ok(await BuildAbsenceReportAsync(id));
    }

    [HttpPost("{id:int}/send-warnings")]
    public async Task<IActionResult> SendWarnings(int id)
    {
        var c = await classes.FindManagedAsync(id, CurrentUserId, IsAdmin);
        if (c is null) return NotFound(NoAccess);

        var subject = await classes.Subjects().FirstOrDefaultAsync(s => s.Id == c.SubjectId);
        var warned = (await BuildAbsenceReportAsync(id)).Where(r => r.IsWarned).ToList();
        foreach (var r in warned)
        {
            await email.SendAsync(
                r.Email,
                $"Cảnh báo vắng học - {c.Name}",
                $"Bạn đã vắng {r.AbsentSessions}/{r.TotalSessions} buổi ({r.AbsentRate:P0}) của lớp {c.Name} ({subject?.Name}). Vui lòng liên hệ giảng viên.");
        }
        return Ok(new { sent = warned.Count });
    }

    private async Task<List<AbsenceRow>> BuildAbsenceReportAsync(int classId)
    {
        var threshold = config.GetValue("Attendance:WarningRate", 0.2);

        var sessionIds = await sessions.Sessions()
            .Where(s => s.ClassRoomId == classId && !s.IsOpen)
            .Select(s => s.Id)
            .ToListAsync();
        var students = await classes.Enrollments().Where(e => e.ClassRoomId == classId)
            .Select(e => new { e.StudentId, e.Student.Username, e.Student.FullName, e.Student.Email })
            .ToListAsync();
        var present = (await sessions.Attendances().Where(a => sessionIds.Contains(a.ClassSessionId))
                .Select(a => new { a.ClassSessionId, a.StudentId })
                .ToListAsync())
            .Select(x => (x.ClassSessionId, x.StudentId))
            .ToHashSet();
        var excused = (await leaves.LeaveRequests()
                .Where(l => sessionIds.Contains(l.ClassSessionId) && l.Status == LeaveStatus.Approved)
                .Select(l => new { l.ClassSessionId, l.StudentId })
                .ToListAsync())
            .Select(x => (x.ClassSessionId, x.StudentId))
            .ToHashSet();

        var total = sessionIds.Count;
        return students.Select(s =>
        {
            var absent = sessionIds.Count(sid => !present.Contains((sid, s.StudentId)) && !excused.Contains((sid, s.StudentId)));
            var rate = total == 0 ? 0 : (double)absent / total;
            return new AbsenceRow(s.StudentId, s.Username, s.FullName, s.Email, total, absent, rate, total > 0 && rate >= threshold);
        }).ToList();
    }
}
