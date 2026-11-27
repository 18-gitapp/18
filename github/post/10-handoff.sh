#!/usr/bin/env bash
# [ماژول تحویل] بکاپ جدید + تغییرات next-repo/ ← ریپوی NEXT_REPO (یا همین ریپو) ← انتقال سکرت‌ها ← hookهای handoff/ ← استارت workflow بعدی.
# حذف این فایل = شیفت تموم میشه و تمام (هیچ اکانتی بعدش اجرا نمیشه).
bash "$REPO_ROOT/runner/handoff.sh"
