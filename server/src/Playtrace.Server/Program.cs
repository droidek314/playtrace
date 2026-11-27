using System.Text;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Playtrace.Server.Data;
using Playtrace.Server.Projects;
using Playtrace.Server.Sessions;

var builder = WebApplication.CreateBuilder(args);

// Settings are read from IConfiguration at use time, so test hosts can override them.
builder.Services.AddDbContext<PlaytraceDb>((sp, options) => options
    .UseNpgsql(sp.GetRequiredService<IConfiguration>().GetConnectionString("Playtrace"))
    .UseSnakeCaseNamingConvention());
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower);
builder.Services.AddCors(o => o.AddPolicy(SessionEndpoints.UploadCorsPolicy, policy => policy
    .AllowAnyOrigin().WithMethods("POST").WithHeaders("Authorization", "Content-Type", "Content-Encoding")));
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    // Partitioned by a hash of the bearer key, never by client IP.
    o.AddPolicy(SessionEndpoints.UploadRateLimitPolicy, http => RateLimitPartition.GetFixedWindowLimiter(
        Convert.ToHexString(ProjectKeys.Hash(http.Request.Headers.Authorization.ToString())),
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = http.RequestServices.GetRequiredService<IConfiguration>().GetValue("Playtrace:UploadsPerMinute", 60),
            Window = TimeSpan.FromMinutes(1),
        }));
});

var app = builder.Build();

if (app.Configuration.GetValue("Playtrace:MigrateOnStart", true))
{
    using var scope = app.Services.CreateScope();
    scope.ServiceProvider.GetRequiredService<PlaytraceDb>().Database.Migrate();
}

if (args is ["create-project", var name])
{
    using var scope = app.Services.CreateScope();
    var (_, ingestKey, readKey) = await ProjectKeys.CreateAsync(scope.ServiceProvider.GetRequiredService<PlaytraceDb>(), name);
    Console.WriteLine(new StringBuilder()
        .AppendLine($"Created project \"{name}\".")
        .AppendLine($"Ingest key (game builds, setting playtrace/server/ingest_key): {ingestKey}")
        .AppendLine($"Read key (editor Server tab, keep private):                  {readKey}")
        .Append("Save both now: the server stores only their SHA-256 hashes and cannot show them again."));
    return;
}

app.UseCors();
app.UseRateLimiter();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapSessionEndpoints();

app.Run();

/// <summary>Application entry point. Public so integration tests can host it with WebApplicationFactory.</summary>
public partial class Program;
