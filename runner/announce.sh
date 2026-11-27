#!/usr/bin/env bash
# announce — ثبت اطلاعات یک برنامه برای «برد اطلاعات» (بعد از تموم شدن نصب‌ها خودکار چاپ میشه)
#   announce "عنوان" "متن"                    (چند آرگومان = چند خط)
#   some-command | announce "عنوان"          (خروجی هر دستوری رو پاس بده)
#   announce -n 20 "عنوان" < file            (فقط ۲۰ خط آخر؛ پیش‌فرض ۴۰)
# با عنوان تکراری، مقدار قبلی جایگزین میشه (مثلاً اول «در حال نصب»، بعد «آماده»).
# ⚠️ رمز/توکن نفرست: لاگ‌ها برای هر کسی که به ریپو دسترسی داره قابل دیدنه.
D=/var/tmp/runner-info; umask 000
N=40
if [ "${1:-}" = "-n" ]; then N="${2:-40}"; shift 2; fi
title="${1:-}"
[ -z "$title" ] && { sed -n '2,8p' "$0"; exit 2; }
shift
if [ $# -gt 0 ]; then body="$(printf '%s\n' "$@")"
elif [ ! -t 0 ]; then body="$(cat)"
else body=""; fi
body="$(printf '%s\n' "$body" | sed -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\r$//' | tail -n "$N")"
mkdir -p "$D"; chmod 1777 "$D" 2>/dev/null
slug="$(printf '%s' "$title" | md5sum | cut -c1-8)"
f="$(ls "$D"/*."$slug" 2>/dev/null | head -1)"
if [ -z "$f" ]; then f="$D/$(printf '%03d' $(( $(ls "$D" 2>/dev/null | wc -l) + 1 ))).$slug"; fi
{ printf '%s\n' "$title"; printf '%s\n' "$body"; } > "$f"
