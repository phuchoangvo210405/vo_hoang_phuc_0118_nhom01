namespace vo_hoang_phuc_0118_nhom01.model;

public record SubjectRequest(string Code, string Name);

public record ClassRequest(string Name, int SubjectId, int TeacherId);

public record EnrollRequest(int StudentId);

// Một dòng trong báo cáo vắng của lớp.
public record AbsenceRow(
    int StudentId,
    string Username,
    string FullName,
    string Email,
    int TotalSessions,
    int AbsentSessions,
    double AbsentRate,
    bool IsWarned);
