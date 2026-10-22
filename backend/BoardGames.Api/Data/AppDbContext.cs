using BoardGames.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace BoardGames.Api.Data;

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Game> Games => Set<Game>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Game>(e =>
        {
            e.Property(g => g.Title).IsRequired().HasMaxLength(200);
        });
    }
}
