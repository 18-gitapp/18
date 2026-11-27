#!/usr/bin/env bash
# بکاپ کل تغییرات ماشین ← یک tar.gz که به پارت‌های ۴۰ مگابایتی تقسیم میشه
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${BACKUP_OUT:-/tmp/new-backup}"
PART_SIZE="${PART_SIZE:-40M}"
export DATA_DIR="${DATA_DIR:-$HOME/data}"
rm -rf "$OUT"; mkdir -p "$OUT"

# ۱) پکیج‌های نصب‌شده + فایل‌های تغییرکرده
sudo env RUNNER_HOME="$HOME" python3 "$ROOT/runner/state.py" prepare /tmp/overlay.list0 || { echo "❌ state.py failed"; exit 1; }

# ۲) مسیرهای صریح backup.paths
explicit=(var/tmp/runner-state)
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  eval "p=$line"
  if [ -e "$p" ]; then explicit+=("${p#/}"); echo "  + $p"; else echo "  - (skip) $p"; fi
done < "$ROOT/backup.paths"
excl=(); [ -f "$ROOT/backup.exclude" ] && excl=(--exclude-from="$ROOT/backup.exclude")

# ۳) دو tar پشت هم (هنگام بازیابی با -i خونده میشن) ← gzip ← تکه‌های ۴۰ مگابایتی
{
  sudo tar --ignore-failed-read -C / -cp "${excl[@]}" -f - "${explicit[@]}" 2>/tmp/backup-tar1.err; echo $? > /tmp/rc1
  sudo tar --ignore-failed-read -C / -cp --no-recursion --null -T /tmp/overlay.list0 -f - 2>/tmp/backup-tar2.err; echo $? > /tmp/rc2
} | gzip -6 | split -b "$PART_SIZE" -d -a 3 - "$OUT/state.tar.gz.part_"
if [ "$(cat /tmp/rc1)" -gt 1 ] || [ "$(cat /tmp/rc2)" -gt 1 ]; then
  echo "❌ tar failed:"; tail -3 /tmp/backup-tar1.err /tmp/backup-tar2.err; exit 1
fi

shopt -s nullglob
parts=("$OUT"/state.tar.gz.part_*)
if [ ${#parts[@]} -eq 0 ]; then echo "⚠️ بکاپ خالی بود."; exit 0; fi
touch "$OUT/.ok"
total=$(du -sm "$OUT" | cut -f1)
echo "✅ بکاپ: ${#parts[@]} پارت، مجموع ${total}MB (هر پارت حداکثر $PART_SIZE)"
[ "$total" -ge 900 ] && echo "⚠️ حجم بکاپ بالای ۹۰۰MB است؛ داده‌های غیرضروری رو پاک کن یا به overlay.exclude اضافه کن."
exit 0
