#!/usr/bin/env bash
# runner/lib.sh — توابع مشترک موتور (با source لود میشه)
RR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rr_init() {
  ROOT="$RR_ROOT"; LOG_DIR="${LOG_DIR:-/tmp/run-logs}"; INFO_DIR=/var/tmp/runner-info
  FG_TIMEOUT="${FG_TIMEOUT:-3600}"; END_TIMEOUT="${END_TIMEOUT:-600}"
  mkdir -p "$LOG_DIR" "$INFO_DIR"; chmod 1777 "$INFO_DIR" 2>/dev/null
  cd "$ROOT" || exit 1
  export REPO_ROOT="$ROOT" DATA_DIR="$HOME/data" LOG_DIR
  mkdir -p "$DATA_DIR"
  command -v announce >/dev/null 2>&1 || sudo install -m 755 "$ROOT/runner/announce.sh" /usr/local/bin/announce 2>/dev/null
}

# سکرت‌های ریپو ← متغیر محیطی. $1 = نام‌هایی که export نشن (جدا شده با فاصله)
load_secrets() {
  [ -n "${ALL_SECRETS:-}" ] || return 0
  eval "$(jq -r --arg hide "${1:-}" '($hide | split(" ")) as $h
    | to_entries[]
    | select(.key != "github_token")
    | select(.key | test("^(PATH|HOME|USER|SHELL|PWD)$") | not)
    | select(.key as $k | (($h | index($k)) == null))
    | "export \(.key)=\(.value|@sh)"' <<<"$ALL_SECRETS")"
}

# اجرای یک اسکریپت (foreground) با لاگ جمع‌شده؛ $1=فایل $2=برچسب $3=timeout
run_fg() {
  local f="$1" label="$2" to="${3:-$FG_TIMEOUT}" rc log
  log="$LOG_DIR/${label//\//__}.log"
  echo "::group::▶ [$label]"
  timeout "$to" bash "$f" 2>&1 | tee -a "$log"
  rc=${PIPESTATUS[0]}
  echo "::endgroup::"
  if [ "$rc" -eq 0 ]; then echo "✔ [$label] done"
  else echo "::warning::[$label] exit code $rc"; echo "✖ [$label] exit code $rc (continuing) — آخرین خطوط:"; tail -n 15 "$log" | sed 's/^/    /'; fi
}

# اجرای همه‌ی *.sh یک پوشه (به ترتیب نام). $1=پوشه (نسبت به ریشه‌ی ریپو) $2=timeout
run_dir() {
  local d="$ROOT/$1" f found=0; shopt -s nullglob
  for f in "$d"/*.sh; do found=1; run_fg "$f" "$1/$(basename "$f" .sh)" "${2:-}"; done
  [ "$found" -eq 0 ] && echo "   (در $1 اسکریپتی نیست)"
  return 0
}

# برد اطلاعات: همه‌ی چیزهایی که برنامه‌ها با `announce` ثبت کردن
print_board() {
  local f files=("$INFO_DIR"/*)
  [ ${#files[@]} -eq 0 ] && return 0
  echo ""
  echo "╔═══════════════════ 📋 اطلاعات برنامه‌ها ═══════════════════╗"
  for f in "${files[@]}"; do
    echo "▸ $(head -1 "$f")"
    tail -n +2 "$f" | sed -e 's/^/     /' -e '/^ *$/d'
    echo ""
  done
  echo "╚═══════ $(date -u '+%F %T UTC') ═══════╝"
  echo ""
}
board_sig() { cat "$INFO_DIR"/* 2>/dev/null | md5sum | cut -d' ' -f1; }
