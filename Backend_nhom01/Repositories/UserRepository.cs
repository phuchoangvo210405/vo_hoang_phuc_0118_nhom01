using vo_hoang_phuc_0118_nhom01.model;

namespace vo_hoang_phuc_0118_nhom01.Repositories;

public class UserRepository(ApplicationDbContext db) : IUserRepository
{
    public IQueryable<AppUser> Users() => db.Users;
    public IQueryable<OtpCode> OtpCodes() => db.OtpCodes;

    public void Add(AppUser user) => db.Users.Add(user);
    public void Remove(AppUser user) => db.Users.Remove(user);
    public void AddOtp(OtpCode otp) => db.OtpCodes.Add(otp);

    public Task<bool> SaveAsync() => db.TrySaveAsync();
}
