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

## Helm-чарт (ЛР №4)

Чарт [`chart/boardgame-shelf/`](chart/boardgame-shelf/) описує той самий застосунок, що й маніфести з `k8s/`, але параметризований і придатний для кількох середовищ.

```
chart/boardgame-shelf/
├── Chart.yaml                  name, description, version, appVersion
├── values.yaml                 значення за замовчуванням (= dev)
├── values-dev.yaml             середовище розробки
├── values-prod.yaml            продакшн-подібне середовище
└── templates/
    ├── _helpers.tpl            іменовані шаблони: імена об'єктів, мітки, образ, пароль БД
    ├── NOTES.txt               інструкція після встановлення
    ├── configmap.yaml          ConfigMap застосунку
    ├── secret.yaml             Secret БД (значення з values)
    ├── postgres-pvc.yaml       PVC (database.persistence.enabled)
    ├── postgres-deployment.yaml
    ├── postgres-service.yaml
    ├── backend-deployment.yaml
    ├── backend-service.yaml
    ├── frontend-configmap.yaml конфіг nginx з адресою backend цього релізу
    ├── frontend-deployment.yaml
    ├── frontend-service.yaml
    ├── ingress.yaml            Ingress (ingress.enabled)
    ├── hooks/pre-upgrade-db-check.yaml   хук pre-upgrade
    └── tests/test-app.yaml     тест релізу (helm test)
```

### version і appVersion

- **`version: 0.1.0`** — версія **чарта**: шаблонів, `values.yaml`, хуків. Підвищується щоразу, коли змінюється пакування (новий параметр, новий об'єкт, виправлення шаблону), навіть якщо застосунок той самий. Саме ця версія потрапляє в ім'я пакета `boardgame-shelf-0.1.0.tgz` і в мітку `helm.sh/chart`.
- **`appVersion: "1.0.0"`** — версія **застосунку** BoardGame Shelf, тобто тег Docker-образів `boardgame-shelf-backend` і `boardgame-shelf-frontend` за замовчуванням (якщо `backend.image.tag` / `frontend.image.tag` порожні). Відповідає git-тегу `v1.0.0`, з якого CI публікує образи.

Тобто вихід нової версії застосунку `1.2.0` — це зміна `appVersion` (і, за правилами SemVer для чарта, мінорне підвищення `version`), а, наприклад, додавання прапорця `ingress.enabled` без зміни коду — лише зміна `version`.

### Параметри values

| Параметр | За замовчуванням (dev) | prod | Опис |
|----------|------------------------|------|------|
| `image.registry` | `ghcr.io/yehorishchuk` | — | реєстр образів застосунку |
| `image.pullPolicy` | `IfNotPresent` | — | політика завантаження образів |
| `rollingUpdate.maxSurge` / `maxUnavailable` | `1` / `0` | — | стратегія оновлення backend і frontend |
| `config.aspnetEnvironment` | `Development` | `Production` | `ASPNETCORE_ENVIRONMENT` |
| `config.clubName` | `Кубик і Ко (dev)` | `Кубик і Ко` | назва клубу (`App__ClubName`) |
| `config.maxBorrowDays` | `14` | — | строк видачі гри (`App__MaxBorrowDays`) |
| `config.logLevel` | `Debug` | `Warning` | рівень логування backend |
| `database.replicaCount` | `1` | — | лише 0 або 1 |
| `database.name` | `boardgames` | — | назва БД |
| `database.auth.username` | `shelf_app` | — | користувач БД (Secret) |
| `database.auth.password` | `dev-only-not-a-secret` | порожньо | пароль БД (Secret); порожньо — згенерувати й зберігати між оновленнями |
| `database.image.repository` / `tag` | `postgres` / `16-alpine` | — | образ PostgreSQL |
| `database.service.port` | `5432` | — | порт Service БД |
| `database.persistence.enabled` | `true` | — | PVC або emptyDir |
| `database.persistence.size` | `1Gi` | `2Gi` | розмір PVC |
| `database.persistence.storageClass` | `""` | — | StorageClass (порожньо — за замовчуванням) |
| `database.persistence.keep` | `false` | — | не видаляти PVC при `helm uninstall` |
| `database.resources` | 50m/128Mi — 500m/256Mi | 100m/256Mi — 1/512Mi | ресурси PostgreSQL |
| `backend.replicaCount` | `1` | `3` | репліки API |
| `backend.image.repository` | `boardgame-shelf-backend` | — | образ API |
| `backend.image.tag` | `""` → appVersion (`1.0.0` у values-dev) | `1.1.0` | тег образу API |
| `backend.service.type` / `port` | `ClusterIP` / `8080` | — | Service API |
| `backend.resources` | 50m/96Mi — 500m/256Mi | 100m/160Mi — 1/384Mi | ресурси API |
| `frontend.replicaCount` | `1` | `2` | репліки nginx |
| `frontend.image.repository` | `boardgame-shelf-frontend` | — | образ frontend |
| `frontend.image.tag` | `""` → appVersion (`1.0.0` у values-dev) | `1.1.0` | тег образу frontend |
| `frontend.service.type` | `NodePort` | `ClusterIP` | тип Service frontend |
| `frontend.service.port` | `80` | — | порт Service frontend |
| `frontend.service.nodePort` | `""` (вибирає Kubernetes) | — | фіксований NodePort |
| `frontend.resources` | 25m/32Mi — 200m/64Mi | 50m/48Mi — 300m/96Mi | ресурси frontend |
| `ingress.enabled` | `false` | `true` | створювати Ingress |
| `ingress.className` | `nginx` | — | IngressClass |
| `ingress.host` | `boardgames-dev.local` | `boardgames.local` | хост Ingress |
| `ingress.annotations` | `{}` | — | анотації Ingress |
| `hooks.preUpgradeDbCheck.enabled` | `true` | — | хук перевірки БД перед `helm upgrade` |
| `tests.enabled` / `tests.image` | `true` / `busybox:1.36` | — | тест релізу |
| `nameOverride` / `fullnameOverride` | `""` | — | перевизначення імен |

### Встановлення

Helm 3 (macOS, Apple Silicon):

```bash
curl -fsSLO https://get.helm.sh/helm-v3.21.3-darwin-arm64.tar.gz
tar -xzf helm-v3.21.3-darwin-arm64.tar.gz
sudo install darwin-arm64/helm /usr/local/bin/helm
helm version
```

**dev:**

```bash
helm install shelf chart/boardgame-shelf -n boardgame-dev --create-namespace \
  -f chart/boardgame-shelf/values-dev.yaml --wait
```

**prod:**

```bash
helm install shelf chart/boardgame-shelf -n boardgame-prod --create-namespace \
  -f chart/boardgame-shelf/values-prod.yaml --wait
# власний пароль замість згенерованого:
#   --set database.auth.password='...'
```

Перевірка, оновлення, відкат, видалення:

```bash
helm lint chart/boardgame-shelf -f chart/boardgame-shelf/values-prod.yaml
helm template shelf chart/boardgame-shelf -f chart/boardgame-shelf/values-prod.yaml   # без встановлення
helm test shelf -n boardgame-dev --logs
helm upgrade shelf chart/boardgame-shelf -n boardgame-dev -f chart/boardgame-shelf/values-dev.yaml --set backend.image.tag=1.1.0
helm history shelf -n boardgame-dev
helm rollback shelf 1 -n boardgame-dev
helm uninstall shelf -n boardgame-dev
```

Імена всіх об'єктів будуються з імені релізу (`<release>-boardgame-shelf-backend` тощо), а NodePort за замовчуванням обирає Kubernetes, тому чарт можна встановити двічі навіть в один namespace.

### Пріоритет значень

Від найнижчого до найвищого:

1. `values.yaml` чарта;
2. файли `-f` / `--values` — у порядку, в якому вказані (наступний перекриває попередній);
3. `--set` / `--set-string` — найвищий пріоритет.

Значення зливаються по ключах: у `values-prod.yaml` достатньо вказати лише те, що відрізняється від `values.yaml`. Приклад: `-f values-prod.yaml --set backend.replicaCount=5` дасть 5 реплік і решту параметрів із prod.

### Відмінності від маніфестів ЛР №3

- **Namespace** не є частиною чарта — його створює `helm install -n <ns> --create-namespace` (рекомендація Helm: чарт не керує namespace, у який встановлюється).
- **ConfigMap `…-frontend-nginx`** — новий об'єкт: в образі frontend адреса API прописана як `http://backend:8080`, а в чарті ім'я Service backend залежить від імені релізу, тому конфіг nginx генерується шаблоном і монтується поверх файлу з образу.
- Мітки розширено стандартними `helm.sh/chart`, `app.kubernetes.io/instance`, `managed-by`; селектори містять `instance`, тож два релізи не «бачать» подів один одного.
- Під поди додано анотації `checksum/config` і `checksum/secret`: зміна ConfigMap чи Secret через `helm upgrade` автоматично перезапускає backend.

### Хук і тест (завдання 9b)

- **`hooks/pre-upgrade-db-check.yaml`** — Job з хуком `pre-upgrade`: перед кожним `helm upgrade` перевіряє `pg_isready` і друкує кількість ігор у БД. Якщо PostgreSQL недоступна, Job падає і Helm скасовує оновлення (ревізія отримує статус `failed`, об'єкти не змінюються). Після успіху Job видаляється (`hook-delete-policy: hook-succeeded`).
- **`tests/test-app.yaml`** — под з хуком `test`: проходить ланцюжок frontend → backend → PostgreSQL (`/healthz`, `/api/ready`, `/api/info`, `/api/games`) і перевіряє, що розгорнута очікувана версія backend. Запуск: `helm test <release> -n <ns> --logs`.

### Де Helm зберігає стан

У namespace релізу, у Secret типу `helm.sh/release.v1` з іменем `sh.helm.release.v1.<release>.v<ревізія>` (окремий Secret на кожну ревізію, мітка `owner=helm`). Усередині — base64(gzip(JSON)) з маніфестами, значеннями й статусом ревізії; на цьому базуються `helm history` і `helm rollback`.

### Демонстрація (ЛР №4)

[`scripts/lab4-demo.sh`](scripts/lab4-demo.sh) проходить пункти 1, 6–9 і зберігає вивід у `report/lab4-output/`:

```bash
./scripts/lab4-demo.sh              # усе по черзі
./scripts/lab4-demo.sh lifecycle    # окремий етап: prep | render | install | twice | lifecycle | extra
```

Звіт: [`report/LAB4-REPORT.md`](report/LAB4-REPORT.md).
