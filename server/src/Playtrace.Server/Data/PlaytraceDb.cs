using Microsoft.EntityFrameworkCore;

namespace Playtrace.Server.Data;

/// <summary>EF Core context for the Playtrace database (PostgreSQL, snake_case names).</summary>
public sealed class PlaytraceDb(DbContextOptions<PlaytraceDb> options) : DbContext(options)
{
    /// <summary>Projects and their hashed keys.</summary>
    public DbSet<Project> Projects => Set<Project>();

    /// <summary>Uploaded sessions.</summary>
    public DbSet<Session> Sessions => Set<Session>();

    /// <inheritdoc />
    protected override void OnModelCreating(ModelBuilder model)
    {
        model.Entity<Project>(e =>
        {
            e.HasIndex(p => p.IngestKeyHash).IsUnique();
            e.HasIndex(p => p.ReadKeyHash).IsUnique();
        });
        model.Entity<Session>(e =>
        {
            e.HasKey(s => s.Seq);
            // Idempotency: one row per session id within a project.
            e.HasIndex(s => new { s.ProjectId, s.SessionId }).IsUnique();
            // Cursor paging: WHERE project_id = @p AND seq > @since ORDER BY seq.
            e.HasIndex(s => new { s.ProjectId, s.Seq });
            e.Property(s => s.Header).HasColumnType("jsonb");
            e.Property(s => s.Events).HasColumnType("jsonb");
            e.HasOne<Project>().WithMany().HasForeignKey(s => s.ProjectId).OnDelete(DeleteBehavior.Cascade);
        });
    }
}

/// <summary>A game project. Keys are stored only as SHA-256 hashes.</summary>
public sealed class Project
{
    /// <summary>Database id.</summary>
    public long Id { get; set; }

    /// <summary>Name given to <c>create-project</c>.</summary>
    public required string Name { get; set; }

    /// <summary>SHA-256 of the ingest (write-only) key.</summary>
    public required byte[] IngestKeyHash { get; set; }

    /// <summary>SHA-256 of the read (read-only) key.</summary>
    public required byte[] ReadKeyHash { get; set; }
}

/// <summary>One uploaded session: summary columns for listing plus the full content as jsonb.</summary>
public sealed class Session
{
    /// <summary>Upload order; the list cursor.</summary>
    public long Seq { get; set; }

    /// <summary>Owning project.</summary>
    public long ProjectId { get; set; }

    /// <summary>The <c>session</c> UUID from the header line.</summary>
    public Guid SessionId { get; set; }

    /// <summary>Header <c>build</c> ("" when missing).</summary>
    public required string Build { get; set; }

    /// <summary>Header <c>started_utc</c> as sent ("" when missing).</summary>
    public required string StartedUtc { get; set; }

    /// <summary>Level ids in order of first <c>level_enter</c>.</summary>
    public required string[] Levels { get; set; }

    /// <summary>Largest event <c>t</c>.</summary>
    public long DurationMs { get; set; }

    /// <summary>"completed", "quit" or "unknown".</summary>
    public required string Outcome { get; set; }

    /// <summary>Number of <c>death</c> events.</summary>
    public int Deaths { get; set; }

    /// <summary>The header line, as a JSON object.</summary>
    public required string Header { get; set; }

    /// <summary>All valid event lines after the header, as a JSON array of objects in file order.</summary>
    public required string Events { get; set; }
}
