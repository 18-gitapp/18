#!/usr/bin/env bash
# بکاپ جدید ← داخل ریپو؛ بعد تحویل کل ریپو (commands + بکاپ + سکرت‌ها) به اکانت بعدی
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"

API="${GITHUB_API_URL:-https://api.github.com}"
SELF="${GITHUB_REPOSITORY:?}"
BRANCH="${GITHUB_REF_NAME:-main}"
PAT="${GH_TOKEN:-}"
OUT="${BACKUP_OUT:-/tmp/new-backup}"
MIN_RUNTIME="${MIN_RUNTIME:-600}"
DISPATCH_RETRIES="${DISPATCH_RETRIES:-6}"; DISPATCH_WAIT="${DISPATCH_WAIT:-10}"

git config user.email "runner-bot@users.noreply.github.com"
git config user.name  "Runner Bot"

remote_url() { echo "${GIT_URL_OVERRIDE:-https://x-access-token:$2@github.com/$1.git}"; }   # $1=repo $2=token

dispatch() {     # $1=repo $2=ref $3=token
  local n code
  for n in $(seq 1 "$DISPATCH_RETRIES"); do
    code=$(curl -s -o /tmp/dispatch.out -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $3" -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "$API/repos/$1/actions/workflows/runner.yml/dispatches" -d "{\"ref\":\"$2\"}")
    [ "$code" = "204" ] && { echo "✅ workflow started on $1"; return 0; }
    echo "dispatch attempt $n → HTTP $code: $(cat /tmp/dispatch.out 2>/dev/null)"; sleep "$DISPATCH_WAIT"
  done
  return 1
}


# ── صندوق تغییرات برای اکانت بعدی: next-repo/ (داخل ریپو) و ~/next-repo/ (روی ماشین) ──
#   ساختار داخلش مثل ریپوئه: next-repo/linux/start/50-app.sh  →  linux/start/50-app.sh
#   فقط یک‌بار اعمال میشه و بعدش خالی میشه (تا دفعه‌ی بعد دوباره اعمال نشه)
safe_rel() { case "$1" in ""|/*|*..*|.git|.git/*|next-repo|next-repo/*) return 1 ;; esac; return 0; }
apply_box() {   # $1 = پوشه‌ی مبدأ
  local box="$1" f rel line n=0
  [ -d "$box" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$box"/}"
    case "$rel" in README.md|.delete|.gitkeep) continue ;; esac
    if ! safe_rel "$rel"; then echo "⚠️ مسیر نامعتبر نادیده گرفته شد: $rel"; continue; fi
    mkdir -p "$(dirname "$rel")" && cp -f "$f" "$rel" && rm -f "$f" && { echo "📝 next-repo → $rel"; n=$((n+1)); }
  done < <(find "$box" -type f -print0 2>/dev/null)
  if [ -f "$box/.delete" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"; line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      if safe_rel "$line"; then rm -rf -- "$line" && echo "🗑️ next-repo ✂ $line"; else echo "⚠️ مسیر نامعتبر در .delete: $line"; fi
    done < "$box/.delete"
    printf '# هر خط یک مسیر (نسبت به ریشه‌ی ریپو) که موقع تحویل حذف میشه. بعد از اعمال، این فایل خالی میشه.\n' > "$box/.delete"
  fi
  find "$box" -mindepth 1 -type d -empty -delete 2>/dev/null
  return 0
}
ONCE=/tmp/handoff-once
take_once_hooks() {   # اسکریپت‌های *.once.sh از درخت برداشته میشن (که همراه ریپو نرن) و بعد از تحویل یک‌بار اجرا میشن
  rm -rf "$ONCE"; mkdir -p "$ONCE"
  local h
  if [ -z "$PAT" ] || ! command -v gh >/dev/null; then ls handoff/*.once.sh >/dev/null 2>&1 && echo "⚠️ once-hook ها بدون GH_TOKEN اجرا نمیشن؛ تو ریپو می‌مونن"; return 0; fi
  for h in handoff/*.once.sh; do [ -f "$h" ] && mv "$h" "$ONCE/" && echo "☝️ once-hook: $(basename "$h")"; done
  return 0
}

# ── آخرین نسخه‌ی ریپو (تغییراتی که وسط شیفت دستی دادی هم حفظ میشه) + بکاپ جدید ──
prepare_tree() {
  if git fetch -q --depth 1 origin "$BRANCH" 2>/dev/null; then git checkout -q -f -B work FETCH_HEAD; fi
  git clean -fdq
  if [ -f "$OUT/.ok" ]; then
    rm -rf backup; mkdir -p backup; cp "$OUT"/state.tar.gz.part_* backup/
    echo "📦 بکاپ جدید جایگزین شد ($(ls backup | wc -l) پارت)"
  else
    echo "⚠️ بکاپ جدید ساخته نشده — بکاپ قبلی دست‌نخورده می‌مونه"
  fi
  rm -f HANDOFF_NOW
  apply_box next-repo            # صندوق داخل ریپو (از سایت گیت‌هاب)
  apply_box "$HOME/next-repo"    # صندوق روی ماشین (بدون commit)؛ بعد از این‌ها برنده است
  take_once_hooks
}

push_normal() {   # بدون توکن شخصی: یک commit روی همین ریپو
  git add -A
  git diff --cached --quiet || git commit -qm "state: $(date -u '+%F %T UTC')"
  git push -q origin "HEAD:$BRANCH" 2>/dev/null \
    || { git pull -q --rebase origin "$BRANCH" && git push -q origin "HEAD:$BRANCH"; } \
    && echo "💾 saved to $SELF" || echo "⚠️ push failed"
}

# پوش با توکن شخصی: هدر Authorization که actions/checkout توی کانفیگ گذاشته (GITHUB_TOKEN) روی آدرس مقصد هم اعمال میشه
# و روی توکن داخل URL غلبه می‌کنه (نتیجه: ۴۰۳ روی ریپوی اکانت دیگه). با مقدار خالی خنثی‌ش می‌کنیم.
gitx() { git -c "http.${GIT_HOST_SCOPE:-https://github.com/}.extraheader=" -c credential.helper= "$@"; }
push_to() {   # آرگومان‌ها مثل git push؛ در صورت خطا دلیل رو چاپ می‌کنه
  local out rc; out="$(gitx push -q "$@" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "❌ git push ناموفق:"; printf '%s\n' "$out" | tail -6 | sed 's/^/   /'
    if printf '%s' "$out" | grep -qi 'workflow.*scope\|without .workflow'; then echo "   💡 توکن scope «workflow» نداره (classic: تیک workflow؛ fine-grained: Workflows = Read and write)"
    elif printf '%s' "$out" | grep -qiE 'denied|403|permission|not found|404'; then echo "   💡 توکن به ریپوی مقصد دسترسی Write نداره (Collaborator نیستی؟ توکن مال همون اکانت نیست؟)"; fi
  fi
  return $rc
}
push_orphan() {   # $1=repo $2=branch $3=token  — تاریخچه پاک میشه تا ریپو حجیم نشه
  local url size; url="$(remote_url "$1" "$3")"
  size=$(du -sm backup 2>/dev/null | cut -f1)
  git checkout -q --orphan handoff
  if [ "${size:-0}" -ge 800 ]; then
    echo "📦 بکاپ بزرگه (${size}MB) — پوش مرحله‌ای"
    git rm -rq --cached backup 2>/dev/null
    git add -A -- . ':!backup'
    git commit -qm "code: $(date -u '+%F %T UTC')"
    push_to "$url" "handoff:refs/heads/$2" --force || return 1
    for f in backup/*; do
      git add "$f"; git commit -qm "backup part: $(basename "$f")"
      push_to "$url" "handoff:refs/heads/$2" || return 1
    done
  else
    git add -A
    git commit -qm "state: $(date -u '+%F %T UTC')"
    push_to "$url" "handoff:refs/heads/$2" --force || return 1
  fi
}

sync_secrets() {  # همه‌ی سکرت‌ها به‌جز GH_TOKEN و NEXT_REPO (اون دو مخصوص هر ریپو هستن)
  command -v gh >/dev/null || { echo "ℹ️ gh نصب نیست — سکرت‌ها منتقل نشد"; return 0; }
  [ -z "${ALL_SECRETS:-}" ] && return 0
  local name val
  while IFS= read -r name; do
    case "$name" in github_token|GH_TOKEN|NEXT_REPO) continue ;; esac
    val="$(jq -j --arg k "$name" '.[$k]' <<<"$ALL_SECRETS")"; [ -z "$val" ] && continue
    printf '%s' "$val" | GH_TOKEN="$PAT" gh secret set "$name" --repo "$1" >/dev/null 2>&1 \
      && echo "🔐 secret synced: $name" || echo "⚠️ secret sync failed: $name"
  done < <(jq -r 'keys[]' <<<"$ALL_SECRETS")
}


# ── اسکریپت‌های handoff/ و outbox (handoff-set) روی ریپویی که قراره بعدی اجرا بشه ──
run_hooks() {   # $1 = ریپوی هدف
  local repo="$1" kind sub f name h
  local OB=/var/tmp/runner-outbox
  local pending; pending=$(compgen -G "$OB/secret/*"; compgen -G "$OB/var/*"; compgen -G "handoff/*.sh"; compgen -G "$ONCE/*.sh")
  [ -z "$pending" ] && return 0
  if [ -z "$PAT" ]; then echo "⚠️ handoff/ و handoff-set به GH_TOKEN نیاز دارن (توکن شخصی) — اجرا نشد"; return 0; fi
  command -v gh >/dev/null || { echo "⚠️ gh نصب نیست — اجرا نشد"; return 0; }
  export GH_TOKEN="$PAT"
  for kind in secret var; do
    sub=secret; [ "$kind" = var ] && sub=variable
    for f in "$OB/$kind"/*; do
      [ -f "$f" ] || continue; name="$(basename "$f")"
      if gh "$sub" set "$name" --repo "$repo" < "$f" >/dev/null 2>&1; then
        echo "✅ $sub $name → $repo"; rm -f "$f"
      else echo "⚠️ ست کردن $sub $name روی $repo ناموفق بود"; fi
    done
  done
  for h in handoff/*.sh "$ONCE"/*.sh; do
    [ -f "$h" ] || continue
    echo "▶ hook: $h"
    (
      if [ -n "${ALL_SECRETS:-}" ]; then
        eval "$(jq -r 'to_entries[] | select(.key != "github_token") | select(.key | test("^(PATH|HOME|USER|SHELL|PWD)$") | not) | "export \(.key)=\(.value|@sh)"' <<<"$ALL_SECRETS")"
      fi
      export GH_TOKEN="$PAT" SELF_REPO="$SELF" NEXT_REPO="$repo" TARGET_REPO="$repo" DATA_DIR="${DATA_DIR:-$HOME/data}"
      timeout 120 bash "$h"
    ) 2>&1 | sed 's/^/   /'
    [ "${PIPESTATUS[0]}" -eq 0 ] || echo "⚠️ hook $h با خطا تموم شد (ادامه می‌دم)"
    case "$h" in "$ONCE"/*) rm -f "$h" ;; esac
  done
}

# بررسی دسترسی توکن به ریپوی مقصد (قبل از پوش)؛ کد HTTP در DIAG_CODE. خروجی ۱ = خطای قطعی
diagnose_target() {
  local hdr body scopes push; hdr="$(mktemp)"
  body="$(curl -s -D "$hdr" -H "Authorization: Bearer $PAT" -H "Accept: application/vnd.github+json" "$API/repos/$1")"
  DIAG_CODE="$(head -1 "$hdr" | awk '{print $2}')"
  scopes="$(grep -i '^x-oauth-scopes:' "$hdr" | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')"
  push="$(printf '%s' "$body" | jq -r '.permissions.push | if . == null then "unknown" else tostring end' 2>/dev/null)"; rm -f "$hdr"
  echo "🔎 دسترسی توکن به $1: HTTP ${DIAG_CODE:-?} | push: ${push:-unknown} | scopes: ${scopes:-نامشخص (توکن fine-grained؟)}"
  case "$DIAG_CODE" in
    401) echo "::error::GH_TOKEN نامعتبر یا منقضی است"; return 1 ;;
    403) echo "::error::گیت‌هاب با ۴۰۳ جواب داد (محدودیت نرخ یا نبودن دسترسی توکن)"; return 1 ;;
  esac
  if [ "$DIAG_CODE" = 200 ] && [ "$push" = false ]; then
    echo "::error::GH_TOKEN به $1 دسترسی Write ندارد (Collaborator با Write بودن + scope repo لازمه)"; return 1
  fi
  if [ -n "$scopes" ] && ! printf '%s' "$scopes" | grep -qw workflow; then
    echo "⚠️ توکن scope «workflow» نداره؛ پوش فایل .github/workflows رد میشه (توکن classic رو با workflow دوباره بساز)"
  fi
  return 0
}
fallback_self() {   # تحویل ناموفق ← ادامه روی همین ریپو
  echo "::error::$1"; echo "❌ $1"; echo "   → فعلاً روی همین ریپو ادامه می‌دم."
  git checkout -q -f work 2>/dev/null || true
  push_normal; run_hooks "$SELF"; dispatch "$SELF" "$BRANCH" "${GITHUB_TOKEN:-}"; exit 0
}

# ═══════════════════════════ اجرا ═══════════════════════════
prepare_tree

if [ -f /tmp/STOP_LOOP ] || [ -f STOP ]; then
  echo "🛑 STOP — فقط ذخیره، بدون اجرای بعدی (فایل STOP رو برای اجرای دوباره پاک کن)"
  push_normal; run_hooks "$SELF"; exit 0
fi
if [ ! -f /tmp/FORCE_HANDOFF ] && [ -n "${JOB_START_EPOCH:-}" ] \
   && [ $(( $(date +%s) - JOB_START_EPOCH )) -lt "$MIN_RUNTIME" ]; then
  echo "⚠️ اجرا خیلی کوتاه بود (کرش؟) — زنجیره ادامه پیدا نمی‌کنه تا حلقه‌ی بی‌نهایت نشه"
  push_normal; exit 0
fi

TARGET="$(printf '%s' "${NEXT_REPO:-}" | tr -d '[:space:]' | sed -E 's#^(https?://)?(www\.)?github\.com/##; s#\.git$##; s#/+$##')"
echo "🔎 تحویل: ریپوی فعلی=$SELF | NEXT_REPO=${TARGET:-<خالی>} | GH_TOKEN=$([ -n "$PAT" ] && echo '✅ هست' || echo '❌ خالی')"
[ -z "$PAT" ] && echo "   💡 GH_TOKEN باید «Secret» باشه (نه Variable) و روی همین ریپو ($SELF) ساخته شده باشه"
[ -z "$TARGET" ] && TARGET="$SELF"

# ── همین ریپو ──
if [ "${TARGET,,}" = "${SELF,,}" ] || [ -z "$PAT" ]; then
  [ "${TARGET,,}" != "${SELF,,}" ] && echo "⚠️ NEXT_REPO تنظیم شده ولی GH_TOKEN خالیه — روی همین ریپو ادامه می‌دم"
  if [ -n "$PAT" ]; then
    push_orphan "$SELF" "$BRANCH" "$PAT" && echo "💾 saved (history reset)" || push_normal
    run_hooks "$SELF"
    dispatch "$SELF" "$BRANCH" "$PAT"
  else
    push_normal
    run_hooks "$SELF"
    dispatch "$SELF" "$BRANCH" "${GITHUB_TOKEN:-}"
  fi
  exit 0
fi

# ── ریپوی اکانت بعدی ──
echo "🔗 hand-off → $TARGET"
diagnose_target "$TARGET" || fallback_self "تحویل به $TARGET ممکن نیست (دلیل: خط 🔎 بالا)"
if [ "$DIAG_CODE" = "404" ]; then
  me=$(curl -s -H "Authorization: Bearer $PAT" "$API/user" | jq -r '.login // empty')
  if [ -n "$me" ] && [ "${me,,}" = "$(echo "${TARGET%%/*}" | tr 'A-Z' 'a-z')" ]; then
    echo "📦 ساخت ریپوی خصوصی $TARGET"
    curl -s -o /dev/null -X POST -H "Authorization: Bearer $PAT" -H "Accept: application/vnd.github+json" \
      "$API/user/repos" -d "{\"name\":\"${TARGET#*/}\",\"private\":true}"; sleep 4
  else
    fallback_self "ریپوی $TARGET وجود نداره یا توکن بهش دسترسی نداره (دوستت باید ریپوی خصوصی بسازه و تو رو Collaborator کنه)"
  fi
fi

if push_orphan "$TARGET" "main" "$PAT"; then
  sync_secrets "$TARGET"
  run_hooks "$TARGET"
  sleep 5
  dispatch "$TARGET" "main" "$PAT" && exit 0
  echo "⚠️ استارت اکانت بعدی ناموفق بود"
fi
fallback_self "تحویل به $TARGET ناموفق بود (دلیل push: بالاتر)"
