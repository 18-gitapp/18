#!/usr/bin/env bash
# [Tailscale] آخر شیفت نود رو از tailnet حذف می‌کنه (بعد از بکاپ).
sudo tailscale logout 2>/dev/null || true
