using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;

namespace Playtrace.Server.Tests;

/// <summary>T31 (key separation), T32 (rate limiting) and CORS.</summary>
[Collection(DbCollection.Name)]
public class KeyAndRateLimitTests(PostgresFixture db)
{
    /// <summary>T31: ingest keys cannot read, read keys cannot write, and keys only see their own project.</summary>
    [Fact]
    public async Task T31_ingest_key_cannot_read_and_read_key_cannot_write()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        var (_, otherRead) = await db.CreateProjectAsync();
        Assert.Equal(HttpStatusCode.Created, (await db.Client(ingest).PostAsync("/v1/sessions", PostgresFixture.UploadFixture("quit.jsonl"))).StatusCode);
        var id = (await db.Client(read).GetFromJsonAsync<JsonElement>("/v1/sessions")).GetProperty("items")[0].GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Client(ingest).GetAsync("/v1/sessions")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Client(ingest).GetAsync($"/v1/sessions/{id}")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Client(null).GetAsync("/v1/sessions")).StatusCode);

        var before = db.CountSessions();
        Assert.Equal(HttpStatusCode.Unauthorized, (await db.Client(read).PostAsync("/v1/sessions", PostgresFixture.UploadFixture("completed.jsonl"))).StatusCode);
        Assert.Equal(before, db.CountSessions());

        Assert.Equal(HttpStatusCode.NotFound, (await db.Client(otherRead).GetAsync($"/v1/sessions/{id}")).StatusCode);
        Assert.Empty((await db.Client(otherRead).GetFromJsonAsync<JsonElement>("/v1/sessions")).GetProperty("items").EnumerateArray());
    }

    /// <summary>T32: more uploads than the per-key limit in a minute get 429; other keys are unaffected.</summary>
    [Fact]
    public async Task T32_over_rate_limit_returns_429()
    {
        using var limited = db.Factory.WithWebHostBuilder(b => b.UseSetting("Playtrace:UploadsPerMinute", "3"));
        var (ingest, _) = await db.CreateProjectAsync();
        var (otherIngest, _) = await db.CreateProjectAsync();
        var client = db.Client(ingest, limited);

        for (var i = 0; i < 3; i++)
            Assert.NotEqual(HttpStatusCode.TooManyRequests, (await client.PostAsync("/v1/sessions", PostgresFixture.UploadFixture("completed.jsonl"))).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await client.PostAsync("/v1/sessions", PostgresFixture.UploadFixture("quit.jsonl"))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await db.Client(otherIngest, limited).PostAsync("/v1/sessions", PostgresFixture.UploadFixture("quit.jsonl"))).StatusCode);
    }

    /// <summary>CORS: any origin may preflight POST /v1/sessions; GET endpoints send no CORS headers.</summary>
    [Fact]
    public async Task Cors_allows_upload_only()
    {
        var client = db.Client(null);
        using var preflight = new HttpRequestMessage(HttpMethod.Options, "/v1/sessions");
        preflight.Headers.Add("Origin", "https://example.itch.io");
        preflight.Headers.Add("Access-Control-Request-Method", "POST");
        preflight.Headers.Add("Access-Control-Request-Headers", "authorization,content-encoding,content-type");
        var response = await client.SendAsync(preflight);
        Assert.Equal("*", response.Headers.GetValues("Access-Control-Allow-Origin").Single());

        using var get = new HttpRequestMessage(HttpMethod.Get, "/v1/sessions");
        get.Headers.Add("Origin", "https://example.itch.io");
        Assert.False((await client.SendAsync(get)).Headers.Contains("Access-Control-Allow-Origin"));
    }
}
