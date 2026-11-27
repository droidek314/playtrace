using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Playtrace.Server.Tests;

/// <summary>T29 (ingest happy path), T30 (validation) and T33 (idempotent upload).</summary>
[Collection(DbCollection.Name)]
public class IngestTests(PostgresFixture db)
{
    /// <summary>T29: a valid upload returns 201, appears in the list with the right summary, and downloads intact.</summary>
    [Fact]
    public async Task T29_valid_upload_is_stored_listed_and_downloadable()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        var file = PostgresFixture.Fixture("completed.jsonl");
        var id = SessionId(file);

        var post = await db.Client(ingest).PostAsync("/v1/sessions", PostgresFixture.UploadFixture("completed.jsonl"));
        Assert.Equal(HttpStatusCode.Created, post.StatusCode);

        var page = await db.Client(read).GetFromJsonAsync<JsonElement>("/v1/sessions");
        var item = Assert.Single(page.GetProperty("items").EnumerateArray());
        Assert.Equal(id, item.GetProperty("id").GetGuid());
        Assert.Equal(["res://demo/sandbox.tscn"], item.GetProperty("levels").EnumerateArray().Select(l => l.GetString()));
        Assert.Equal("0.1.0", item.GetProperty("build").GetString());
        Assert.Equal("2026-11-20T10:00:00Z", item.GetProperty("started_utc").GetString());
        Assert.Equal(12400, item.GetProperty("duration_ms").GetInt64());
        Assert.Equal("completed", item.GetProperty("outcome").GetString());
        Assert.Equal(0, item.GetProperty("deaths").GetInt32());
        Assert.Equal(JsonValueKind.Null, page.GetProperty("next").ValueKind);

        var get = await db.Client(read).GetAsync($"/v1/sessions/{id}");
        Assert.Equal(HttpStatusCode.OK, get.StatusCode);
        Assert.Contains("gzip", get.Content.Headers.ContentEncoding);
        var expected = Lines(file);
        var actual = Lines(await Gunzip(get));
        Assert.Equal(expected.Length, actual.Length);
        for (var i = 0; i < expected.Length; i++)
            Assert.True(JsonElement.DeepEquals(Parse(expected[i]), Parse(actual[i])), $"line {i + 1} differs: {actual[i]}");
    }

    /// <summary>T29: summaries count deaths and outcomes; corrupt event lines are skipped, unknown types kept.</summary>
    [Fact]
    public async Task T29_summaries_and_corrupt_lines()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        foreach (var name in new[] { "many_deaths.jsonl", "corrupt.jsonl", "with_feedback.jsonl" })
            Assert.Equal(HttpStatusCode.Created, (await db.Client(ingest).PostAsync("/v1/sessions", PostgresFixture.UploadFixture(name))).StatusCode);

        var items = (await db.Client(read).GetFromJsonAsync<JsonElement>("/v1/sessions")).GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(3, items.Count);
        Assert.Equal((9, "quit"), (items[0].GetProperty("deaths").GetInt32(), items[0].GetProperty("outcome").GetString()));
        Assert.Equal((1, "unknown"), (items[1].GetProperty("deaths").GetInt32(), items[1].GetProperty("outcome").GetString()));
        Assert.Equal(["level_1"], items[2].GetProperty("levels").EnumerateArray().Select(l => l.GetString()));

        // corrupt.jsonl: header + 5 JSON-object lines (level_enter, 2 pos, unknown teleport, death).
        var corruptId = items[1].GetProperty("id").GetGuid();
        var lines = Lines(await Gunzip(await db.Client(read).GetAsync($"/v1/sessions/{corruptId}")));
        Assert.Equal(6, lines.Length);
        Assert.Contains(lines, l => l.Contains("teleport"));
    }

    /// <summary>T30: bad schema/header/gzip → 400, too large → 413, bad key → 401; nothing is stored.</summary>
    [Fact]
    public async Task T30_invalid_uploads_are_rejected_and_nothing_is_stored()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        var client = db.Client(ingest);
        var good = Encoding.UTF8.GetString(PostgresFixture.Fixture("completed.jsonl"));
        var before = db.CountSessions();

        async Task Expect(HttpStatusCode status, HttpContent content, HttpClient? c = null) =>
            Assert.Equal(status, (await (c ?? client).PostAsync("/v1/sessions", content)).StatusCode);
        HttpContent Gz(string text) => PostgresFixture.Upload(PostgresFixture.Gzip(Encoding.UTF8.GetBytes(text)));

        await Expect(HttpStatusCode.BadRequest, Gz(good.Replace("\"schema\":1", "\"schema\":2")));
        await Expect(HttpStatusCode.BadRequest, Gz(good.Replace("\"type\":\"session_start\"", "\"type\":\"pos\"")));
        await Expect(HttpStatusCode.BadRequest, Gz(good.Replace("0b6f2c1e-4a8d-4c1b-9f3e-2a7d5c8e1f01", "not-a-uuid")));
        await Expect(HttpStatusCode.BadRequest, Gz("this is not json\n"));
        await Expect(HttpStatusCode.BadRequest, Gz(""));
        await Expect(HttpStatusCode.BadRequest, PostgresFixture.Upload(Encoding.UTF8.GetBytes(good))); // not gzip
        await Expect(HttpStatusCode.BadRequest, new ByteArrayContent(PostgresFixture.Gzip(Encoding.UTF8.GetBytes(good)))); // no Content-Encoding

        await Expect(HttpStatusCode.RequestEntityTooLarge, PostgresFixture.Upload(new byte[2 * 1024 * 1024 + 1]));
        var bomb = new byte[17 * 1024 * 1024]; // compresses to a few KB, inflates past the 16 MB cap
        await Expect(HttpStatusCode.RequestEntityTooLarge, PostgresFixture.Upload(PostgresFixture.Gzip(bomb)));

        await Expect(HttpStatusCode.Unauthorized, PostgresFixture.UploadFixture("completed.jsonl"), db.Client(null));
        await Expect(HttpStatusCode.Unauthorized, PostgresFixture.UploadFixture("completed.jsonl"), db.Client("pt_ingest_wrong"));

        Assert.Equal(before, db.CountSessions());
        var page = await db.Client(read).GetFromJsonAsync<JsonElement>("/v1/sessions");
        Assert.Empty(page.GetProperty("items").EnumerateArray());
    }

    /// <summary>T33: uploading the same session twice returns 201 then 200 and stores it once.</summary>
    [Fact]
    public async Task T33_same_session_twice_is_idempotent()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        var client = db.Client(ingest);
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsync("/v1/sessions", PostgresFixture.UploadFixture("stuck.jsonl"))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync("/v1/sessions", PostgresFixture.UploadFixture("stuck.jsonl"))).StatusCode);

        var item = Assert.Single((await db.Client(read).GetFromJsonAsync<JsonElement>("/v1/sessions")).GetProperty("items").EnumerateArray());
        var lines = Lines(await Gunzip(await db.Client(read).GetAsync($"/v1/sessions/{item.GetProperty("id").GetGuid()}")));
        Assert.Equal(Lines(PostgresFixture.Fixture("stuck.jsonl")).Length, lines.Length);
    }

    /// <summary>List filters (level, build) and cursor paging with limit.</summary>
    [Fact]
    public async Task List_filters_and_pages()
    {
        var (ingest, read) = await db.CreateProjectAsync();
        foreach (var name in new[] { "completed.jsonl", "quit.jsonl", "with_feedback.jsonl" })
            await db.Client(ingest).PostAsync("/v1/sessions", PostgresFixture.UploadFixture(name));
        var c = db.Client(read);

        async Task<JsonElement> Page(string query) => await c.GetFromJsonAsync<JsonElement>("/v1/sessions" + query);
        Assert.Single((await Page("?level=level_1")).GetProperty("items").EnumerateArray());
        Assert.Equal(2, (await Page("?level=res://demo/sandbox.tscn")).GetProperty("items").GetArrayLength());
        Assert.Empty((await Page("?build=9.9.9")).GetProperty("items").EnumerateArray());

        var first = await Page("?limit=2");
        Assert.Equal(2, first.GetProperty("items").GetArrayLength());
        var next = first.GetProperty("next").GetString();
        Assert.NotNull(next);
        var second = await Page($"?limit=2&since={next}");
        Assert.Single(second.GetProperty("items").EnumerateArray());
        Assert.Equal(JsonValueKind.Null, second.GetProperty("next").ValueKind);

        Assert.Equal(HttpStatusCode.NotFound, (await c.GetAsync($"/v1/sessions/{Guid.NewGuid()}")).StatusCode);
    }

    private static Guid SessionId(byte[] file) => Parse(Lines(file)[0]).GetProperty("session").GetGuid();

    private static JsonElement Parse(string line) => JsonDocument.Parse(line).RootElement;

    private static string[] Lines(byte[] file) =>
        Encoding.UTF8.GetString(file).Split('\n', StringSplitOptions.RemoveEmptyEntries);

    private static async Task<byte[]> Gunzip(HttpResponseMessage response)
    {
        await using var gzip = new GZipStream(await response.Content.ReadAsStreamAsync(), CompressionMode.Decompress);
        using var output = new MemoryStream();
        await gzip.CopyToAsync(output);
        return output.ToArray();
    }
}
