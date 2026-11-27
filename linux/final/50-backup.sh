#!/usr/bin/env bash
# [ماژول بکاپ] بکاپ تغییرات ماشین (پکیج‌ها + فایل‌های تغییرکرده + backup.paths) در تکه‌های ۴۰MB.
# خروجی توی /tmp/new-backup میره و ماژول تحویل (github/post/10-handoff.sh) اون رو داخل ریپو می‌ذاره.
bash "$REPO_ROOT/runner/backup.sh"
