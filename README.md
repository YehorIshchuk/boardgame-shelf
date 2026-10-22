# BoardGame Shelf

![CI](https://github.com/YehorIshchuk/boardgame-shelf/actions/workflows/ci.yml/badge.svg)

Невеликий вебзастосунок для обліку настільних ігор клубу (додати гру, видати, повернути, видалити).

Використовується в лабораторних з предмету «Технології DevOps».

## Архітектура

| Частина  | Технології                         | Порт |
|----------|------------------------------------|------|
| frontend | React + Vite, віддається nginx     | 3000 |
| backend  | ASP.NET Core 8 (Minimal API), EF Core | 8080 |
| db       | PostgreSQL 16                      | —    |

Тести: `backend/BoardGames.Tests` (xUnit, EF Core InMemory).

## Запуск (Docker)

```bash
cp .env.example .env     # за потреби змінити пароль
docker compose up --build
```

- Застосунок: http://localhost:3000
- API: http://localhost:8080/api/games
- Health: http://localhost:8080/api/health

Зупинити: `docker compose down` (разом з даними: `docker compose down -v`).

## Тести

```bash
cd backend
dotnet test BoardGames.Tests
```

## Локальна розробка без Docker

```bash
# БД
docker compose up db -d
# backend
cd backend/BoardGames.Api && dotnet run
# frontend
cd frontend && npm install && npm run dev
```

## CI/CD (GitHub Actions)

Пайплайн `.github/workflows/ci.yml` запускається на кожен push і на кожен Pull Request у `main`.

| Job | Що робить |
|-----|-----------|
| `backend` | restore → build → `dotnet format` (лінт) → xUnit тести (кеш NuGet) |
| `frontend` | `npm ci` → ESLint → Vitest → build (кеш npm) |
| `images` | збірка Docker-образів (matrix) → Trivy-скан; потребує успіху `backend` і `frontend` |
| `publish` | лише для push: публікація в `ghcr.io` з тегами `sha-<commit>` та `latest` (тільки `main`) |

Запуск із опублікованих образів: `docker compose -f docker-compose.registry.yml up`.
