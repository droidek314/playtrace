using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Playtrace.Server.Tests;

/// <summary>T01 placeholder: the server starts and answers /health.</summary>
public class HealthTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
{
    /// <summary>GET /health returns 200 with {"status":"ok"}.</summary>
    [Fact]
    public async Task Health_returns_ok()
    {
        var response = await factory.CreateClient().GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.Equal("ok", body!["status"]);
    }
}
