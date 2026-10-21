using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public interface IUserRepository
{
    IQueryable<AppUser> Users();
    IQueryable<OtpCode> OtpCodes();
    void Add(AppUser user);
    void Remove(AppUser user);
    void AddOtp(OtpCode otp);
    Task<bool> SaveAsync();
}
