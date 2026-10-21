using System.Net;
using System.Net.Mail;

namespace vo_hoang_phuc_0118_nhom01.Services;

public class EmailService(IConfiguration config, ILogger<EmailService> logger)
{
    public async Task SendAsync(string to, string subject, string body)
    {
        var host = config["Smtp:Host"];

        // Chưa cấu hình SMTP thì ghi nội dung ra log để test (ví dụ mã OTP).
        if (string.IsNullOrWhiteSpace(host))
        {
            logger.LogWarning("SMTP chưa cấu hình. Gửi tới {To} | {Subject} | {Body}", to, subject, body);
            return;
        }

        using var client = new SmtpClient(host, int.Parse(config["Smtp:Port"] ?? "587"))
        {
            EnableSsl = true,
            Credentials = new NetworkCredential(config["Smtp:User"], config["Smtp:Password"])
        };
        using var message = new MailMessage(config["Smtp:From"]!, to, subject, body);
        await client.SendMailAsync(message);
    }
}
