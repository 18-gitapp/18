#!/usr/bin/env bash
# handoff-set — ثبت Secret/Variable برای ست شدن روی ریپوی بعدی در لحظه‌ی تحویل شیفت
#   handoff-set secret NAME [VALUE]     (اگه VALUE ندی، از stdin می‌خونه)
#   handoff-set var    NAME [VALUE]
#   handoff-set list | clear
# مقدارها فقط روی دیسک موقت همین ماشین می‌مونن (هیچ‌جا commit یا بکاپ نمیشن).
set -u
D=/var/tmp/runner-outbox; umask 077
case "${1:-}" in
  secret|var)
    kind="$1"; name="${2:-}"; [ -z "$name" ] && { echo "usage: handoff-set $kind NAME [VALUE]"; exit 2; }
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "❌ نام نامعتبر: $name"; exit 2; }
    case "$name" in GITHUB_*) echo "❌ نام نباید با GITHUB_ شروع بشه"; exit 2 ;; esac
    mkdir -p "$D/$kind"
    if [ $# -ge 3 ]; then printf '%s' "$3" > "$D/$kind/$name"; else cat > "$D/$kind/$name"; fi
    echo "✅ $kind $name ثبت شد — موقع تحویل روی ریپوی بعدی ست میشه." ;;
  list)  ls -1 "$D"/secret "$D"/var 2>/dev/null | sed 's/^/  /' ;;
  clear) rm -rf "$D"; echo "پاک شد." ;;
  *) sed -n '2,7p' "$0"; exit 2 ;;
esac
