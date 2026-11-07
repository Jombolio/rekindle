using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Rekindle.Server.Landing;
using Xunit;

namespace Rekindle.Tests.Unit;

public class ContactLinksTests
{
    [Theory]
    [InlineData("https://discord.gg/abc123", "https://discord.gg/abc123", "discord.gg/abc123")]
    [InlineData("http://example.com", "http://example.com/", "example.com")]
    [InlineData("https://www.example.com/me/", "https://www.example.com/me/", "example.com/me")]
    [InlineData("https://matrix.to/#/@me:example.org", "https://matrix.to/#/@me:example.org", "matrix.to/#/@me:example.org")]
    [InlineData("  https://mastodon.social/@me  ", "https://mastodon.social/@me", "mastodon.social/@me")]
    public void WebLinks_AreAccepted(string url, string href, string detail)
    {
        ContactLinks.TryCreate("Name", url, out var link).Should().BeTrue();
        link.Href.Should().Be(href);
        link.Detail.Should().Be(detail);
        link.IsEmail.Should().BeFalse();
    }

    [Theory]
    [InlineData("mailto:admin@example.com")]
    [InlineData("admin@example.com")]
    [InlineData("mailto:admin@example.com?subject=Rekindle")]
    public void EmailAddresses_AreAccepted(string url)
    {
        ContactLinks.TryCreate(null, url, out var link).Should().BeTrue();
        link.Href.Should().StartWith("mailto:admin@example.com");
        link.Detail.Should().Be("admin@example.com");
        link.Name.Should().Be("Email");
        link.IsEmail.Should().BeTrue();
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("javascript:alert(1)")]
    [InlineData("JavaScript:alert(1)")]
    [InlineData("data:text/html,<script>alert(1)</script>")]
    [InlineData("vbscript:msgbox(1)")]
    [InlineData("file:///etc/passwd")]
    [InlineData("ftp://example.com")]
    [InlineData("matrix:u/me:example.org")]
    [InlineData("/relative/path")]
    [InlineData("example.com")]
    [InlineData("https://")]
    [InlineData("https://user:pass@example.com")]
    [InlineData("https://exa mple.com")]
    [InlineData("https://example.com/\nx")]
    [InlineData("mailto:")]
    [InlineData("mailto:nobody")]
    [InlineData("@example.com")]
    public void EverythingElse_IsRefused(string? url)
    {
        ContactLinks.TryCreate("Name", url, out _).Should().BeFalse();
    }

    [Fact]
    public void MissingName_FallsBackToTheHost()
    {
        ContactLinks.TryCreate("  ", "https://www.example.com/contact", out var link).Should().BeTrue();
        link.Name.Should().Be("example.com");
    }

    [Fact]
    public void LongNames_AreShortened()
    {
        ContactLinks.TryCreate(new string('a', 200), "https://example.com", out var link).Should().BeTrue();
        link.Name.Length.Should().BeLessThanOrEqualTo(60);
    }

    [Fact]
    public void FromOptions_KeepsOrder_AndReportsRejects()
    {
        var rejected = new List<string>();
        var links = ContactLinks.FromOptions(
        [
            new() { Name = "Discord", Url = "https://discord.gg/abc" },
            new() { Name = "Bad", Url = "javascript:alert(1)" },
            new() { Name = "Email", Url = "me@example.com" },
            new() { Name = "Nothing" },
        ], rejected);

        links.Select(l => l.Name).Should().Equal("Discord", "Email");
        rejected.Should().Equal("javascript:alert(1)", "(no Url)");
    }

    [Fact]
    public void Render_EscapesAdminSuppliedText()
    {
        ContactLinks.TryCreate("<script>alert('x')</script>",
            "https://example.com/?a=\"><img/src=x/onerror=alert(1)>", out var link).Should().BeTrue();

        var html = LandingPage.Render("http://localhost:8080", [link], "nonce");

        html.Should().NotContain("<script>alert");
        html.Should().NotContain("<img/src=x");
        html.Should().Contain("&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;");
        // The URL itself comes out percent-encoded, so it can't break out of the href.
        html.Should().Contain("href=\"https://example.com/?a=%22%3E%3Cimg/src=x/onerror=alert(1)%3E\"");
    }

    [Fact]
    public void Render_EscapesTheAddress()
    {
        var html = LandingPage.Render("http://evil\"><script>x()</script>", [], "nonce");
        html.Should().NotContain("<script>x()");
        html.Should().Contain("http://evil&quot;&gt;&lt;script&gt;");
    }

    [Fact]
    public void Render_HidesTheContactSection_WhenThereAreNoContacts()
    {
        LandingPage.Render("http://localhost:8080", [], "nonce")
            .Should().NotContain("Contact the administrator");
    }

    [Fact]
    public void Render_ShowsEachContact()
    {
        ContactLinks.TryCreate("Discord", "https://discord.gg/abc", out var discord);
        ContactLinks.TryCreate(null, "admin@example.com", out var email);

        var html = LandingPage.Render("http://localhost:8080", [discord, email], "nonce");

        html.Should().Contain("Contact the administrator");
        html.Should().Contain("<a href=\"https://discord.gg/abc\" rel=\"me noopener noreferrer\">");
        html.Should().Contain("<a href=\"mailto:admin@example.com\">");
        html.Should().Contain("<strong>Discord</strong>");
    }

    [Fact]
    public void Contacts_FollowChangesToTheSettings()
    {
        var monitor = new TestMonitor(new LandingOptions
        {
            Contacts = [new() { Name = "Site", Url = "https://example.com" }],
        });
        var page = new LandingPage(monitor, NullLogger<LandingPage>.Instance);

        page.Contacts.Select(c => c.Name).Should().Equal("Site");

        monitor.CurrentValue = new LandingOptions();
        page.Contacts.Should().BeEmpty();
    }

    [Theory]
    [InlineData(null, LandingTheme.System)]
    [InlineData("", LandingTheme.System)]
    [InlineData("System", LandingTheme.System)]
    [InlineData("light", LandingTheme.Light)]
    [InlineData(" Dark ", LandingTheme.Dark)]
    [InlineData("DARK", LandingTheme.Dark)]
    public void Theme_Parses(string? value, LandingTheme expected)
    {
        LandingPage.TryParseTheme(value, out var theme).Should().BeTrue();
        theme.Should().Be(expected);
    }

    [Theory]
    [InlineData("2")]
    [InlineData("midnight")]
    [InlineData("dark mode")]
    public void UnknownTheme_FallsBackToSystem(string value)
    {
        LandingPage.TryParseTheme(value, out var theme).Should().BeFalse();
        theme.Should().Be(LandingTheme.System);
    }

    [Fact]
    public void Render_FollowsTheVisitor_ByDefault()
    {
        var html = LandingPage.Render("http://localhost:8080", [], "nonce");
        html.Should().Contain("<html lang=\"en\">");
        html.Should().Contain("<meta name=\"color-scheme\" content=\"light dark\">");
    }

    [Theory]
    [InlineData(LandingTheme.Dark, "dark")]
    [InlineData(LandingTheme.Light, "light")]
    public void Render_FixesTheTheme_WhenSet(LandingTheme theme, string name)
    {
        var html = LandingPage.Render("http://localhost:8080", [], "nonce", theme);
        html.Should().Contain($"<html lang=\"en\" data-theme=\"{name}\">");
        html.Should().Contain($"<meta name=\"color-scheme\" content=\"{name}\">");
    }

    [Fact]
    public void Theme_FollowsChangesToTheSettings()
    {
        var monitor = new TestMonitor(new LandingOptions { LandingTheme = "Dark" });
        var page = new LandingPage(monitor, NullLogger<LandingPage>.Instance);

        page.Theme.Should().Be(LandingTheme.Dark);

        monitor.CurrentValue = new LandingOptions { LandingTheme = "Light" };
        page.Theme.Should().Be(LandingTheme.Light);
    }

    private sealed class TestMonitor(LandingOptions value) : IOptionsMonitor<LandingOptions>
    {
        public LandingOptions CurrentValue { get; set; } = value;
        public LandingOptions Get(string? name) => CurrentValue;
        public IDisposable? OnChange(Action<LandingOptions, string?> listener) => null;
    }
}
