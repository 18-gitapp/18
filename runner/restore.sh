#!/usr/bin/env bash
# بازیابی: فایل‌ها ← نصب مجدد پکیج‌های apt
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
shopt -s nullglob
parts=("$ROOT"/backup/state.tar.gz.part_*)
if [ ${#parts[@]} -eq 0 ]; then echo "ℹ️ بکاپی برای بازیابی وجود نداره (اجرای اول)."; exit 0; fi

echo "♻️ بازیابی فایل‌ها (${#parts[@]} پارت)..."
if cat "${parts[@]}" | sudo tar -xzpi -C / ; then echo "✅ فایل‌ها بازیابی شد."; else echo "⚠️ tar با خطا تموم شد (ادامه می‌دم)."; fi

list=/var/tmp/runner-state/pkgs.repo
if [ -s "$list" ]; then
  echo "📦 نصب مجدد $(wc -l < "$list") پکیج apt..."
  sudo apt-get update -qq
  opts=(-y -qq --no-install-recommends -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
  if ! xargs -a "$list" sudo env DEBIAN_FRONTEND=noninteractive apt-get install "${opts[@]}"; then
    echo "⚠️ نصب گروهی خطا داد — تک‌به‌تک"
    while read -r p; do
      [ -n "$p" ] && { sudo env DEBIAN_FRONTEND=noninteractive apt-get install "${opts[@]}" "$p" >/dev/null 2>&1 || echo "  ✖ $p"; }
    done < "$list"
  fi
  echo "✅ پکیج‌ها نصب شد."
fi
exit 0
