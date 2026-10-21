namespace vo_hoang_phuc_0118_nhom01.model;

public record SessionRequest(string Title, DateTime StartsAt, double Latitude, double Longitude, double RadiusMeters);

// Điểm danh gửi dạng multipart/form-data vì có kèm ảnh.
public class CheckInForm
{
    public string QrToken { get; set; } = "";
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public IFormFile? Photo { get; set; }
}
