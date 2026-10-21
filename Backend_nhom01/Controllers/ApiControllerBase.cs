using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Controllers;

public abstract class ApiControllerBase : ControllerBase
{
    protected int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    protected bool IsAdmin => User.IsInRole(nameof(UserRole.Admin));
}
