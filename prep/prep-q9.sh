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
      | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null || true)"
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

# ===== Soal 9: OpenShift Pipelines - perbaiki YAML pipeline + trigger (aplikasi Maven) =====
# Peserta menerima YAML lengkap (PVC, Pipeline, PipelineRun, TriggerBinding,
# TriggerTemplate, Trigger, EventListener). Pipeline dan TriggerTemplate
# sengaja berisi nilai yang salah, termasuk build arg Maven mirror.
WORK="${SET_DIR}/q9"
NEXUS_JAVA="http://nexus-infra.apps.ocp4.example.com/repository/java"
login_dev
if ! oc api-resources --api-group=tekton.dev 2>/dev/null | grep -q '^pipelines '; then
  warn "CRD Tekton tidak terdeteksi. Pastikan operator OpenShift Pipelines terpasang."
fi
oc api-resources --api-group=triggers.tekton.dev 2>/dev/null | grep -q eventlisteners \
  || warn "CRD Tekton Triggers (EventListener) tidak terdeteksi. Bagian trigger Soal 9 butuh operator OpenShift Pipelines lengkap."
curl -s --max-time 10 -o /dev/null "${NEXUS_JAVA}/" \
  || warn "Nexus java (${NEXUS_JAVA}) tidak terjangkau. Build Maven bisa gagal karena lingkungan."
reset_project pipeline-lab

# Nama parameter task ClusterTask/cluster-resolver berbeda antar versi
# OpenShift Pipelines, jadi YAML dibuat sesuai versi yang terpasang.
task_params() {
  local kc=""
  [ "$ADMIN_OK" -eq 1 ] && kc="$ADMIN_KC"
  KUBECONFIG="${kc:-$KUBECONFIG}" oc get task "$1" -n openshift-pipelines \
    -o jsonpath='{range .spec.params[*]}{.name}{" "}{.type}{"\n"}{end}' 2>/dev/null
}
has_param() { echo "$1" | awk '{print $1}' | grep -qx "$2"; }
pick() { # daftar-param kandidat... -> nama pertama yang ada
  local list="$1" c; shift
  for c in "$@"; do has_param "$list" "$c" && { echo "$c"; return; }; done
  echo "$1"
}
GC="$(task_params git-clone)"; BH="$(task_params buildah)"; OC_T="$(task_params openshift-client)"
[ -n "$GC" ] || warn "Task git-clone tidak terlihat di openshift-pipelines (cek: oc get tasks -n openshift-pipelines)"
[ -n "$BH" ] || warn "Task buildah tidak terlihat di openshift-pipelines"
[ -n "$OC_T" ] || warn "Task openshift-client tidak terlihat di openshift-pipelines"
GC_URL="$(pick "$GC" URL url)"; GC_REV="$(pick "$GC" REVISION revision)"
BH_TLS="$(pick "$BH" TLSVERIFY TLS_VERIFY)"
OC_SCRIPT="$(pick "$OC_T" SCRIPT script)"
# Build arg: BUILD_ARGS (array) kalau tersedia, kalau tidak BUILD_EXTRA_ARGS (string)
if echo "$BH" | grep -qE '^BUILD_ARGS array'; then
  BUILD_ARG_BLOCK='    - name: BUILD_ARGS
      value:
      - MAVEN_REPO=$(params.MAVEN_MIRROR_URL)'
else
  BUILD_ARG_BLOCK='    - name: BUILD_EXTRA_ARGS
      value: --build-arg MAVEN_REPO=$(params.MAVEN_MIRROR_URL)'
fi

# ---------- Repo aplikasi Maven (sumber dari DO288-apps, sama seperti Soal 11) ----------
rm -rf "$WORK"; mkdir -p "$WORK"
cd "$WORK"
if ! git clone -q --depth 1 "https://${GIT_USER}:${GIT_PASS}@${GIT_HOST}/${GIT_USER}/DO288-apps.git" apps-src; then
  echo "Repo DO288-apps tidak ditemukan di GitLab lab. Soal 9 butuh repo bawaan kelas DO288."; exit 1
fi
SRC=""
for cand in '*/docker-app/myapp1-docker' '*/builds-review/expense-service' \
            '*/deployments-applications/expense-service' '*/expense-service'; do
  SRC="$(find apps-src -type d -path "$cand" -not -path '*/.git/*' 2>/dev/null | sort | head -1)"
  [ -n "$SRC" ] && [ -f "$SRC/pom.xml" ] && break
  SRC=""
done
[ -n "$SRC" ] || { echo "Tidak ada proyek Maven (myapp1-docker / expense-service) di DO288-apps"; exit 1; }
log "Memakai proyek Maven dari DO288-apps: ${SRC#apps-src/}"
mkdir -p repo
cp -r "$SRC"/. repo/
rm -rf repo/.git repo/target repo/.s2i repo/Dockerfile repo/Containerfile apps-src

# settings.xml membaca mirror dari env MAVEN_MIRROR_URL (diisi lewat build arg)
cat > repo/settings.xml <<'EOF'
<settings>
  <mirrors>
    <mirror>
      <id>build-mirror</id>
      <mirrorOf>*</mirrorOf>
      <url>${env.MAVEN_MIRROR_URL}</url>
    </mirror>
  </mirrors>
</settings>
EOF

cat > repo/Containerfile <<EOF
FROM ${CLASS_REGISTRY}/redhattraining/ocpdev-ubi8-openjdk-17-base:1.16

# URL Maven mirror wajib diisi saat build: --build-arg MAVEN_MIRROR_URL=<url>
ARG MAVEN_MIRROR_URL

COPY settings.xml pom.xml ./
COPY src src
RUN test -n "\${MAVEN_MIRROR_URL}" || { echo "ERROR: build arg MAVEN_MIRROR_URL is not set"; exit 1; } \\
 && mvn -B -s settings.xml clean package -DskipTests

ENV BUILT_BY=tekton
EXPOSE 8080
CMD java -jar \$(ls target/*-runner.jar target/quarkus-app/quarkus-run.jar 2>/dev/null | head -1)
EOF
EP="$(grep -rhoP '@Path\("\K[^"{]+' repo/src/main/java 2>/dev/null | head -1)"
[ -n "$EP" ] && log "Endpoint REST aplikasi: ${EP}"
push_repo "$WORK/repo" tekton-maven main
cd "$HOME"; rm -rf "$WORK/repo"

# ---------- YAML yang diberikan ke peserta ----------
cat > "$WORK/pvc.yaml" <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: maven-workspace
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Pipeline: nilai SALAH yang disengaja ditandai di kunci jawaban, bukan di sini.
cat > "$WORK/pipeline.yaml" <<EOF
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: maven-build-deploy
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
  - name: MAVEN_MIRROR_URL
    type: string
    default: https://repo.maven.apache.org/maven2
  workspaces:
  - name: source
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
    - name: ${GC_URL}
      value: \$(params.GIT_URL)
    - name: ${GC_REV}
      value: master
    workspaces:
    - name: output
      workspace: source
  - name: build-image
    runAfter:
    - fetch-source
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: buildah
      - name: namespace
        value: openshift-pipelines
    params:
    - name: IMAGE
      value: \$(params.IMAGE)
    - name: DOCKERFILE
      value: ./Dockerfile
    - name: ${BH_TLS}
      value: "false"
${BUILD_ARG_BLOCK}
    workspaces:
    - name: source
      workspace: source
  - name: deploy
    runAfter:
    - build-image
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: openshift-client
      - name: namespace
        value: openshift-pipelines
    params:
    - name: ${OC_SCRIPT}
      value: |
        oc get deployment \$(params.APP_NAME) >/dev/null 2>&1 || \\
          oc create deployment \$(params.APP_NAME) --image=\$(params.IMAGE) --port=8080
        oc rollout restart deployment/\$(params.APP_NAME)
        oc rollout status deployment/\$(params.APP_NAME) --timeout=300s
        oc get service \$(params.APP_NAME) >/dev/null 2>&1 || \\
          oc expose deployment \$(params.APP_NAME) --port=8080
        oc get route \$(params.APP_NAME) >/dev/null 2>&1 || \\
          oc expose service \$(params.APP_NAME)
EOF

cat > "$WORK/pipelinerun.yaml" <<'EOF'
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: maven-build-deploy-run-
spec:
  pipelineRef:
    name: maven-build-deploy
  taskRunTemplate:
    serviceAccountName: pipeline
  params:
  - name: GIT_URL
    value: https://git.ocp4.example.com/developer/tekton-maven.git
  - name: GIT_REVISION
    value: main
  - name: IMAGE
    value: image-registry.openshift-image-registry.svc:5000/pipeline-lab/tekton-maven:latest
  - name: APP_NAME
    value: tekton-maven
  workspaces:
  - name: source
    persistentVolumeClaim:
      claimName: maven-workspace
EOF

cat > "$WORK/trigger-binding.yaml" <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: maven-binding
spec:
  params:
  - name: git-url
    value: $(body.git_url)
  - name: git-revision
    value: $(body.revision)
EOF

cat > "$WORK/trigger-template.yaml" <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: maven-template
spec:
  params:
  - name: git-url
  - name: git-revision
    default: main
  resourcetemplates:
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      generateName: maven-build-deploy-trigger-
    spec:
      pipelineRef:
        name: maven-pipeline
      taskRunTemplate:
        serviceAccountName: pipeline
      params:
      - name: GIT_URL
        value: $(tt.params.git-url)
      - name: GIT_REVISION
        value: $(tt.params.git-revision)
      - name: IMAGE
        value: image-registry.openshift-image-registry.svc:5000/openshift/tekton-maven:latest
      - name: APP_NAME
        value: tekton-maven
      workspaces:
      - name: source
        persistentVolumeClaim:
          claimName: maven-pvc
EOF

cat > "$WORK/trigger.yaml" <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: Trigger
metadata:
  name: maven-trigger
spec:
  serviceAccountName: pipeline
  bindings:
  - ref: maven-binding
  template:
    ref: maven-template
EOF

cat > "$WORK/event-listener.yaml" <<'EOF'
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: maven-listener
spec:
  serviceAccountName: pipeline
  triggers:
  - triggerRef: maven-trigger
EOF

# Hak akses EventListener untuk SA pipeline (bukan bagian dari soal)
if [ "$ADMIN_OK" -eq 1 ]; then
  KUBECONFIG="$ADMIN_KC" oc policy add-role-to-user tekton-triggers-eventlistener-roles \
    -z pipeline -n pipeline-lab >/dev/null 2>&1 \
    || warn "Gagal memberi role tekton-triggers-eventlistener-roles ke SA pipeline."
  KUBECONFIG="$ADMIN_KC" oc adm policy add-cluster-role-to-user tekton-triggers-eventlistener-clusterroles \
    -z pipeline -n pipeline-lab >/dev/null 2>&1 \
    || warn "Gagal memberi role tekton-triggers-eventlistener-clusterroles ke SA pipeline. EventListener bisa CrashLoopBackOff (forbidden)."
else
  warn "Tidak bisa login admin. Kalau pod EventListener forbidden, beri role triggers ke SA pipeline (lihat kunci)."
fi

store_git_cred
log "Soal 9 siap. Project: pipeline-lab. YAML ada di $WORK:"
ls -1 "$WORK" | sed 's/^/    /'
