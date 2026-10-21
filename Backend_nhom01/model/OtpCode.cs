namespace vo_hoang_phuc_0118_nhom01.model;

public class OtpCode
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public AppUser User { get; set; } = null!;
    public string Code { get; set; } = "";
    public OtpPurpose Purpose { get; set; }
    public DateTime ExpiresAt { get; set; }
    public int Attempts { get; set; }
    public bool IsUsed { get; set; }
}
