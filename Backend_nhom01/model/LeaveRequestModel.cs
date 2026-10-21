namespace vo_hoang_phuc_0118_nhom01.model;

public record ReviewLeaveRequest(bool Approve);

// Đơn nghỉ gửi dạng multipart/form-data vì có kèm minh chứng.
public class LeaveForm
{
    public int SessionId { get; set; }
    public string Reason { get; set; } = "";
    public IFormFile? Evidence { get; set; }
}
