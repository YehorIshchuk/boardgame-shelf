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

app.MapGet("/api/health", () => Results.Ok(new { status = "ok" }));

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
