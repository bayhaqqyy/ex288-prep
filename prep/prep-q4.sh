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

log()  { echo -e "\n\033[1;34m[prep]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

login_dev() {
  oc login -u "${OCP_USER}" -p "${OCP_PASS}" "${OCP_API}" >/dev/null
}

login_admin() {
  oc login -u "${OCP_ADMIN}" -p "${OCP_ADMIN_PASS}" "${OCP_API}" >/dev/null
}

# reset_project <nama>: hapus project lama (kalau ada) lalu buat baru
reset_project() {
  local p="$1"
  if oc get project "$p" >/dev/null 2>&1; then
    log "Menghapus project lama $p ..."
    oc delete project "$p" --wait=true >/dev/null
    # tunggu sampai benar-benar hilang
    for _ in $(seq 1 60); do
      oc get project "$p" >/dev/null 2>&1 || break
      sleep 3
    done
  fi
  log "Membuat project $p"
  for _ in $(seq 1 20); do
    oc new-project "$p" >/dev/null 2>&1 && return 0
    sleep 3
  done
  oc new-project "$p"
}

# push_repo <dir> <nama-repo> <branch>
push_repo() {
  local dir="$1" repo="$2" branch="$3"
  ( cd "$dir"
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
  git config --global credential.helper store
  echo "https://${GIT_USER}:${GIT_PASS}@${GIT_HOST}" > ~/.git-credentials
  chmod 600 ~/.git-credentials
}

check_npm_pkg() {
  local pkg="$1"
  if curl -sf -o /dev/null "${NEXUS_NPM}/${pkg}"; then
    log "Nexus punya paket npm '${pkg}'"
  else
    warn "Paket npm '${pkg}' tidak terjangkau di ${NEXUS_NPM}. Build bisa gagal karena lingkungan, bukan karena jawabanmu."
  fi
}

# ===== Soal 4: httpd Docker build dengan binary tar di BuildConfig =====
WORK="${SET_DIR}/q4"
login_dev
reset_project deploy-docs

rm -rf "$WORK"; mkdir -p "$WORK"
cd "$WORK"

make_bundle() {
  local ver="$1" tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/content"
  cat > "$tmp/content/index.html" <<EOF
<html><body><h1>EX288 Docs Site ${ver}</h1></body></html>
EOF
  echo "ok" > "$tmp/content/health.html"
  tar -czf "$tmp/site-content.tar.gz" -C "$tmp/content" .

  # FROM sengaja pakai nama pendek. Build akan gagal kalau
  # BuildConfig tidak menimpa FROM dengan ImageStreamTag yang benar.
  cat > "$tmp/Dockerfile" <<'EOF'
FROM httpd:2.4-ubi9
ADD site-content.tar.gz /var/www/html/
EXPOSE 8080
CMD ["run-httpd"]
EOF
  tar -cf "$WORK/docs-site-${ver}.tar" -C "$tmp" Dockerfile site-content.tar.gz
  rm -rf "$tmp"
}

make_bundle v1
make_bundle v2
log "Binary tersedia: $WORK/docs-site-v1.tar dan $WORK/docs-site-v2.tar"
log "Soal 4 siap. Project: deploy-docs"
