#!/usr/bin/env bash
# اجرای یک پوشه‌ی github/* (هر پوشه یک مرحله‌ی جدا توی workflow). همه‌ی سکرت‌ها متغیر محیطی‌ان.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"; rr_init
load_secrets ""                       # ALL_SECRETS هم می‌مونه (hookهای تحویل لازمش دارن)
dir="${1:?usage: run-dir.sh github/pre|github/post|github/always}"
echo "════════ $dir ════════"
shopt -s nullglob
run_dir "$dir" "${GH_TIMEOUT:-900}"
exit 0
