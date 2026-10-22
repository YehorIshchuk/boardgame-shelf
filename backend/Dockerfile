# ---- build stage ----
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# restore first for better layer caching
COPY BoardGames.Api/BoardGames.Api.csproj BoardGames.Api/
RUN dotnet restore BoardGames.Api/BoardGames.Api.csproj

COPY BoardGames.Api/ BoardGames.Api/
RUN dotnet publish BoardGames.Api/BoardGames.Api.csproj -c Release -o /app/publish --no-restore

# ---- runtime stage ----
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "BoardGames.Api.dll"]
