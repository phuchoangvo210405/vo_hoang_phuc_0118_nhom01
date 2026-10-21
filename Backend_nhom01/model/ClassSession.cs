namespace vo_hoang_phuc_0118_nhom01.model;

public class ClassSession
{
    public int Id { get; set; }
    public int ClassRoomId { get; set; }
    public ClassRoom ClassRoom { get; set; } = null!;
    public string Title { get; set; } = "";
    public DateTime StartsAt { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double RadiusMeters { get; set; }
    public string QrToken { get; set; } = "";
    public bool IsOpen { get; set; } = true;
}
