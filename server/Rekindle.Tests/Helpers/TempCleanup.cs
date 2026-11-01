namespace Rekindle.Tests.Helpers;

/// Best-effort removal of test temp files. On Windows, a file can stay locked
/// for a moment after the code that wrote it lets go (antivirus scanning, the
/// search indexer, a SQLite pool closing), so deletes are retried briefly and
/// then given up on. A leftover temp file must never fail a test run.
public static class TempCleanup
{
    private const int Attempts = 10;
    private static readonly TimeSpan Delay = TimeSpan.FromMilliseconds(200);

    public static void DeleteFile(string path) =>
        Retry(path, () => { if (File.Exists(path)) File.Delete(path); });

    public static void DeleteDirectory(string path) =>
        Retry(path, () => { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); });

    private static void Retry(string path, Action delete)
    {
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                delete();
                return;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                if (attempt == Attempts)
                {
                    Console.Error.WriteLine($"Test cleanup left '{path}' behind: {ex.Message}");
                    return;
                }
                Thread.Sleep(Delay);
            }
        }
    }
}
