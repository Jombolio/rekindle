using System.Threading.Channels;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Rekindle.Core.Repositories;
using Rekindle.Core.Utilities;

namespace Rekindle.Core.Services;

public sealed class CoverGenerationService(
    Channel<CoverJob> queue,
    ArchiveService archiveService,
    MediaRepository mediaRepository,
    ScanProgressTracker progressTracker,
    IOptions<RekindleOptions> options,
    ILogger<CoverGenerationService> logger) : BackgroundService
{
    private readonly string _coversDir = Path.Combine(options.Value.CachePath, "covers");

    // Max source-image pixel count before decoding a cover (~100 MP ≈ 400 MB
    // decoded). A real cover is a few megapixels; anything larger is a bomb.
    private const long MaxCoverPixels = 100_000_000;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        Directory.CreateDirectory(_coversDir);

        await foreach (var job in queue.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await GenerateCoverAsync(job);
                progressTracker.Get(job.LibraryId)?.RecordCoverGenerated();
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Cover generation failed for media {MediaId}", job.MediaId);
                // Still count as processed so the counter doesn't stall at the last item.
                progressTracker.Get(job.LibraryId)?.RecordCoverGenerated();
            }
        }
    }

    private async Task GenerateCoverAsync(CoverJob job)
    {
        var outputPath = Path.Combine(_coversDir, $"{job.MediaId}.jpg");

        if (File.Exists(outputPath))
            return;

        byte[] source;
        await using (var sourceStream = await archiveService.OpenCoverStreamAsync(job.FilePath))
        {
            if (sourceStream is null)
            {
                logger.LogWarning("No cover image found in {FilePath}", job.FilePath);
                return;
            }

            using var buffer = new MemoryStream();
            await sourceStream.CopyToAsync(buffer);
            source = buffer.ToArray();
        }

        // Guard against an image decompression bomb (a tiny file declaring huge
        // dimensions): inspect the header first and skip anything that would
        // allocate gigabytes on full decode.
        var size = ImageCodec.TryGetSize(source);
        if (size is null)
        {
            logger.LogWarning("Cover image for {MediaId} is not a supported image format", job.MediaId);
            return;
        }
        if ((long)size.Value.Width * size.Value.Height > MaxCoverPixels)
        {
            logger.LogWarning(
                "Cover for {MediaId} is {Width}x{Height}, exceeding the {Max}px limit — skipped",
                job.MediaId, size.Value.Width, size.Value.Height, MaxCoverPixels);
            return;
        }

        var thumbnail = ImageCodec.CreateJpegThumbnail(source, maxWidth: 300, maxHeight: 450);
        await File.WriteAllBytesAsync(outputPath, thumbnail);
        await mediaRepository.UpdateCoverAsync(job.MediaId, outputPath);

        logger.LogDebug("Cover generated for {MediaId}", job.MediaId);
    }
}

public record CoverJob(string MediaId, string FilePath, string LibraryId);
