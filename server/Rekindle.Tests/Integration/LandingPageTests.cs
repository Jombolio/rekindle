using System.Net;
using FluentAssertions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Rekindle.Server.Landing;
using Xunit;

namespace Rekindle.Tests.Integration;

public class LandingPageTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly TestWebApplicationFactory factory;

    public LandingPageTests(TestWebApplicationFactory factory) => this.factory = factory;

    [Fact]
    public async Task Root_ServesTheLandingPage()
    {
        var resp = await factory.CreateClient().GetAsync("/");

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        resp.Content.Headers.ContentType!.MediaType.Should().Be("text/html");
        resp.Content.Headers.ContentType.CharSet.Should().Be("utf-8");

        var html = await resp.Content.ReadAsStringAsync();
        html.Should().Contain("<title>Rekindle</title>");
        html.Should().Contain("self-hosted comic, manga and book server");
        html.Should().Contain("<code id=\"server-address\">http://localhost</code>");
        html.Should().Contain(LandingPage.GiteaReleases);
        html.Should().Contain(LandingPage.GitHubReleases);
        html.Should().Contain(LandingPage.FDroidRepo);
        html.IndexOf(LandingPage.GiteaReleases).Should().BeLessThan(html.IndexOf(LandingPage.GitHubReleases),
            "Gitea is the primary download");
    }

    [Fact]
    public async Task Root_LoadsNothingFromOutside()
    {
        var resp = await factory.CreateClient().GetAsync("/");
        var html = await resp.Content.ReadAsStringAsync();

        html.Should().NotMatchRegex("<(script|link|img)[^>]+(src|href)=\"(https?:)?//");

        var csp = resp.Headers.GetValues("Content-Security-Policy").Single();
        csp.Should().Contain("default-src 'none'");
        csp.Should().Contain("script-src 'nonce-");
        csp.Should().NotContain("unsafe-inline");
        var nonce = csp.Split("script-src 'nonce-")[1].Split('\'')[0];
        html.Should().Contain($"<script nonce=\"{nonce}\">");
        html.Should().Contain($"<style nonce=\"{nonce}\">");
    }

    [Fact]
    public async Task Root_UsesAFreshNonceEachTime()
    {
        var client = factory.CreateClient();
        var first = (await client.GetAsync("/")).Headers.GetValues("Content-Security-Policy").Single();
        var second = (await client.GetAsync("/")).Headers.GetValues("Content-Security-Policy").Single();
        first.Should().NotBe(second);
    }

    [Fact]
    public async Task Root_AnswersHead()
    {
        var resp = await factory.CreateClient().SendAsync(new HttpRequestMessage(HttpMethod.Head, "/"));
        resp.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Root_HasNoContactSection_ByDefault()
    {
        var html = await factory.CreateClient().GetStringAsync("/");
        html.Should().NotContain("Contact the administrator");
    }

    [Fact]
    public async Task Icon_IsServed()
    {
        var resp = await factory.CreateClient().GetAsync("/" + LandingPage.IconPath);

        resp.StatusCode.Should().Be(HttpStatusCode.OK);
        resp.Content.Headers.ContentType!.MediaType.Should().Be("image/png");
        var bytes = await resp.Content.ReadAsByteArrayAsync();
        bytes.Take(4).Should().Equal(0x89, (byte)'P', (byte)'N', (byte)'G');
    }

    [Fact]
    public async Task ApiRoutes_AreUnaffected()
    {
        var client = factory.CreateClient();

        // The clients' reachability probe still answers 401 without a token.
        (await client.GetAsync("/api/auth/me")).StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        // Unknown routes still 404 rather than falling back to the page.
        var missing = await client.GetAsync("/api/does-not-exist");
        missing.StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await client.GetAsync("/libraries")).StatusCode.Should().Be(HttpStatusCode.NotFound);

        // Only GET and HEAD are answered at the root.
        (await client.PostAsync("/", null)).StatusCode.Should().Be(HttpStatusCode.MethodNotAllowed);
    }

    [Fact]
    public async Task Theme_FollowsTheVisitor_ByDefault()
    {
        var html = await factory.CreateClient().GetStringAsync("/");
        html.Should().Contain("<html lang=\"en\">");
    }

    [Fact]
    public async Task Theme_FromSettings_IsApplied()
    {
        using var configured = factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Rekindle:LandingTheme"] = "Dark",
                })));

        var html = await configured.CreateClient().GetStringAsync("/");
        html.Should().Contain("<html lang=\"en\" data-theme=\"dark\">");
        html.Should().Contain("<meta name=\"color-scheme\" content=\"dark\">");
    }

    [Fact]
    public async Task Contacts_FromSettings_AreShown_AndUnsafeOnesDropped()
    {
        using var configured = factory.WithWebHostBuilder(builder =>
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["Rekindle:Contacts:0:Name"] = "Discord",
                    ["Rekindle:Contacts:0:Url"] = "https://discord.gg/abc123",
                    ["Rekindle:Contacts:1:Name"] = "Sneaky",
                    ["Rekindle:Contacts:1:Url"] = "javascript:alert(1)",
                    ["Rekindle:Contacts:2:Name"] = "<b>Email</b>",
                    ["Rekindle:Contacts:2:Url"] = "admin@example.com",
                })));

        var html = await configured.CreateClient().GetStringAsync("/");

        html.Should().Contain("Contact the administrator");
        html.Should().Contain("href=\"https://discord.gg/abc123\"");
        html.Should().Contain("href=\"mailto:admin@example.com\"");
        html.Should().Contain("&lt;b&gt;Email&lt;/b&gt;");
        html.Should().NotContain("javascript:");
        html.Should().NotContain("Sneaky");
    }
}
