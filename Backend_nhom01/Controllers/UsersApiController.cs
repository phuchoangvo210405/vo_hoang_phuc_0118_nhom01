using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using vo_hoang_phuc_0118_nhom01.model;
using vo_hoang_phuc_0118_nhom01.Repositories;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

[ApiController]
[Route("api/users")]
[Authorize(Roles = nameof(UserRole.Admin))]
public class UsersApiController(IUserRepository users, PasswordHasher<AppUser> hasher) : ApiControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var list = await users.Users().OrderBy(u => u.Id).ToListAsync();
        return Ok(list.Select(ToDto));
    }

    [HttpGet("{id:int}")]
    public async Task<IActionResult> GetOne(int id)
    {
        var u = await users.Users().FirstOrDefaultAsync(x => x.Id == id);
        return u is null ? NotFound() : Ok(ToDto(u));
    }

    [HttpPost]
    public async Task<IActionResult> Create(RegisterRequest req)
    {
        if (req.Password.Length < 6) return BadRequest("Mật khẩu tối thiểu 6 ký tự.");
        if (await users.Users().AnyAsync(u => u.Username == req.Username || u.Email == req.Email))
            return Conflict("Tên đăng nhập hoặc email đã tồn tại.");

        var u = new AppUser
        {
            Username = req.Username.Trim(),
            Email = req.Email.Trim(),
            FullName = req.FullName.Trim(),
            Role = req.Role,
            IsActive = true
        };
        u.PasswordHash = hasher.HashPassword(u, req.Password);
        users.Add(u);
        await users.SaveAsync();
        return Ok(ToDto(u));
    }

    [HttpPut("{id:int}")]
    public async Task<IActionResult> Update(int id, UserUpdateRequest req)
    {
        var u = await users.Users().FirstOrDefaultAsync(x => x.Id == id);
        if (u is null) return NotFound();

        u.Email = req.Email.Trim();
        u.FullName = req.FullName.Trim();
        u.Role = req.Role;
        u.IsActive = req.IsActive;
        if (!await users.SaveAsync()) return Conflict("Email đã được dùng bởi tài khoản khác.");
        return Ok(ToDto(u));
    }

    [HttpDelete("{id:int}")]
    public async Task<IActionResult> Delete(int id)
    {
        var u = await users.Users().FirstOrDefaultAsync(x => x.Id == id);
        if (u is null) return NotFound();

        users.Remove(u);
        if (!await users.SaveAsync()) return Conflict("Không thể xoá: tài khoản đang có dữ liệu liên quan.");
        return NoContent();
    }

    private static object ToDto(AppUser u) => new { u.Id, u.Username, u.Email, u.FullName, u.Role, u.IsActive };
}
