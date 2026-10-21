namespace vo_hoang_phuc_0118_nhom01.model;

public class ClassRoom
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public int SubjectId { get; set; }
    public Subject Subject { get; set; } = null!;
    public int TeacherId { get; set; }
    public AppUser Teacher { get; set; } = null!;
    public List<Enrollment> Enrollments { get; set; } = [];
}
