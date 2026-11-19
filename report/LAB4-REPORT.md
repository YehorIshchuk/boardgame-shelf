# Звіт з лабораторної роботи №4

**Тема:** Пакування застосунку в Helm-чарт
**Студент:** _ПІБ, група_
**Проєкт:** BoardGame Shelf (React + nginx, ASP.NET Core 8, PostgreSQL 16)
**Репозиторій:** https://github.com/YehorIshchuk/boardgame-shelf

**Середовище:** MacBook Air (Apple M1), Colima, minikube (драйвер docker), Helm _версія_.

Чарт: [`chart/boardgame-shelf/`](../chart/boardgame-shelf/). Вивід команд збережено скриптом `scripts/lab4-demo.sh` у [`lab4-output/`](lab4-output/), скриншоти — у [`screenshots-lab4/`](screenshots-lab4/).

## 1. Середовище

Вивід: [`lab4-output/01-prep.txt`](lab4-output/01-prep.txt) — `helm version`, кластер minikube, маніфести ЛР №3 розгорнуто й перевірено (`/api/info`), після чого видалено (`kubectl delete -f k8s/`), щоб уникнути конфлікту імен і NodePort.

## 2–5. Структура чарта

Структура, призначення файлів, різниця `version`/`appVersion` і таблиця параметрів — у [README](../README.md#helm-чарт-лр-4).

- кожен маніфест ЛР №3 — окремий файл у `templates/`; усі значення — з `.Values`;
- імена об'єктів будуються шаблоном `boardgame-shelf.fullname` з імені релізу;
- Secret бере логін і пароль із `database.auth`; якщо пароль не задано — генерується при першому встановленні й зберігається при оновленнях (через `lookup`);
- `_helpers.tpl`: `fullname`, `labels`, `selectorLabels`, імена компонентів, образ, пароль; підключені в усіх шаблонах через `include`;
- `NOTES.txt` виводить команди для відкриття застосунку залежно від Ingress/NodePort.

## 6. Два середовища

_заповнюється після запуску_

## 7. Перевірка та встановлення

_заповнюється після запуску_

## 8. Життєвий цикл релізу

_заповнюється після запуску_

## 9. Завдання на вибір: хук pre-upgrade і тест релізу (9b)

_заповнюється після запуску_

## Висновки

_заповнюється після запуску_
