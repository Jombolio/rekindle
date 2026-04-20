namespace Rekindle.Core.Models;

public class ReadingProgress
{
    public string UserId { get; set; } = string.Empty;
    public string MediaId { get; set; } = string.Empty;
    public int CurrentPage { get; set; } = 0;
    public bool IsCompleted { get; set; } = false;
    public DateTime LastReadAt { get; set; } = DateTime.UtcNow;
}
