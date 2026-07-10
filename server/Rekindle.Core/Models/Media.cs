using System.Text.Json.Serialization;

namespace Rekindle.Core.Models;

public class Media
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string LibraryId { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Series { get; set; }
    public int? Volume { get; set; }

    // Absolute server filesystem paths — internal only. [JsonIgnore] keeps the
    // server's directory layout out of API responses that any read user can see.
    [JsonIgnore] public string FilePath { get; set; } = string.Empty;

    public string Format { get; set; } = string.Empty;
    public int? PageCount { get; set; }

    [JsonIgnore] public string? CoverCachePath { get; set; }

    public string MediaType { get; set; } = "archive"; // "archive" | "folder"
    public string RelativePath { get; set; } = string.Empty;
    public string? ParentId { get; set; }
    public DateTime AddedAt { get; set; } = DateTime.UtcNow;
}
