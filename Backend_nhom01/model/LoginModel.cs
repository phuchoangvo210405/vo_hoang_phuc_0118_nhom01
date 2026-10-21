namespace vo_hoang_phuc_0118_nhom01.model;

public record LoginRequest(string Username, string Password);

public record VerifyOtpRequest(string Username, string Code);
