using BoardGames.Api.Data;
using BoardGames.Api.Models;
using BoardGames.Api.Services;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? "Host=localhost;Port=5432;Database=boardgames;Username=postgres;Password=postgres";

builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(connectionString));
builder.Services.AddScoped<GameService>();
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    // simple retry: the DB container may need a few seconds
    for (var attempt = 1; ; attempt++)
    {
        try { db.Database.EnsureCreated(); break; }
        catch when (attempt < 10) { Thread.Sleep(2000); }
    }
}

app.UseCors();

// liveness: the process is up and serving HTTP
app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

// readiness: the instance can reach the database and may receive traffic
app.MapGet("/api/ready", async (AppDbContext db) =>
    await db.Database.CanConnectAsync()
        ? Results.Ok(new { status = "ready" })
        : Results.Json(new { status = "db unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

// runtime info: image version, pod name and values that come from ConfigMap/Secret
var dbInfo = new Npgsql.NpgsqlConnectionStringBuilder(connectionString);
app.MapGet("/api/info", (IConfiguration cfg, IWebHostEnvironment env) => Results.Ok(new
{
    version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "dev",
    instance = Environment.MachineName,
    environment = env.EnvironmentName,
    clubName = cfg["App:ClubName"] ?? "BoardGame Club",
    maxBorrowDays = cfg.GetValue("App:MaxBorrowDays", 14),
    dbHost = dbInfo.Host,
    dbUser = dbInfo.Username,
    // never expose the secret itself, only the fact that it was provided
    dbPasswordSet = !string.IsNullOrEmpty(dbInfo.Password)
}));

app.MapGet("/api/games", async (GameService s) => Results.Ok(await s.GetAllAsync()));

app.MapPost("/api/games", async (CreateGameRequest r, GameService s) =>
{
    try
    {
        var game = await s.AddAsync(r.Title, r.MinPlayers, r.MaxPlayers);
        return Results.Created($"/api/games/{game.Id}", game);
    }
    catch (ArgumentException e) { return Results.BadRequest(new { error = e.Message }); }
});

app.MapPost("/api/games/{id:int}/borrow", async (int id, BorrowRequest r, GameService s) =>
{
    try
    {
        var game = await s.BorrowAsync(id, r.Name);
        return game is null ? Results.NotFound() : Results.Ok(game);
    }
    catch (ArgumentException e) { return Results.BadRequest(new { error = e.Message }); }
    catch (InvalidOperationException e) { return Results.Conflict(new { error = e.Message }); }
});

app.MapPost("/api/games/{id:int}/return", async (int id, GameService s) =>
{
    var game = await s.ReturnAsync(id);
    return game is null ? Results.NotFound() : Results.Ok(game);
});

app.MapDelete("/api/games/{id:int}", async (int id, GameService s) =>
    await s.DeleteAsync(id) ? Results.NoContent() : Results.NotFound());

app.Run();
