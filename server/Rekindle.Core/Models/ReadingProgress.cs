namespace Rekindle.Core.Models;

public class ReadingProgress
{
    public string UserId { get; set; } = string.Empty;
    public string MediaId { get; set; } = string.Empty;
    public int CurrentPage { get; set; } = 0;
    public bool IsCompleted { get; set; } = false;
    /// How far through the current chapter the reader is, 0 to 1. Text books
    /// only: null for comics, and for writes from clients that predate it.
    public double? PositionFraction { get; set; }
    public DateTime LastReadAt { get; set; } = DateTime.UtcNow;
}
