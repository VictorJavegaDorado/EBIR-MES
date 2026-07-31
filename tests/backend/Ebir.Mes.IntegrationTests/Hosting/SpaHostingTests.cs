using System.Net;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace Ebir.Mes.IntegrationTests.Hosting;

public sealed class SpaHostingTests : IDisposable
{
    private const string IndexMarker = "EBIR MES SPA TEST";
    private readonly string webRoot;

    public SpaHostingTests()
    {
        webRoot = Path.Combine(
            Path.GetTempPath(),
            $"ebir-mes-spa-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(webRoot, "assets"));
        File.WriteAllText(
            Path.Combine(webRoot, "index.html"),
            $"<!doctype html><title>{IndexMarker}</title>");
        File.WriteAllText(
            Path.Combine(webRoot, "assets", "pilot.js"),
            "globalThis.ebirMesPilot = true;");
    }

    [Fact]
    public async Task ApiRoute_PreservesItsJsonContract()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/system/info");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);
        Assert.DoesNotContain(IndexMarker, body);
    }

    [Fact]
    public async Task FrontendAsset_IsServedFromTheApiWebRoot()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/assets/pilot.js");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("ebirMesPilot", body);
        Assert.DoesNotContain(IndexMarker, body);
    }

    [Fact]
    public async Task SpaNavigation_ReturnsIndexHtml()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/pallet-close/manual");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/html", response.Content.Headers.ContentType?.MediaType);
        Assert.Contains(IndexMarker, body);
    }

    [Fact]
    public async Task UnknownApiRoute_DoesNotFallBackToTheSpa()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/api/not-a-real-endpoint");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain(IndexMarker, body);
    }

    [Fact]
    public async Task MissingAsset_DoesNotFallBackToTheSpa()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();

        using var response = await client.GetAsync("/assets/missing.js");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain(IndexMarker, body);
    }

    public void Dispose()
    {
        if (Directory.Exists(webRoot))
        {
            Directory.Delete(webRoot, recursive: true);
        }
    }

    private WebApplicationFactory<Program> CreateFactory()
    {
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");
                builder.UseWebRoot(webRoot);
            });
    }
}
