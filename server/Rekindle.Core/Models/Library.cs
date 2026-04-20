namespace Rekindle.Core.Models;

public class Library
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = string.Empty;
    public string RootPath { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
}
