{{/*
Коротке ім'я чарта (можна перевизначити nameOverride).
*/}}
{{- define "boardgame-shelf.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Повне ім'я — основа для імен усіх об'єктів релізу.
Будується з імені релізу, тому чарт можна встановити двічі в один кластер/namespace.
Обмеження 63 символи — ліміт DNS-імен Kubernetes; суфікс компонента ("-frontend-nginx")
займає до 15 символів, тому основу обрізаємо до 48.
*/}}
{{- define "boardgame-shelf.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 48 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 48 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 48 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Ім'я та версія чарта для мітки helm.sh/chart.
*/}}
{{- define "boardgame-shelf.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Мітки-селектори (незмінні впродовж життя релізу).
*/}}
{{- define "boardgame-shelf.selectorLabels" -}}
app.kubernetes.io/name: {{ include "boardgame-shelf.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Повний набір міток для metadata.labels усіх об'єктів.
*/}}
{{- define "boardgame-shelf.labels" -}}
helm.sh/chart: {{ include "boardgame-shelf.chart" . }}
{{ include "boardgame-shelf.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: {{ .Chart.Name }}
{{- end }}

{{/*
Імена об'єктів компонентів (одне місце правди — на них посилаються інші шаблони).
*/}}
{{- define "boardgame-shelf.configName" -}}
{{- include "boardgame-shelf.fullname" . }}-config
{{- end }}

{{- define "boardgame-shelf.secretName" -}}
{{- if .Values.database.auth.existingSecret }}
{{- .Values.database.auth.existingSecret }}
{{- else }}
{{- include "boardgame-shelf.fullname" . }}-db
{{- end }}
{{- end }}

{{- define "boardgame-shelf.postgresName" -}}
{{- include "boardgame-shelf.fullname" . }}-postgres
{{- end }}

{{- define "boardgame-shelf.backendName" -}}
{{- include "boardgame-shelf.fullname" . }}-backend
{{- end }}

{{- define "boardgame-shelf.frontendName" -}}
{{- include "boardgame-shelf.fullname" . }}-frontend
{{- end }}

{{/*
Повне посилання на образ компонента: <registry>/<repository>:<tag>.
Тег: тег компонента -> спільний image.tag -> appVersion чарта. Виклик: include "boardgame-shelf.image" (dict "root" $ "image" .Values.backend.image)
*/}}
{{- define "boardgame-shelf.image" -}}
{{- $tag := .image.tag | default .root.Values.image.tag | default .root.Chart.AppVersion -}}
{{- printf "%s/%s:%s" .root.Values.image.registry .image.repository (toString $tag) }}
{{- end }}

{{/*
Пароль БД:
  1) якщо задано database.auth.password — беремо його;
  2) інакше, якщо Secret уже існує в кластері (оновлення релізу) — зберігаємо старий пароль,
     бо PostgreSQL ініціалізує користувача лише один раз;
  3) інакше генеруємо випадковий.
*/}}
{{- define "boardgame-shelf.dbPassword" -}}
{{- if .Values.database.auth.password }}
{{- .Values.database.auth.password }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .Release.Namespace (include "boardgame-shelf.secretName" .) }}
{{- if and $existing $existing.data (index $existing.data "POSTGRES_PASSWORD") }}
{{- index $existing.data "POSTGRES_PASSWORD" | b64dec }}
{{- else }}
{{- randAlphaNum 24 }}
{{- end }}
{{- end }}
{{- end }}
