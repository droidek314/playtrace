using System.IO.Compression;
using System.Net.Http.Headers;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Playtrace.Server.Data;
using Playtrace.Server.Projects;
using Testcontainers.PostgreSql;

namespace Playtrace.Server.Tests;

/// <summary>Starts one PostgreSQL container (Testcontainers, needs Docker) and a server host using it.</summary>
public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder("postgres:17").Build();

    /// <summary>Server host connected to the container; migrations run on start.</summary>
    public WebApplicationFactory<Program> Factory { get; private set; } = null!;

    /// <inheritdoc />
    public async Task InitializeAsync()
    {
        await _db.StartAsync();
        Factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ConnectionStrings:Playtrace", _db.GetConnectionString()));
    }

    /// <inheritdoc />
    public async Task DisposeAsync()
    {
        await Factory.DisposeAsync();
        await _db.DisposeAsync();
    }

    /// <summary>Creates a fresh project (so tests never share keys or sessions) and returns its keys.</summary>
    public async Task<(string Ingest, string Read)> CreateProjectAsync()
    {
        using var scope = Factory.Services.CreateScope();
        var (_, ingest, read) = await ProjectKeys.CreateAsync(scope.ServiceProvider.GetRequiredService<PlaytraceDb>(), "test");
        return (ingest, read);
    }

    /// <summary>Total sessions stored across all projects.</summary>
    public int CountSessions()
    {
        using var scope = Factory.Services.CreateScope();
        return scope.ServiceProvider.GetRequiredService<PlaytraceDb>().Sessions.Count();
    }

    /// <summary>A client that sends <paramref name="key"/> as bearer token (none when null).</summary>
    public HttpClient Client(string? key, WebApplicationFactory<Program>? factory = null)
    {
        var client = (factory ?? Factory).CreateClient();
        if (key is not null)
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", key);
        return client;
    }

    /// <summary>Bytes of a file from tests/fixtures.</summary>
    public static byte[] Fixture(string name) => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "fixtures", name));

    /// <summary>Gzip-compresses bytes.</summary>
    public static byte[] Gzip(byte[] data)
    {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Optimal))
            gzip.Write(data);
        return output.ToArray();
    }

    /// <summary>Upload body with <c>Content-Encoding: gzip</c>.</summary>
    public static ByteArrayContent Upload(byte[] gzipped)
    {
        var content = new ByteArrayContent(gzipped);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/x-ndjson");
        content.Headers.ContentEncoding.Add("gzip");
        return content;
    }

    /// <summary>Upload body for a fixture file.</summary>
    public static ByteArrayContent UploadFixture(string name) => Upload(Gzip(Fixture(name)));
}

/// <summary>All database tests share one container and run one after another.</summary>
[CollectionDefinition(Name)]
public sealed class DbCollection : ICollectionFixture<PostgresFixture>
{
    /// <summary>Collection name.</summary>
    public const string Name = "db";
}
