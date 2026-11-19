#!/usr/bin/env bash
# Демонстрація ЛР №4 (Helm). Кожна команда та її вивід зберігаються у report/lab4-output/NN-*.txt.
#
#   ./scripts/lab4-demo.sh              # усі етапи по черзі, з паузами для скриншотів
#   ./scripts/lab4-demo.sh render       # один етап: prep | render | install | twice | lifecycle | extra
#   PAUSE=0 ./scripts/lab4-demo.sh      # без пауз
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/chart/boardgame-shelf"
NS="${NS:-boardgame-dev}"
REL="${REL:-shelf}"
OUT="$ROOT/report/lab4-output"
PAUSE="${PAUSE:-1}"
FULL="$REL-boardgame-shelf"
mkdir -p "$OUT"

run() {
  local file="$OUT/$1.txt"; shift
  printf '\n$ %s\n' "$*" | tee -a "$file"
  bash -c "$*" 2>&1 | tee -a "$file"
}
note() { local f="$OUT/$1.txt"; shift; printf '\n# %s\n' "$*" | tee -a "$f"; }
section() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$*"; }
pause() {
  if [[ "$PAUSE" == "1" && -t 0 ]]; then
    read -rp $'\n[Enter] — далі (зробіть скриншот, якщо потрібно) '
  fi
}

# GET-запит зсередини кластера окремим тимчасовим подом (працює на будь-якій ОС, без tunnel)
incluster_get() { # <file> <url> [host-header]
  local file="$1" url="$2" host="${3:-}" pod="curl-check-$RANDOM"
  local hdr=""; [[ -n "$host" ]] && hdr="--header 'Host: $host'"
  run "$file" "kubectl -n $NS run $pod --image=busybox:1.36 --restart=Never --command -- sh -c \"wget -qO- -T 5 $hdr $url; echo\" >/dev/null && kubectl -n $NS wait --for=jsonpath='{.status.phase}'=Succeeded pod/$pod --timeout=90s >/dev/null; kubectl -n $NS logs $pod; kubectl -n $NS delete pod $pod --wait=false >/dev/null"
}

# Логи хука pre-upgrade: Job видаляється після успіху, тому читаємо їх паралельно з helm upgrade
capture_hook_logs() { # <file>
  local file="$OUT/$1.txt" old
  # поди попередніх запусків хука (якщо ще не видалені) ігноруємо
  old=$(kubectl -n "$NS" get pods -l app.kubernetes.io/component=pre-upgrade-hook -o name 2>/dev/null | tr '\n' ' ')
  (
    for _ in $(seq 1 120); do
      pod=""
      for p in $(kubectl -n "$NS" get pods -l app.kubernetes.io/component=pre-upgrade-hook -o name 2>/dev/null); do
        case " $old " in *" $p "*) ;; *) pod="$p"; break ;; esac
      done
      if [[ -n "$pod" ]]; then
        logs=$(kubectl -n "$NS" logs "$pod" 2>/dev/null)
        if echo "$logs" | grep -q 'database OK\|NOT ready'; then
          printf '\n# логи хука pre-upgrade (%s):\n%s\n' "$pod" "$logs" >> "$file"
          echo "$logs"
          break
        fi
      fi
      sleep 1
    done
  ) &
  HOOK_PID=$!
}

api_info() { # <file>
  run "$1" "kubectl -n $NS exec deploy/$FULL-frontend -- wget -qO- http://localhost/api/info; echo"
}

# ---------------------------------------------------------------- 1. середовище
stage_prep() {
  section "1. Підготовка середовища"
  rm -f "$OUT"/01-*.txt
  run 01-prep "helm version"
  run 01-prep "minikube status || minikube start --driver=docker --cpus=2 --memory=3072"
  run 01-prep "minikube addons enable ingress >/dev/null && minikube addons enable metrics-server >/dev/null && minikube addons list | grep -E 'ingress |metrics-server'"
  note 01-prep "1c. маніфести ЛР №3 розгортаються і працюють"
  run 01-prep "kubectl apply -f '$ROOT/k8s/'"
  run 01-prep "kubectl -n boardgame-shelf rollout status deploy/backend --timeout=180s && kubectl -n boardgame-shelf rollout status deploy/frontend --timeout=180s"
  run 01-prep "kubectl -n boardgame-shelf exec deploy/frontend -- wget -qO- http://localhost/api/info; echo"
  note 01-prep "1d. видаляємо розгортання ЛР №3, щоб не було конфлікту (NodePort 30080 тощо)"
  run 01-prep "kubectl delete -f '$ROOT/k8s/' --wait=true"
  run 01-prep "kubectl get ns boardgame-shelf 2>&1 || true"
  pause
}

# ---------------------------------------------------------------- 6b, 6c, 7a, 7b
stage_render() {
  section "7a. Перевірка чарта (helm lint)"
  rm -f "$OUT"/02-*.txt "$OUT"/03-*.txt "$OUT"/rendered-*.yaml
  run 02-lint "helm lint '$CHART'"
  run 02-lint "helm lint '$CHART' -f '$CHART/values-dev.yaml'"
  run 02-lint "helm lint '$CHART' -f '$CHART/values-prod.yaml'"
  pause

  section "6b. Різниця dev/prod без встановлення (helm template)"
  run 03-template "helm template $REL '$CHART' -n $NS -f '$CHART/values-dev.yaml' > '$OUT/rendered-dev.yaml' && echo 'dev  -> rendered-dev.yaml'"
  run 03-template "helm template $REL '$CHART' -n boardgame-prod -f '$CHART/values-prod.yaml' > '$OUT/rendered-prod.yaml' && echo 'prod -> rendered-prod.yaml'"
  run 03-template "for e in dev prod; do echo \"== \$e\"; grep -E '^kind:' '$OUT/rendered-'\$e'.yaml' | sort | uniq -c; done"
  run 03-template "for e in dev prod; do echo \"== \$e\"; grep -E '^  name: |^  replicas:|image: \"ghcr|ASPNETCORE_ENVIRONMENT|^  type: (NodePort|ClusterIP)|cpu: [0-9]+m$' '$OUT/rendered-'\$e'.yaml' | grep -v 'name: $FULL-test' ; done"
  run 03-template "diff -u '$OUT/rendered-dev.yaml' '$OUT/rendered-prod.yaml' | grep -E '^[-+][^-+]' | grep -vE 'checksum/|POSTGRES_PASSWORD' | head -60"
  pause

  section "6c. Пріоритет значень: values.yaml < -f (по черзі) < --set"
  run 03-template "helm template $REL '$CHART' --show-only templates/backend-deployment.yaml | grep -E 'replicas:|image:'"
  run 03-template "helm template $REL '$CHART' -f '$CHART/values-prod.yaml' --show-only templates/backend-deployment.yaml | grep -E 'replicas:|image:'"
  run 03-template "helm template $REL '$CHART' -f '$CHART/values-prod.yaml' -f '$CHART/values-dev.yaml' --show-only templates/backend-deployment.yaml | grep -E 'replicas:|image:'"
  run 03-template "helm template $REL '$CHART' -f '$CHART/values-prod.yaml' --set backend.replicaCount=5 --set backend.image.tag=1.0.0 --show-only templates/backend-deployment.yaml | grep -E 'replicas:|image:'"
  pause

  section "7b. Згенеровані маніфести проти маніфестів ЛР №3"
  run 03-template "echo '== ЛР №3 (k8s/)'; grep -h '^kind:' '$ROOT'/k8s/*.yaml | sort | uniq -c; for e in dev prod; do echo \"== чарт, \$e (без hook/test)\"; awk '/^# Source:/{f=(\$0 ~ /hooks|tests/)} !f' '$OUT/rendered-'\$e'.yaml' | grep '^kind:' | sort | uniq -c; done"
  run 03-template "diff <(sed -n '/^kind: Deployment/,\$p' '$ROOT/k8s/20-backend-deployment.yaml') <(awk '/Source: boardgame-shelf\\/templates\\/backend-deployment.yaml/{f=1;next} /^# Source:/{f=0} f' '$OUT/rendered-dev.yaml' | sed -n '/^kind: Deployment/,\$p') | head -60"
  pause
}

# ---------------------------------------------------------------- 7c–7e
stage_install() {
  section "7c. Встановлення релізу в namespace $NS"
  rm -f "$OUT"/04-*.txt
  run 04-install "helm install $REL '$CHART' -n $NS --create-namespace -f '$CHART/values-dev.yaml' --wait --timeout 5m"
  pause

  section "7d. Релізи, статус і значення"
  run 04-install "helm list -A"
  run 04-install "helm status $REL -n $NS | head -12"
  run 04-install "helm get values $REL -n $NS"
  run 04-install "kubectl -n $NS get deploy,rs,pods,svc,cm,secret,pvc,ingress"
  api_info 04-install
  pause

  section "7e. Де Helm зберігає стан релізу"
  run 04-install "kubectl -n $NS get secrets -l owner=helm --show-labels"
  run 04-install "kubectl -n $NS get secret sh.helm.release.v1.$REL.v1 -o jsonpath='{.type}'; echo"
  run 04-install "kubectl -n $NS get secret sh.helm.release.v1.$REL.v1 -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | head -c 600; echo ' ...'"
  cat <<EOF

  Відкрити застосунок (в окремій вкладці Terminal):
    kubectl -n $NS port-forward svc/$FULL-frontend 8081:80   ->  http://localhost:8081
EOF
  pause
}

# ---------------------------------------------------------------- 3c. два релізи в одному кластері
stage_twice() {
  section "3c. Другий реліз того самого чарта в тому ж namespace"
  rm -f "$OUT"/05-*.txt
  run 05-twice "helm install $REL-b '$CHART' -n $NS -f '$CHART/values-dev.yaml' --set config.clubName='Другий клуб' --wait --timeout 5m | head -5"
  run 05-twice "helm list -n $NS"
  run 05-twice "kubectl -n $NS get deploy,svc -o custom-columns=KIND:.kind,NAME:.metadata.name,RELEASE:.metadata.labels.app\\.kubernetes\\.io/instance"
  run 05-twice "helm uninstall $REL-b -n $NS --wait"
  pause
}

# ---------------------------------------------------------------- 8. життєвий цикл
stage_lifecycle() {
  rm -f "$OUT"/06-*.txt "$OUT"/07-*.txt "$OUT"/08-*.txt
  section "8a. Оновлення: новий тег образу через --set (ревізія 2)"
  capture_hook_logs 06-upgrade-set
  run 06-upgrade-set "helm upgrade $REL '$CHART' -n $NS -f '$CHART/values-dev.yaml' --set backend.image.tag=1.1.0 --set frontend.image.tag=1.1.0 --wait --timeout 5m | head -8"
  wait "$HOOK_PID" 2>/dev/null
  run 06-upgrade-set "kubectl -n $NS get deploy -o wide | awk '{print \$1, \$2, \$7}'"
  api_info 06-upgrade-set
  pause

  section "8b. Оновлення файлом значень іншого середовища: values-prod.yaml (ревізія 3)"
  capture_hook_logs 07-upgrade-prod
  run 07-upgrade-prod "helm upgrade $REL '$CHART' -n $NS -f '$CHART/values-prod.yaml' --wait --timeout 5m | head -8"
  wait "$HOOK_PID" 2>/dev/null
  run 07-upgrade-prod "kubectl -n $NS get deploy,svc,ingress"
  api_info 07-upgrade-prod
  note 07-upgrade-prod "Ingress зсередини кластера: запит до ingress-nginx з заголовком Host: boardgames.local"
  incluster_get 07-upgrade-prod "http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/api/info" "boardgames.local"
  pause

  section "8c. Історія ревізій і що змінювалось"
  run 08-history "helm history $REL -n $NS"
  run 08-history "for r in 1 2 3; do echo \"== ревізія \$r (значення, задані при встановленні/оновленні)\"; helm get values $REL -n $NS --revision \$r; done"
  pause

  section "8d. Відкат до ревізії 2 (dev + 1.1.0)"
  run 08-history "helm rollback $REL 2 -n $NS --wait --timeout 5m"
  run 08-history "helm history $REL -n $NS"
  run 08-history "kubectl -n $NS get deploy,svc,ingress"
  api_info 08-history
  pause

  section "8e. Видалення релізу однією командою"
  run 08-history "helm uninstall $REL -n $NS --wait"
  run 08-history "helm list -A"
  run 08-history "kubectl -n $NS get all,cm,secret,pvc,ingress,jobs"
  note 08-history "kube-root-ca.crt — ConfigMap, який Kubernetes сам створює в кожному namespace; до релізу не належить"
  pause
}

# ---------------------------------------------------------------- 9b. хук pre-upgrade і helm test
stage_extra() {
  rm -f "$OUT"/09-*.txt
  section "9b. Хук pre-upgrade і тест релізу"
  run 09-hook-test "helm install $REL '$CHART' -n $NS --create-namespace -f '$CHART/values-dev.yaml' --wait --timeout 5m | head -6"
  run 09-hook-test "helm test $REL -n $NS --logs"
  run 09-hook-test "kubectl -n $NS delete pod $FULL-test --wait=false"

  note 09-hook-test "Хук при успішному оновленні: перевірив БД і дозволив upgrade"
  capture_hook_logs 09-hook-test
  run 09-hook-test "helm upgrade $REL '$CHART' -n $NS -f '$CHART/values-dev.yaml' --set config.maxBorrowDays=7 --wait --timeout 5m | head -6"
  wait "$HOOK_PID" 2>/dev/null
  api_info 09-hook-test
  pause

  note 09-hook-test "Хук при недоступній БД: зупиняємо PostgreSQL і пробуємо оновитись — Helm має скасувати upgrade"
  run 09-hook-test "kubectl -n $NS scale deploy/$FULL-postgres --replicas=0 && kubectl -n $NS wait --for=delete pod -l app.kubernetes.io/component=database --timeout=60s"
  capture_hook_logs 09-hook-test
  run 09-hook-test "helm upgrade $REL '$CHART' -n $NS -f '$CHART/values-dev.yaml' --set config.maxBorrowDays=21 --timeout 3m 2>&1 | tail -3"
  wait "$HOOK_PID" 2>/dev/null
  run 09-hook-test "helm history $REL -n $NS"
  run 09-hook-test "kubectl -n $NS get configmap $FULL-config -o jsonpath='{.data.App__MaxBorrowDays}'; echo '  <- значення не змінилось на 21'"
  pause

  note 09-hook-test "Повертаємо БД і повторюємо оновлення"
  run 09-hook-test "kubectl -n $NS scale deploy/$FULL-postgres --replicas=1 && kubectl -n $NS rollout status deploy/$FULL-postgres --timeout=120s"
  capture_hook_logs 09-hook-test
  run 09-hook-test "helm upgrade $REL '$CHART' -n $NS -f '$CHART/values-dev.yaml' --set config.maxBorrowDays=21 --wait --timeout 5m | head -6"
  wait "$HOOK_PID" 2>/dev/null
  run 09-hook-test "helm history $REL -n $NS"
  run 09-hook-test "helm test $REL -n $NS --logs"
  pause

  section "Прибирання"
  run 09-hook-test "kubectl -n $NS delete pod $FULL-test --ignore-not-found"
  run 09-hook-test "helm uninstall $REL -n $NS --wait"
  run 09-hook-test "kubectl -n $NS get all,cm,secret,pvc,ingress,jobs"
}

case "${1:-all}" in
  prep)      stage_prep ;;
  render)    stage_render ;;
  install)   stage_install ;;
  twice)     stage_twice ;;
  lifecycle) stage_lifecycle ;;
  extra)     stage_extra ;;
  all)       stage_prep; stage_render; stage_install; stage_twice; stage_lifecycle; stage_extra ;;
  *) echo "usage: $0 [all|prep|render|install|twice|lifecycle|extra]" >&2; exit 1 ;;
esac

section "Готово. Вивід команд: report/lab4-output/"
ls -1 "$OUT"
