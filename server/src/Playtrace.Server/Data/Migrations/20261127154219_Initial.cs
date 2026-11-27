using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace Playtrace.Server.Data.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "projects",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    name = table.Column<string>(type: "text", nullable: false),
                    ingest_key_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    read_key_hash = table.Column<byte[]>(type: "bytea", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_projects", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "sessions",
                columns: table => new
                {
                    seq = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    project_id = table.Column<long>(type: "bigint", nullable: false),
                    session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    build = table.Column<string>(type: "text", nullable: false),
                    started_utc = table.Column<string>(type: "text", nullable: false),
                    levels = table.Column<string[]>(type: "text[]", nullable: false),
                    duration_ms = table.Column<long>(type: "bigint", nullable: false),
                    outcome = table.Column<string>(type: "text", nullable: false),
                    deaths = table.Column<int>(type: "integer", nullable: false),
                    header = table.Column<string>(type: "jsonb", nullable: false),
                    events = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_sessions", x => x.seq);
                    table.ForeignKey(
                        name: "fk_sessions_projects_project_id",
                        column: x => x.project_id,
                        principalTable: "projects",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_projects_ingest_key_hash",
                table: "projects",
                column: "ingest_key_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_projects_read_key_hash",
                table: "projects",
                column: "read_key_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_sessions_project_id_seq",
                table: "sessions",
                columns: new[] { "project_id", "seq" });

            migrationBuilder.CreateIndex(
                name: "ix_sessions_project_id_session_id",
                table: "sessions",
                columns: new[] { "project_id", "session_id" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "sessions");

            migrationBuilder.DropTable(
                name: "projects");
        }
    }
}
