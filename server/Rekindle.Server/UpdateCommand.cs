using System.Reflection;
using Rekindle.Core.Update;

namespace Rekindle.Server;

/// <summary>
/// The server's self-update commands. Each runs instead of the server and exits:
/// <list type="bullet">
/// <item><c>--check-update</c>: report the newest stable release and pre-release;</item>
/// <item><c>--update</c>: install the newest stable release if it is newer;</item>
/// <item><c>--dev-update</c>: the same, including pre-releases.</item>
/// </list>
/// Releases come from the Gitea repository in <c>Rekindle:UpdateSource</c>.
/// Only files shipped in the release zip are replaced; appsettings*.json and
/// the data and cache directories are left as they are.
/// </summary>
internal static class UpdateCommand
{
    public const string DefaultSource = "https://git.jombo.uk/Jombo/rekindle";

    private const string Check = "--check-update";
    private const string Stable = "--update";
    private const string Dev = "--dev-update";

    /// Returns the update flag given, if any, and the remaining arguments for
    /// the host. The flags must not reach ASP.NET's command-line configuration,
    /// which would read "--update" as a setting and swallow the next argument.
    public static string? Extract(string[] args, out string[] hostArgs)
    {
        string? command = null;
        var rest = new List<string>();
        foreach (var arg in args)
        {
            if (arg is Check or Stable or Dev)
            {
                if (command is not null && command != arg)
                    throw new ArgumentException($"Use only one of {Check}, {Stable} and {Dev}.");
                command = arg;
            }
            else
            {
                rest.Add(arg);
            }
        }
        hostArgs = [.. rest];
        return command;
    }

    public static async Task<int> RunAsync(string command, string[] hostArgs)
    {
        // Read the settings from the install directory, not the current one: the
        // server is usually started from there (systemd WorkingDirectory, the
        // Windows service), but the update may be run from anywhere.
        var installDir = AppContext.BaseDirectory;
        var config = new ConfigurationBuilder()
            .SetBasePath(installDir)
            .AddJsonFile("appsettings.json", optional: true)
            .AddEnvironmentVariables()
            .AddCommandLine(hostArgs)
            .Build();

        var current = CurrentVersion();
        var assetName = ServerUpdater.PlatformAssetName();
        if (assetName is null)
        {
            Console.Error.WriteLine("No server build is published for this platform; update manually.");
            return 1;
        }

        var sourceText = config["Rekindle:UpdateSource"] is { Length: > 0 } s ? s : DefaultSource;
        if (!Uri.TryCreate(sourceText, UriKind.Absolute, out var source))
        {
            Console.Error.WriteLine($"Rekindle:UpdateSource '{sourceText}' is not a valid URL.");
            return 1;
        }

        using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };
        http.DefaultRequestHeaders.UserAgent.ParseAdd($"Rekindle-Server/{current}");
        var updater = new ServerUpdater(http, source, current, assetName);

        try
        {
            if (command == Check) return await ReportAsync(updater, current);

            var includePre = command == Dev;
            var check = await updater.CheckAsync(includePre);
            if (!check.IsNewer)
            {
                var channel = includePre ? "including pre-releases" : "stable";
                Console.WriteLine($"Rekindle Server {current} is up to date ({channel}, from {source}).");
                return 0;
            }

            var release = check.Latest!;
            Console.WriteLine($"Updating Rekindle Server {current} → {release.Version} ({release.TagName})");

            var result = await updater.InstallAsync(
                release, installDir, ProtectedDirectories(config, installDir), new ConsoleProgress(assetName));

            Console.WriteLine();
            Console.WriteLine($"Installed {release.Version}: {result.Replaced.Count} file(s) replaced, {result.Added.Count} added.");
            foreach (var kept in result.KeptExisting)
                Console.WriteLine($"  Kept your existing {kept}.");
            if (result.PendingCleanup.Count > 0)
                Console.WriteLine("  Old files still in use will be removed on the next start.");
            Console.WriteLine("Restart Rekindle Server to run the new version.");
            return 0;
        }
        catch (Exception e) when (e is HttpRequestException or InvalidOperationException
                                      or InvalidDataException or IOException or UnauthorizedAccessException
                                      or TaskCanceledException or System.Text.Json.JsonException)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine($"Update failed: {e.Message}");
            Console.Error.WriteLine("Nothing was changed unless stated above.");
            return 1;
        }
    }

    private static async Task<int> ReportAsync(ServerUpdater updater, SemVersion current)
    {
        var stable = await updater.CheckAsync(includePreReleases: false);
        var any = await updater.CheckAsync(includePreReleases: true);

        Console.WriteLine($"Rekindle Server {current}, updates from {updater.RepositoryUrl}");
        Console.WriteLine($"  Newest release:     {Describe(stable)}");
        Console.WriteLine($"  Newest pre-release: {(any.Latest?.Version?.IsPreRelease == true ? Describe(any) : "none newer than the release")}");
        if (stable.IsNewer) Console.WriteLine($"Run with {Stable} to install it.");
        else if (any.IsNewer) Console.WriteLine($"Run with {Dev} to install the pre-release.");
        return 0;
    }

    private static string Describe(UpdateCheck check) => check.Latest is null
        ? "none published"
        : $"{check.Latest.Version}{(check.IsNewer ? " (newer)" : "")}";

    /// The data and cache directories, with the server's defaults. Relative
    /// paths are resolved against the install directory, where the server runs.
    private static IEnumerable<string> ProtectedDirectories(IConfiguration config, string installDir)
    {
        yield return Path.GetFullPath(config["Rekindle:DataPath"] ?? "/config", installDir);
        yield return Path.GetFullPath(config["Rekindle:CachePath"] ?? "/cache", installDir);
    }

    public static SemVersion CurrentVersion()
    {
        var info = Assembly.GetEntryAssembly()?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
        return SemVersion.TryParse(info) ?? new SemVersion(0, 0, 0, null);
    }

    /// Prints download progress in 10% steps.
    private sealed class ConsoleProgress(string name) : IProgress<(long Received, long? Total)>
    {
        private int _lastTenth = -1;

        public void Report((long Received, long? Total) value)
        {
            if (value.Total is not > 0) return;
            var tenth = (int)(value.Received * 10 / value.Total.Value);
            if (tenth == _lastTenth) return;
            _lastTenth = tenth;
            Console.Write($"\rDownloading {name}: {tenth * 10}%");
        }
    }
}
