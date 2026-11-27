#!/usr/bin/env bash
# [ماژول تحویل] نصب دستور handoff-set (ثبت Secret/Variable برای ست شدن روی ریپوی بعدی)
sudo install -m 755 "$REPO_ROOT/runner/handoff-set.sh" /usr/local/bin/handoff-set
