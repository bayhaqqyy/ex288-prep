#!/bin/bash
# ---------------------------------------------------------------
# EX288 Prep - bersihkan semua sisa latihan
#
#   bash prep/cleanup.sh                 # bersihkan soal 1-16 (minta konfirmasi)
#   bash prep/cleanup.sh 2 7             # bersihkan soal tertentu saja
#   bash prep/cleanup.sh -y              # tanpa konfirmasi
#   bash prep/cleanup.sh --safe          # jangan lepas finalizer paksa
#   bash prep/cleanup.sh --all-extra     # + hapus clone lokal repo latihan,
#                                        #   image podman, dan matikan default
#                                        #   route internal registry
#
# Yang dihapus per soal:
#   - project OpenShift soal itu (beserta semua isinya, termasuk release Helm)
#   - file lab di /home/student/ex288-set2/qN
# Repo di GitLab lab TIDAK dihapus (butuh token API). Prep berikutnya
# akan menimpa isinya, jadi aman dibiarkan.
# ---------------------------------------------------------------
set -u

OCP_API="https://api.ocp4.example.com:6443"
SET_DIR="/home/student/ex288-set2"
GIT_HOST="git.ocp4.example.com"

if [ -t 1 ]; then G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else G=; Y=; B=; N=; fi

declare -A PROJECTS=(
  [1]="metrics-prod"
  [2]="legacy-prod"
  [3]="deploy-portal"
  [4]="deploy-docs"
  [5]="inventory"
  [6]="lion"
  [7]="webstore-lab webstore-prod"
  [8]="deploy-health"
  [9]="pipeline-lab"
  [10]="registry-lab"
  [11]="docker-app"
  [12]="greetings-app"
  [13]="builds-s2i"
  [14]="production2"
  [15]="hooks-lab"
  [16]="java-builds"
)
declare -A REPOS=(
  [1]="metrics-api" [2]="legacy-web" [3]="portal-s2i" [6]="shop-ui"
  [7]="webstore-helm" [9]="tekton-web" [11]="myapp1-docker" [13]="hello-s2i"
  [14]="site-images" [15]="hooks-api" [16]="vertx-site"
)

YES=0; EXTRA=0; SAFE=0; QS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) YES=1 ;;
    --all-extra) EXTRA=1 ;;
    --safe) SAFE=1 ;;
    [1-9]|1[0-6]) QS+=("$a") ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $a"; exit 1 ;;
  esac
done
[ ${#QS[@]} -gt 0 ] || QS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)

ALL_PROJECTS=""
for q in "${QS[@]}"; do ALL_PROJECTS="$ALL_PROJECTS ${PROJECTS[$q]}"; done

echo "${B}Akan dihapus:${N}"
echo "  Project :$ALL_PROJECTS"
echo "  Folder  : $(for q in "${QS[@]}"; do printf '%s/q%s ' "$SET_DIR" "$q"; done)"
[ "$EXTRA" -eq 1 ] && echo "  Extra   : clone lokal repo latihan, image podman custom-nginx, default route registry -> off"
if [ "$YES" -ne 1 ]; then
  read -r -p "Lanjutkan? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Dibatalkan."; exit 0 ;; esac
fi

oc whoami >/dev/null 2>&1 || oc login -u developer -p developer "$OCP_API" >/dev/null

# Cek namespace pakai admin di kubeconfig terpisah. Developer tidak bisa
# melihat project yang sedang Terminating, jadi tanpa ini project dianggap
# sudah hilang padahal namespace-nya masih ada.
ADMIN_KC="$(mktemp)"
trap 'rm -f "$ADMIN_KC"' EXIT
ADMIN_OK=0
if KUBECONFIG="$ADMIN_KC" oc login -u admin -p redhatocp "$OCP_API" >/dev/null 2>&1 \
   || KUBECONFIG="$ADMIN_KC" oc login -u admin -p redhatocp "$OCP_API" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  ADMIN_OK=1
fi
ns_exists() {
  if [ "$ADMIN_OK" -eq 1 ]; then KUBECONFIG="$ADMIN_KC" oc get namespace "$1" >/dev/null 2>&1
  else oc get project "$1" >/dev/null 2>&1; fi
}

# finalize_if_stuck <nama>: kalau isi namespace sudah kosong tapi tertahan
# NamespaceDeletionDiscoveryFailure (ada APIService cluster yang down),
# selesaikan penghapusan lewat subresource finalize. Hanya untuk kondisi itu.
finalize_if_stuck() {
  local p="$1" conds
  [ "$ADMIN_OK" -eq 1 ] || return 1
  conds="$(KUBECONFIG="$ADMIN_KC" oc get namespace "$p" \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' 2>/dev/null)" || return 1
  echo "$conds" | grep -q '^NamespaceDeletionDiscoveryFailure=True$' || return 1
  echo "$conds" | grep -q '^NamespaceContentRemaining=False$' || return 1
  echo "$conds" | grep -q '^NamespaceFinalizersRemaining=False$' || return 1
  KUBECONFIG="$ADMIN_KC" oc get namespace "$p" -o json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d["spec"]["finalizers"]=[]; print(json.dumps(d))' \
    | KUBECONFIG="$ADMIN_KC" oc replace --raw "/api/v1/namespaces/$p/finalize" -f - >/dev/null 2>&1
}

# strip_finalizers <nama>: lepas finalizer semua objek yang masih tersisa
strip_finalizers() {
  local p="$1" types o
  types="$(KUBECONFIG="$ADMIN_KC" oc api-resources --verbs=list --namespaced -o name 2>/dev/null | paste -sd, -)"
  [ -n "$types" ] || return 0
  KUBECONFIG="$ADMIN_KC" oc get "$types" -n "$p" --ignore-not-found -o name 2>/dev/null | while read -r o; do
    KUBECONFIG="$ADMIN_KC" oc patch "$o" -n "$p" --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  done
}

# force_finalize_ns <nama>: selesaikan penghapusan namespace secara paksa
force_finalize_ns() {
  local p="$1"
  KUBECONFIG="$ADMIN_KC" oc get namespace "$p" -o json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d["spec"]["finalizers"]=[]; print(json.dumps(d))' \
    | KUBECONFIG="$ADMIN_KC" oc replace --raw "/api/v1/namespaces/$p/finalize" -f - >/dev/null 2>&1
}

# Hapus project (tanpa menunggu satu per satu)
for p in $ALL_PROJECTS; do
  if ns_exists "$p"; then
    # Force: matikan Pod tanpa grace period dan hapus isinya dulu
    oc delete pods --all -n "$p" --grace-period=0 --force --wait=false >/dev/null 2>&1 || true
    for t in all pvc pipelinerun taskrun; do
      oc delete "$t" --all -n "$p" --grace-period=0 --wait=false >/dev/null 2>&1 || true
    done
    if oc delete project "$p" --wait=false >/dev/null 2>&1 \
       || { [ "$ADMIN_OK" -eq 1 ] && KUBECONFIG="$ADMIN_KC" oc delete namespace "$p" --wait=false >/dev/null 2>&1; }; then
      echo "  ${G}hapus${N} project $p"
    else
      echo "  ${Y}gagal${N} hapus project $p (cek hak akses)"
    fi
  else
    echo "  lewati  project $p (tidak ada)"
  fi
done

# Hapus folder lab per soal
for q in "${QS[@]}"; do
  if [ -d "$SET_DIR/q$q" ]; then rm -rf "${SET_DIR:?}/q$q" && echo "  ${G}hapus${N} $SET_DIR/q$q"; fi
done

if [ "$EXTRA" -eq 1 ]; then
  # Clone lokal: hanya folder git yang origin-nya repo latihan di GitLab lab
  for q in "${QS[@]}"; do
    r="${REPOS[$q]:-}"; [ -n "$r" ] || continue
    for d in "$HOME/$r" "$HOME/ex288/$r" "$SET_DIR/$r"; do
      [ -d "$d/.git" ] || continue
      if git -C "$d" remote get-url origin 2>/dev/null | grep -q "$GIT_HOST/developer/$r"; then
        rm -rf "$d" && echo "  ${G}hapus${N} clone lokal $d"
      fi
    done
  done
  # Image podman soal 12
  if printf '%s\n' "${QS[@]}" | grep -qx 12; then
    podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '/developer/greetings' | while read -r img; do
      podman rmi -f "$img" >/dev/null 2>&1 && echo "  ${G}hapus${N} image $img"
    done
  fi
  # Image podman soal 10
  if printf '%s\n' "${QS[@]}" | grep -qx 10; then
    podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep 'custom-nginx' | while read -r img; do
      podman rmi -f "$img" >/dev/null 2>&1 && echo "  ${G}hapus${N} image $img"
    done
    if oc login -u admin -p redhatocp "$OCP_API" >/dev/null 2>&1; then
      oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
        -p '{"spec":{"defaultRoute":false}}' >/dev/null 2>&1 && echo "  ${G}matikan${N} default route internal registry"
      oc login -u developer -p developer "$OCP_API" >/dev/null 2>&1
    fi
  fi
fi

echo
echo "Menunggu semua project benar-benar terhapus (finalizer dilepas paksa setelah 10 detik)..."
t=0; left=""
while :; do
  left=""
  for p in $ALL_PROJECTS; do ns_exists "$p" && left="$left $p"; done
  [ -z "$left" ] && break
  [ "$t" -ge 420 ] && break
  if [ "$t" -ge 10 ] && [ "$ADMIN_OK" -eq 1 ]; then
    for p in $left; do
      if [ "$SAFE" -eq 1 ]; then
        finalize_if_stuck "$p" && printf '\n  %s: isi sudah kosong, API cluster down -> finalize\n' "$p"
      else
        strip_finalizers "$p"
        force_finalize_ns "$p" && printf '\n  %s: finalizer dilepas, namespace di-finalize paksa\n' "$p"
      fi
    done
  fi
  printf '\r  masih Terminating:%-60s (%ss)' "$left" "$t"
  sleep 5; t=$((t + 5))
done
echo
if [ -n "$left" ]; then
  echo "${Y}Masih Terminating setelah ${t}s:${N}$left"
  echo "Cek sebagai admin: oc get ns$left ; jalankan cleanup lagi nanti sebelum prep."
  exit 1
fi
[ "$ADMIN_OK" -eq 1 ] || echo "${Y}Catatan: login admin gagal, pengecekan memakai developer (kurang akurat).${N}"
echo "${G}Selesai. Semua project soal sudah benar-benar bersih.${N}"
