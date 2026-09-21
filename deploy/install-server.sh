#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
base=/srv/experta-tech
[[ ! -L "$base" ]] || { echo 'Unexpected symlink at deployment root' >&2; exit 1; }
for program in caddy git curl systemctl runuser flock; do command -v "$program" > /dev/null; done
if ! id experta-deploy > /dev/null 2>&1; then
  useradd --system --home-dir "$base" --shell /usr/sbin/nologin experta-deploy
fi
install -d -m 755 -o experta-deploy -g experta-deploy "$base" "$base/releases"
install -d -m 755 /usr/local/libexec
install -m 755 update-site.sh /usr/local/libexec/experta-update-site
install -m 644 experta-deploy.service /etc/systemd/system/experta-deploy.service
install -m 644 experta-deploy.timer /etc/systemd/system/experta-deploy.timer
runuser -u experta-deploy -- /usr/local/libexec/experta-update-site

backup=$(mktemp -d /etc/caddy/experta-backup.XXXXXXXX)
cp -a /etc/caddy/Caddyfile "$backup/Caddyfile"
if [[ -e /etc/caddy/experta-tech.caddy ]]; then
  cp -a /etc/caddy/experta-tech.caddy "$backup/experta-tech.caddy"
fi
install -m 644 experta-tech.caddy /etc/caddy/experta-tech.caddy
# Preserve all existing sites, adding just this site's import.
if ! grep -qxF 'import /etc/caddy/experta-tech.caddy' /etc/caddy/Caddyfile; then
  printf '\nimport /etc/caddy/experta-tech.caddy\n' >> /etc/caddy/Caddyfile
fi
if ! caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
  cp -a "$backup/Caddyfile" /etc/caddy/Caddyfile
  [[ ! -f "$backup/experta-tech.caddy" ]] || cp -a "$backup/experta-tech.caddy" /etc/caddy/experta-tech.caddy
  echo "Validation failed. Previous main configuration restored; backup: $backup" >&2
  exit 1
fi
if ! systemctl reload caddy; then
  cp -a "$backup/Caddyfile" /etc/caddy/Caddyfile
  [[ ! -f "$backup/experta-tech.caddy" ]] || cp -a "$backup/experta-tech.caddy" /etc/caddy/experta-tech.caddy
  systemctl reload caddy
  echo "Reload failed; restored configuration from $backup" >&2
  exit 1
fi
curl --fail --silent --show-error --max-time 10 -H 'Host: 79.174.90.25' http://127.0.0.1/ > /dev/null
systemctl daemon-reload
systemctl enable --now experta-deploy.timer
echo "Installed experta.tech. Configuration backup: $backup"
