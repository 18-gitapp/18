#!/usr/bin/env bash
# فاز لینوکس: linux/start ← linux/services ← (زنده می‌مونه) ← linux/end ← خاموشی سرویس‌ها ← linux/final
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; rr_init
FLAG_CHECK_EVERY="${FLAG_CHECK_EVERY:-120}"; BOARD_EVERY="${BOARD_EVERY:-600}"
BRANCH="${GITHUB_REF_NAME:-main}"; START="${JOB_START_EPOCH:-$(date +%s)}"
rm -f /tmp/STOP_LOOP /tmp/FORCE_HANDOFF

# سکرت‌ها (به‌جز آن‌هایی که در LINUX_HIDE_SECRETS هستن — پیش‌فرض: GH_TOKEN و NEXT_REPO)
load_secrets "${LINUX_HIDE_SECRETS-GH_TOKEN NEXT_REPO}"; unset ALL_SECRETS

# طول شیفت (بعد از لود سکرت‌ها تا Secret هم کار کنه) + اعتبارسنجی + سقف امن
RUN_MINUTES="${RUN_MINUTES:-320}"
case "$RUN_MINUTES" in ""|*[!0-9]*) echo "⚠️ RUN_MINUTES نامعتبر ('$RUN_MINUTES') → ۳۲۰"; RUN_MINUTES=320 ;; esac
if [ "$RUN_MINUTES" -gt 340 ]; then echo "⚠️ RUN_MINUTES=$RUN_MINUTES از سقف مجاز (۳۴۰) بیشتره → ۳۴۰"; RUN_MINUTES=340; fi
[ "$RUN_MINUTES" -lt 1 ] && RUN_MINUTES=1
DEADLINE=$(( START + RUN_MINUTES * 60 ))
echo "⏱️ طول شیفت: ${RUN_MINUTES} دقیقه"

BG_FILES=(); BG_LABELS=(); BG_PIDS=(); BG_START=(); BG_NEXT=(); BG_FAILS=(); LAST_PID=""
start_bg() {   # $1=فایل $2=برچسب — خروجی هم فایل لاگ، هم زنده توی لاگ Actions با پیشوند [برچسب]
  setsid bash -c 'set -o pipefail; bash "$1" 2>&1 | tee -a "$2" | sed -u "s|^|[$3] |"' _ "$1" "$LOG_DIR/${2//\//__}.log" "$2" </dev/null &
  LAST_PID=$!
}
check_remote_flags() {   # فایل STOP یا HANDOFF_NOW در ریپو (از سایت گیت‌هاب)
  git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null || return 0
  git cat-file -e FETCH_HEAD:STOP 2>/dev/null && touch /tmp/STOP_LOOP
  git cat-file -e FETCH_HEAD:HANDOFF_NOW 2>/dev/null && touch /tmp/FORCE_HANDOFF
}

shopt -s nullglob
echo "════════ linux/start ════════"
run_dir linux/start "$FG_TIMEOUT"

echo "════════ linux/services ════════"
for f in "$ROOT"/linux/services/*.sh; do
  label="linux/services/$(basename "$f" .sh)"
  echo "▶ [$label] starting (background)"
  start_bg "$f" "$label"
  BG_FILES+=("$f"); BG_LABELS+=("$label"); BG_PIDS+=("$LAST_PID"); BG_START+=("$(date +%s)"); BG_NEXT+=(0); BG_FAILS+=(0)
done
[ ${#BG_FILES[@]} -eq 0 ] && echo "   (در linux/services سرویسی نیست)"
print_board; last_sig="$(board_sig)"; last_board=$(date +%s)

echo "════════ keep-alive until $(date -u -d "@$DEADLINE" '+%F %T UTC') ════════"
last_flag_check=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  now=$(date +%s)
  if [ $(( now - last_flag_check )) -ge "$FLAG_CHECK_EVERY" ]; then check_remote_flags; last_flag_check=$now; fi
  if [ -f /tmp/STOP_LOOP ];     then echo "🛑 STOP requested — saving and stopping"; break; fi
  if [ -f /tmp/FORCE_HANDOFF ]; then echo "🔁 HANDOFF_NOW requested — handing off early"; break; fi
  for i in "${!BG_FILES[@]}"; do
    pid="${BG_PIDS[$i]}"; [ -z "$pid" ] && continue
    nm="${BG_LABELS[$i]}"; now=$(date +%s)
    if [ "$pid" = "WAIT" ]; then                       # منتظر زمان ری‌استارت
      if [ "$now" -ge "${BG_NEXT[$i]}" ]; then start_bg "${BG_FILES[$i]}" "$nm"; BG_PIDS[$i]="$LAST_PID"; BG_START[$i]=$now; fi
      continue
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null; rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "✔ [$nm] finished (exit 0)"; BG_PIDS[$i]=""
      else
        n="${BG_FAILS[$i]}"; [ $(( now - BG_START[$i] )) -gt 120 ] && n=0      # اگه >۲ دقیقه کار کرده بود، شمارنده صفر
        delay=$(( 5 * (1 << (n > 6 ? 6 : n)) )); [ "$delay" -gt 300 ] && delay=300
        BG_FAILS[$i]=$(( n + 1 )); BG_NEXT[$i]=$(( now + delay )); BG_PIDS[$i]="WAIT"
        echo "::warning::[$nm] exited ($rc)"
        echo "↻ [$nm] exited ($rc) — failure #$(( n + 1 )); restart in ${delay}s (دلیل: خطوط [$nm] بالاتر)"
      fi
    fi
  done
  sig="$(board_sig)"; now=$(date +%s)
  if [ "$sig" != "$last_sig" ] && [ $(( now - last_board )) -ge 10 ]; then print_board; last_sig="$sig"; last_board=$now
  elif [ $(( now - last_board )) -ge "$BOARD_EVERY" ]; then print_board; last_board=$now; fi
  sleep 5
done

echo "════════ linux/end ════════"
run_dir linux/end "$END_TIMEOUT"

echo "════════ توقف سرویس‌ها ════════"
for pid in "${BG_PIDS[@]}"; do [ -n "$pid" ] && [ "$pid" != WAIT ] && kill -TERM -- "-$pid" 2>/dev/null; done
[ ${#BG_FILES[@]} -gt 0 ] && sleep 10
for pid in "${BG_PIDS[@]}"; do [ -n "$pid" ] && [ "$pid" != WAIT ] && kill -KILL -- "-$pid" 2>/dev/null; done

echo "════════ linux/final ════════"
run_dir linux/final "$END_TIMEOUT"
exit 0
