#!/usr/bin/env bash
# [VNC] سرور TigerVNC روی پورت 5901 با دسکتاپ XFCE. با RealVNC Viewer به <Tailscale-IP>:5901 وصل شو.
# اختیاری (سکرت): VNC_GEOMETRY (پیش‌فرض 1920x1080)، VNC_SESSION (پیش‌فرض startxfce4)
PORT=5901; DISP=:1
log() { echo "[vnc] $*"; }
open_port() { (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; }
fail() { log "❌ $*"; announce "VNC" "❌ $*" "(جزئیات: خطوط [linux/services/30-vnc] در لاگ)"; sleep 30; exit 1; }

command -v Xtigervnc >/dev/null || fail "Xtigervnc نصب نیست — خروجی [linux/start/40-desktop] رو ببین"
[ -s "$HOME/.vnc/passwd" ] || fail "~/.vnc/passwd نیست — سکرت VNC_PASSWORD ست شده؟"
SESSION="${VNC_SESSION:-startxfce4}"
command -v "${SESSION%% *}" >/dev/null || fail "دسکتاپ '${SESSION%% *}' نصب نیست"

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null
mkdir -p "$HOME/.vnc"
Xtigervnc "$DISP" -rfbport "$PORT" -rfbauth "$HOME/.vnc/passwd" -SecurityTypes VncAuth \
  -geometry "${VNC_GEOMETRY:-1920x1080}" -depth 24 -AlwaysShared -desktop gh-linux \
  >> "$HOME/.vnc/xtigervnc.log" 2>&1 &
XPID=$!
for i in $(seq 1 20); do open_port && break; sleep 1; done
if ! open_port; then log "--- آخر لاگ Xtigervnc ---"; tail -n 30 "$HOME/.vnc/xtigervnc.log"; fail "پورت $PORT باز نشد"; fi

DISPLAY="$DISP" nohup dbus-launch --exit-with-session $SESSION >> "$HOME/.vnc/session.log" 2>&1 &
ip="$(tailscale ip -4 2>/dev/null | head -1)"
{ echo "RealVNC Viewer : ${ip:-<tailscale-ip>}:$PORT"; echo "رمز            : سکرت VNC_PASSWORD (۸ کاراکتر)"; } | announce "VNC"
log "✅ VNC آماده است (پورت $PORT)"
while kill -0 "$XPID" 2>/dev/null && open_port; do sleep 10; done
log "--- آخر لاگ Xtigervnc ---"; tail -n 20 "$HOME/.vnc/xtigervnc.log"
fail "سرور VNC متوقف شد"
