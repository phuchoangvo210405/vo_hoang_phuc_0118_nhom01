using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using vo_hoang_phuc_0118_nhom01.model;
using vo_hoang_phuc_0118_nhom01.Repositories;
using vo_hoang_phuc_0118_nhom01.Services;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

[ApiController]
[Authorize]
public class SessionsApiController(
    ISessionRepository sessions,
    IClassRepository classes,
    FileStorageService files) : ApiControllerBase
{
    [HttpGet("api/classes/{classId:int}/sessions")]
    public async Task<IActionResult> GetByClass(int classId)
    {
        var c = await classes.FindManagedAsync(classId, CurrentUserId, IsAdmin);
        if (c is null && !await classes.IsEnrolledAsync(classId, CurrentUserId)) return NotFound();

        // Chỉ giảng viên/admin mới nhận được mã QR.
        var owner = c is not null;
        var list = await sessions.Sessions().Where(s => s.ClassRoomId == classId)
            .OrderByDescending(s => s.StartsAt)
            .ToListAsync();
        return Ok(list.Select(s => new
        {
            s.Id, s.Title, s.StartsAt, s.Latitude, s.Longitude, s.RadiusMeters, s.IsOpen,
            QrToken = owner ? s.QrToken : null
        }));
    }

    [HttpPost("api/classes/{classId:int}/sessions")]
    public async Task<IActionResult> Create(int classId, SessionRequest req)
    {
        if (await classes.FindManagedAsync(classId, CurrentUserId, IsAdmin) is null)
            return NotFound("Không tìm thấy lớp hoặc bạn không có quyền.");
        if (req.RadiusMeters <= 0) return BadRequest("Bán kính phải lớn hơn 0.");

        var s = new ClassSession
        {
            ClassRoomId = classId,
            Title = req.Title.Trim(),
            StartsAt = req.StartsAt,
            Latitude = req.Latitude,
            Longitude = req.Longitude,
            RadiusMeters = req.RadiusMeters,
            QrToken = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)),
            IsOpen = true
        };
        sessions.AddSession(s);
        await sessions.SaveAsync();
        return Ok(new { s.Id, s.Title, s.QrToken, s.IsOpen });
    }

    [HttpPut("api/sessions/{id:int}")]
    public async Task<IActionResult> Update(int id, SessionRequest req)
    {
        var s = await FindManagedSessionAsync(id);
        if (s is null) return NotFound();
        if (req.RadiusMeters <= 0) return BadRequest("Bán kính phải lớn hơn 0.");

        s.Title = req.Title.Trim();
        s.StartsAt = req.StartsAt;
        s.Latitude = req.Latitude;
        s.Longitude = req.Longitude;
        s.RadiusMeters = req.RadiusMeters;
        await sessions.SaveAsync();
        return Ok(new { s.Id, s.Title, s.StartsAt, s.Latitude, s.Longitude, s.RadiusMeters, s.IsOpen });
    }

    [HttpDelete("api/sessions/{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var s = await FindManagedSessionAsync(id);
        if (s is null) return NotFound();

        sessions.RemoveSession(s);
        if (!await sessions.SaveAsync()) return Conflict("Không thể xoá: buổi học đã có dữ liệu điểm danh hoặc đơn nghỉ.");
        return NoContent();
    }

    [HttpPost("api/sessions/{id:int}/close")]
    public async Task<IActionResult> Close(int id)
    {
        var s = await FindManagedSessionAsync(id);
        if (s is null) return NotFound();

        s.IsOpen = false;
        await sessions.SaveAsync();
        return Ok(new { message = "Đã đóng điểm danh." });
    }

    // Sinh viên quét QR (gửi kèm mã QR), kiểm tra đăng ký lớp, khoảng cách GPS và ảnh chụp.
    [HttpPost("api/sessions/{id:int}/check-in")]
    [Authorize(Roles = nameof(UserRole.SinhVien))]
    public async Task<IActionResult> CheckIn(int id, [FromForm] CheckInForm form)
    {
        var s = await sessions.Sessions().FirstOrDefaultAsync(x => x.Id == id);
        if (s is null) return NotFound();
        if (!s.IsOpen) return BadRequest("Buổi học đã đóng điểm danh.");
        if (!string.Equals(form.QrToken, s.QrToken, StringComparison.Ordinal))
            return BadRequest("Mã QR không hợp lệ.");
        if (!await classes.IsEnrolledAsync(s.ClassRoomId, CurrentUserId)) return Forbid();
        if (await sessions.Attendances().AnyAsync(a => a.ClassSessionId == id && a.StudentId == CurrentUserId))
            return Conflict("Bạn đã điểm danh buổi này.");

        var distance = GeoHelper.DistanceMeters(s.Latitude, s.Longitude, form.Latitude, form.Longitude);
        if (distance > s.RadiusMeters)
            return BadRequest(new { message = "Bạn đang ở ngoài phạm vi lớp học.", distanceMeters = Math.Round(distance) });

        string? photoPath = null;
        if (form.Photo is { Length: > 0 })
        {
            try
            {
                photoPath = await files.SaveAsync(form.Photo, "attendance");
            }
            catch (InvalidOperationException ex)
            {
                return BadRequest(ex.Message);
            }
        }

        sessions.AddAttendance(new Attendance
        {
            ClassSessionId = id,
            StudentId = CurrentUserId,
            CheckedInAt = DateTime.UtcNow,
            Latitude = form.Latitude,
            Longitude = form.Longitude,
            DistanceMeters = distance,
            PhotoPath = photoPath
        });
        if (!await sessions.SaveAsync()) return Conflict("Bạn đã điểm danh buổi này.");
        return Ok(new { message = "Điểm danh thành công.", distanceMeters = Math.Round(distance) });
    }

    [HttpGet("api/sessions/{id:int}/attendances")]
    public async Task<IActionResult> GetAttendances(int id)
    {
        if (await FindManagedSessionAsync(id) is null) return NotFound();

        var list = await sessions.Attendances().Where(a => a.ClassSessionId == id)
            .OrderBy(a => a.CheckedInAt)
            .Select(a => new
            {
                a.Id, a.StudentId, a.Student.Username, a.Student.FullName,
                a.CheckedInAt, a.DistanceMeters, HasPhoto = a.PhotoPath != null
            })
            .ToListAsync();
        return Ok(list);
    }

    [HttpGet("api/attendances/{id:int}/photo")]
    public async Task<IActionResult> GetPhoto(int id)
    {
        var a = await sessions.Attendances().Include(x => x.ClassSession).FirstOrDefaultAsync(x => x.Id == id);
        if (a is null || a.PhotoPath is null) return NotFound();
        if (a.StudentId != CurrentUserId && await classes.FindManagedAsync(a.ClassSession.ClassRoomId, CurrentUserId, IsAdmin) is null)
            return NotFound();

        return PhysicalFile(files.FullPath(a.PhotoPath), FileStorageService.MimeOf(a.PhotoPath));
    }

    // Trả về buổi học nếu người dùng là admin hoặc giảng viên của lớp chứa buổi học đó.
    private async Task<ClassSession?> FindManagedSessionAsync(int id)
    {
        var s = await sessions.Sessions().FirstOrDefaultAsync(x => x.Id == id);
        return s is not null && await classes.FindManagedAsync(s.ClassRoomId, CurrentUserId, IsAdmin) is not null ? s : null;
    }
}
