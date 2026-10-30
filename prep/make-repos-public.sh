#!/bin/bash
# ---------------------------------------------------------------
# EX288 Prep - jadikan repo latihan di GitLab lab public
#
#   bash prep/make-repos-public.sh            # semua repo latihan
#   bash prep/make-repos-public.sh legacy-web # repo tertentu
#
# Tidak me-reset isi repo maupun project OpenShift.
# ---------------------------------------------------------------
set -u
GIT_HOST="git.ocp4.example.com"
GIT_USER="developer"
GIT_PASS="d3v3lop3r"
REPOS=(metrics-api legacy-web portal-s2i shop-ui webstore-helm tekton-web
       myapp1-docker hello-s2i site-images hooks-api vertx-site)
[ $# -gt 0 ] && REPOS=("$@")

TOKEN="$(curl -sk --max-time 20 -X POST "https://${GIT_HOST}/oauth/token" \
  -d grant_type=password -d "username=${GIT_USER}" --data-urlencode "password=${GIT_PASS}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)"
if [ -z "$TOKEN" ]; then
  echo "Gagal mengambil token GitLab (password grant mungkin dimatikan)."
  echo "Ubah manual: buka https://${GIT_HOST}, masuk ke tiap project > Settings > General > Visibility > Public."
  exit 1
fi

for r in "${REPOS[@]}"; do
  resp="$(curl -sk --max-time 20 -X PUT -H "Authorization: Bearer ${TOKEN}" \
    "https://${GIT_HOST}/api/v4/projects/${GIT_USER}%2F${r}" -d visibility=public)"
  if echo "$resp" | grep -q '"visibility":"public"'; then
    echo "  public  ${r}"
  elif echo "$resp" | grep -q '404'; then
    echo "  lewati  ${r} (repo belum ada; jalankan prep soalnya dulu)"
  else
    echo "  gagal   ${r}: ${resp:0:120}"
  fi
done
