using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using vo_hoang_phuc_0118_nhom01.model;
using vo_hoang_phuc_0118_nhom01.Repositories;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

[ApiController]
[Route("api/subjects")]
[Authorize]
public class SubjectsApiController(IClassRepository classes) : ApiControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll() => Ok(await classes.Subjects().OrderBy(s => s.Id).ToListAsync());

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetOne(int id)
    {
        var s = await classes.Subjects().FirstOrDefaultAsync(x => x.Id == id);
        return s is null ? NotFound() : Ok(s);
    }

    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Create(SubjectRequest req)
    {
        var s = new Subject { Code = req.Code.Trim(), Name = req.Name.Trim() };
        classes.AddSubject(s);
        if (!await classes.SaveAsync()) return Conflict("Mã môn học đã tồn tại.");
        return Ok(s);
    }

    [HttpPut("{id:int}")]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Update(int id, SubjectRequest req)
    {
        var s = await classes.Subjects().FirstOrDefaultAsync(x => x.Id == id);
        if (s is null) return NotFound();

        s.Code = req.Code.Trim();
        s.Name = req.Name.Trim();
        if (!await classes.SaveAsync()) return Conflict("Mã môn học đã tồn tại.");
        return Ok(s);
    }

    [HttpDelete("{id:int}")]
    [Authorize(Roles = nameof(UserRole.Admin))]
    public async Task<IActionResult> Delete(int id)
    {
        var s = await classes.Subjects().FirstOrDefaultAsync(x => x.Id == id);
        if (s is null) return NotFound();

        classes.RemoveSubject(s);
        if (!await classes.SaveAsync()) return Conflict("Không thể xoá: môn học đang có lớp.");
        return NoContent();
    }
}
