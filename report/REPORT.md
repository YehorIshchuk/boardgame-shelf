# Звіт з лабораторної роботи №3

**Тема:** Розгортання власного застосунку в Kubernetes
**Студент:** _ПІБ, група_
**Проєкт:** BoardGame Shelf (React + nginx, ASP.NET Core 8, PostgreSQL 16)
**Репозиторій:** https://github.com/YehorIshchuk/boardgame-shelf

Вивід усіх команд збережено скриптом `scripts/lab3-demo.sh` у каталозі [`output/`](output/). Скриншоти — у [`screenshots/`](screenshots/).

## 1. Образи

| Образ | Теги |
|-------|------|
| `ghcr.io/yehorishchuk/boardgame-shelf-backend` | `1.0.0`, `1.1.0` |
| `ghcr.io/yehorishchuk/boardgame-shelf-frontend` | `1.0.0`, `1.1.0` |

Спосіб публікації: _GHCR через CI (git-теги v1.0.0, v1.1.0) / `minikube image load`_.
Версія вшита в образ (`APP_VERSION`) і повертається ендпоінтом `/api/info`.

## 2. Кластер

Вивід: [`output/01-cluster.txt`](output/01-cluster.txt) — `kubectl get nodes`, поди `kube-system`, увімкнені доповнення `metrics-server` та `ingress`.

![nodes](screenshots/01-cluster.png)

## 3–4. Namespace і маніфести

Namespace `boardgame-shelf`. Маніфести — каталог [`k8s/`](../k8s/), по одному файлу на об'єкт: Namespace, ConfigMap, Secret, PVC, 3 Deployment, 3 Service, Ingress. Опис параметрів ConfigMap і Secret — у [README](../README.md#параметри-configmap-boardgame-config).

## 5. Розгортання

**a, b.** `kubectl apply -f k8s/` та перелік об'єктів (поди, Deployment, ReplicaSet, Service, Ingress, PVC): [`output/02-deploy.txt`](output/02-deploy.txt).

**c.** Застосунок у браузері (http://boardgames.local) — у футері видно версію і под backend:

![app](screenshots/02-browser.png)

**d.** Значення з ConfigMap і Secret у контейнері: [`output/03-config.txt`](output/03-config.txt) — змінні оточення в поді backend, довжина пароля збігається з Secret, `/api/info` повертає `clubName`, `maxBorrowDays`, `dbUser` і `dbPasswordSet: true`.

## 6. Керування життєвим циклом

| Пункт | Що показано | Вивід |
|-------|-------------|-------|
| a. Самовідновлення | под видалено, ReplicaSet створив новий | [`04-self-healing.txt`](output/04-self-healing.txt) |
| b. Масштабування | 2 → 4 репліки, 40 запитів розподілились між подами | [`05-scaling.txt`](output/05-scaling.txt) |
| c. Rolling update | `1.0.0` → `1.1.0`, нові ReplicaSet, Events деплойменту | [`06-rolling-update.txt`](output/06-rolling-update.txt) |
| d. Історія і відкат | `rollout history`, `rollout undo` → знову `1.0.0` | [`07-rollback.txt`](output/07-rollback.txt) |
| e. Доступність | запити кожні 0,3 с під час оновлення: _N_ успішних, _0_ невдалих | [`06-availability.log`](output/06-availability.log) |

## 7. Діагностика

Вивід: [`output/08-diagnostics.txt`](output/08-diagnostics.txt).

- **a.** Тег `9.9.9-does-not-exist` → под у стані `ImagePullBackOff`; старі поди продовжують працювати завдяки `maxUnavailable: 0`.
- **b.** `kubectl describe pod` і Events: `Failed to pull image ... not found` → причина — неіснуючий тег.
- **c.** `kubectl logs` і інтерактивний вхід `kubectl exec -it ... -- /bin/sh` (скриншот нижче).
- **d.** Повернуто робочий образ, `rollout status` успішний, усі поди `Running`.

![exec](screenshots/03-exec.png)

## Висновки

_2–4 речення: що дають Deployment/ReplicaSet (самовідновлення, масштабування), як readiness-проби та `maxUnavailable: 0` забезпечують оновлення без простою, як ConfigMap і Secret відокремлюють конфігурацію від образу._
