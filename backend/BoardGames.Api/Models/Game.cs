namespace BoardGames.Api.Models;

public class Game
{
    public int Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public int MinPlayers { get; set; }
    public int MaxPlayers { get; set; }
    public bool IsBorrowed { get; set; }
    public string? BorrowedBy { get; set; }
}

public record CreateGameRequest(string Title, int MinPlayers, int MaxPlayers);
public record BorrowRequest(string Name);
