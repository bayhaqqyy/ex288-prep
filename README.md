# EX288 Prep — 10 Soal Latihan + Script Preparation

Set latihan untuk ujian **EX288 (Red Hat Certified OpenShift Application Developer)** di lab kelas **DO288 OCP 4.18**. Pola soalnya mengikuti kisi-kisi ujian asli dan repo [anishrana2001/Openshift DO288 V.4.18](https://github.com/anishrana2001/Openshift/tree/main/DO288/V.4.18).

| File | Isi |
| --- | --- |
| [`SOAL.md`](SOAL.md) | 16 soal dalam bahasa Inggris (gaya ujian EX288), tanpa jawaban |
| [`KUNCI.md`](KUNCI.md) | Kunci jawaban dan verifikasi per soal |
| [`prep/`](prep/) | Script preparation `prep-q1.sh` … `prep-q16.sh`, `prep-all.sh` (semua sekaligus), `cleanup.sh` (bersih-bersih), `make-repos-public.sh` (repo GitLab jadi public) |
| [`grade/grade.sh`](grade/grade.sh) | Script penilaian otomatis: ujian inti 1–10 = 300 (lulus 210), tambahan 11–16 = 180 |

## Daftar soal

| No | Topik | Project |
| --- | --- | --- |
| 1 | S2I Node.js: JSON error + `Cannot find module 'prom-client'` | `metrics-prod` |
| 2 | Docker build dari base image + env Nexus (`npm_config_registry`) | `legacy-prod` |
| 3 | S2I httpd: `SERVER_PORT=8081` lewat `.s2i/bin/run` | `deploy-portal` |
| 4 | httpd Docker build dengan binary tar (`--from-archive`) | `deploy-docs` |
| 5 | ConfigMap + Secret untuk backend PostgreSQL | `inventory` |
| 6 | Template build + deploy (`REGISTRY_URL`, label, selector) | `lion` |
| 7 | Helm lab + production (limit, replicas, TLS, hostname) | `webstore-lab`, `webstore-prod` |
| 8 | Startup, liveness, readiness probe | `deploy-health` |
| 9 | OpenShift Pipelines (Tekton): git-clone → buildah → deploy | `pipeline-lab` |
| 10 | Expose internal registry + push dengan podman | `registry-lab` |

Soal tambahan (11–16), diambil dari materi referensi Devopswala yang lain:

| No | Topik | Project | Referensi |
| --- | --- | --- | --- |
| 11 | Troubleshoot Docker build aplikasi Maven (`COPY src .`) | `docker-app` | `01-01-Containerfile.md` |
| 12 | Podman build + fix image, push ke registry kelas, ImageStream + pull secret | `greetings-app` | `01-02-Building-Containers-...md` |
| 13 | Kustomisasi S2I `assemble` + `run` httpd | `builds-s2i` | `01-02-customizing-existing-S2I-image.md` |
| 14 | Optimasi Containerfile + parent/child `ONBUILD` | `production2` | `02-02-Optimize-containerfile.md` |
| 15 | Post-commit build hook + ConfigMap build input + generic webhook | `hooks-lab` | `04-02-EX288-task66-lab-creation.md` |
| 16 | S2I Java: `MAVEN_MIRROR_URL`, `JAVA_APP_JAR`, incremental build | `java-builds` | `01:02-oc-new-app.md`, `01-02-java-app.md` |

Soal 11 dan 16 memakai isi repo bawaan kelas `DO288-apps` di GitLab lab (`apps/docker-app/myapp1-docker` dan `apps/builds-applications/vertx-site`), jadi dependency Maven-nya sudah tersedia di Nexus kelas.

## Lingkungan lab

| Item | Nilai |
| --- | --- |
| API OpenShift | `https://api.ocp4.example.com:6443` |
| User OpenShift | `developer` / `developer` (admin: `admin` / `redhatocp`) |
| Git server | `https://git.ocp4.example.com`, user `developer` / `d3v3lop3r` |
| Registry kelas | `registry.ocp4.example.com:8443` |
| NPM Nexus | `http://nexus-infra.apps.ocp4.example.com/repository/npm` |
| Wildcard route | `*.apps.ocp4.example.com` |

Kredensial di atas adalah kredensial standar lab kelas, bukan kredensial produksi.

## Cara pakai

Di workstation lab, sebagai user `student`:

1. Simpan kredensial Git lab. Langkah ini wajib supaya `git clone` dan `oc new-app` bisa membaca repo private di `git.ocp4.example.com` tanpa ditanya password:

    ```bash
    git config --global credential.helper store
    echo "https://developer:d3v3lop3r@git.ocp4.example.com" > ~/.git-credentials
    chmod 600 ~/.git-credentials

    # cek: harus menampilkan hash, tanpa minta password
    git ls-remote https://git.ocp4.example.com/developer/legacy-web.git
    ```

2. Clone repo ini dan siapkan soal:

    ```bash
    git clone https://github.com/bayhaqqyy/ex288-prep.git
    cd ex288-prep

    bash prep/prep-all.sh          # siapkan semua soal 1-16 sekaligus
    bash prep/prep-all.sh 2 6 7    # atau soal tertentu saja
    bash prep/prep-q1.sh           # atau satu soal langsung
    ```

    `prep-all.sh` menjalankan setiap prep berurutan. Kalau satu soal gagal, soal lain tetap disiapkan, lalu muncul ringkasan OK/GAGAL. Log per soal ada di `/home/student/ex288-set2/logs/`.

3. Setelah selesai latihan, bersihkan:

    ```bash
    bash prep/cleanup.sh               # hapus project + file lab soal 1-16 (minta konfirmasi)
    bash prep/cleanup.sh 2 7           # soal tertentu saja
    bash prep/cleanup.sh -y            # tanpa konfirmasi
    bash prep/cleanup.sh --all-extra   # + clone lokal repo latihan, image podman, default route registry off
    ```

    Cleanup mematikan Pod tanpa grace period, menghapus isi project, lalu menghapus project. Kalau setelah 10 detik masih Terminating, finalizer semua objek dilepas dan namespace di-finalize paksa sebagai admin, jadi tidak ada lagi yang stuck. Kalau mau mode hati-hati (tanpa lepas finalizer paksa), tambahkan `--safe`.

    Repo di GitLab lab tidak dihapus karena butuh token API. Prep berikutnya menimpa isinya, jadi aman dibiarkan.

Script prep otomatis menjadikan repo latihan di GitLab lab **public**, supaya `oc new-app` bisa membaca repo tanpa kredensial. Untuk repo yang sudah ada tanpa me-reset isinya, jalankan `bash prep/make-repos-public.sh`. Soal tetap meminta secret Git untuk build, sesuai pola ujian.

Kalau `oc new-app` menampilkan `warning: Cannot check if git requires authentication` lalu `none of the arguments provided could be classified as a source code location`, berarti langkah 1 belum jalan. Ulangi langkah 1, lalu coba lagi.

Lalu kerjakan soal di `SOAL.md` tanpa membuka `KUNCI.md`. Gunakan `oc --help`, `oc explain`, dan dokumentasi OpenShift seperti saat ujian.

## Penilaian (ujian inti 300, lulus 210)

Setelah selesai, periksa jawabanmu dengan:

```bash
cd ex288-prep
bash grade/grade.sh          # semua soal 1-16 -> nilai per soal, inti /300 + LULUS, tambahan /180
bash grade/grade.sh 1 2 3 4 5 6 7 8 9 10   # hanya ujian inti
bash grade/grade.sh 3 7      # hanya soal tertentu
```

Setiap soal bernilai 30 poin, dipecah menjadi beberapa pemeriksaan berbobot. Contohnya Soal 7: chart 2.1.0 di Git, release lab dan prod, jumlah Pod, limit/request, label, env, serta route dan TLS. Vonis lulus dihitung dari ujian inti Soal 1–10: batas 210/300 (70%), mengikuti EX288. Soal 11–16 dinilai terpisah (/180) sebagai latihan tambahan, dan total keseluruhan /480 ikut ditampilkan.

Cara kerja grader:

- Login sebagai `admin` di KUBECONFIG sementara, jadi sesi `oc` milikmu tidak berubah. Grader hanya membaca, tidak mengubah apa pun.
- Memeriksa objek di cluster (BuildConfig, Deployment, Route, probe, Pipeline, ImageStream, dan lain-lain).
- Meng-clone repo Git lab untuk memastikan perbaikan sudah di-push, bukan hanya diubah lokal.
- Mengakses route dengan `curl` untuk memastikan aplikasi benar-benar merespons.
- Menyimpan laporan ke `/home/student/ex288-set2/grade-report-<tanggal>.txt`.

Contoh potongan output:

```text
Soal 7 - Helm lab + production
  [PASS]  3 poin  Chart di Git: version 2.1.0 dan template me-render resources
  [PASS]  2 poin  [lab] Release webstore-lab deployed di webstore-lab
  [FAIL]  4 poin  [prod] Limit 500m/512Mi, request 250m/256Mi
  ...
  Subtotal: 26/30

Ringkasan
  Soal 1     30/30   S2I Node.js: JSON error + prom-client
  ...
  Ujian inti (Soal 1-10)    254/300
  Soal tambahan (11-16)     150/180
  TOTAL                     404/480  (84%)
  LULUS ujian inti (batas lulus 210/300)
```

Catatan:

- Setiap script bisa diulang: project soal dihapus lalu dibuat ulang, dan repo Git di lab ditimpa.
- Script menyimpan kredensial Git lab di `~/.git-credentials`, sama seperti lab Devopswala.
- Beberapa soal sengaja berisi bug (JSON rusak, port salah, label tidak cocok, probe salah). Itu bagian dari soal.
- Soal 2 di ujian asli memakai base image CentOS. Di lab kelas diganti image Node dari registry kelas; ganti lewat `BASE_IMAGE=<image> bash prep-q2.sh`.
- `prep-q10.sh` login sebagai `admin` untuk me-reset default route internal registry.
