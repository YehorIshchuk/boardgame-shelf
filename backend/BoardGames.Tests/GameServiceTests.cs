using BoardGames.Api.Data;
using BoardGames.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace BoardGames.Tests;

public class GameServiceTests
{
    private static GameService CreateService()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new GameService(new AppDbContext(options));
    }

    [Fact]
    public async Task AddAsync_ValidData_SavesGame()
    {
        var service = CreateService();

        var game = await service.AddAsync("Catan", 3, 4);

        Assert.True(game.Id > 0);
        Assert.Single(await service.GetAllAsync());
    }

    [Theory]
    [InlineData("", 2, 4)]
    [InlineData("Carcassonne", 0, 4)]
    [InlineData("Carcassonne", 5, 2)]
    public async Task AddAsync_InvalidData_Throws(string title, int min, int max)
    {
        var service = CreateService();

        await Assert.ThrowsAsync<ArgumentException>(() => service.AddAsync(title, min, max));
    }

    [Fact]
    public async Task BorrowAsync_FreeGame_MarksAsBorrowed()
    {
        var service = CreateService();
        var game = await service.AddAsync("Dixit", 3, 6);

        var result = await service.BorrowAsync(game.Id, "Olena");

        Assert.NotNull(result);
        Assert.True(result!.IsBorrowed);
        Assert.Equal("Olena", result.BorrowedBy);
    }

    [Fact]
    public async Task BorrowAsync_AlreadyBorrowed_Throws()
    {
        var service = CreateService();
        var game = await service.AddAsync("Dixit", 3, 6);
        await service.BorrowAsync(game.Id, "Olena");

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.BorrowAsync(game.Id, "Taras"));
    }

    [Fact]
    public async Task ReturnAsync_BorrowedGame_ClearsBorrower()
    {
        var service = CreateService();
        var game = await service.AddAsync("Azul", 2, 4);
        await service.BorrowAsync(game.Id, "Olena");

        var result = await service.ReturnAsync(game.Id);

        Assert.False(result!.IsBorrowed);
        Assert.Null(result.BorrowedBy);
    }

    [Fact]
    public async Task DeleteAsync_UnknownId_ReturnsFalse()
    {
        var service = CreateService();

        Assert.False(await service.DeleteAsync(999));
    }
}
