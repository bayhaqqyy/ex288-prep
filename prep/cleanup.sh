#!/bin/bash
# ---------------------------------------------------------------
# EX288 Prep - bersihkan semua sisa latihan
#
#   bash prep/cleanup.sh                 # bersihkan soal 1-10 (minta konfirmasi)
#   bash prep/cleanup.sh 2 7             # bersihkan soal tertentu saja
#   bash prep/cleanup.sh -y              # tanpa konfirmasi
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
)
declare -A REPOS=(
  [1]="metrics-api" [2]="legacy-web" [3]="portal-s2i" [6]="shop-ui"
  [7]="webstore-helm" [9]="tekton-web"
)

YES=0; EXTRA=0; QS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) YES=1 ;;
    --all-extra) EXTRA=1 ;;
    [1-9]|10) QS+=("$a") ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "Argumen tidak dikenal: $a"; exit 1 ;;
  esac
done
[ ${#QS[@]} -gt 0 ] || QS=(1 2 3 4 5 6 7 8 9 10)

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

# Hapus project (tanpa menunggu satu per satu)
for p in $ALL_PROJECTS; do
  if oc get project "$p" >/dev/null 2>&1; then
    oc delete project "$p" --wait=false >/dev/null 2>&1 \
      && echo "  ${G}hapus${N} project $p" \
      || echo "  ${Y}gagal${N} hapus project $p (cek hak akses)"
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
echo "Menunggu project terhapus..."
for _ in $(seq 1 60); do
  left=""
  for p in $ALL_PROJECTS; do oc get project "$p" >/dev/null 2>&1 && left="$left $p"; done
  [ -z "$left" ] && break
  sleep 5
done
if [ -n "${left:-}" ]; then
  echo "${Y}Masih dalam proses terhapus:${N}$left (biasanya selesai dalam 1-2 menit)"
else
  echo "${G}Selesai. Semua project soal sudah bersih.${N}"
fi
