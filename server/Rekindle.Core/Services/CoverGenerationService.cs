using System.Threading.Channels;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Rekindle.Core.Repositories;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;

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

        using var sourceStream = await archiveService.OpenCoverStreamAsync(job.FilePath);
        if (sourceStream is null)
        {
            logger.LogWarning("No cover image found in {FilePath}", job.FilePath);
            return;
        }

        using var image = await Image.LoadAsync(sourceStream);
        image.Mutate(x => x.Resize(new ResizeOptions
        {
            Size = new Size(300, 450),
            Mode = ResizeMode.Max
        }));

        await image.SaveAsJpegAsync(outputPath);
        await mediaRepository.UpdateCoverAsync(job.MediaId, outputPath);

        logger.LogDebug("Cover generated for {MediaId}", job.MediaId);
    }
}

public record CoverJob(string MediaId, string FilePath, string LibraryId);
