#!/bin/bash
# ---------------------------------------------------------------
# EX288 Prep - script penilaian (total 300, lulus >= 210)
#
#   bash grade/grade.sh          # nilai semua soal
#   bash grade/grade.sh 1 5 7    # nilai soal tertentu saja
#
# Jalankan di workstation lab DO288 sebagai student. Script login
# sebagai admin di KUBECONFIG terpisah (hanya membaca), jadi sesi
# oc milikmu tidak berubah. Repo Git lab di-clone ke folder sementara.
# ---------------------------------------------------------------
set -u

OCP_API="https://api.ocp4.example.com:6443"
OCP_ADMIN="admin"
OCP_ADMIN_PASS="redhatocp"
GIT_BASE="https://developer:d3v3lop3r@git.ocp4.example.com/developer"
NEXUS_NPM="http://nexus-infra.apps.ocp4.example.com/repository/npm"
APPS="apps.ocp4.example.com"
INT_REG="image-registry.openshift-image-registry.svc:5000"
PASS_MARK=210
REPORT_DIR="/home/student/ex288-set2"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export KUBECONFIG="$TMP/kubeconfig"

if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; Y=; B=; N=; fi

mkdir -p "$REPORT_DIR" 2>/dev/null || REPORT_DIR="$TMP"
REPORT="$REPORT_DIR/grade-report-$(date +%Y%m%d-%H%M).txt"
: > "$REPORT"
out()  { printf '%s\n' "$*"; printf '%s\n' "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT"; }

declare -A SCORE MAXQ
TITLE=(
  ""
  "S2I Node.js: JSON error + prom-client devDependencies"
  "Docker build + env Nexus"
  "S2I httpd SERVER_PORT=8081"
  "Binary tar build httpd"
  "ConfigMap + Secret PostgreSQL"
  "Template build + deploy"
  "Helm lab + production"
  "Startup, liveness, readiness probe"
  "OpenShift Pipelines (Tekton)"
  "Expose internal registry + push"
  "Troubleshoot Docker build Maven"
  "Podman build + push + ImageStream"
  "Kustomisasi S2I assemble + run"
  "Optimasi Containerfile + ONBUILD"
  "Build hook + config map + webhook"
  "S2I Java: Maven mirror + incremental"
)

# Objective ujian EX288 (urutan sama dengan laporan hasil resmi Red Hat)
OBJ_KEYS=(OCP MULTI IMG TRBL IS CMS S2I TPL PIPE)
declare -A OBJ_NAME=(
  [OCP]="Work with Red Hat OpenShift Container Platform"
  [MULTI]="Deploy multi-container applications"
  [IMG]="Work with container images in OpenShift Container Platform"
  [TRBL]="Troubleshoot application builds and deployment issues"
  [IS]="Work with image streams"
  [CMS]="Work with configuration maps and secrets"
  [S2I]="Work with the source-to-image (S2I) framework"
  [TPL]="Work with templates"
  [PIPE]="Work with OpenShift Pipelines"
)
declare -A OSC OMX   # key: "<core|extra>:<OBJ>"

# hint <teks>: alasan kegagalan yang dicetak di bawah baris [FAIL]
HINT_FILE="$TMP/hint"
hint() { printf '%s\n' "$*" >> "$HINT_FILE"; }

# check <soal> <objective> <poin> <deskripsi> <perintah...>
check() {
  local q="$1" obj="$2" pts="$3" desc="$4" set=core; shift 4
  [ "$q" -le 10 ] || set=extra
  MAXQ[$q]=$(( ${MAXQ[$q]:-0} + pts ))
  OMX[$set:$obj]=$(( ${OMX[$set:$obj]:-0} + pts ))
  : > "$HINT_FILE"
  if "$@" >/dev/null 2>&1; then
    SCORE[$q]=$(( ${SCORE[$q]:-0} + pts ))
    OSC[$set:$obj]=$(( ${OSC[$set:$obj]:-0} + pts ))
    out "  ${G}[PASS]${N} $(printf '%2d' "$pts") poin  $(printf '%-5s' "$obj")  $desc"
  else
    SCORE[$q]=$(( ${SCORE[$q]:-0} ))
    OSC[$set:$obj]=$(( ${OSC[$set:$obj]:-0} ))
    out "  ${R}[FAIL]${N} $(printf '%2d' "$pts") poin  $(printf '%-5s' "$obj")  $desc"
    while IFS= read -r h; do out "                       ${Y}-> $h${N}"; done < "$HINT_FILE"
  fi
}

# objective_report <core|extra>: persentase per objective seperti email hasil EX288
objective_report() {
  local set="$1" k mx pct
  out "Performance on exam objectives:"
  out ""
  out "      OBJECTIVE: SCORE"
  for k in "${OBJ_KEYS[@]}"; do
    mx="${OMX[$set:$k]:-0}"
    if [ "$mx" -gt 0 ]; then
      pct=$(( (OSC[$set:$k] * 100 + mx / 2) / mx ))
      out "      ${OBJ_NAME[$k]}: ${pct}%"
    else
      out "      ${OBJ_NAME[$k]}: -"
    fi
  done
}

# ---------- helper ----------
jp()          { oc get -n "$1" "$2" -o jsonpath="$3" 2>/dev/null; }
jp_eq() {
  local v; v="$(jp "$1" "$2" "$3")"
  [ "$v" = "$4" ] && return 0
  hint "$2 $3 = '${v:-kosong}', harus '$4'"; return 1
}
jp_has() {
  local v; v="$(jp "$1" "$2" "$3")"
  printf '%s' "$v" | grep -qF -- "$4" && return 0
  hint "$2 $3 = '${v:-kosong}', harus memuat '$4'"; return 1
}
jp_nonempty() { [ -n "$(jp "$1" "$2" "$3")" ] && return 0; hint "$2 $3 kosong"; return 1; }
exists() { oc get -n "$1" "$2" >/dev/null 2>&1 && return 0; hint "$2 tidak ada di project $1"; return 1; }
# url_eq / dir_eq: sama seperti jp_eq, tapi abaikan garis miring di ujung (dan ./ di awal untuk path)
url_eq() {
  local v; v="$(jp "$1" "$2" "$3")"
  [ "${v%/}" = "${4%/}" ] && return 0
  hint "$2 $3 = '${v:-kosong}', harus '$4'"; return 1
}
dir_eq() {
  local v n; v="$(jp "$1" "$2" "$3")"; n="${v#./}"; n="${n#/}"; n="${n%/}"
  [ "$n" = "$4" ] && return 0
  hint "$2 $3 = '${v:-kosong}', harus '$4'"; return 1
}

deploy_ready() { # ns name [replicas]
  local want="${3:-}" ready spec
  ready="$(jp "$1" "deploy/$2" '{.status.readyReplicas}')"
  spec="$(jp "$1" "deploy/$2" '{.spec.replicas}')"
  if [ -n "$ready" ] && [ "$ready" = "$spec" ] && { [ -z "$want" ] || [ "$spec" = "$want" ]; }; then return 0; fi
  if ! oc get -n "$1" "deploy/$2" >/dev/null 2>&1; then hint "deploy/$2 tidak ada di project $1"
  else hint "deploy/$2 ready ${ready:-0}/${spec:-?}${want:+ (butuh $want replica)}"; fi
  return 1
}

build_complete() { # ns bc  -> build terakhir Complete
  local v; v="$(jp "$1" "bc/$2" '{.status.lastVersion}')"
  [ -n "$v" ] || { hint "bc/$2 tidak ada atau belum pernah build"; return 1; }
  jp_eq "$1" "build/$2-$v" '{.status.phase}' Complete
}

route_ok() { # ns name host termination insecurePolicy  ("-" = abaikan)
  local ns="$1" n="$2"
  [ "$3" = "-" ] || jp_eq "$ns" "route/$n" '{.spec.host}' "$3" || return 1
  [ "$4" = "-" ] || jp_eq "$ns" "route/$n" '{.spec.tls.termination}' "$4" || return 1
  [ "$5" = "-" ] || jp_eq "$ns" "route/$n" '{.spec.tls.insecureEdgeTerminationPolicy}' "$5" || return 1
}

http_has() {
  local b; b="$(curl -sk --max-time 15 "$1")"
  printf '%s' "$b" | grep -qF -- "$2" && return 0
  hint "$1 tidak memuat '$2' (respons: '$(printf '%s' "$b" | head -c 80 | tr '\n' ' ')')"; return 1
}
http_code() {
  local c; c="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$1")"
  [ "$c" = "$2" ] && return 0
  hint "$1 -> HTTP $c, harus $2"; return 1
}

pod_env() { # ns deploy var value
  local v; v="$(oc exec -n "$1" "deploy/$2" -- printenv "$3" 2>/dev/null)"
  [ "$v" = "$4" ] && return 0
  hint "printenv $3 di deploy/$2 = '${v:-kosong}', harus '$4'"; return 1
}

git_dir() { # repo branch -> path clone (cache)
  local d="$TMP/git-$1-$2"
  [ -d "$d" ] || git clone -q --depth 1 -b "$2" "$GIT_BASE/$1.git" "$d" >/dev/null 2>&1 \
    || { hint "repo $1 branch $2 tidak bisa di-clone dari GitLab"; return 1; }
  printf '%s' "$d"
}
git_grep() { # repo branch file regex
  local d; d="$(git_dir "$1" "$2")" || return 1
  [ -f "$d/$3" ] || { hint "$3 tidak ada di repo $1 branch $2"; return 1; }
  grep -qE -- "$4" "$d/$3" && return 0
  hint "$3 di repo $1 ($2) belum sesuai (commit terakhir: $(git -C "$d" log -1 --format='%h %s' 2>/dev/null))"; return 1
}

# yaml_json <file>: ubah YAML ke JSON (PyYAML, atau oc sebagai cadangan)
yaml_json() {
  python3 -c 'import sys,json,yaml; json.dump(yaml.safe_load(open(sys.argv[1])),sys.stdout)' "$1" 2>/dev/null \
    || oc create --dry-run=client -o json -f "$1" 2>/dev/null
}

admin_login() {
  oc login -u "$OCP_ADMIN" -p "$OCP_ADMIN_PASS" "$OCP_API" >/dev/null 2>&1 \
    || oc login -u "$OCP_ADMIN" -p "$OCP_ADMIN_PASS" "$OCP_API" --insecure-skip-tls-verify=true >/dev/null 2>&1
}

# =================== SOAL 1 ===================
q1_git() {
  local d; d="$(git_dir metrics-api release-v1)" || return 1
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "prom-client" in d.get("dependencies",{}) else 1)' \
    "$d/apps/metrics/package.json" 2>/dev/null
}
q1_bc() {
  jp_has metrics-prod bc/metrics-api '{.spec.source.git.uri}' 'developer/metrics-api' &&
  jp_eq metrics-prod bc/metrics-api '{.spec.source.git.ref}' release-v1 &&
  dir_eq metrics-prod bc/metrics-api '{.spec.source.contextDir}' apps/metrics
}
q1_builder() {
  jp_eq metrics-prod bc/metrics-api '{.spec.strategy.sourceStrategy.from.name}' nodejs:18-ubi9 &&
  jp_eq metrics-prod bc/metrics-api '{.spec.strategy.sourceStrategy.from.namespace}' openshift
}
grade_q1() {
  local ns=metrics-prod
  check 1 S2I 4 "BuildConfig metrics-api: repo, branch release-v1, context apps/metrics" q1_bc
  check 1 S2I 3 "Builder openshift/nodejs:18-ubi9" q1_builder
  check 1 CMS 4 "Git secret terpasang sebagai sourceSecret BuildConfig" jp_nonempty $ns bc/metrics-api '{.spec.source.sourceSecret.name}'
  check 1 S2I 3 "Build env npm_config_registry = Nexus" url_eq $ns bc/metrics-api '{.spec.strategy.sourceStrategy.env[?(@.name=="npm_config_registry")].value}' "$NEXUS_NPM"
  check 1 TRBL 4 "package.json di Git valid, prom-client di dependencies (bukan devDependencies)" q1_git
  check 1 TRBL 3 "Build terakhir Complete" build_complete $ns metrics-api
  check 1 OCP 3 "Deployment metrics-api Ready" deploy_ready $ns metrics-api
  check 1 OCP 3 "Route edge + insecure Allow di metrics-api-metrics-prod.$APPS" route_ok $ns metrics-api "metrics-api-metrics-prod.$APPS" edge Allow
  check 1 TRBL 3 "HTTPS /metrics mengembalikan metrik Prometheus" http_has "https://metrics-api-metrics-prod.$APPS/metrics" "process_cpu"
}

# =================== SOAL 2 ===================
q2_bc() {
  jp_eq legacy-prod bc/legacy-web '{.spec.strategy.type}' Docker &&
  jp_has legacy-prod bc/legacy-web '{.spec.source.git.uri}' 'developer/legacy-web' &&
  dir_eq legacy-prod bc/legacy-web '{.spec.source.contextDir}' apps/legacy
}
q2_dockerfile() {
  local d f u; d="$(git_dir legacy-web main)" || return 1
  f="$d/apps/legacy/Dockerfile"
  u="$(awk '/^USER[ \t]/{u=$2} END{print u}' "$f")"
  [ -n "$u" ] && [ "$u" != root ] && [ "$u" != 0 ] &&
  ! grep -qE '^(EXPOSE[ \t]+80|ENV[ \t]+PORT=80)[ \t]*$' "$f" &&
  grep -qE '8080' "$f"
}
grade_q2() {
  local ns=legacy-prod
  check 2 OCP 4 "BuildConfig legacy-web: Docker strategy, repo legacy-web, context apps/legacy" q2_bc
  check 2 TRBL 4 "Docker build env npm_config_registry = Nexus" url_eq $ns bc/legacy-web '{.spec.strategy.dockerStrategy.env[?(@.name=="npm_config_registry")].value}' "$NEXUS_NPM"
  check 2 TRBL 5 "Dockerfile di Git: USER non-root, tanpa port 80, port 8080" q2_dockerfile
  check 2 TRBL 3 "Build terakhir Complete" build_complete $ns legacy-web
  check 2 TRBL 4 "Container punya env APP_ENV=legacy-prod" pod_env $ns legacy-web APP_ENV legacy-prod
  check 2 OCP 3 "Deployment legacy-web Ready" deploy_ready $ns legacy-web
  check 2 OCP 3 "Route hostname default legacy-web-legacy-prod.$APPS" route_ok $ns legacy-web "legacy-web-legacy-prod.$APPS" - -
  check 2 OCP 4 "Aplikasi menampilkan 'mode: legacy-prod'" http_has "http://legacy-web-legacy-prod.$APPS/" "mode: legacy-prod"
}

# =================== SOAL 3 ===================
q3_builder() {
  jp_eq deploy-portal bc/portal-web '{.spec.strategy.sourceStrategy.from.name}' httpd:2.4-ubi9 &&
  jp_eq deploy-portal bc/portal-web '{.spec.strategy.sourceStrategy.from.namespace}' openshift
}
q3_src() {
  jp_has deploy-portal bc/portal-web '{.spec.source.git.uri}' 'developer/portal-s2i' &&
  dir_eq deploy-portal bc/portal-web '{.spec.source.contextDir}' site
}
q3_no_env() {
  ! oc get -n deploy-portal bc/portal-web -o yaml | grep -q SERVER_PORT &&
  ! oc get -n deploy-portal deploy/portal-web -o yaml | grep -q SERVER_PORT &&
  exists deploy-portal bc/portal-web
}
q3_runscript() { # export SERVER_PORT=8081, boleh pakai kutip atau export terpisah
  local d f; d="$(git_dir portal-s2i main)" || return 1
  f="$d/site/.s2i/bin/run"
  [ -f "$f" ] || { hint "site/.s2i/bin/run tidak ada di repo portal-s2i"; return 1; }
  grep -v '^[[:space:]]*#' "$f" | grep -qE "SERVER_PORT=[\"']?8081[\"']?([[:space:];]|$)" &&
  grep -v '^[[:space:]]*#' "$f" | grep -qE '(^|[[:space:];])export[[:space:]]+([A-Za-z_]+[^;]*[[:space:]])?SERVER_PORT' && return 0
  hint "site/.s2i/bin/run belum berisi 'export SERVER_PORT=8081' (commit terakhir: $(git -C "$d" log -1 --format='%h %s'))"
  return 1
}
q3_runtime() { # proses apa pun di container (tidak harus PID 1) punya SERVER_PORT=8081
  oc logs -n deploy-portal deploy/portal-web 2>/dev/null | grep -q 'SERVER_PORT=8081' && return 0
  oc exec -n deploy-portal deploy/portal-web -- sh -c 'cat /proc/[0-9]*/environ 2>/dev/null | tr "\0" "\n" | grep -qx SERVER_PORT=8081' && return 0
  hint "tidak ada proses di container portal-web dengan SERVER_PORT=8081"; return 1
}
q3_http() {
  http_code "http://portal.$APPS/" 200 && http_code "https://portal.$APPS/" 200
}
grade_q3() {
  local ns=deploy-portal
  check 3 S2I 3 "Builder openshift/httpd:2.4-ubi9 (Source strategy)" q3_builder
  check 3 S2I 3 "Source repo portal-s2i, context site" q3_src
  check 3 CMS 3 "Git secret terpasang sebagai sourceSecret" jp_nonempty $ns bc/portal-web '{.spec.source.sourceSecret.name}'
  check 3 S2I 3 "SERVER_PORT tidak di-set lewat env BuildConfig/Deployment" q3_no_env
  check 3 S2I 5 "S2I run script di Git men-export SERVER_PORT=8081" q3_runscript
  check 3 S2I 3 "Build terakhir Complete" build_complete $ns portal-web
  check 3 S2I 4 "Container berjalan dengan SERVER_PORT=8081" q3_runtime
  check 3 OCP 3 "Route edge + Allow di portal.$APPS" route_ok $ns portal-web "portal.$APPS" edge Allow
  check 3 OCP 3 "HTTP dan HTTPS sama-sama 200" q3_http
}

# =================== SOAL 4 ===================
q4_from() {
  local k n ns
  k="$(jp deploy-docs bc/docs-site '{.spec.strategy.dockerStrategy.from.kind}')"
  n="$(jp deploy-docs bc/docs-site '{.spec.strategy.dockerStrategy.from.name}')"
  ns="$(jp deploy-docs bc/docs-site '{.spec.strategy.dockerStrategy.from.namespace}')"
  [ "$k" = ImageStreamTag ] && [ "$n" = httpd:2.4-ubi9 ] && [ "$ns" = openshift ] && return 0
  [ "$k" = DockerImage ] && echo "$n" | grep -q '/openshift/httpd:2\.4-ubi9$' && return 0
  hint "dockerStrategy.from = ${k:-kosong} ${ns:+$ns/}${n:-kosong}, harus ImageStreamTag openshift/httpd:2.4-ubi9"; return 1
}
q4_two_builds() {
  [ "$(oc get builds -n deploy-docs -l openshift.io/build-config.name=docs-site \
      -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c '^Complete$')" -ge 2 ]
}
q4_one_bc() { [ "$(oc get bc -n deploy-docs -o name 2>/dev/null | wc -l)" -eq 1 ]; }
grade_q4() {
  local ns=deploy-docs
  check 4 OCP 5 "BuildConfig docs-site bertipe source Binary" jp_eq $ns bc/docs-site '{.spec.source.type}' Binary
  check 4 OCP 5 "Docker strategy memakai openshift/httpd:2.4-ubi9" q4_from
  check 4 OCP 5 "Minimal 2 build Complete (v1 dan v2)" q4_two_builds
  check 4 OCP 3 "Hanya satu BuildConfig di project" q4_one_bc
  check 4 OCP 3 "Deployment docs-site Ready" deploy_ready $ns docs-site
  check 4 OCP 3 "Route hostname default docs-site-deploy-docs.$APPS" route_ok $ns docs-site "docs-site-deploy-docs.$APPS" - -
  check 4 OCP 6 "Aplikasi menampilkan 'EX288 Docs Site v2'" http_has "http://docs-site-deploy-docs.$APPS/" "EX288 Docs Site v2"
}

# =================== SOAL 5 ===================
q5_cm() {
  jp_eq inventory cm/inventory-db-config '{.data.DB_HOST}' inventory-db &&
  jp_eq inventory cm/inventory-db-config '{.data.DB_USER}' inventory &&
  jp_eq inventory cm/inventory-db-config '{.data.DB_NAME}' inventorydb
}
q5_secret() {
  [ "$(jp inventory secret/inventory-db-secret '{.data.database-password}' | base64 -d 2>/dev/null)" = "Inv3nt0ry" ]
}
q5_pwd() {
  jp_eq inventory deploy/inventory-api '{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}' inventory-db-secret &&
  jp_eq inventory deploy/inventory-api '{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.key}' database-password
}
q5_podname() {
  local pod
  jp_eq inventory deploy/inventory-api '{.spec.template.spec.containers[0].env[?(@.name=="POD_NAME")].valueFrom.fieldRef.fieldPath}' metadata.name || return 1
  pod="$(oc get pods -n inventory -l app=inventory-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  [ -n "$pod" ] && [ "$(oc exec -n inventory "$pod" -- printenv POD_NAME 2>/dev/null)" = "$pod" ]
}
q5_log() { oc logs -n inventory deploy/inventory-api --tail=3 2>/dev/null | tail -1 | grep -q 'DB connection OK'; }
grade_q5() {
  local ns=inventory
  check 5 CMS 5 "ConfigMap inventory-db-config berisi DB_HOST, DB_USER, DB_NAME yang benar" q5_cm
  check 5 CMS 3 "Secret inventory-db-secret key database-password = Inv3nt0ry" q5_secret
  check 5 CMS 5 "Deployment memakai envFrom configMapRef inventory-db-config" jp_has $ns deploy/inventory-api '{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}' inventory-db-config
  check 5 CMS 5 "Env DB_PASSWORD dari secretKeyRef inventory-db-secret/database-password" q5_pwd
  check 5 CMS 5 "Env POD_NAME dari fieldRef metadata.name dan sama dengan nama Pod" q5_podname
  check 5 OCP 2 "Deployment inventory-api Ready" deploy_ready $ns inventory-api
  check 5 CMS 5 "Log terakhir inventory-api: DB connection OK" q5_log
}

# =================== SOAL 6 ===================
# Template dibaca sebagai YAML (bukan grep), jadi urutan key, tanda kutip,
# dan gaya inline tidak berpengaruh. Kalau gagal, alasannya dicetak.
q6_json() { # file -> path JSON
  local d out="$TMP/q6-$(basename "$1").json"
  [ -s "$out" ] && { printf '%s' "$out"; return 0; }
  d="$(git_dir shop-ui v2)" || { hint "repo shop-ui branch v2 tidak bisa di-clone dari GitLab"; return 1; }
  [ -f "$d/$1" ] || { hint "$1 tidak ada di branch v2"; return 1; }
  yaml_json "$d/$1" > "$out" && [ -s "$out" ] \
    || { rm -f "$out"; hint "$1 di branch v2 bukan YAML valid (cek: oc process -f $1 --parameters)"; return 1; }
  printf '%s' "$out"
}
q6_last_commit() {
  local d; d="$(git_dir shop-ui v2)" || return 0
  hint "commit terakhir di origin/v2: $(git -C "$d" log -1 --format='%h %s' 2>/dev/null) (perubahan sudah di-push?)"
}
# q6_py <file> <mode> [arg...]: cek isi template, cetak alasan kalau gagal
q6_py() {
  local j; j="$(q6_json "$1")" || return 1; shift
  local msg
  msg="$(python3 - "$j" "$@" <<'PY'
import json, sys
t = json.load(open(sys.argv[1])); mode = sys.argv[2]; a = sys.argv[3:]
def param(name, desc):
    ps = [p for p in (t.get("parameters") or []) if str(p.get("name", "")).strip() == name]
    if not ps: return f"parameter {name} tidak ditemukan"
    p = ps[0]; e = []
    if str(p.get("required", "")).strip().lower() != "true":
        e.append(f"{name}: required harus true (sekarang: {p.get('required')})")
    if str(p.get("description", "")).strip() != desc:
        e.append(f"{name}: description harus '{desc}' (sekarang: '{p.get('description')}')")
    return "; ".join(e)
err = ""
if mode == "param":
    err = param(a[0], a[1])
elif mode == "secret":
    err = param("GIT_SECRET", "Git source secret")
    bcs = [o for o in (t.get("objects") or []) if o.get("kind") == "BuildConfig"]
    if not bcs:
        err = (err + "; " if err else "") + "tidak ada objek BuildConfig di template"
    else:
        ss = ((bcs[0].get("spec") or {}).get("source") or {}).get("sourceSecret") or {}
        if str(ss.get("name", "")).replace(" ", "") != "${GIT_SECRET}":
            err = (err + "; " if err else "") + \
                f"BuildConfig spec.source.sourceSecret.name harus ${{GIT_SECRET}} (sekarang: {ss.get('name')})"
elif mode == "label":
    ml = ((t.get("metadata") or {}).get("labels") or {})
    if str(ml.get("template", "")).strip() != "shop-ui":
        top = (t.get("labels") or {})
        if str(top.get("template", "")).strip() == "shop-ui":
            err = "label template: shop-ui ada di 'labels:' (label untuk objek), harusnya di metadata.labels milik Template"
        else:
            err = f"metadata.labels template harus shop-ui (sekarang: {ml or 'kosong'})"
if err:
    print(err); sys.exit(1)
PY
)" && return 0
  [ -n "$msg" ] && hint "$msg"
  q6_last_commit
  return 1
}
q6_bc() {
  jp_nonempty lion bc/shop-ui '{.spec.source.sourceSecret.name}' &&
  jp_eq lion bc/shop-ui '{.spec.source.git.ref}' v2 &&
  dir_eq lion bc/shop-ui '{.spec.source.contextDir}' app &&
  jp_eq lion bc/shop-ui '{.spec.output.to.name}' "$INT_REG/lion/shop-ui:latest"
}
q6_labels() {
  local k lb rc=0
  for k in bc deploy svc route; do
    if ! oc get -n lion "$k/shop-ui" >/dev/null 2>&1; then
      hint "$k/shop-ui tidak ada di project lion"; rc=1; continue
    fi
    lb="$(oc get -n lion "$k/shop-ui" -o jsonpath='{.metadata.labels.app}={.metadata.labels.tier}' 2>/dev/null)"
    if [ "$lb" != "shop-ui=frontend" ]; then
      hint "$k/shop-ui label app=${lb%%=*} tier=${lb#*=} (butuh app=shop-ui, tier=frontend)"; rc=1
    fi
  done
  return $rc
}
grade_q6() {
  local ns=lion
  check 6 TPL 4 "Build template: parameter wajib REGISTRY_URL 'My shop image registry'" q6_py templates/shop-build.yaml param REGISTRY_URL "My shop image registry"
  check 6 CMS 3 "Build template: parameter GIT_SECRET dipakai sebagai sourceSecret" q6_py templates/shop-build.yaml secret
  check 6 TPL 2 "Build template punya label template: shop-ui" q6_py templates/shop-build.yaml label
  check 6 TPL 4 "BuildConfig shop-ui: secret, branch v2, context app, output ke $INT_REG/lion/shop-ui:latest" q6_bc
  check 6 TPL 3 "Build terakhir Complete" build_complete $ns shop-ui
  check 6 OCP 3 "Deployment shop-ui 2 replica Ready" deploy_ready $ns shop-ui 2
  check 6 TPL 2 "Env BACKEND_URL benar" jp_eq $ns deploy/shop-ui '{.spec.template.spec.containers[0].env[?(@.name=="BACKEND_URL")].value}' "https://shop-api-lion.$APPS/"
  check 6 OCP 3 "Route edge di shop-ui-lion.$APPS" route_ok $ns shop-ui "shop-ui-lion.$APPS" edge -
  check 6 OCP 4 "bc, deploy, svc, route terpilih oleh app=shop-ui,tier=frontend" q6_labels
  check 6 OCP 2 "Frontend merespons via HTTPS" http_has "https://shop-ui-lion.$APPS/" "shop-ui frontend"
}

# =================== SOAL 7 ===================
q7_chart() {
  local d; d="$(git_dir webstore-helm main)" || return 1
  grep -qE '^version:[[:space:]]*"?2\.1\.0"?' "$d/webstore/Chart.yaml" &&
  grep -q '\.Values\.resources' "$d/webstore/templates/deployment.yaml"
}
q7_release() { [ -n "$(oc get secret -n "$1" -l owner=helm,name="$2",status=deployed -o name 2>/dev/null)" ]; }
q7_res() { # ns cpu mem [reqcpu reqmem]
  local p='{.spec.template.spec.containers[0].resources'
  jp_eq "$1" "deploy/$1" "$p.limits.cpu}" "$2" && jp_eq "$1" "deploy/$1" "$p.limits.memory}" "$3" || return 1
  [ -z "${4:-}" ] || { jp_eq "$1" "deploy/$1" "$p.requests.cpu}" "$4" && jp_eq "$1" "deploy/$1" "$p.requests.memory}" "$5"; }
}
q7_meta() { # ns stage appenv
  jp_eq "$1" "deploy/$1" '{.spec.template.metadata.labels.stage}' "$2" &&
  jp_eq "$1" "deploy/$1" '{.spec.template.spec.containers[0].env[?(@.name=="APP_ENV")].value}' "$3"
}
q7_chartlabel() {
  jp_eq webstore-lab deploy/webstore-lab '{.metadata.labels.chart}' webstore-2.1.0 &&
  jp_eq webstore-prod deploy/webstore-prod '{.metadata.labels.chart}' webstore-2.1.0
}
grade_q7() {
  check 7 MULTI 3 "Chart di Git: version 2.1.0 dan template me-render resources" q7_chart
  check 7 MULTI 2 "[lab] Release webstore-lab deployed di webstore-lab" q7_release webstore-lab webstore-lab
  check 7 MULTI 2 "[lab] 2 Pod Ready" deploy_ready webstore-lab webstore-lab 2
  check 7 MULTI 3 "[lab] Limit CPU 200m, memory 256Mi" q7_res webstore-lab 200m 256Mi
  check 7 MULTI 2 "[lab] Label stage=lab dan APP_ENV=lab" q7_meta webstore-lab lab lab
  check 7 MULTI 3 "[lab] Route webstore-lab.$APPS edge + Allow" route_ok webstore-lab webstore-lab "webstore-lab.$APPS" edge Allow
  check 7 MULTI 2 "[prod] Release webstore-prod deployed di webstore-prod" q7_release webstore-prod webstore-prod
  check 7 MULTI 2 "[prod] 4 Pod Ready" deploy_ready webstore-prod webstore-prod 4
  check 7 MULTI 4 "[prod] Limit 500m/512Mi, request 250m/256Mi" q7_res webstore-prod 500m 512Mi 250m 256Mi
  check 7 MULTI 2 "[prod] Label stage=production dan APP_ENV=production" q7_meta webstore-prod production production
  check 7 MULTI 3 "[prod] Route webstore.$APPS edge + Redirect" route_ok webstore-prod webstore-prod "webstore.$APPS" edge Redirect
  check 7 MULTI 2 "Kedua Deployment berlabel chart=webstore-2.1.0" q7_chartlabel
}

# =================== SOAL 8 ===================
P8='{.spec.template.spec.containers[0]'
q8_startup() {
  jp_eq deploy-health deploy/health-app "$P8.startupProbe.httpGet.path}" / &&
  jp_eq deploy-health deploy/health-app "$P8.startupProbe.httpGet.port}" 8080 &&
  jp_eq deploy-health deploy/health-app "$P8.startupProbe.periodSeconds}" 5 &&
  jp_eq deploy-health deploy/health-app "$P8.startupProbe.failureThreshold}" 12
}
q8_liveness() {
  jp_eq deploy-health deploy/health-app "$P8.livenessProbe.tcpSocket.port}" 8080 &&
  jp_eq deploy-health deploy/health-app "$P8.livenessProbe.initialDelaySeconds}" 15 &&
  jp_eq deploy-health deploy/health-app "$P8.livenessProbe.periodSeconds}" 10 &&
  jp_eq deploy-health deploy/health-app "$P8.livenessProbe.timeoutSeconds}" 3 &&
  jp_eq deploy-health deploy/health-app "$P8.livenessProbe.failureThreshold}" 3
}
q8_readiness() {
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.httpGet.path}" / &&
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.httpGet.port}" 8080 &&
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.periodSeconds}" 10 &&
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.timeoutSeconds}" 2 &&
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.successThreshold}" 2 &&
  jp_eq deploy-health deploy/health-app "$P8.readinessProbe.failureThreshold}" 3
}
grade_q8() {
  check 8 OCP 8 "Startup probe: HTTP / 8080, period 5, failure 12" q8_startup
  check 8 OCP 8 "Liveness probe: TCP 8080, delay 15, period 10, timeout 3, failure 3" q8_liveness
  check 8 OCP 8 "Readiness probe: HTTP / 8080, period 10, timeout 2, success 2, failure 3" q8_readiness
  check 8 OCP 3 "Deployment health-app Ready" deploy_ready deploy-health health-app
  check 8 OCP 3 "Route health-app merespons 200" http_code "http://health-app-deploy-health.$APPS/" 200
}

# =================== SOAL 9 ===================
q9_order() {
  local names ra_b ra_d ra_f t
  names=" $(jp pipeline-lab pipeline/build-and-deploy '{.spec.tasks[*].name}') "
  for t in fetch-source build-image deploy; do
    case "$names" in *" $t "*) ;; *) hint "task $t tidak ada di pipeline (task sekarang:$names)"; return 1;; esac
  done
  ra_f=" $(jp pipeline-lab pipeline/build-and-deploy '{.spec.tasks[?(@.name=="fetch-source")].runAfter[*]}') "
  ra_b=" $(jp pipeline-lab pipeline/build-and-deploy '{.spec.tasks[?(@.name=="build-image")].runAfter[*]}') "
  ra_d=" $(jp pipeline-lab pipeline/build-and-deploy '{.spec.tasks[?(@.name=="deploy")].runAfter[*]}') "
  [ "$ra_f" = "  " ] || { hint "fetch-source tidak boleh punya runAfter (sekarang:$ra_f)"; return 1; }
  case "$ra_b" in *" fetch-source "*) ;; *) hint "build-image runAfter harus memuat fetch-source (sekarang:$ra_b)"; return 1;; esac
  case "$ra_d" in *" build-image "*) ;; *) hint "deploy runAfter harus memuat build-image (sekarang:$ra_d)"; return 1;; esac
}
q9_refs() {
  local t want
  for t in fetch-source:git-clone build-image:buildah deploy:openshift-client; do
    want="${t#*:}"
    jp_eq pipeline-lab pipeline/build-and-deploy "{.spec.tasks[?(@.name==\"${t%%:*}\")].taskRef.resolver}" cluster || return 1
    jp_has pipeline-lab pipeline/build-and-deploy "{.spec.tasks[?(@.name==\"${t%%:*}\")].taskRef.params[*].value}" "$want" || return 1
  done
}
q9_gitsecret() {
  local s
  for s in $(jp pipeline-lab sa/pipeline '{.secrets[*].name}'); do
    oc get -n pipeline-lab secret "$s" -o jsonpath='{.metadata.annotations}' 2>/dev/null | grep -q 'tekton.dev/git-' && return 0
  done
  return 1
}
q9_params() { # PipelineRun Succeeded dengan GIT_URL tekton-web; GIT_REVISION main (atau tidak diisi -> default main)
  oc get pipelinerun -n pipeline-lab -o json 2>/dev/null | python3 -c '
import json, sys
for r in json.load(sys.stdin).get("items", []):
    c = (r.get("status", {}).get("conditions") or [{}])[0]
    if c.get("reason") not in ("Succeeded", "Completed"): continue
    p = {x.get("name"): x.get("value") for x in r.get("spec", {}).get("params", [])}
    if "developer/tekton-web" in str(p.get("GIT_URL", "")) and p.get("GIT_REVISION", "main") == "main":
        sys.exit(0)
sys.exit(1)' && return 0
  hint "tidak ada PipelineRun Succeeded dengan GIT_URL .../developer/tekton-web.git dan GIT_REVISION main"; return 1
}
q9_run() {
  oc get pipelinerun -n pipeline-lab -o jsonpath='{range .items[*]}{.spec.pipelineRef.name} {.status.conditions[0].reason}{"\n"}{end}' 2>/dev/null \
    | grep -qE '^build-and-deploy (Succeeded|Completed)$'
}
q9_tb() {
  local names
  names="$(jp pipeline-lab triggerbinding/tekton-web-binding '{.spec.params[*].name}')"
  echo " $names " | grep -q ' git-url ' && echo " $names " | grep -q ' git-revision ' &&
  jp_has pipeline-lab triggerbinding/tekton-web-binding '{.spec.params[?(@.name=="git-url")].value}' 'body.git_url' &&
  jp_has pipeline-lab triggerbinding/tekton-web-binding '{.spec.params[?(@.name=="git-revision")].value}' 'body.revision'
}
q9_tt() {
  jp_eq pipeline-lab triggertemplate/tekton-web-template '{.spec.resourcetemplates[0].spec.pipelineRef.name}' build-and-deploy &&
  jp_has pipeline-lab triggertemplate/tekton-web-template '{.spec.resourcetemplates[0].spec.params[?(@.name=="GIT_URL")].value}' 'tt.params.git-url'
}
q9_el() {
  jp_eq pipeline-lab eventlistener/tekton-web-listener '{.spec.serviceAccountName}' pipeline &&
  jp_has pipeline-lab eventlistener/tekton-web-listener '{.spec.triggers[*].bindings[*].ref}' tekton-web-binding &&
  jp_has pipeline-lab eventlistener/tekton-web-listener '{.spec.triggers[*].template.ref}' tekton-web-template &&
  jp_eq pipeline-lab eventlistener/tekton-web-listener '{.status.conditions[?(@.type=="Ready")].status}' True
}
q9_el_route() {
  oc get route -n pipeline-lab -o jsonpath='{.items[*].spec.to.name}' 2>/dev/null | tr ' ' '\n' | grep -qx el-tekton-web-listener
}
q9_triggered() {
  oc get pipelinerun -n pipeline-lab -l triggers.tekton.dev/eventlistener=tekton-web-listener \
    -o jsonpath='{range .items[*]}{.status.conditions[0].reason}{"\n"}{end}' 2>/dev/null | grep -qE '^(Succeeded|Completed)$'
}
grade_q9() {
  local ns=pipeline-lab
  check 9 PIPE 2 "Pipeline build-and-deploy ada" exists $ns pipeline/build-and-deploy
  check 9 PIPE 3 "Urutan task fetch-source -> build-image -> deploy" q9_order
  check 9 PIPE 3 "Task diambil dari cluster resolver: git-clone, buildah, openshift-client" q9_refs
  check 9 PIPE 2 "Git secret beranotasi tekton.dev/git-* ter-link ke SA pipeline" q9_gitsecret
  check 9 PIPE 3 "PipelineRun build-and-deploy Succeeded" q9_run
  check 9 PIPE 2 "PipelineRun memakai GIT_URL tekton-web.git dan GIT_REVISION main" q9_params
  check 9 IS 2 "ImageStreamTag tekton-web:latest ada" exists $ns istag/tekton-web:latest
  check 9 PIPE 3 "Deployment tekton-web Ready dengan BUILT_BY=tekton" pod_env $ns tekton-web BUILT_BY tekton
  check 9 PIPE 2 "Route tekton-web merespons 200" http_code "http://tekton-web-pipeline-lab.$APPS/" 200
  check 9 PIPE 2 "[trigger] TriggerBinding tekton-web-binding: git-url dan git-revision dari body" q9_tb
  check 9 PIPE 2 "[trigger] TriggerTemplate tekton-web-template membuat PipelineRun build-and-deploy" q9_tt
  check 9 PIPE 2 "[trigger] EventListener tekton-web-listener Ready, SA pipeline, pakai binding+template" q9_el
  check 9 PIPE 1 "[trigger] Route ke service el-tekton-web-listener ada" q9_el_route
  check 9 PIPE 1 "[trigger] PipelineRun dari EventListener Succeeded" q9_triggered
}

# =================== SOAL 10 ===================
q10_img_env() {
  oc get -n registry-lab istag/custom-nginx:1.0 -o jsonpath='{.image.dockerImageMetadata.Config.Env}' 2>/dev/null | grep -q 'APP_TIER=registry-lab'
}
grade_q10() {
  local ns=registry-lab
  check 10 IMG 6 "Internal registry: defaultRoute true" jp_eq openshift-image-registry configs.imageregistry.operator.openshift.io/cluster '{.spec.defaultRoute}' true
  check 10 IMG 3 "Route default-route ada di openshift-image-registry" exists openshift-image-registry route/default-route
  check 10 IS 6 "ImageStreamTag custom-nginx:1.0 ada di registry-lab" exists $ns istag/custom-nginx:1.0
  check 10 IMG 3 "Image berasal dari Containerfile (env APP_TIER=registry-lab)" q10_img_env
  check 10 OCP 4 "Deployment custom-nginx Ready" deploy_ready $ns custom-nginx
  check 10 IMG 4 "Pod custom-nginx punya APP_TIER=registry-lab" pod_env $ns custom-nginx APP_TIER registry-lab
  check 10 OCP 4 "Route custom-nginx merespons 200" http_code "http://custom-nginx-registry-lab.$APPS/" 200
}

# =================== helper tambahan ===================
http_ok_any() { # app merespons (200-499), bukan 503 router/000
  local c; c="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$1")"
  [ "$c" -ge 200 ] 2>/dev/null && [ "$c" -lt 500 ]
}
git_mode_exec() { # repo branch path -> file executable di Git
  local d; d="$(git_dir "$1" "$2")" || return 1
  [ "$(git -C "$d" ls-files -s -- "$3" | awk '{print $1}')" = "100755" ]
}
last_complete_build() { # ns bc -> nama build Complete terakhir
  oc get builds -n "$1" -l "openshift.io/build-config.name=$2" \
    -o jsonpath='{range .items[*]}{.status.phase} {.metadata.name}{"\n"}{end}' 2>/dev/null \
    | awk '$1=="Complete"{n=split($2,a,"-"); print a[n], $2}' | sort -n | tail -1 | cut -d' ' -f2
}
count_complete_builds() {
  oc get builds -n "$1" -l "openshift.io/build-config.name=$2" \
    -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c '^Complete$'
}

# =================== SOAL 11 ===================
q11_bc() {
  jp_eq docker-app bc/myapp1-docker '{.spec.strategy.type}' Docker &&
  jp_has docker-app bc/myapp1-docker '{.spec.source.git.uri}' 'developer/myapp1-docker' &&
  dir_eq docker-app bc/myapp1-docker '{.spec.source.contextDir}' apps/myapp1
}
q11_dockerfile() {
  local d f; d="$(git_dir myapp1-docker main)" || return 1
  f="$d/apps/myapp1/Dockerfile"
  [ -f "$f" ] || { hint "apps/myapp1/Dockerfile tidak ada"; return 1; }
  if grep -qiE '^[[:space:]]*COPY[[:space:]]+(\./)?src/?[[:space:]]+\.?/?[[:space:]]*$' "$f"; then
    hint "Dockerfile masih 'COPY src .' (isi src jadi tercecer di WORKDIR, struktur Maven rusak)"; return 1
  fi
  # COPY src <tujuan berakhiran /src>, atau COPY . <WORKDIR>
  grep -qiE '^[[:space:]]*COPY[[:space:]]+((--[a-z]+=[^[:space:]]+[[:space:]]+)*)((\./)?src/?[[:space:]]+[^[:space:]]*src/?|\.[[:space:]]+[^[:space:]]+)[[:space:]]*$' "$f" && return 0
  hint "Dockerfile tidak menyalin src ke folder src (contoh: COPY src src)"; return 1
}
q11_logs() {
  local l; l="$(oc logs -n docker-app deploy/myapp1-docker 2>/dev/null)" || return 1
  ! echo "$l" | grep -q 'Unable to access jarfile'
}
grade_q11() {
  local ns=docker-app
  check 11 OCP 4 "BuildConfig myapp1-docker: Docker strategy, repo myapp1-docker, context apps/myapp1" q11_bc
  check 11 TRBL 6 "Dockerfile di Git mempertahankan struktur src Maven (bukan 'COPY src .')" q11_dockerfile
  check 11 TRBL 4 "Build terakhir Complete" build_complete $ns myapp1-docker
  check 11 OCP 6 "Deployment myapp1-docker Ready dan JAR ditemukan" q11_ready_logs
  check 11 OCP 4 "Route hostname default myapp1-docker-docker-app.$APPS" route_ok $ns myapp1-docker "myapp1-docker-docker-app.$APPS" - -
  check 11 OCP 6 "Endpoint REST aplikasi merespons 200 lewat route (source Java ter-compile)" q11_endpoint
}
q11_endpoint() { # path diambil dari anotasi @Path di source Java repo
  local d ep; d="$(git_dir myapp1-docker main)" || return 1
  local c
  for ep in expenses $(grep -rhoP '@Path\("\K[^"{]+' "$d/apps/myapp1/src/main/java" 2>/dev/null | sort -u); do
    c="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "http://myapp1-docker-docker-app.$APPS/${ep#/}")"
    [ "$c" = 200 ] && return 0
  done
  hint "endpoint REST tidak ada yang mengembalikan 200 (terakhir /${ep#/} -> $c)"; return 1
}
q11_ready_logs() { deploy_ready docker-app myapp1-docker && q11_logs; }

# =================== SOAL 12 ===================
q12_istag() {
  exists greetings-app istag/greetings:1.0.1 || return 1
  { jp greetings-app istag/greetings:1.0.1 '{.tag.from.name}'; echo; jp greetings-app istag/greetings:1.0.1 '{.image.dockerImageReference}'; } \
    | grep -qF 'registry.ocp4.example.com:8443/developer/greetings' && return 0
  hint "istag greetings:1.0.1 tidak berasal dari registry.ocp4.example.com:8443/developer/greetings"; return 1
}
q12_pullsecret() {
  local s
  for s in $(oc get secret -n greetings-app --field-selector=type=kubernetes.io/dockerconfigjson -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    oc get secret -n greetings-app "$s" -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | base64 -d 2>/dev/null \
      | grep -q 'registry.ocp4.example.com:8443' && return 0
  done
  return 1
}
q12_image_cfg() {
  local u p
  u="$(jp greetings-app istag/greetings:1.0.1 '{.image.dockerImageMetadata.Config.User}')"
  p="$(jp greetings-app istag/greetings:1.0.1 '{.image.dockerImageMetadata.Config.ExposedPorts}')"
  [ -n "$u" ] && [ "$u" != root ] && [ "$u" != 0 ] && [ "${u%%:*}" != 0 ] && [ "${u%%:*}" != root ] &&
  echo "$p" | grep -q '8080' && ! echo "$p" | grep -q '"80/'
}
q12_deploy() {
  deploy_ready greetings-app greetings &&
  oc get deploy greetings -n greetings-app -o yaml 2>/dev/null | grep -qE 'greetings:1\.0\.1|image-registry\.openshift-image-registry\.svc:5000/greetings-app/greetings'
}
q12_logs() { oc logs -n greetings-app deploy/greetings 2>/dev/null | grep -q 'File cache OK'; }
grade_q12() {
  local ns=greetings-app
  check 12 IS 4 "ImageStreamTag greetings:1.0.1 diimpor dari registry.ocp4.example.com:8443/developer/greetings" q12_istag
  check 12 CMS 4 "Pull secret dockerconfigjson untuk registry.ocp4.example.com:8443 ada di project" q12_pullsecret
  check 12 IS 4 "Tag greetings:1.0.1 memakai referencePolicy Local" jp_eq $ns is/greetings '{.spec.tags[?(@.name=="1.0.1")].referencePolicy.type}' Local
  check 12 IMG 5 "Image 1.0.1: USER non-root dan expose port 8080" q12_image_cfg
  check 12 IS 5 "Deployment greetings Ready memakai image dari image stream greetings:1.0.1" q12_deploy
  check 12 IMG 4 "Log aplikasi: File cache OK (izin /var/cache benar)" q12_logs
  check 12 OCP 4 "Route greetings-greetings-app.$APPS mengembalikan JSON greeting" http_has "http://greetings-greetings-app.$APPS/" '"greeting"'
}

# =================== SOAL 13 ===================
q13_bc() {
  jp_eq builds-s2i bc/hello-web '{.spec.strategy.sourceStrategy.from.name}' httpd:2.4-ubi9 &&
  jp_has builds-s2i bc/hello-web '{.spec.source.git.uri}' 'developer/hello-s2i'
}
q13_assemble_info() {
  local d; d="$(git_dir hello-s2i main)" || return 1
  grep -q 'info.html' "$d/.s2i/bin/assemble" && grep -q 'Page built on' "$d/.s2i/bin/assemble" &&
  grep -q 'HTTPD_VERSION' "$d/.s2i/bin/assemble"
}
q13_run() {
  local d; d="$(git_dir hello-s2i main)" || return 1
  [ -f "$d/.s2i/bin/run" ] || { hint ".s2i/bin/run tidak ada di repo hello-s2i"; return 1; }
  git_mode_exec hello-s2i main .s2i/bin/run || { hint ".s2i/bin/run belum executable di Git (git update-index --chmod=+x)"; return 1; }
  grep -qE "^[[:space:]]*exec[[:space:]]+[^[:space:]]*(run-httpd|httpd)([[:space:]].*)?[[:space:]]-e[[:space:]]*[\"']?debug" "$d/.s2i/bin/run" && return 0
  hint ".s2i/bin/run harus 'exec run-httpd -e debug' (exec supaya httpd jadi PID 1)"; return 1
}
q13_debug_log() { oc logs -n builds-s2i deploy/hello-web 2>/dev/null | grep -q ':debug\]'; }
grade_q13() {
  local ns=builds-s2i
  check 13 S2I 3 "BuildConfig hello-web: builder httpd:2.4-ubi9, repo hello-s2i" q13_bc
  check 13 S2I 5 "assemble di Git executable (mode 100755)" git_mode_exec hello-s2i main .s2i/bin/assemble
  check 13 S2I 5 "assemble membuat info.html (Page built on + HTTPD_VERSION)" q13_assemble_info
  check 13 S2I 5 "run script ada, executable, memakai exec run-httpd -e debug" q13_run
  check 13 S2I 3 "Build terakhir Complete" build_complete $ns hello-web
  check 13 OCP 3 "Route hostname default hello-web-builds-s2i.$APPS" route_ok $ns hello-web "hello-web-builds-s2i.$APPS" - -
  check 13 S2I 3 "/info.html berisi 'Page built on'" http_has "http://hello-web-builds-s2i.$APPS/info.html" "Page built on"
  check 13 S2I 3 "Log httpd berlevel debug" q13_debug_log
}

# =================== SOAL 14 ===================
q14_parent_file() {
  local d f; d="$(git_dir site-images main)" || return 1
  f="$d/parent/Containerfile"
  [ -f "$f" ] || { hint "parent/Containerfile tidak ada"; return 1; }
  grep -qiE '^[[:space:]]*ONBUILD[[:space:]]+COPY[[:space:]]+((--[a-z]+=[^[:space:]]+[[:space:]]+)*)(\./)?src/?\.?[[:space:]]+/var/www/html/?\.?[[:space:]]*$' "$f" \
    || { hint "parent/Containerfile belum punya 'ONBUILD COPY src/ /var/www/html/'"; return 1; }
  [ "$(grep -ciE '^[[:space:]]*RUN[[:space:]]' "$f")" -le 1 ] && return 0
  hint "parent/Containerfile masih punya $(grep -ciE '^[[:space:]]*RUN[[:space:]]' "$f") instruksi RUN (maksimal 1)"; return 1
}
q14_parent_bc() {
  jp_eq production2 bc/site-base '{.spec.strategy.type}' Docker &&
  dir_eq production2 bc/site-base '{.spec.source.contextDir}' parent &&
  jp_eq production2 bc/site-base '{.spec.strategy.dockerStrategy.from.name}' httpd:2.4-ubi9
}
q14_layers() {
  local base parent
  base="$(oc get istag httpd:2.4-ubi9 -n openshift -o jsonpath='{range .image.dockerImageLayers[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -c .)"
  parent="$(jp production2 istag/site-base:latest '{range .image.dockerImageLayers[*]}{.name}{"\n"}{end}' | grep -c .)"
  [ "$base" -gt 0 ] && [ "$parent" -gt 0 ] && [ $(( parent - base )) -le 1 ]
}
q14_child() {
  dir_eq production2 bc/site-child '{.spec.source.contextDir}' child &&
  jp_eq production2 bc/site-child '{.spec.strategy.dockerStrategy.from.name}' site-base:latest &&
  build_complete production2 site-child
}
grade_q14() {
  local ns=production2
  check 14 IMG 4 "Containerfile parent di Git: ONBUILD COPY src/ /var/www/html/ dan maksimal 1 RUN" q14_parent_file
  check 14 IMG 4 "BuildConfig site-base: Docker, context parent, FROM openshift/httpd:2.4-ubi9" q14_parent_bc
  check 14 IMG 3 "Build site-base terakhir Complete" build_complete $ns site-base
  check 14 IMG 5 "Image site-base menambah maksimal 1 layer di atas base" q14_layers
  check 14 IMG 4 "Image site-base menyimpan instruksi ONBUILD COPY" jp_has $ns istag/site-base:latest '{.image.dockerImageMetadata.Config.OnBuild}' 'COPY'
  check 14 IMG 4 "BuildConfig site-child: context child, FROM site-base:latest, build Complete" q14_child
  check 14 OCP 3 "Deployment site-child Ready" deploy_ready $ns site-child
  check 14 OCP 3 "Route site-child-production2.$APPS menampilkan konten child" http_has "http://site-child-production2.$APPS/" "Child site from ONBUILD"
}

# =================== SOAL 15 ===================
q15_cm() { jp_nonempty hooks-lab cm/smoke-test '{.data.smoke\.py}'; }
q15_hook() {
  oc get bc hooks-api -n hooks-lab -o jsonpath='{.spec.postCommit}' 2>/dev/null | grep -q 'smoke.py'
}
q15_webhook_build() {
  oc get builds -n hooks-lab -l openshift.io/build-config.name=hooks-api \
    -o jsonpath='{range .items[*]}{.status.phase}|{.spec.triggeredBy[*].message}{"\n"}{end}' 2>/dev/null \
    | grep -qE '^Complete\|.*Generic WebHook'
}
q15_hook_log() {
  local b; b="$(last_complete_build hooks-lab hooks-api)"; [ -n "$b" ] || return 1
  oc logs -n hooks-lab "build/$b" 2>/dev/null | grep -q 'SMOKE TEST PASSED'
}
grade_q15() {
  local ns=hooks-lab
  check 15 CMS 5 "ConfigMap smoke-test berisi key smoke.py" q15_cm
  check 15 CMS 5 "BuildConfig hooks-api memakai ConfigMap smoke-test sebagai build input" jp_has $ns bc/hooks-api '{.spec.source.configMaps[*].configMap.name}' smoke-test
  check 15 S2I 6 "Post-commit build hook menjalankan smoke.py" q15_hook
  check 15 S2I 4 "BuildConfig punya trigger Generic webhook" jp_has $ns bc/hooks-api '{.spec.triggers[*].type}' Generic
  check 15 S2I 4 "Ada build Complete yang dipicu Generic WebHook" q15_webhook_build
  check 15 S2I 4 "Log build terakhir berisi SMOKE TEST PASSED" q15_hook_log
  check 15 OCP 2 "Route hooks-api merespons 200" http_code "http://hooks-api-hooks-lab.$APPS/" 200
}

# =================== SOAL 16 ===================
q16_bc() {
  jp_eq java-builds bc/vertx-site '{.spec.strategy.sourceStrategy.from.name}' redhat-openjdk18-openshift:1.8 &&
  jp_eq java-builds bc/vertx-site '{.spec.strategy.sourceStrategy.from.namespace}' openshift &&
  jp_has java-builds bc/vertx-site '{.spec.source.git.uri}' 'developer/vertx-site'
}
q16_two_builds() { [ "$(count_complete_builds java-builds vertx-site)" -ge 2 ]; }
grade_q16() {
  local ns=java-builds
  check 16 S2I 4 "BuildConfig vertx-site: S2I openshift/redhat-openjdk18-openshift:1.8, repo vertx-site" q16_bc
  check 16 S2I 5 "Build env MAVEN_MIRROR_URL = Nexus java" url_eq $ns bc/vertx-site '{.spec.strategy.sourceStrategy.env[?(@.name=="MAVEN_MIRROR_URL")].value}' "http://nexus-infra.apps.ocp4.example.com/repository/java"
  check 16 S2I 5 "Runtime env JAVA_APP_JAR = vertx-site-1.0.0-SNAPSHOT-fat.jar" jp_eq $ns deploy/vertx-site '{.spec.template.spec.containers[0].env[?(@.name=="JAVA_APP_JAR")].value}' vertx-site-1.0.0-SNAPSHOT-fat.jar
  check 16 S2I 5 "Incremental build aktif di BuildConfig" jp_eq $ns bc/vertx-site '{.spec.strategy.sourceStrategy.incremental}' true
  check 16 S2I 4 "Minimal 2 build Complete" q16_two_builds
  check 16 OCP 3 "Deployment vertx-site Ready" deploy_ready $ns vertx-site
  check 16 OCP 4 "Route vertx-site-java-builds.$APPS merespons 200" http_code "http://vertx-site-java-builds.$APPS/" 200
}

# =================== MAIN ===================
oc get --help >/dev/null 2>&1 || { echo "oc tidak ditemukan"; exit 1; }
admin_login || { echo "Gagal login sebagai admin ke $OCP_API"; exit 1; }

if [ $# -gt 0 ]; then QS=("$@"); else QS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16); fi

out "${B}EX288 Prep - Penilaian$(date '+  (%F %T)')${N}"
for q in "${QS[@]}"; do
  case "$q" in [1-9]|1[0-6]) ;; *) echo "Nomor soal tidak dikenal: $q"; continue ;; esac
  out ""
  out "${B}Soal $q - ${TITLE[$q]}${N}"
  "grade_q$q"
  out "  ${B}Subtotal: ${SCORE[$q]}/${MAXQ[$q]}${N}"
done

out ""
out "${B}Ringkasan${N}"
TOTAL=0; MAXT=0; CORE=0; CORE_MAX=0; CORE_N=0; EXTRA=0; EXTRA_MAX=0
for q in "${QS[@]}"; do
  [ -n "${MAXQ[$q]:-}" ] || continue
  TOTAL=$(( TOTAL + SCORE[$q] )); MAXT=$(( MAXT + MAXQ[$q] ))
  if [ "$q" -le 10 ]; then
    CORE=$(( CORE + SCORE[$q] )); CORE_MAX=$(( CORE_MAX + MAXQ[$q] )); CORE_N=$(( CORE_N + 1 ))
  else
    EXTRA=$(( EXTRA + SCORE[$q] )); EXTRA_MAX=$(( EXTRA_MAX + MAXQ[$q] ))
  fi
  out "  $(printf 'Soal %-3s %3d/%-3d  %s' "$q" "${SCORE[$q]}" "${MAXQ[$q]}" "${TITLE[$q]}")"
done
out "  ---------------------------------------------"
[ "$CORE_MAX" -gt 0 ]  && out "  ${B}$(printf 'Ujian inti (Soal 1-10)    %3d/%-3d' "$CORE" "$CORE_MAX")${N}"
[ "$EXTRA_MAX" -gt 0 ] && out "  ${B}$(printf 'Soal tambahan (11-16)     %3d/%-3d' "$EXTRA" "$EXTRA_MAX")${N}"
out "  ${B}$(printf 'TOTAL                     %3d/%-3d  (%d%%)' "$TOTAL" "$MAXT" $(( MAXT > 0 ? TOTAL * 100 / MAXT : 0 )))${N}"
out ""
out "${B}=================================================================${N}"
out "${B} Hasil ala email Red Hat${N}"
out "${B}=================================================================${N}"
out ""
out "The results of your EX288 practice exam are reported below."
out ""
out "Exam domain number:   EX288 Practice Set 2 (Soal 1-10)"
out "Passing score:        $PASS_MARK"
out "Your score:           $CORE"
out ""
if [ "$CORE_N" -eq 10 ]; then
  if [ "$CORE" -ge "$PASS_MARK" ]; then
    out "Result: ${G}${B}PASS${N}"
  else
    out "Result: ${R}${B}NO PASS${N}  (kurang $(( PASS_MARK - CORE )) poin)"
  fi
else
  out "Result: ${Y}- (penilaian sebagian, jalankan tanpa argumen untuk vonis)${N}"
fi
out ""
if [ "$CORE_MAX" -gt 0 ]; then
  objective_report core
fi
if [ "$EXTRA_MAX" -gt 0 ]; then
  out ""
  out "${B}Latihan tambahan (Soal 11-16): $EXTRA/$EXTRA_MAX${N}"
  out ""
  objective_report extra
fi
out ""
out "Laporan tersimpan di: $REPORT"
