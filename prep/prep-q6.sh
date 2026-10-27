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

# ===== Soal 6: Template build + template deploy =====
WORK="${SET_DIR}/q6"
login_dev
reset_project lion
check_npm_pkg express

rm -rf "$WORK"; mkdir -p "$WORK/app" "$WORK/templates"
cd "$WORK"

cat > app/package.json <<'EOF'
{
  "name": "shop-ui",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.20.0"
  }
}
EOF

cat > app/server.js <<'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;
const backend = process.env.BACKEND_URL || 'not-set';

app.get('/', (req, res) => {
  res.send(`shop-ui frontend. Backend: ${backend}\n`);
});

app.listen(port, () => console.log(`shop-ui listening on ${port}`));
EOF

# GAP (disengaja): REGISTRY_URL dipakai di output build tapi belum
# dideklarasikan sebagai parameter, belum ada source secret, belum ada label.
cat > templates/shop-build.yaml <<'EOF'
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: shop-ui-build
objects:
- apiVersion: image.openshift.io/v1
  kind: ImageStream
  metadata:
    name: ${NAME}
- apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: ${NAME}
  spec:
    source:
      type: Git
      git:
        uri: ${GIT_URL}
        ref: ${GIT_REF}
      contextDir: ${CONTEXT_DIR}
    strategy:
      type: Source
      sourceStrategy:
        from:
          kind: ImageStreamTag
          namespace: openshift
          name: nodejs:18-ubi9
        env:
        - name: npm_config_registry
          value: ${NPM_REGISTRY}
    output:
      to:
        kind: DockerImage
        name: ${REGISTRY_URL}/${IMAGE_NAMESPACE}/${NAME}:latest
    triggers:
    - type: ConfigChange
parameters:
- name: NAME
  description: Application name
  required: true
- name: GIT_URL
  description: Git repository URL
  required: true
- name: GIT_REF
  description: Git branch
  value: main
- name: CONTEXT_DIR
  description: Application source directory
  required: true
- name: NPM_REGISTRY
  description: NPM registry URL
  required: true
- name: IMAGE_NAMESPACE
  description: Registry namespace (project) for the image
  required: true
EOF

# GAP (disengaja): selector Deployment tidak cocok dengan label Pod.
cat > templates/shop-deploy.yaml <<'EOF'
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: shop-ui-deploy
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: ${NAME}
  spec:
    replicas: ${{REPLICAS}}
    selector:
      matchLabels:
        app: shop
    template:
      metadata:
        labels:
          app: ${NAME}
      spec:
        containers:
        - name: ${NAME}
          image: ${REGISTRY_URL}/${IMAGE_NAMESPACE}/${NAME}:latest
          imagePullPolicy: Always
          ports:
          - containerPort: 8080
          env:
          - name: BACKEND_URL
            value: ${BACKEND_URL}
- apiVersion: v1
  kind: Service
  metadata:
    name: ${NAME}
  spec:
    selector:
      app: ${NAME}
    ports:
    - port: 8080
      targetPort: 8080
- apiVersion: route.openshift.io/v1
  kind: Route
  metadata:
    name: ${NAME}
  spec:
    host: ${APP_HOST}
    to:
      kind: Service
      name: ${NAME}
    tls:
      termination: edge
parameters:
- name: NAME
  description: Application name
  required: true
- name: REGISTRY_URL
  description: Container image registry URL
  required: true
- name: IMAGE_NAMESPACE
  description: Registry namespace (project) for the image
  required: true
- name: REPLICAS
  description: Number of pods
  value: "1"
- name: BACKEND_URL
  description: Public backend URL
  required: true
- name: APP_HOST
  description: Route hostname
  required: true
EOF

push_repo "$WORK" shop-ui v2
rm -rf "$WORK"
store_git_cred
log "Soal 6 siap. Project: lion"
