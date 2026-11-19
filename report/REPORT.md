# Звіт з лабораторної роботи №3

**Тема:** Розгортання власного застосунку в Kubernetes
**Студент:** Прізвище Ім'я, група XX-00
**Проєкт:** BoardGame Shelf (React + nginx, ASP.NET Core 8, PostgreSQL 16)
**Репозиторій:** https://github.com/YehorIshchuk/boardgame-shelf

**Середовище:** MacBook Air (Apple M1), Colima (Docker runtime, 4 CPU / 6 GB), minikube v1.39.0 (драйвер docker), Kubernetes v1.37.0, kubectl v1.37.2.

Вивід усіх команд збережено скриптом `scripts/lab3-demo.sh` у каталозі [`output/`](output/). Скриншоти — у [`screenshots/`](screenshots/).

## 1. Образи

| Образ | Теги | Архітектури |
|-------|------|-------------|
| `ghcr.io/yehorishchuk/boardgame-shelf-backend` | `1.0.0`, `1.1.0` | linux/amd64, linux/arm64 |
| `ghcr.io/yehorishchuk/boardgame-shelf-frontend` | `1.0.0`, `1.1.0` | linux/amd64, linux/arm64 |

Публікація — через GitHub Actions: git-теги `v1.0.0` і `v1.1.0` запускають job `publish`, який збирає образи з `--build-arg APP_VERSION=<версія>` і пушить їх у GHCR з тегами `X.Y.Z` та `X.Y`. Тег `latest` у маніфестах не використовується. Версія образу видна в `/api/info` та у футері сторінки.

## 2. Кластер

Вивід: [`output/01-cluster.txt`](output/01-cluster.txt). Вузол `minikube` у стані `Ready`, усі поди `kube-system` — `1/1 Running`, увімкнені доповнення `metrics-server` та `ingress` (контролер `ingress-nginx` готовий).

![Кластер](screenshots/01-cluster.png)

## 3–4. Namespace і маніфести

Namespace `boardgame-shelf`. Маніфести — каталог [`k8s/`](../k8s/), по одному файлу на об'єкт:

| Файл | Об'єкт |
|------|--------|
| `00-namespace.yaml` | Namespace |
| `01-configmap.yaml` | ConfigMap `boardgame-config` (7 параметрів) |
| `02-secret.yaml` | Secret `boardgame-db-secret` (користувач і пароль БД) |
| `10-postgres-pvc.yaml` | PersistentVolumeClaim 1Gi |
| `11-postgres-deployment.yaml` | Deployment PostgreSQL (1 репліка, Recreate) |
| `12-postgres-service.yaml` | Service ClusterIP :5432 |
| `20-backend-deployment.yaml` | Deployment API (2 репліки, requests/limits, startup/liveness/readiness) |
| `21-backend-service.yaml` | Service ClusterIP :8080 |
| `30-frontend-deployment.yaml` | Deployment nginx + React (2 репліки, requests/limits, liveness/readiness) |
| `31-frontend-service.yaml` | Service NodePort 30080 |
| `40-ingress.yaml` | Ingress `boardgames.local` → frontend |

Опис параметрів ConfigMap і Secret — у [README](../README.md#параметри-configmap-boardgame-config).

## 5. Розгортання

**a, b.** `kubectl apply -f k8s/` створює всі 11 об'єктів однією командою; перелік подів, Deployment, ReplicaSet, Service, Ingress і PVC — [`output/02-deploy.txt`](output/02-deploy.txt).

**c.** Застосунок відкрито в браузері через `kubectl port-forward svc/frontend 8081:80` (http://localhost:8081). Додавання ігор працює, дані зберігаються в PostgreSQL. У заголовку — назва клубу з ConfigMap, у футері — `web v1.0.0 · API v1.0.0 · под backend-7cbc7b86c5-n9jxt · видача до 14 дн.`

![Застосунок](screenshots/02-browser.png)

**d.** Значення з ConfigMap і Secret у контейнері ([`output/03-config.txt`](output/03-config.txt)):

- `printenv` у поді backend показує `App__ClubName=Кубик і Ко`, `App__MaxBorrowDays=14`, `POSTGRES_HOST=postgres`, `POSTGRES_USER=shelf_app` та інші;
- довжина `POSTGRES_PASSWORD` у контейнері (19) збігається з довжиною значення в Secret (19), сам пароль не виводиться;
- `/api/info` повертає `"clubName":"Кубик і Ко","maxBorrowDays":14,"dbHost":"postgres","dbUser":"shelf_app","dbPasswordSet":true` — застосунок справді використовує ці значення.

## 6. Керування життєвим циклом

| Пункт | Результат | Вивід |
|-------|-----------|-------|
| a. Самовідновлення | под `backend-7cbc7b86c5-gt75k` видалено; ReplicaSet одразу створив `backend-7cbc7b86c5-kbl9d` (подія `SuccessfulCreate`), кількість реплік відновилась до 2 | [`04-self-healing.txt`](output/04-self-healing.txt) |
| b. Масштабування | `kubectl scale --replicas=4`; 40 запитів до Service `backend` розподілились між подами 10 / 6 / 15 / 9 | [`05-scaling.txt`](output/05-scaling.txt) |
| c. Rolling update | `kubectl set image` → `1.1.0`; у Events деплойменту нова ReplicaSet `backend-5d48845d4` поступово зростає 0→4, а стара `backend-7cbc7b86c5` зменшується 4→0 по одному поду (`maxSurge: 1`, `maxUnavailable: 0`) | [`06-rolling-update.txt`](output/06-rolling-update.txt) |
| d. Історія і відкат | `rollout history` показує ревізії з `change-cause`; `rollout undo` повернув обидва Deployment до `1.0.0` (ревізія 1 стала ревізією 3) | [`07-rollback.txt`](output/07-rollback.txt) |
| e. Доступність | окремий под надсилав запит через frontend → backend кожні 0,3 с під час оновлення: **151 успішний запит, 0 невдалих**; у лозі видно, як відповіді поступово переходять з `1.0.0` на `1.1.0` | [`06-availability.log`](output/06-availability.log) |

Доступність під час оновлення забезпечують readiness-проба `/api/ready` (под отримує трафік лише після підключення до БД), `maxUnavailable: 0` та `preStop: sleep 5` (под встигає зникнути з endpoints до зупинки процесу).

## 7. Діагностика

Вивід: [`output/08-diagnostics.txt`](output/08-diagnostics.txt).

- **a.** `kubectl set image ... :9.9.9-does-not-exist` → новий под `backend-6fc9f9dc45-hs92k` у стані `ImagePullBackOff`, `rollout status` не завершується. Два старі поди лишились `Running` (завдяки `maxUnavailable: 0`), застосунок відповідав `{"status":"ok"}`.
- **b.** `kubectl describe pod` та Events: `Failed to pull image "ghcr.io/yehorishchuk/boardgame-shelf-backend:9.9.9-does-not-exist": ... not found`, далі `ErrImagePull` → `Back-off pulling image` → `ImagePullBackOff`. Причина — неіснуючий тег образу.
- **c.** `kubectl logs` показує запити проб `/api/health` і `/api/ready` з кодом 200. Інтерактивний вхід `kubectl exec -it ... -- /bin/sh`: `hostname` збігається з іменем пода, `env | grep App__` показує значення з ConfigMap, `ls /app` — зібраний застосунок.
- **d.** `kubectl set image ... :1.0.0` → `rollout status` успішний, поди `Running`, ReplicaSet з поганим тегом зменшено до 0. Історія: ревізії `update to 1.1.0`, `broken tag 9.9.9-does-not-exist`, `fix: back to 1.0.0`.

![Вхід у контейнер](screenshots/03-exec.png)

## Розгортання з нуля

`kubectl delete namespace boardgame-shelf`, потім `kubectl apply -f k8s/` — усі 5 подів (postgres, 2 × backend, 2 × frontend) перейшли в `1/1 Running` приблизно за 10 секунд. Застосунок розгортається на чистому кластері однією командою з каталогу `k8s/`.

## Висновки

Застосунок BoardGame Shelf описано набором декларативних маніфестів і розгорнуто в minikube однією командою. Deployment і ReplicaSet автоматично відновлюють видалені поди та дозволяють масштабувати сервіс, а Service розподіляє трафік між репліками. Readiness-проби разом зі стратегією `RollingUpdate` (`maxUnavailable: 0`) дали змогу оновити застосунок і відкотити його без жодного невдалого запиту, а при помилковому тезі образу старі поди продовжили обслуговувати користувачів. ConfigMap і Secret відокремлюють конфігурацію та облікові дані від образу, тож один і той самий образ можна запускати з різними налаштуваннями.

Відоме обмеження: контейнер backend працює від користувача root (`uid=0`); у продакшн-середовищі варто додати `securityContext.runAsNonRoot: true` або `USER app` у Dockerfile.
