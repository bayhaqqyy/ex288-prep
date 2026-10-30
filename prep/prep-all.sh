#!/bin/bash
# ---------------------------------------------------------------
# EX288 Prep - siapkan semua soal sekaligus
#
#   bash prep/prep-all.sh          # siapkan soal 1-16
#   bash prep/prep-all.sh 1 3 6    # siapkan soal tertentu saja
#
# Setiap prep-qN.sh dijalankan berurutan di proses terpisah. Kalau satu
# soal gagal, soal berikutnya tetap disiapkan. Log lengkap per soal
# disimpan di /home/student/ex288-set2/logs/.
# ---------------------------------------------------------------
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="/home/student/ex288-set2/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="$(mktemp -d)"

if [ -t 1 ]; then G=$'\e[32m'; R=$'\e[31m'; B=$'\e[1m'; N=$'\e[0m'; else G=; R=; B=; N=; fi

if [ $# -gt 0 ]; then QS=("$@"); else QS=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16); fi

# Kredensial Git dulu, supaya git dan oc new-app bisa membaca repo lab
git config --global credential.helper store
echo "https://developer:d3v3lop3r@git.ocp4.example.com" > ~/.git-credentials
chmod 600 ~/.git-credentials

declare -A RESULT
START=$(date +%s)
for q in "${QS[@]}"; do
  script="$DIR/prep-q$q.sh"
  if [ ! -f "$script" ]; then
    echo "${R}Soal $q: $script tidak ditemukan${N}"
    RESULT[$q]="TIDAK ADA"
    continue
  fi
  log="$LOG_DIR/prep-q$q.log"
  echo "${B}[$(date +%T)] ===== Menyiapkan soal $q =====${N}"
  if ( set -o pipefail; cd "$HOME" && bash "$script" </dev/null 2>&1 | tee "$log" | sed 's/^/    /' ); then
    echo "${G}[$(date +%T)] Soal $q OK${N}"
    RESULT[$q]="OK"
  else
    echo "${R}[$(date +%T)] Soal $q GAGAL${N} (log: $log)"
    RESULT[$q]="GAGAL"
  fi
  echo
done

echo
echo "${B}Ringkasan prep ($(( $(date +%s) - START )) detik)${N}"
FAILED=0
for q in "${QS[@]}"; do
  case "${RESULT[$q]}" in
    OK) echo "  Soal $q  ${G}OK${N}" ;;
    *)  echo "  Soal $q  ${R}${RESULT[$q]}${N}"; FAILED=1 ;;
  esac
done
echo "Log per soal: $LOG_DIR"
exit $FAILED
