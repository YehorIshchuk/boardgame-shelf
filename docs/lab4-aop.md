# Лабораторна робота №4 — AOP

Три пари «власна анотація + аспект». Кожна реалізує реальну наскрізну задачу коворкінгу
і застосована в робочому коді. Плюс навмисна демонстрація проблеми самовиклику.

| Анотація | Аспект і тип advice | Наскрізна задача | Що видно | Де застосована |
|---|---|---|---|---|
| `@RateLimited(maxCalls, windowSeconds)` | `RateLimitAspect`, **@Around** | Захист від спаму: не більше 10 бронювань за 60 с на користувача (ковзне вікно) | Виняток → **429** + `Retry-After`, `proceed()` не викликається | `BookingService.create` |
| `@Audited(action)` | `AuditAspect`, **@AfterReturning** | Журнал аудиту бізнес-дій у БД: хто, що, над яким об'єктом, коли. Лише успішні дії | Запис у таблиці `audit_event`, перегляд `GET /api/admin/audit` | `BookingService.confirm / cancel / delete`, `WorkspaceService.create / update / delete` |
| `@SlaMonitored(thresholdMs)` | `SlaAspect`, **@Around** | Моніторинг SLA: кількість викликів, середній і максимальний час, перевищення порогу, падіння | Статистика `GET /api/admin/sla` + WARN у лозі при перевищенні | `BookingService.create / findVisible`, `WorkspaceService.findAll` |

Пакет: `src/main/java/ua/lab/coworking/aop/` (`ratelimit/`, `audit/`, `sla/`, `AopConfig`).
Таблицю `audit_event` створює Liquibase changeset `004-create-audit-event.yaml`.
Залежність: `spring-boot-starter-aop` (проксі вмикає `AopAutoConfiguration`).

---

## Сценарій 1. Анотація правильно пов'язана з аспектом

Усі три анотації мають `@Retention(RetentionPolicy.RUNTIME)` і `@Target(ElementType.METHOD)`.
Без `RUNTIME` анотації не було б у байткоді під час виконання, і pointcut її не побачив би.

Pointcut'и використовують `@annotation(...)` з прив'язкою параметра, тож advice одразу отримує атрибути анотації:
```java
@Around("@annotation(rateLimited)")
public Object enforce(ProceedingJoinPoint joinPoint, RateLimited rateLimited)

@AfterReturning(pointcut = "@annotation(audited)", returning = "result")
public void record(JoinPoint joinPoint, Audited audited, Object result)

@Around("@annotation(slaMonitored)")
public Object measure(ProceedingJoinPoint joinPoint, SlaMonitored slaMonitored)
```

## Сценарії 2–3. Поведінка спрацьовує при зовнішньому виклику

Виклик з іншого біна (контролер → `BookingService`) проходить через Spring-проксі, і advice виконується:

| Аспект | Як побачити | Тест |
|---|---|---|
| `@Audited` | `POST /api/bookings/{id}/confirm`, потім у `GET /api/admin/audit` з'являється `BOOKING_CONFIRMED` (колекція L4.2–L4.3) | `AopIntegrationTest.audited_externalCallThroughProxy_recordsAuditEvent` |
| `@RateLimited` | 11-те бронювання за хвилину дає **429** (скрипт нижче) | `AopIntegrationTest.rateLimited_eleventhBookingWithinMinute_isRejectedWith429` |
| `@SlaMonitored` | `GET /api/admin/sla` показує статистику (L4.8) | `AopIntegrationTest.slaMonitored_callsAreCountedInAdminStats` |

`AopIntegrationTest.bookingService_injectedBean_isAopProxy` підтверджує, що в контролер інжектується саме проксі.

## Сценарій 4. Самовиклик НЕ активує аспект (свідомий задум вправи)

Той самий метод `BookingService.confirm(Long id)` з `@Audited` викликається двома способами:

```
1) ЗОВНІШНІЙ:  BookingController ──► [проксі BookingService] ──► AuditAspect ──► confirm()   ✅ запис аудиту є
2) САМОВИКЛИК: BookingController ──► [проксі] ──► confirmAllPending()
                                                      └──► this.confirm(id)               ❌ запису немає
```

`confirmAllPending(workspaceId)` (`POST /api/bookings/confirm-pending?workspaceId=…`) підтверджує всі PENDING-бронювання місця
через `this.confirm(id)`. `this` — це сам об'єкт сервісу, а не проксі, тому Spring не має де втрутитися.
Бронювання підтверджуються, помилок немає, але запису `BOOKING_CONFIRMED` в аудиті не з'являється.

- Вручну: колекція L4.4 → L4.7 (порівняйте з L4.1 → L4.3).
- Тест: `AopIntegrationTest.audited_selfInvocationViaThis_confirmsBookingsButRecordsNoAuditEvent`. Він перевіряє, що статус `CONFIRMED`, а записів аудиту для цих бронювань немає.

Це **не виправляється** — так задумано у вправі. У реальному проєкті виправлення таке: винести `confirm` в інший бін
або викликати його через самоін'єкцію проксі (`@Lazy BookingService self` → `self.confirm(id)`).

## Сценарій 5. Advice перевіряється unit-тестом (mock `ProceedingJoinPoint`, без Spring)

| Тест | Що перевіряє в логіці advice |
|---|---|
| `RateLimitAspectTest` (8 тестів) | Під лімітом `proceed()` викликається і результат повертається. Ліміт досягнуто — виняток, `proceed()` **не** викликається (`verify(..., never())`). Вікно минуло — знову дозволено. Різні користувачі мають окремі ліміти. Точне повідомлення і `retryAfter`. Виняток методу не ковтається |
| `SlaAspectTest` (5 тестів) | Результат повертається без змін. Повільний виклик рахується як порушення. Рівно поріг — не порушення (межа). Виняток прокидається той самий і рахується як падіння. Середнє й максимум |
| `AuditAspectTest` (6 тестів) | Який запис формується (`ArgumentCaptor<AuditEvent>`): дія, автор, `targetId` з аргументу або з результату, час, `system` без автентифікації |

«Тривалість» і час задає керований годинник `MutableClock`, тож у тестах немає `Thread.sleep` і реального часу.

---

## Порядок аспектів (знайдена під час лаби проблема)

`RateLimitAspect` має `@Order(0)`, тому виконується раніше за `@PreAuthorize` (порядок 200) і `@Transactional`
(LOWEST_PRECEDENCE). Спочатку я поставив `@Order(Ordered.HIGHEST_PRECEDENCE)`, і кожен виклик `create` падав з помилкою
*Required to bind 2 arguments, but only bound 1 (JoinPointMatch was NOT bound in invocation)*.
Причина: службовий `ExposeInvocationInterceptor`, який Spring ставить першим у ланцюжок (порядок `HIGHEST_PRECEDENCE + 1`),
публікує дані поточного виклику, потрібні для прив'язки параметра `@annotation(rateLimited)`. Аспект із `HIGHEST_PRECEDENCE`
опинявся ще перед ним, і прив'язати параметр було нічим. Висновок: власні аспекти не можна ставити на `HIGHEST_PRECEDENCE`.

## Демонстрація 429 з терміналу

Отримайте токен користувача і надішліть 11 бронювань поспіль (різні дні, щоб не було конфлікту часу):

```bash
TOKEN=$(curl -s -X POST http://localhost:8180/realms/coworking/protocol/openid-connect/token \
  -d grant_type=password -d client_id=coworking-app -d client_secret=coworking-secret \
  -d username=user2 -d password=user2 | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

for day in $(seq 10 20); do
  curl -s -o /dev/null -w "день $day -> %{http_code}\n" -X POST http://localhost:8081/api/bookings \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "{\"workspaceId\":3,\"startTime\":\"2030-10-${day}T10:00:00\",\"endTime\":\"2030-10-${day}T11:00:00\"}"
done
```

Перші 10 запитів повертають `201`, 11-й — `429`. Через хвилину ліміт знову звільняється.
Під час повторного запуску змініть місяць (`2030-11-…`), інакше отримаєте `409` через уже наявні бронювання.

## Як перевірити

```bash
mvn clean verify                                 # усі тести, включно з AopIntegrationTest
mvn clean verify -DexcludedGroups=integration    # лише unit-тести + поріг покриття 60%
```
