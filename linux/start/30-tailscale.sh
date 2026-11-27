#!/usr/bin/env bash
# [Tailscale] اتصال ماشین به tailnet شما.
# سکرت‌ها: TS_OAUTH_SECRET (tskey-client-...) یا TS_AUTHKEY / TAILSCALE_AUTHKEY (tskey-auth-...)
#          TS_TAGS (با OAuth الزامی؛ مثلاً tag:hermes)  |  TS_HOSTNAME (اختیاری؛ پیش‌فرض gh-linux)
KEY="${TS_OAUTH_SECRET:-${TS_AUTHKEY:-${TAILSCALE_AUTHKEY:-}}}"
if [ -z "$KEY" ]; then announce "Tailscale" "❌ سکرت TS_OAUTH_SECRET (یا TS_AUTHKEY) ست نشده"; echo "❌ کلید Tailscale ست نشده"; exit 1; fi
if [[ "$KEY" == tskey-client-* ]] && [ -z "${TS_TAGS:-}" ]; then
  announce "Tailscale" "❌ با کلید OAuth باید سکرت TS_TAGS هم ست باشه (تگی که OAuth client بهش اجازه داره، مثلاً tag:hermes)"
  echo "❌ TS_TAGS ست نشده"; exit 1
fi

command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled 2>/dev/null || true
if [ ! -S /var/run/tailscale/tailscaled.sock ]; then          # اگه systemd سرویس رو بالا نیاورد
  sudo nohup tailscaled --tun=userspace-networking >/tmp/tailscaled.log 2>&1 &
  sleep 3
fi

args=(--hostname="${TS_HOSTNAME:-gh-linux}" --ssh --accept-dns=false)
if [[ "$KEY" == tskey-client-* ]]; then
  AUTH="${KEY}?ephemeral=true&preauthorized=true"
  args+=(--advertise-tags="$TS_TAGS")
else
  AUTH="$KEY"
fi
sudo env TS_EXPERIMENT_OAUTH_AUTHKEY=true tailscale up --authkey="$AUTH" "${args[@]}" || {
  announce "Tailscale" "❌ tailscale up ناموفق — کلید/تگ/ACL رو چک کن (جزئیات: گروه [linux/start/30-tailscale])"; echo "❌ tailscale up ناموفق"; exit 1; }
ip="$(tailscale ip -4 2>/dev/null | head -1)"
{ echo "IP   : $ip"; echo "SSH  : ssh runner@$ip   (Tailscale SSH؛ بدون رمز)"; } | announce "Tailscale"
echo "✅ Tailscale IP: $ip"
