var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.Run();

/// <summary>Application entry point. Public so integration tests can host it with WebApplicationFactory.</summary>
public partial class Program;
