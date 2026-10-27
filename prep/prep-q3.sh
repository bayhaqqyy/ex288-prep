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

login_dev() {
  oc login -u "${OCP_USER}" -p "${OCP_PASS}" "${OCP_API}" >/dev/null
}

login_admin() {
  oc login -u "${OCP_ADMIN}" -p "${OCP_ADMIN_PASS}" "${OCP_API}" >/dev/null
}

# Cek namespace pakai admin di kubeconfig terpisah: developer tidak bisa
# melihat project yang sedang Terminating, jadi tanpa ini project dianggap
# sudah hilang padahal namespace-nya masih ada.
ADMIN_KC="$(mktemp)"
trap 'rm -f "$ADMIN_KC"' EXIT
ADMIN_OK=0
if KUBECONFIG="$ADMIN_KC" oc login -u "${OCP_ADMIN}" -p "${OCP_ADMIN_PASS}" "${OCP_API}" >/dev/null 2>&1 \
   || KUBECONFIG="$ADMIN_KC" oc login -u "${OCP_ADMIN}" -p "${OCP_ADMIN_PASS}" "${OCP_API}" --insecure-skip-tls-verify=true >/dev/null 2>&1; then
  ADMIN_OK=1
fi

ns_exists() {
  if [ "$ADMIN_OK" -eq 1 ]; then
    KUBECONFIG="$ADMIN_KC" oc get namespace "$1" >/dev/null 2>&1
  else
    oc get project "$1" >/dev/null 2>&1
  fi
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
    sleep 5; t=$((t + 5))
  done
  [ "$t" -gt 0 ] && echo " hilang (${t}s)"
  return 0
}

# reset_project <nama>: hapus project lama (kalau ada), tunggu hilang, buat baru
reset_project() {
  local p="$1"
  if ns_exists "$p"; then
    log "Menghapus project lama $p ..."
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

# push_repo <dir> <nama-repo> <branch>
push_repo() {
  local dir="$1" repo="$2" branch="$3"
  ( cd "$dir" || exit 1
    rm -rf .git
    git init -q -b "$branch"
    git config user.name "Student"
    git config user.email "student@ocp4.example.com"
    git add -A
    git commit -qm "EX288 practice set 2: initial files"
    git remote add origin "https://${GIT_USER}:${GIT_PASS}@${GIT_HOST}/${GIT_USER}/${repo}.git"
    git push -q -u origin "$branch" --force )
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

# ===== Soal 3: S2I httpd - SERVER_PORT=8081 lewat S2I script =====
WORK="${SET_DIR}/q3"
login_dev
reset_project deploy-portal

rm -rf "$WORK"; mkdir -p "$WORK/site/.s2i/bin"
cd "$WORK/site"

cat > index.html <<'EOF'
<html>
  <body>
    <h1>EX288 Portal</h1>
    <p>Served by httpd S2I</p>
  </body>
</html>
EOF

cat > .s2i/bin/run <<'EOF'
#!/bin/bash
source ${HTTPD_CONTAINER_SCRIPTS_PATH}/common.sh
export HTTPD_RUN_BY_S2I=1

echo "---> Starting portal, SERVER_PORT=${SERVER_PORT:-not-set}"

# Make Apache show 'debug' level logs during start up
exec run-httpd -e debug $@
EOF
chmod +x .s2i/bin/run

push_repo "$WORK" portal-s2i main
cd "$HOME"; rm -rf "$WORK"
store_git_cred
log "Soal 3 siap. Project: deploy-portal"
