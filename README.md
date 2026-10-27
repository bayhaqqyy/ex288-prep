# EX288 Prep — 10 Soal Latihan + Script Preparation

Set latihan untuk ujian **EX288 (Red Hat Certified OpenShift Application Developer)** di lab kelas **DO288 OCP 4.18**. Pola soalnya mengikuti kisi-kisi ujian asli dan repo [anishrana2001/Openshift DO288 V.4.18](https://github.com/anishrana2001/Openshift/tree/main/DO288/V.4.18).

| File | Isi |
| --- | --- |
| [`SOAL.md`](SOAL.md) | 10 soal, tanpa jawaban |
| [`KUNCI.md`](KUNCI.md) | Kunci jawaban dan verifikasi per soal |
| [`prep/`](prep/) | Script preparation `prep-q1.sh` … `prep-q10.sh` |

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

```bash
git clone https://github.com/bayhaqqyy/ex288-prep.git
cd ex288-prep/prep
bash prep-q1.sh        # siapkan satu soal saja
```

Lalu kerjakan soal di `SOAL.md` tanpa membuka `KUNCI.md`. Gunakan `oc --help`, `oc explain`, dan dokumentasi OpenShift seperti saat ujian.

Catatan:

- Setiap script bisa diulang: project soal dihapus lalu dibuat ulang, dan repo Git di lab ditimpa.
- Script menyimpan kredensial Git lab di `~/.git-credentials`, sama seperti lab Devopswala.
- Beberapa soal sengaja berisi bug (JSON rusak, port salah, label tidak cocok, probe salah). Itu bagian dari soal.
- Soal 2 di ujian asli memakai base image CentOS. Di lab kelas diganti image Node dari registry kelas; ganti lewat `BASE_IMAGE=<image> bash prep-q2.sh`.
- `prep-q10.sh` login sebagai `admin` untuk me-reset default route internal registry.
