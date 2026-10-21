namespace vo_hoang_phuc_0118_nhom01.model;

public class LeaveRequest
{
    public int Id { get; set; }
    public int ClassSessionId { get; set; }
    public ClassSession ClassSession { get; set; } = null!;
    public int StudentId { get; set; }
    public AppUser Student { get; set; } = null!;
    public string Reason { get; set; } = "";
    public string? EvidencePath { get; set; }
    public LeaveStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ReviewedAt { get; set; }
}
