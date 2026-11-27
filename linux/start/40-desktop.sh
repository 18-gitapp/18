#!/usr/bin/env bash
# [VNC] دسکتاپ XFCE + سرور VNC استاندارد (TigerVNC) — با RealVNC Viewer و هر کلاینت VNC دیگه‌ای کار می‌کنه.
# سکرت: VNC_PASSWORD  (⚠️ پروتکل VNC فقط ۸ کاراکتر اول رو می‌خونه؛ رمز ۸ کاراکتری بذار)
export DEBIAN_FRONTEND=noninteractive
if [ -z "${VNC_PASSWORD:-}" ]; then announce "VNC" "❌ سکرت VNC_PASSWORD ست نشده"; echo "❌ VNC_PASSWORD ست نشده"; exit 1; fi
sudo apt-get update -qq
sudo apt-get install -y -qq xfce4 xfce4-terminal dbus-x11 tigervnc-standalone-server tigervnc-common \
  fonts-noto fonts-noto-color-emoji papirus-icon-theme arc-theme
[ "${#VNC_PASSWORD}" -gt 8 ] && echo "⚠️ VNC_PASSWORD بیشتر از ۸ کاراکتره؛ فقط ۸ کاراکتر اول اعتبار داره"
mkdir -p "$HOME/.vnc" && chmod 700 "$HOME/.vnc"
printf '%s' "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd" && chmod 600 "$HOME/.vnc/passwd"
# قفل‌کننده‌ی صفحه رو غیرفعال کن (رمز کاربر نداریم؛ قفل شد دیگه باز نمیشه)
mkdir -p "$HOME/.config/autostart"
for n in light-locker xfce4-screensaver xscreensaver; do
  printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$n" > "$HOME/.config/autostart/$n.desktop"
done
echo "✅ دسکتاپ + TigerVNC آماده"
