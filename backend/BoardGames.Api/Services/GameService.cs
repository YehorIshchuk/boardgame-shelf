using BoardGames.Api.Data;
using BoardGames.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BoardGames.Api.Services;

public class GameService
{
    private readonly AppDbContext _db;

    public GameService(AppDbContext db) => _db = db;

    public Task<List<Game>> GetAllAsync() =>
        _db.Games.OrderBy(g => g.Title).ToListAsync();

    public async Task<Game> AddAsync(string title, int minPlayers, int maxPlayers)
    {
        if (string.IsNullOrWhiteSpace(title))
            throw new ArgumentException("Title is required.");
        if (minPlayers < 1 || maxPlayers < minPlayers)
            throw new ArgumentException("Invalid players range.");

        var game = new Game
        {
            Title = title.Trim(),
            MinPlayers = minPlayers,
            MaxPlayers = maxPlayers
        };
        _db.Games.Add(game);
        await _db.SaveChangesAsync();
        return game;
    }

    public async Task<Game?> BorrowAsync(int id, string name)
    {
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("Borrower name is required.");

        var game = await _db.Games.FindAsync(id);
        if (game is null) return null;
        if (game.IsBorrowed)
            throw new InvalidOperationException("Game is already borrowed.");

        game.IsBorrowed = true;
        game.BorrowedBy = name.Trim();
        await _db.SaveChangesAsync();
        return game;
    }

    public async Task<Game?> ReturnAsync(int id)
    {
        var game = await _db.Games.FindAsync(id);
        if (game is null) return null;

        game.IsBorrowed = false;
        game.BorrowedBy = null;
        await _db.SaveChangesAsync();
        return game;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var game = await _db.Games.FindAsync(id);
        if (game is null) return false;
        _db.Games.Remove(game);
        await _db.SaveChangesAsync();
        return true;
    }
}
