using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Playtrace.Server.Tests;

/// <summary>T01: the server starts and answers /health. Runs without a database (and without Docker).</summary>
public class HealthTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
{
    /// <summary>GET /health returns 200 with {"status":"ok"}.</summary>
    [Fact]
    public async Task Health_returns_ok()
    {
        var client = factory.WithWebHostBuilder(b => b.UseSetting("Playtrace:MigrateOnStart", "false")).CreateClient();
        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.Equal("ok", body!["status"]);
    }
}
