#!/usr/bin/env bash
# Демонстрація ЛР №3 (пункти 2, 5–7). Кожна команда та її вивід зберігаються
# у report/output/NN-*.txt — ці файли й є "збереженим виводом команд" для звіту.
#
#   ./scripts/lab3-demo.sh            # усі етапи по черзі, з паузами для скриншотів
#   ./scripts/lab3-demo.sh deploy     # лише один етап: cluster | deploy | lifecycle | diagnose
#   PAUSE=0 ./scripts/lab3-demo.sh    # без пауз
#
# Передумова: образи :1.0.0 і :1.1.0 опубліковані в GHCR або завантажені в minikube
# (./scripts/build-images.sh 1.0.0 && ./scripts/build-images.sh 1.1.0).
set -uo pipefail

NS=boardgame-shelf
REGISTRY="${REGISTRY:-ghcr.io/yehorishchuk}"
V1="${V1:-1.0.0}"
V2="${V2:-1.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/report/output"
PAUSE="${PAUSE:-1}"
BE_SEL="app.kubernetes.io/component=backend"
mkdir -p "$OUT"

k() { kubectl -n "$NS" "$@"; }

# run <file> <command...> — показує команду, виконує, дописує в report/output/<file>.txt
run() {
  local file="$OUT/$1.txt"; shift
  printf '\n$ %s\n' "$*" | tee -a "$file"
  bash -c "$*" 2>&1 | tee -a "$file"
}

section() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$*"; }

pause() {
  if [[ "$PAUSE" == "1" && -t 0 ]]; then
    read -rp $'\n[Enter] — далі (зробіть скриншот, якщо потрібно) '
  fi
}

backend_pod() {
  k get pods -l "$BE_SEL" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}

# N запитів до API через Service backend зсередини поду frontend; виводить, який под відповів
hit_backend() {
  local n="$1"
  k exec deploy/frontend -- sh -c \
    "for i in \$(seq $n); do wget -qO- -T 2 http://backend:8080/api/info; echo; done" \
    | grep -o '"instance":"[^"]*"' | sort | uniq -c
}

# ---------------------------------------------------------------- 2. кластер
stage_cluster() {
  section "2. Локальний кластер minikube"
  rm -f "$OUT"/01-*.txt
  run 01-cluster "minikube status || minikube start --driver=docker --cpus=2 --memory=3072"
  run 01-cluster "kubectl version"
  run 01-cluster "kubectl get nodes -o wide"
  run 01-cluster "kubectl get pods -n kube-system"
  run 01-cluster "minikube addons enable metrics-server"
  run 01-cluster "minikube addons enable ingress"
  run 01-cluster "kubectl -n ingress-nginx wait --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s"
  run 01-cluster "minikube addons list | grep -E 'metrics-server|ingress '"
  pause
}

# ---------------------------------------------------------------- 5. розгортання
stage_deploy() {
  section "5. Розгортання застосунку"
  rm -f "$OUT"/02-*.txt "$OUT"/03-*.txt
  run 02-deploy "kubectl apply -f '$ROOT/k8s/'"
  run 02-deploy "kubectl -n $NS annotate deploy/backend deploy/frontend kubernetes.io/change-cause='initial deploy $V1' --overwrite"
  run 02-deploy "kubectl -n $NS rollout status deploy/postgres --timeout=180s"
  run 02-deploy "kubectl -n $NS rollout status deploy/backend --timeout=180s"
  run 02-deploy "kubectl -n $NS rollout status deploy/frontend --timeout=180s"
  run 02-deploy "kubectl -n $NS get pods,deployments,replicasets,services,ingress,pvc -o wide"
  run 02-deploy "kubectl -n $NS top pods || echo 'metrics-server ще збирає метрики, повторіть за хвилину'"

  section "Доступ з браузера"
  # перевірка Ingress з терміналу (Linux/WSL; на macOS/Windows без tunnel може не відповісти)
  run 02-deploy "curl -s --max-time 5 -H 'Host: boardgames.local' http://\$(minikube ip)/api/info || echo 'Ingress недоступний напряму — див. README (minikube tunnel)'; echo"
  cat <<EOF

  Відкрити в браузері (в ОКРЕМОМУ терміналі, не закривати його):
    kubectl -n $NS port-forward svc/frontend 8081:80      ->  http://localhost:8081
  або через Ingress:
    Linux:          \$(minikube ip)  boardgames.local   у /etc/hosts
    macOS/Windows:  127.0.0.1  boardgames.local         у hosts + 'minikube tunnel' в окремому терміналі
    ->  http://boardgames.local

  Додайте гру у браузері — у футері сторінки видно версію і под, що відповів.
EOF
  pause

  section "5d. Значення з ConfigMap і Secret у контейнері"
  local pod; pod="$(backend_pod)"
  run 03-config "kubectl -n $NS get configmap boardgame-config -o yaml"
  run 03-config "kubectl -n $NS describe secret boardgame-db-secret"
  run 03-config "kubectl -n $NS exec $pod -- printenv | grep -E '^(ASPNETCORE_ENVIRONMENT|App__|Logging__|POSTGRES_HOST|POSTGRES_PORT|POSTGRES_DB|POSTGRES_USER)=' | sort"
  # пароль не друкуємо — лише доводимо, що він переданий і збігається з Secret
  run 03-config "kubectl -n $NS exec $pod -- sh -c 'echo POSTGRES_PASSWORD length: \${#POSTGRES_PASSWORD}'"
  run 03-config "echo Secret value length: \$(kubectl -n $NS get secret boardgame-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d | wc -c)"
  run 03-config "kubectl -n $NS exec deploy/frontend -- wget -qO- http://backend:8080/api/info; echo"
  pause
}

# ---------------------------------------------------------------- 6. життєвий цикл
stage_lifecycle() {
  rm -f "$OUT"/04-*.txt "$OUT"/05-*.txt "$OUT"/06-*.txt "$OUT"/07-*.txt
  section "6a. Самовідновлення"
  local victim; victim="$(backend_pod)"
  run 04-self-healing "kubectl -n $NS get pods -l $BE_SEL"
  run 04-self-healing "kubectl -n $NS delete pod $victim --wait=false"
  run 04-self-healing "sleep 2; kubectl -n $NS get pods -l $BE_SEL"
  run 04-self-healing "kubectl -n $NS rollout status deploy/backend --timeout=120s"
  run 04-self-healing "kubectl -n $NS get pods -l $BE_SEL"
  run 04-self-healing "kubectl -n $NS get events --field-selector involvedObject.kind=ReplicaSet --sort-by=.lastTimestamp | tail -5"
  pause

  section "6b. Масштабування та розподіл трафіку"
  run 05-scaling "kubectl -n $NS scale deploy/backend --replicas=4"
  run 05-scaling "kubectl -n $NS rollout status deploy/backend --timeout=180s"
  run 05-scaling "kubectl -n $NS get pods -l $BE_SEL -o wide"
  printf '\n$ 40 запитів до Service backend — скільки відповів кожен под:\n' | tee -a "$OUT/05-scaling.txt"
  hit_backend 40 | tee -a "$OUT/05-scaling.txt"
  pause

  section "6c/6e. Rolling update $V1 -> $V2 під навантаженням"
  # окремий под-зонд: кожні 0,3 с запит через frontend -> backend, пише час, код і версію
  k delete pod availability-probe --ignore-not-found --wait=true >/dev/null
  k run availability-probe --image=busybox:1.36 --restart=Never -- sh -c \
    'while true; do r=$(wget -qO- -T 2 http://frontend/api/info 2>/dev/null) && echo "$(date +%T) OK $(echo "$r" | grep -o "\"version\":\"[^\"]*\"")" || echo "$(date +%T) FAIL"; sleep 0.3; done' >/dev/null
  k wait --for=condition=Ready pod/availability-probe --timeout=60s >/dev/null

  run 06-rolling-update "kubectl -n $NS set image deploy/backend backend=$REGISTRY/boardgame-shelf-backend:$V2"
  run 06-rolling-update "kubectl -n $NS annotate deploy/backend kubernetes.io/change-cause='update to $V2' --overwrite"
  run 06-rolling-update "kubectl -n $NS rollout status deploy/backend --timeout=300s"
  run 06-rolling-update "kubectl -n $NS set image deploy/frontend frontend=$REGISTRY/boardgame-shelf-frontend:$V2"
  run 06-rolling-update "kubectl -n $NS annotate deploy/frontend kubernetes.io/change-cause='update to $V2' --overwrite"
  run 06-rolling-update "kubectl -n $NS rollout status deploy/frontend --timeout=300s"
  run 06-rolling-update "kubectl -n $NS get rs -l app.kubernetes.io/part-of=boardgame-shelf -o wide"
  run 06-rolling-update "kubectl -n $NS describe deploy backend | sed -n '/^Events:/,\$p'"

  k logs availability-probe > "$OUT/06-availability.log"
  local ok fail
  ok=$(grep -c ' OK ' "$OUT/06-availability.log"); fail=$(grep -c ' FAIL' "$OUT/06-availability.log")
  {
    printf '\n$ Доступність під час оновлення (повний лог: 06-availability.log)\n'
    echo "успішних запитів: $ok, невдалих: $fail"
    grep -o '"version":"[^"]*"' "$OUT/06-availability.log" | uniq -c
  } | tee -a "$OUT/06-rolling-update.txt"
  k delete pod availability-probe --wait=false >/dev/null
  pause

  section "6d. Історія оновлень і відкат"
  run 07-rollback "kubectl -n $NS rollout history deploy/backend"
  run 07-rollback "kubectl -n $NS rollout history deploy/backend --revision=2 | grep -E 'Image|change-cause'"
  run 07-rollback "kubectl -n $NS rollout undo deploy/backend"
  run 07-rollback "kubectl -n $NS rollout undo deploy/frontend"
  run 07-rollback "kubectl -n $NS rollout status deploy/backend --timeout=300s"
  run 07-rollback "kubectl -n $NS rollout status deploy/frontend --timeout=300s"
  run 07-rollback "kubectl -n $NS rollout history deploy/backend"
  run 07-rollback "kubectl -n $NS get deploy -o wide"
  run 07-rollback "kubectl -n $NS exec deploy/frontend -- wget -qO- http://backend:8080/api/info; echo"
  run 07-rollback "kubectl -n $NS scale deploy/backend --replicas=2"
  pause
}

# ---------------------------------------------------------------- 7. діагностика
stage_diagnose() {
  rm -f "$OUT"/08-*.txt
  section "7a. Неіснуючий тег образу"
  local good_image; good_image="$(k get deploy backend -o jsonpath='{.spec.template.spec.containers[0].image}')"
  run 08-diagnostics "kubectl -n $NS set image deploy/backend backend=$REGISTRY/boardgame-shelf-backend:9.9.9-does-not-exist"
  run 08-diagnostics "kubectl -n $NS annotate deploy/backend kubernetes.io/change-cause='broken tag 9.9.9-does-not-exist' --overwrite"
  echo "чекаємо 40 с, поки kubelet спробує завантажити образ..."; sleep 40
  run 08-diagnostics "kubectl -n $NS get pods -l $BE_SEL"
  run 08-diagnostics "kubectl -n $NS rollout status deploy/backend --timeout=5s || true"
  pause

  section "7b. Причина: describe і Events"
  local bad
  bad="$(k get pods -l "$BE_SEL" --no-headers | awk '/ImagePull|ErrImage/{print $1; exit}')"
  run 08-diagnostics "kubectl -n $NS describe pod $bad | sed -n '/^Containers:/,/^    Ready:/p;/^Events:/,\$p'"
  run 08-diagnostics "kubectl -n $NS get events --field-selector involvedObject.name=$bad --sort-by=.lastTimestamp"
  echo "Старі поди продовжують обслуговувати запити (maxUnavailable: 0):" | tee -a "$OUT/08-diagnostics.txt"
  run 08-diagnostics "kubectl -n $NS exec deploy/frontend -- wget -qO- http://backend:8080/api/health; echo"
  pause

  section "7c. Логи та вхід у контейнер"
  local pod; pod="$(backend_pod)"
  run 08-diagnostics "kubectl -n $NS logs $pod --tail=20"
  run 08-diagnostics "kubectl -n $NS exec $pod -- sh -c 'hostname; id; echo APP_VERSION=\$APP_VERSION; ls /app | head -5'"
  if [[ -t 0 ]]; then
    echo
    echo "Інтерактивна сесія в $pod. Спробуйте: hostname; env | grep App__; ls /app; exit"
    kubectl -n "$NS" exec -it "$pod" -- /bin/sh
  fi
  pause

  section "7d. Виправлення"
  run 08-diagnostics "kubectl -n $NS set image deploy/backend backend=$good_image"
  run 08-diagnostics "kubectl -n $NS annotate deploy/backend kubernetes.io/change-cause='fix: back to ${good_image##*:}' --overwrite"
  run 08-diagnostics "kubectl -n $NS rollout status deploy/backend --timeout=180s"
  run 08-diagnostics "kubectl -n $NS get pods,rs -l $BE_SEL"
  run 08-diagnostics "kubectl -n $NS rollout history deploy/backend"
  run 08-diagnostics "kubectl -n $NS exec deploy/frontend -- wget -qO- http://backend:8080/api/info; echo"
}

case "${1:-all}" in
  cluster)   stage_cluster ;;
  deploy)    stage_deploy ;;
  lifecycle) stage_lifecycle ;;
  diagnose)  stage_diagnose ;;
  all)       stage_cluster; stage_deploy; stage_lifecycle; stage_diagnose ;;
  *) echo "usage: $0 [all|cluster|deploy|lifecycle|diagnose]" >&2; exit 1 ;;
esac

section "Готово. Вивід команд: report/output/"
ls -1 "$OUT"
