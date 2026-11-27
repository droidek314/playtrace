using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Playtrace.Server.Data;

namespace Playtrace.Server.Projects;

/// <summary>Creates projects and resolves bearer keys to projects.</summary>
/// <remarks>
/// Keys are 32 random bytes (256 bits), so a plain SHA-256 is enough to store them safely;
/// a slow password hash would only add cost to every request.
/// </remarks>
public static class ProjectKeys
{
    /// <summary>Creates a project and returns it with its plain-text keys (shown once, never stored).</summary>
    public static async Task<(Project Project, string IngestKey, string ReadKey)> CreateAsync(
        PlaytraceDb db, string name, CancellationToken ct = default)
    {
        var ingest = "pt_ingest_" + Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        var read = "pt_read_" + Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        var project = new Project { Name = name, IngestKeyHash = Hash(ingest), ReadKeyHash = Hash(read) };
        db.Projects.Add(project);
        await db.SaveChangesAsync(ct);
        return (project, ingest, read);
    }

    /// <summary>SHA-256 of a key's UTF-8 bytes.</summary>
    public static byte[] Hash(string key) => SHA256.HashData(Encoding.UTF8.GetBytes(key));

    /// <summary>Returns the token from an <c>Authorization: Bearer</c> header, or null.</summary>
    public static string? BearerToken(HttpRequest request)
    {
        var value = request.Headers.Authorization.ToString();
        return value.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) && value.Length > 7 ? value[7..].Trim() : null;
    }

    /// <summary>Project whose ingest key is the request's bearer token, or null.</summary>
    public static Task<Project?> FindByIngestKeyAsync(PlaytraceDb db, HttpRequest request, CancellationToken ct) =>
        BearerToken(request) is { } token
            ? db.Projects.AsNoTracking().FirstOrDefaultAsync(p => p.IngestKeyHash == Hash(token), ct)
            : Task.FromResult<Project?>(null);

    /// <summary>Project whose read key is the request's bearer token, or null.</summary>
    public static Task<Project?> FindByReadKeyAsync(PlaytraceDb db, HttpRequest request, CancellationToken ct) =>
        BearerToken(request) is { } token
            ? db.Projects.AsNoTracking().FirstOrDefaultAsync(p => p.ReadKeyHash == Hash(token), ct)
            : Task.FromResult<Project?>(null);
}
