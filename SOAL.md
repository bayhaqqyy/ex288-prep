# EX288 Prep — Soal

Jalankan script prep soal yang mau dikerjakan dari folder `prep/`, lalu kerjakan tanpa membuka [`KUNCI.md`](KUNCI.md).

Sekali saja sebelum mulai, simpan kredensial Git lab di workstation:

```bash
git config --global credential.helper store
echo "https://developer:d3v3lop3r@git.ocp4.example.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
```

## Soal 1 — S2I Node.js: JSON error dan module not found

Persiapan: `bash prep/prep-q1.sh`

- Build dan deploy aplikasi dari `https://git.ocp4.example.com/developer/metrics-api.git`, branch `release-v1`, subdirektori `apps/metrics`.
- Project: `metrics-prod`. Semua resource bernama `metrics-api`.
- Gunakan image stream tag `nodejs:18-ubi9` dari namespace `openshift`.
- Dependency npm diambil dari `http://nexus-infra.apps.ocp4.example.com/repository/npm`.
- Kredensial Git (`developer` / `d3v3lop3r`) disimpan sebagai secret dan dipakai oleh proses build.
- Aplikasi harus berjalan tanpa error dan bisa diakses lewat `http://metrics-api-metrics-prod.apps.ocp4.example.com` dan `https://metrics-api-metrics-prod.apps.ocp4.example.com`.
- Endpoint `/metrics` harus mengembalikan metrik Prometheus.

Hint: perbaikan kode harus di-push ke Git. Jangan menambal file langsung di Pod.

## Soal 2 — Docker build dari base image dan env Nexus

Persiapan: `bash prep/prep-q2.sh` (opsional: `BASE_IMAGE=<image> bash prep/prep-q2.sh`)

- Build dan deploy aplikasi dari `https://git.ocp4.example.com/developer/legacy-web.git`, branch `main`, subdirektori `apps/legacy`.
- Project: `legacy-prod`. Semua resource bernama `legacy-web`.
- Build wajib memakai Dockerfile yang ada di repo (Docker strategy).
- Selama build, npm harus memakai registry Nexus lewat environment variable `npm_config_registry`.
- Saat runtime, container harus punya env `APP_ENV=legacy-prod`.
- Image harus kompatibel dengan OpenShift: tidak berjalan sebagai root, listen di port 8080.
- Aplikasi bisa diakses di hostname default route dan menampilkan `legacy-web running in mode: legacy-prod`.

## Soal 3 — S2I httpd: SERVER_PORT 8081 lewat S2I script

Persiapan: `bash prep/prep-q3.sh`

- Build dan deploy dari `https://git.ocp4.example.com/developer/portal-s2i.git`, branch `main`, subdirektori `site`.
- Project: `deploy-portal`. Semua resource bernama `portal-web`.
- Builder: `httpd:2.4-ubi9` dari namespace `openshift`.
- Build harus memodifikasi S2I script yang sudah ada di repo agar environment variable `SERVER_PORT` bernilai `8081`. Tidak boleh lewat `--build-env` atau `oc set env`.
- Kredensial Git disimpan sebagai secret dan dipakai build.
- Aplikasi bisa diakses lewat `http://portal.apps.ocp4.example.com` dan `https://portal.apps.ocp4.example.com`.

## Soal 4 — httpd Docker build dengan binary tar

Persiapan: `bash prep/prep-q4.sh` → menghasilkan `/home/student/ex288-set2/q4/docs-site-v1.tar` dan `docs-site-v2.tar`

- Project: `deploy-docs`. Semua resource bernama `docs-site`.
- Buat BuildConfig Docker strategy dengan source tipe **Binary**. Isi build berasal dari file `docs-site-v1.tar`.
- Build harus memakai image stream tag `httpd:2.4-ubi9` dari namespace `openshift` sebagai base image.
- Deploy hasil build dan expose di hostname default. `curl` harus menampilkan `EX288 Docs Site v1`.
- Lanjutan: jalankan build baru dari `docs-site-v2.tar` tanpa membuat BuildConfig baru. Deployment harus ikut terupdate dan menampilkan `EX288 Docs Site v2`.

## Soal 5 — ConfigMap dan Secret untuk backend PostgreSQL

Persiapan: `bash prep/prep-q5.sh` → membuat database `inventory-db` dan backend `inventory-api` yang belum bisa konek.

- Project: `inventory`.
- Buat ConfigMap `inventory-db-config` berisi `DB_HOST=inventory-db`, `DB_USER=inventory`, `DB_NAME=inventorydb`.
- Buat Secret `inventory-db-secret` dengan key `database-password` bernilai `Inv3nt0ry`.
- Semua key ConfigMap masuk ke Deployment `inventory-api` sebagai environment variable dengan nama yang sama.
- Password dari Secret masuk ke `inventory-api` sebagai env `DB_PASSWORD` (bukan `DATABASE_PASSWORD`).
- Penambahan key baru ke ConfigMap di masa depan tidak boleh butuh edit Deployment lagi.
- Expose nama Pod `inventory-api` sebagai environment variable `POD_NAME`. Nilainya harus sama dengan nama Pod yang sedang berjalan.
- Log `oc logs deploy/inventory-api` harus menampilkan `DB connection OK`.

## Soal 6 — Template untuk build dan deploy

Persiapan: `bash prep/prep-q6.sh`

Semua dikerjakan di project `lion`. Gunakan nilai-nilai ini persis seperti tertulis:

| Item | Nilai |
| --- | --- |
| Git repository | `https://git.ocp4.example.com/developer/shop-ui.git` |
| Branch | `v2` |
| Context dir aplikasi | `app` |
| Build template | `templates/shop-build.yaml` di repo tersebut |
| Deploy template | `templates/shop-deploy.yaml` di repo tersebut |
| Kredensial Git | `developer` / `d3v3lop3r` |
| NPM registry | `http://nexus-infra.apps.ocp4.example.com/repository/npm` |
| Container image registry (`REGISTRY_URL`) | `image-registry.openshift-image-registry.svc:5000` |
| Namespace image di registry | `lion` |
| Image hasil build | `image-registry.openshift-image-registry.svc:5000/lion/shop-ui:latest` |
| Backend URL | `https://shop-api-lion.apps.ocp4.example.com/` |
| Hostname frontend | `shop-ui-lion.apps.ocp4.example.com` |

Build template:

- Template sudah memakai `${REGISTRY_URL}` di output build, tapi parameternya belum ada. Tambahkan parameter wajib `REGISTRY_URL` dengan deskripsi `My shop image registry`.
- Tambahkan parameter wajib `GIT_SECRET` dengan deskripsi `Git source secret`, lalu pakai sebagai source secret BuildConfig.
- Template punya label `template: shop-ui`.
- Semua resource bernama `shop-ui`. Build harus push image ke alamat "Image hasil build" di tabel.

Deploy template:

- Semua resource bernama `shop-ui`, 2 replica, image diambil dari registry dan namespace di tabel.
- Env `BACKEND_URL` berisi Backend URL di tabel.
- Route HTTPS dengan hostname frontend di tabel.
- Deployment harus benar-benar bisa mengelola Pod-nya.

Kedua template:

- Semua resource yang dibuat dari template bisa dipilih dengan selector `app=shop-ui,tier=frontend`.
- Perubahan template wajib di-commit dan di-push ke branch `v2`.

## Soal 7 — Helm untuk lab dan production

Persiapan: `bash prep/prep-q7.sh`

Chart ada di `https://git.ocp4.example.com/developer/webstore-helm.git`, folder `webstore`. Versi chart harus `2.1.0` dan semua perubahan di-push ke Git.

**Untuk environment Lab**, penuhi requirement berikut:

- Deploy aplikasi ke project `webstore-lab`.
- Gunakan Helm release name `webstore-lab`.
- Gunakan values file `webstore/values-lab.yaml`.
- Image: `registry.ocp4.example.com:8443/redhattraining/hello-world-nginx:v1.0`.
- Jumlah Pod: `2`.
- Resource limit: CPU `200m`, memory `256Mi`.
- Aplikasi tersedia di `https://webstore-lab.apps.ocp4.example.com` dengan TLS edge. Akses HTTP tetap diizinkan.
- Label Pod: `stage=lab`.
- Environment variable container: `APP_ENV=lab`.

**Untuk environment Production**, penuhi requirement berikut:

- Deploy aplikasi ke project `webstore-prod`.
- Gunakan Helm release name `webstore-prod`.
- Gunakan values file `webstore/values-prod.yaml`.
- Image: `registry.ocp4.example.com:8443/redhattraining/hello-world-nginx:v1.0`.
- Jumlah Pod: `4`.
- Resource limit: CPU `500m`, memory `512Mi`. Resource request: CPU `250m`, memory `256Mi`.
- Aplikasi tersedia di `https://webstore.apps.ocp4.example.com` dengan TLS edge. Akses HTTP harus di-redirect ke HTTPS.
- Label Pod: `stage=production`.
- Environment variable container: `APP_ENV=production`.

Hint: pastikan nilai di values file benar-benar muncul di objek yang dibuat. Cek dengan `helm template` sebelum install.

## Soal 8 — Startup, liveness, dan readiness probe

Persiapan: `bash prep/prep-q8.sh` → Deployment `health-app` sudah punya readiness probe yang salah, jadi Pod tidak pernah Ready.

Di project `deploy-health`, konfigurasikan container `hello-world-nginx` pada Deployment `health-app`:

| Probe | Pemeriksaan | Setting |
| --- | --- | --- |
| Startup | HTTP GET `/` port 8080 | period 5s, failure threshold 12 |
| Liveness | TCP socket port 8080 | initial delay 15s, period 10s, timeout 3s, failure threshold 3 |
| Readiness | HTTP GET `/` port 8080 | period 10s, timeout 2s, success threshold 2, failure threshold 3 |

Probe lama yang salah tidak boleh tersisa. Pod harus `1/1 Running` dan route `health-app` merespons.

## Soal 9 — Deploy dengan OpenShift Pipelines (Tekton)

Persiapan: `bash prep/prep-q9.sh` → repo `tekton-web` dan skeleton `/home/student/ex288-set2/q9/pipeline-skeleton.yaml`

Semua dikerjakan di project `pipeline-lab`. Gunakan nilai-nilai ini persis seperti tertulis:

| Item | Nilai |
| --- | --- |
| Git repository (`GIT_URL`) | `https://git.ocp4.example.com/developer/tekton-web.git` |
| Git revision (`GIT_REVISION`) | `main` |
| Kredensial Git | `developer` / `d3v3lop3r` |
| File build | `Containerfile` di root repo |
| Image hasil build (`IMAGE`) | `image-registry.openshift-image-registry.svc:5000/pipeline-lab/tekton-web:latest` |
| Nama aplikasi (`APP_NAME`) | `tekton-web` |
| Service account | `pipeline` |
| Namespace task | `openshift-pipelines` (cluster resolver) |

- Buat Pipeline `build-and-deploy` dari skeleton dengan tiga task berurutan: `fetch-source` (git-clone), `build-image` (buildah), `deploy` (openshift-client).
- `fetch-source` meng-clone `GIT_URL` pada `GIT_REVISION` di atas.
- `build-image` mem-build `Containerfile` dan push ke alamat image di tabel.
- `deploy` membuat Deployment, Service, dan Route `tekton-web` jika belum ada. Jika sudah ada, task ini me-restart rollout.
- Repo Git private: kredensial disimpan sebagai secret dan dipakai service account `pipeline`.
- Workspace memakai PVC 1Gi dari volumeClaimTemplate.
- Jalankan PipelineRun dengan parameter `GIT_URL`, `GIT_REVISION`, `IMAGE`, dan `APP_NAME` sesuai tabel sampai `Succeeded`. Pod `tekton-web` harus Running dengan env `BUILT_BY=tekton`.

## Soal 10 — Expose internal registry dan push image

Persiapan: `bash prep/prep-q10.sh` → default route registry dimatikan, Containerfile di `/home/student/ex288-set2/q10/`.

- Sebagai `admin`, expose internal registry OpenShift lewat default route.
- Sebagai `developer`, build image dari Containerfile tersebut dengan nama `custom-nginx:1.0` memakai podman.
- Push image ke project `registry-lab` di internal registry lewat route tadi.
- Pastikan image stream `custom-nginx` dengan tag `1.0` muncul di `registry-lab`.
- Hapus image lokal, lalu pull kembali dari internal registry untuk membuktikan push berhasil.
- Deploy `custom-nginx:1.0` dari image stream, expose di hostname default, dan pastikan env `APP_TIER=registry-lab` ada di Pod.
