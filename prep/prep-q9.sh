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

# ===== Soal 9: Deploy lewat OpenShift Pipelines (Tekton) =====
WORK="${SET_DIR}/q9"
login_dev
if ! oc get crd pipelines.tekton.dev >/dev/null 2>&1 && ! oc api-resources 2>/dev/null | grep -q '^pipelines '; then
  warn "CRD Tekton tidak terdeteksi. Pastikan operator OpenShift Pipelines terpasang."
fi
for t in git-clone buildah openshift-client; do
  oc get task "$t" -n openshift-pipelines >/dev/null 2>&1 \
    || warn "Task $t tidak terlihat di namespace openshift-pipelines (cek: oc get tasks -n openshift-pipelines)"
done
reset_project pipeline-lab

# Repo aplikasi
rm -rf "$WORK"; mkdir -p "$WORK/repo"
cd "$WORK/repo"
cat > Containerfile <<EOF
FROM ${CLASS_REGISTRY}/redhattraining/hello-world-nginx:v1.0
LABEL org.opencontainers.image.title="tekton-web" \\
      org.opencontainers.image.description="EX288 practice image built by Tekton"
ENV BUILT_BY=tekton
EOF
cat > README.md <<'EOF'
# tekton-web
Aplikasi latihan EX288 yang di-build dan di-deploy lewat OpenShift Pipelines.
EOF
push_repo "$WORK/repo" tekton-web main
rm -rf "$WORK/repo"

# Skeleton pipeline untuk dilengkapi peserta
cat > "$WORK/pipeline-skeleton.yaml" <<'EOF'
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: build-and-deploy
spec:
  params:
  - name: GIT_URL
    type: string
  - name: GIT_REVISION
    type: string
    default: main
  - name: IMAGE
    type: string
  - name: APP_NAME
    type: string
  workspaces:
  - name: shared-workspace
  tasks:
  - name: fetch-source
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: git-clone
      - name: namespace
        value: openshift-pipelines
    params:
    - name: URL
      value: $(params.GIT_URL)
    - name: REVISION
      value: $(params.GIT_REVISION)
    workspaces:
    - name: output
      workspace: shared-workspace
  # TODO 1: task "build-image" (buildah) setelah fetch-source
  # TODO 2: task "deploy" (openshift-client) setelah build-image
EOF
store_git_cred
log "Soal 9 siap. Project: pipeline-lab. Skeleton: $WORK/pipeline-skeleton.yaml"
