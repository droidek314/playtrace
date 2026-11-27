using System.Text;
using System.Text.Json;
using Playtrace.Server.Data;

namespace Playtrace.Server.Sessions;

/// <summary>Turns one session file (JSON Lines, schema v1) into a <see cref="Session"/> row.</summary>
/// <remarks>
/// The header (line 1) must be a JSON object with <c>schema</c> = 1, <c>type</c> = "session_start" and a UUID
/// <c>session</c>; otherwise the upload is rejected. Event lines follow the reader rule from the contract:
/// lines that are not JSON objects are skipped, unknown types and fields are kept. Skipping (not rejecting) matters
/// because a crashed game can leave a truncated last line, and a 400 would make the uploader drop the session.
/// </remarks>
public static class SessionParser
{
    /// <summary>Parses UTF-8 JSONL. Returns null when the header line is invalid.</summary>
    public static Session? Parse(Stream jsonl, long projectId)
    {
        using var reader = new StreamReader(jsonl, Encoding.UTF8);
        var headerLine = reader.ReadLine();
        if (headerLine is null || !TryParseObject(headerLine, out var header))
            return null;
        using (header)
        {
            var h = header.RootElement;
            if (!(h.TryGetProperty("schema", out var schema) && schema.ValueKind == JsonValueKind.Number
                  && schema.TryGetInt32(out var v) && v == 1)
                || Str(h, "type") != "session_start"
                || !Guid.TryParse(Str(h, "session"), out var id))
                return null;

            var events = new StringBuilder("[");
            var levels = new List<string>();
            long duration = 0;
            int deaths = 0;
            bool completed = false, quit = false;
            while (reader.ReadLine() is { } line)
            {
                if (!TryParseObject(line, out var ev))
                    continue;
                using (ev)
                {
                    var e = ev.RootElement;
                    if (e.TryGetProperty("t", out var t) && t.ValueKind == JsonValueKind.Number && t.TryGetInt64(out var ms))
                        duration = Math.Max(duration, ms);
                    switch (Str(e, "type"))
                    {
                        case "level_enter" when Str(e, "level") is { } level && !levels.Contains(level):
                            levels.Add(level);
                            break;
                        case "death": deaths++; break;
                        case "level_complete": completed = true; break;
                        case "quit": quit = true; break;
                    }
                }
                if (events.Length > 1)
                    events.Append(',');
                events.Append(line);
            }
            events.Append(']');

            return new Session
            {
                ProjectId = projectId,
                SessionId = id,
                Build = Str(h, "build") ?? "",
                StartedUtc = Str(h, "started_utc") ?? "",
                Levels = [.. levels],
                DurationMs = duration,
                Outcome = completed ? "completed" : quit ? "quit" : "unknown",
                Deaths = deaths,
                Header = headerLine,
                Events = events.ToString(),
            };
        }
    }

    private static string? Str(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;

    private static bool TryParseObject(string line, out JsonDocument doc)
    {
        doc = null!;
        try
        {
            doc = JsonDocument.Parse(line);
        }
        catch (JsonException)
        {
            return false;
        }
        if (doc.RootElement.ValueKind == JsonValueKind.Object)
            return true;
        doc.Dispose();
        return false;
    }
}
