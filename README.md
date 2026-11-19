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
| `publish` | лише для push: публікація в `ghcr.io` з тегами `sha-<commit>`, `latest` (тільки `main`) та `X.Y.Z` (для git-тегів `vX.Y.Z`) |

Запуск із опублікованих образів: `docker compose -f docker-compose.registry.yml up`.

## Kubernetes (minikube)

Маніфести лежать у [`k8s/`](k8s/), по одному файлу на об'єкт. Усі об'єкти створюються в namespace `boardgame-shelf`.

```
k8s/
├── 00-namespace.yaml            Namespace boardgame-shelf
├── 01-configmap.yaml            ConfigMap boardgame-config
├── 02-secret.yaml               Secret boardgame-db-secret
├── 10-postgres-pvc.yaml         PersistentVolumeClaim postgres-data (1Gi)
├── 11-postgres-deployment.yaml  Deployment postgres (1 репліка, Recreate)
├── 12-postgres-service.yaml     Service postgres (ClusterIP :5432)
├── 20-backend-deployment.yaml   Deployment backend (2 репліки, RollingUpdate)
├── 21-backend-service.yaml      Service backend (ClusterIP :8080)
├── 30-frontend-deployment.yaml  Deployment frontend (2 репліки, RollingUpdate)
├── 31-frontend-service.yaml     Service frontend (NodePort 30080)
└── 40-ingress.yaml              Ingress boardgames.local -> frontend
```

```
браузер ─► Ingress (boardgames.local) / NodePort 30080
              └─► Service frontend ─► nginx (2 поди) ── /api/ ──► Service backend ─► ASP.NET (2 поди)
                                                                                  └─► Service postgres ─► PostgreSQL + PVC
```

### 1. Образи

Використовуються образи `ghcr.io/yehorishchuk/boardgame-shelf-{backend,frontend}` з тегами версій `1.0.0` і `1.1.0` (тег `latest` у маніфестах не використовується). Версія вшивається в образ через `--build-arg APP_VERSION` і видна в `/api/info` та у футері сторінки.

**Варіант А — GHCR через CI:**

```bash
git tag v1.0.0 && git push origin v1.0.0
# ... зміни ...
git tag v1.1.0 && git push origin v1.1.0
```

Пакети в GHCR мають бути публічними (Package settings → Change visibility), інакше кластер не зможе їх завантажити.

**Варіант Б — локально, одразу в minikube:**

```bash
./scripts/build-images.sh 1.0.0
./scripts/build-images.sh 1.1.0
```

Маніфести мають `imagePullPolicy: IfNotPresent`, тому працюють з обома варіантами без змін.

### 2. Кластер

На macOS (Apple Silicon) з Colima: VM Colima має мати запас пам'яті під minikube.

```bash
brew install minikube kubectl
colima stop && colima start --cpu 4 --memory 6     # якщо Colima запущена з меншими ресурсами
```

```bash
minikube start --driver=docker --cpus=2 --memory=3072
minikube addons enable metrics-server
minikube addons enable ingress
kubectl get nodes
kubectl get pods -n kube-system
```

### 3. Розгортання (одна команда)

```bash
kubectl apply -f k8s/
kubectl -n boardgame-shelf get pods,deploy,rs,svc,ingress,pvc
```

Відкрити застосунок:

- **port-forward (працює на будь-якій ОС):** `kubectl -n boardgame-shelf port-forward svc/frontend 8081:80` → http://localhost:8081;
- **NodePort:** `minikube service frontend -n boardgame-shelf` (на macOS/Windows команда тримає тунель, не закривайте термінал);
- **Ingress:** додати в hosts-файл `$(minikube ip) boardgames.local` (Linux) або `127.0.0.1 boardgames.local` + запущений `minikube tunnel` (macOS/Windows) і відкрити http://boardgames.local.

Видалити все: `kubectl delete namespace boardgame-shelf`.

### Параметри ConfigMap `boardgame-config`

Підключаються до backend через `envFrom` (ASP.NET Core читає `App__ClubName` як `App:ClubName`).

| Ключ | Значення | Де використовується |
|------|----------|---------------------|
| `ASPNETCORE_ENVIRONMENT` | `Production` | режим ASP.NET Core |
| `App__ClubName` | `Кубик і Ко` | назва клубу в заголовку сторінки та `/api/info` |
| `App__MaxBorrowDays` | `14` | строк видачі гри, показується у футері та `/api/info` |
| `Logging__LogLevel__Default` | `Information` | рівень логування backend |
| `POSTGRES_HOST` | `postgres` | ім'я Service БД, частина рядка підключення |
| `POSTGRES_PORT` | `5432` | порт БД, частина рядка підключення |
| `POSTGRES_DB` | `boardgames` | назва БД (backend і контейнер postgres) |

### Параметри Secret `boardgame-db-secret`

| Ключ | Де використовується |
|------|---------------------|
| `POSTGRES_USER` | користувач БД — створюється контейнером postgres, використовується backend |
| `POSTGRES_PASSWORD` | пароль БД — те саме |

Рядок підключення `ConnectionStrings__Default` збирається в Deployment backend з ConfigMap і Secret через підстановку `$(VAR)`. Значення в `02-secret.yaml` навчальні; для реального середовища Secret створюють поза репозиторієм (`kubectl create secret generic ... --from-literal`), а не комітять.

Зміни ConfigMap/Secret не перезапускають поди автоматично: після редагування виконайте `kubectl -n boardgame-shelf rollout restart deploy/backend`.

### Проби і ресурси

| Компонент | startup | liveness | readiness | requests / limits |
|-----------|---------|----------|-----------|-------------------|
| backend | `GET /api/health` (до 60 с) | `GET /api/health` | `GET /api/ready` (перевіряє з'єднання з БД) | 100m/128Mi — 500m/256Mi |
| frontend | — | `GET /healthz` | `GET /healthz` | 50m/32Mi — 200m/64Mi |
| postgres | — | `pg_isready` | `pg_isready` | 100m/256Mi — 500m/512Mi |

Оновлення backend і frontend — `RollingUpdate` з `maxSurge: 1`, `maxUnavailable: 0` та `preStop: sleep 5`, тому під час заміни образу застосунок лишається доступним.

### Демонстрація (ЛР №3)

[`scripts/lab3-demo.sh`](scripts/lab3-demo.sh) проходить пункти 2 і 5–7 (розгортання, ConfigMap/Secret у контейнері, самовідновлення, масштабування, rolling update під навантаженням, історія і відкат, ImagePullBackOff і виправлення) та зберігає вивід кожної команди в `report/output/`:

```bash
./scripts/lab3-demo.sh              # усе по черзі, з паузами для скриншотів
./scripts/lab3-demo.sh lifecycle    # окремий етап: cluster | deploy | lifecycle | diagnose
```

Звіт: [`report/REPORT.md`](report/REPORT.md).
