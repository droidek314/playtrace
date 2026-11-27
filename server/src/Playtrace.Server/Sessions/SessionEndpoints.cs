using System.IO.Compression;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Playtrace.Server.Data;
using Playtrace.Server.Projects;

namespace Playtrace.Server.Sessions;

/// <summary>The <c>/v1/sessions</c> endpoints (contract 6.4, docs/openapi.yaml).</summary>
public static class SessionEndpoints
{
    /// <summary>CORS policy name: any origin may POST uploads.</summary>
    public const string UploadCorsPolicy = "upload";

    /// <summary>Rate limiter policy name: uploads per minute per ingest key.</summary>
    public const string UploadRateLimitPolicy = "upload";

    /// <summary>Max compressed upload size (contract: 2 MB).</summary>
    public const int MaxUploadBytes = 2 * 1024 * 1024;

    /// <summary>Max decompressed size. Guards against gzip bombs; a 10-minute session is about 200 KB.</summary>
    public const int MaxDecompressedBytes = 16 * 1024 * 1024;

    /// <summary>Maps the session endpoints.</summary>
    public static void MapSessionEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/v1/sessions");
        group.MapPost("", Upload).RequireCors(UploadCorsPolicy).RequireRateLimiting(UploadRateLimitPolicy);
        group.MapGet("", List);
        group.MapGet("{id:guid}", Get);
    }

    /// <summary>One item of the session list.</summary>
    /// <param name="Id">Session UUID.</param>
    /// <param name="Levels">Level ids in order of first entry.</param>
    /// <param name="Build">Game build.</param>
    /// <param name="StartedUtc">Start time from the header.</param>
    /// <param name="DurationMs">Session length in ms.</param>
    /// <param name="Outcome">"completed", "quit" or "unknown".</param>
    /// <param name="Deaths">Number of deaths.</param>
    public sealed record SessionSummary(
        Guid Id, string[] Levels, string Build, string StartedUtc, long DurationMs, string Outcome, int Deaths);

    /// <summary>One page of the session list.</summary>
    /// <param name="Items">Sessions, oldest upload first.</param>
    /// <param name="Next">Cursor for the next page, or null when there are no more items.</param>
    public sealed record SessionPage(List<SessionSummary> Items, string? Next);

    private static async Task<IResult> Upload(HttpRequest request, PlaytraceDb db, CancellationToken ct)
    {
        var project = await ProjectKeys.FindByIngestKeyAsync(db, request, ct);
        if (project is null)
            return Results.Unauthorized();
        if (request.ContentLength > MaxUploadBytes)
            return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);
        if (!string.Equals(request.Headers.ContentEncoding, "gzip", StringComparison.OrdinalIgnoreCase))
            return Results.BadRequest("Content-Encoding must be gzip.");

        using var body = await ReadLimitedAsync(request.Body, MaxUploadBytes, ct);
        if (body is null)
            return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);

        MemoryStream? jsonl;
        try
        {
            await using var gzip = new GZipStream(body, CompressionMode.Decompress);
            jsonl = await ReadLimitedAsync(gzip, MaxDecompressedBytes, ct);
        }
        catch (InvalidDataException)
        {
            return Results.BadRequest("Body is not valid gzip.");
        }
        if (jsonl is null)
            return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);

        Session? session;
        using (jsonl)
            session = SessionParser.Parse(jsonl, project.Id);
        if (session is null)
            return Results.BadRequest("Line 1 must be a session_start header with schema 1 and a UUID session id.");

        if (await db.Sessions.AnyAsync(s => s.ProjectId == project.Id && s.SessionId == session.SessionId, ct))
            return Results.Ok();
        db.Sessions.Add(session);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            // A concurrent upload of the same session won the insert.
            return Results.Ok();
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException
                   { SqlState: PostgresErrorCodes.InvalidTextRepresentation or PostgresErrorCodes.UntranslatableCharacter })
        {
            // Text jsonb rejects, e.g. "\u0000" or a lone surrogate escape.
            return Results.BadRequest("Session contains text PostgreSQL cannot store.");
        }
        return Results.Created($"/v1/sessions/{session.SessionId}", null);
    }

    private static async Task<IResult> List(
        HttpRequest request, PlaytraceDb db, long? since, string? level, string? build, int? limit, CancellationToken ct)
    {
        var project = await ProjectKeys.FindByReadKeyAsync(db, request, ct);
        if (project is null)
            return Results.Unauthorized();

        var take = Math.Clamp(limit ?? 100, 1, 500);
        var query = db.Sessions.AsNoTracking().Where(s => s.ProjectId == project.Id && s.Seq > (since ?? 0));
        if (level is not null)
            query = query.Where(s => s.Levels.Contains(level));
        if (build is not null)
            query = query.Where(s => s.Build == build);
        var rows = await query.OrderBy(s => s.Seq).Take(take + 1)
            .Select(s => new { s.Seq, Item = new SessionSummary(s.SessionId, s.Levels, s.Build, s.StartedUtc, s.DurationMs, s.Outcome, s.Deaths) })
            .ToListAsync(ct);

        var more = rows.Count > take;
        if (more)
            rows.RemoveAt(take);
        return Results.Ok(new SessionPage([.. rows.Select(r => r.Item)], more ? rows[^1].Seq.ToString() : null));
    }

    private static async Task<IResult> Get(Guid id, HttpRequest request, HttpResponse response, PlaytraceDb db, CancellationToken ct)
    {
        var project = await ProjectKeys.FindByReadKeyAsync(db, request, ct);
        if (project is null)
            return Results.Unauthorized();
        var session = await db.Sessions.AsNoTracking()
            .Where(s => s.ProjectId == project.Id && s.SessionId == id)
            .Select(s => new { s.Header, s.Events })
            .FirstOrDefaultAsync(ct);
        if (session is null)
            return Results.NotFound();

        using var output = new MemoryStream();
        await using (var gzip = new GZipStream(output, CompressionLevel.Fastest, leaveOpen: true))
        await using (var writer = new StreamWriter(gzip, new UTF8Encoding(false)) { NewLine = "\n" })
        {
            using var events = JsonDocument.Parse(session.Events);
            await writer.WriteLineAsync(session.Header);
            foreach (var e in events.RootElement.EnumerateArray())
                await writer.WriteLineAsync(e.GetRawText());
        }
        response.Headers.ContentEncoding = "gzip";
        return Results.Bytes(output.ToArray(), "application/x-ndjson");
    }

    /// <summary>Copies at most <paramref name="max"/> bytes into memory; null if the source is longer.</summary>
    private static async Task<MemoryStream?> ReadLimitedAsync(Stream source, int max, CancellationToken ct)
    {
        var buffer = new MemoryStream();
        var chunk = new byte[81920];
        int n;
        while ((n = await source.ReadAsync(chunk, ct)) > 0)
        {
            if (buffer.Length + n > max)
            {
                await buffer.DisposeAsync();
                return null;
            }
            buffer.Write(chunk, 0, n);
        }
        buffer.Position = 0;
        return buffer;
    }
}
