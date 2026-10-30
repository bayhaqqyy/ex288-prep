#!/bin/bash
# ---------------------------------------------------------------
# EX288 Practice Set 2 - preparation script
# Jalankan di workstation lab DO288 (OCP 4.18) sebagai user student.
# Script ini aman diulang: repo Git ditimpa, project soal di-reset.
# ---------------------------------------------------------------
set -euo pipefail

OCP_API="https://api.ocp4.example.com:6443"
OCP_USER="developer"
OCP_PASS="developer"
OCP_ADMIN="admin"
OCP_ADMIN_PASS="redhatocp"
GIT_HOST="git.ocp4.example.com"
GIT_USER="developer"
GIT_PASS="d3v3lop3r"
NEXUS_NPM="http://nexus-infra.apps.ocp4.example.com/repository/npm"
CLASS_REGISTRY="registry.ocp4.example.com:8443"
SET_DIR="/home/student/ex288-set2"
export GIT_TERMINAL_PROMPT=0

log()  { echo -e "\n\033[1;34m[prep]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

# oc login tanpa pernah menunggu input (prep-all menjalankan script dengan
# stdin kosong). Kalau CA cluster belum dipercaya, ulangi dengan insecure.
oc_login() {
  oc login -u "$1" -p "$2" "${OCP_API}" </dev/null >/dev/null 2>&1 \
    || oc login -u "$1" -p "$2" "${OCP_API}" --insecure-skip-tls-verify=true </dev/null >/dev/null
}

login_dev()   { oc_login "${OCP_USER}" "${OCP_PASS}"; }
login_admin() { oc_login "${OCP_ADMIN}" "${OCP_ADMIN_PASS}"; }

# Cek namespace pakai admin di kubeconfig terpisah: developer tidak bisa
# melihat project yang sedang Terminating, jadi tanpa ini project dianggap
# sudah hilang padahal namespace-nya masih ada.
ADMIN_KC="$(mktemp)"
trap 'rm -f "$ADMIN_KC"' EXIT
ADMIN_OK=0
if KUBECONFIG="$ADMIN_KC" oc_login "${OCP_ADMIN}" "${OCP_ADMIN_PASS}" 2>/dev/null; then
  ADMIN_OK=1
fi

ns_exists() {
  if [ "$ADMIN_OK" -eq 1 ]; then
    KUBECONFIG="$ADMIN_KC" oc get namespace "$1" >/dev/null 2>&1
  else
    oc get project "$1" >/dev/null 2>&1
  fi
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

# wait_ns_gone <nama> [detik]: tunggu sampai namespace benar-benar hilang
wait_ns_gone() {
  local p="$1" max="${2:-420}" t=0
  while ns_exists "$p"; do
    if [ "$t" -ge "$max" ]; then
      echo
      warn "Project $p masih Terminating setelah ${max}s. Cek: oc get ns $p -o yaml (sebagai admin)"
      return 1
    fi
    [ "$t" -eq 0 ] && printf '\033[1;34m[prep]\033[0m Menunggu project %s selesai terhapus ' "$p"
    printf '.'
    if [ "$t" -ge 15 ] && finalize_if_stuck "$p"; then
      printf ' (isi sudah kosong, API cluster down -> finalize)'
    fi
    sleep 5; t=$((t + 5))
  done
  [ "$t" -gt 0 ] && echo " hilang (${t}s)"
  return 0
}

# force_empty_ns <nama>: matikan Pod tanpa grace period dan hapus isi project
# lebih dulu, supaya penghapusan namespace tidak menunggu ~30s per Pod.
force_empty_ns() {
  local p="$1" t
  oc delete pods --all -n "$p" --grace-period=0 --force --wait=false >/dev/null 2>&1 || true
  for t in all pvc pipelinerun taskrun; do
    oc delete "$t" --all -n "$p" --grace-period=0 --wait=false >/dev/null 2>&1 || true
  done
}

# reset_project <nama>: hapus project lama (kalau ada), tunggu hilang, buat baru
reset_project() {
  local p="$1"
  if ns_exists "$p"; then
    log "Menghapus project lama $p (force) ..."
    force_empty_ns "$p"
    oc delete project "$p" --wait=false >/dev/null 2>&1 \
      || { [ "$ADMIN_OK" -eq 1 ] && KUBECONFIG="$ADMIN_KC" oc delete namespace "$p" --wait=false >/dev/null 2>&1; } \
      || true
  fi
  wait_ns_gone "$p"
  log "Membuat project $p"
  for _ in $(seq 1 40); do
    oc new-project "$p" >/dev/null 2>&1 && return 0
    sleep 3
  done
  oc new-project "$p"
}

# make_public <nama-repo>: jadikan project GitLab public supaya oc new-app
# bisa membaca repo tanpa kredensial. Token OAuth diambil dari user/password
# GitLab (password grant) dan di-cache selama script berjalan.
GITLAB_TOKEN=""
make_public() {
  local repo="$1" resp
  if [ -z "$GITLAB_TOKEN" ]; then
    GITLAB_TOKEN="$(curl -sk --max-time 20 -X POST "https://${GIT_HOST}/oauth/token" \
      -d grant_type=password -d "username=${GIT_USER}" --data-urlencode "password=${GIT_PASS}" 2>/dev/null \
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)"
  fi
  if [ -z "$GITLAB_TOKEN" ]; then
    warn "Tidak bisa mengambil token GitLab. Ubah repo ${repo} jadi public manual: Settings > General > Visibility."
    return 0
  fi
  resp="$(curl -sk --max-time 20 -X PUT -H "Authorization: Bearer ${GITLAB_TOKEN}" \
    "https://${GIT_HOST}/api/v4/projects/${GIT_USER}%2F${repo}" -d visibility=public 2>/dev/null)"
  if echo "$resp" | grep -q '"visibility":"public"'; then
    log "Repo ${repo} sekarang public"
  else
    warn "Gagal menjadikan ${repo} public (${resp:0:120}). Ubah manual di GitLab: Settings > General > Visibility."
  fi
}

# push_repo <dir> <nama-repo> <branch>
# Tanpa force push (branch di GitLab lab otomatis protected setelah push
# pertama). Kalau repo/branch sudah ada: clone history-nya, ganti isinya
# dengan file soal asli, commit "reset soal", lalu push biasa.
push_repo() {
  local dir="$1" repo="$2" branch="$3" url tmp rc
  url="https://${GIT_USER}:${GIT_PASS}@${GIT_HOST}/${GIT_USER}/${repo}.git"
  tmp="$(mktemp -d)"
  (
    set -e
    cd "$dir"
    rm -rf .git
    if git clone -q -b "$branch" "$url" "$tmp/r" >/dev/null 2>&1; then
      mv "$tmp/r/.git" .git
      git config user.name "Student"
      git config user.email "student@ocp4.example.com"
      git add -A
      if git diff --cached --quiet; then
        echo "    repo sudah berisi file soal asli, tidak ada perubahan"
      else
        git commit -qm "EX288 practice set 2: reset soal"
        git push -q origin "$branch"
      fi
    else
      git init -q -b "$branch"
      git config user.name "Student"
      git config user.email "student@ocp4.example.com"
      git add -A
      git commit -qm "EX288 practice set 2: initial files"
      git remote add origin "$url"
      git push -q -u origin "$branch"
    fi
  )
  rc=$?
  rm -rf "$tmp"
  [ "$rc" -eq 0 ] || return "$rc"
  make_public "$repo"
  log "Repo https://${GIT_HOST}/${GIT_USER}/${repo}.git (branch ${branch}) siap"
}

store_git_cred() {
  cd "$HOME"
  git config --global credential.helper store
  echo "https://${GIT_USER}:${GIT_PASS}@${GIT_HOST}" > ~/.git-credentials
  chmod 600 ~/.git-credentials
}

check_npm_pkg() {
  local pkg="$1"
  if curl -sf --max-time 10 -o /dev/null "${NEXUS_NPM}/${pkg}"; then
    log "Nexus punya paket npm '${pkg}'"
  else
    warn "Paket npm '${pkg}' tidak terjangkau di ${NEXUS_NPM}. Build bisa gagal karena lingkungan, bukan karena jawabanmu."
  fi
}

# ===== Soal 13: Kustomisasi S2I assemble + run httpd (ref 01-02 customizing S2I) =====
WORK="${SET_DIR}/q13"
login_dev
reset_project builds-s2i
rm -rf "$WORK"; mkdir -p "$WORK/hello/.s2i/bin"
cd "$WORK/hello"

cat > index.html <<'EOF'
<html><body><h1>Hello from custom S2I</h1></body></html>
EOF

# BUG (disengaja): assemble tidak executable dan belum membuat info.html,
# run script belum ada.
cat > .s2i/bin/assemble <<'EOF'
#!/bin/bash
set -e
source ${HTTPD_CONTAINER_SCRIPTS_PATH}/common.sh

echo "---> Enabling s2i support in httpd24 image"
config_s2i

######## CUSTOMIZATION STARTS HERE ############
echo "---> Installing application source"
cp -Rf /tmp/src/*.html ./
# TODO: buat info.html
######## CUSTOMIZATION ENDS HERE ############

# Fix source directory permissions
fix-permissions ./
EOF
chmod 644 .s2i/bin/assemble

push_repo "$WORK/hello" hello-s2i main
cd "$HOME"; rm -rf "$WORK"
store_git_cred
log "Soal 13 siap. Project: builds-s2i"
