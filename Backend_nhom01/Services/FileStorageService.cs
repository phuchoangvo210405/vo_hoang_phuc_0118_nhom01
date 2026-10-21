using Microsoft.AspNetCore.StaticFiles;

namespace vo_hoang_phuc_0118_nhom01.Services;

public class FileStorageService(IWebHostEnvironment env)
{
    private static readonly string[] AllowedExtensions = [".jpg", ".jpeg", ".png", ".webp", ".pdf"];
    private const long MaxBytes = 5 * 1024 * 1024;

    private string RootPath => Path.Combine(env.ContentRootPath, "Uploads");

    // Lưu file vào thư mục con, trả về đường dẫn tương đối để ghi vào DB.
    public async Task<string> SaveAsync(IFormFile file, string folder)
    {
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!AllowedExtensions.Contains(ext))
            throw new InvalidOperationException("Chỉ chấp nhận file JPG, PNG, WEBP hoặc PDF.");
        if (file.Length > MaxBytes)
            throw new InvalidOperationException("File tối đa 5 MB.");

        var dir = Path.Combine(RootPath, folder);
        Directory.CreateDirectory(dir);
        var name = $"{Guid.NewGuid():N}{ext}";

        await using var stream = File.Create(Path.Combine(dir, name));
        await file.CopyToAsync(stream);
        return $"{folder}/{name}";
    }

    public string FullPath(string relativePath) => Path.Combine(RootPath, relativePath);

    public static string MimeOf(string path) =>
        new FileExtensionContentTypeProvider().TryGetContentType(path, out var mime) ? mime : "application/octet-stream";
}
