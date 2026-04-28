using System.Collections.Concurrent;

namespace Rekindle.Core.Services;

/// <summary>
/// Per-library scan progress snapshot. All counters are updated with Interlocked
/// so reads from a polling endpoint are always consistent without locking.
/// </summary>
public sealed class ScanProgress
{
    private int _filesProcessed;
    private int _added;
    private int _removed;
    private int _folders;
    private int _coversQueued;
    private int _coversGenerated;

    public string    LibraryId       { get; init;         } = string.Empty;
    public string    Phase           { get; private set;  } = "idle";
    public int       FilesTotal      { get; private set;  }
    public int       FilesProcessed  => _filesProcessed;
    public int       Added           => _added;
    public int       Removed         => _removed;
    public int       Folders         => _folders;
    public int       CoversQueued    => _coversQueued;
    public int       CoversGenerated => _coversGenerated;
    public DateTime? StartedAt       { get; private set;  }
    public DateTime? CompletedAt     { get; private set;  }

    internal void Begin(int filesTotal)
    {
        Phase            = "scanning";
        FilesTotal       = filesTotal;
        _filesProcessed  = 0;
        _added           = 0;
        _removed         = 0;
        _folders         = 0;
        _coversQueued    = 0;
        _coversGenerated = 0;
        StartedAt        = DateTime.UtcNow;
        CompletedAt      = null;
    }

    internal void Complete()
    {
        Phase       = "complete";
        CompletedAt = DateTime.UtcNow;
    }

    public void RecordProcessed()      => Interlocked.Increment(ref _filesProcessed);
    public void RecordAdded()          => Interlocked.Increment(ref _added);
    public void RecordRemoved()        => Interlocked.Increment(ref _removed);
    public void RecordFolder()         => Interlocked.Increment(ref _folders);
    public void RecordCoverQueued()    => Interlocked.Increment(ref _coversQueued);
    public void RecordCoverGenerated() => Interlocked.Increment(ref _coversGenerated);
}

/// <summary>
/// Singleton holding the most-recent <see cref="ScanProgress"/> for each library.
/// The previous entry is replaced whenever a new scan starts.
/// </summary>
public sealed class ScanProgressTracker
{
    private readonly ConcurrentDictionary<string, ScanProgress> _state = new();

    public ScanProgress Begin(string libraryId, int filesTotal)
    {
        var p = new ScanProgress { LibraryId = libraryId };
        p.Begin(filesTotal);
        _state[libraryId] = p;
        return p;
    }

    public ScanProgress? Get(string libraryId)
        => _state.TryGetValue(libraryId, out var p) ? p : null;
}
