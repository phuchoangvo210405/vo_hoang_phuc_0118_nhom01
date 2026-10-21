namespace vo_hoang_phuc_0118_nhom01.model;

public record RegisterRequest(string Username, string Email, string Password, string FullName, UserRole Role);

public record UserUpdateRequest(string Email, string FullName, UserRole Role, bool IsActive);
