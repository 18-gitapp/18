#!/usr/bin/env bash
# [ماژول بکاپ] ثبت وضعیت اولیه‌ی ماشین (لیست پکیج‌ها + زمان). لازمه‌ی بکاپ آخر شیفت (linux/final/50-backup.sh).
# باید قبل از هر نصبی اجرا بشه (شماره‌ی کمتر از بقیه).
sudo env RUNNER_HOME="$HOME" python3 "$REPO_ROOT/runner/state.py" start
