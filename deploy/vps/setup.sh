#!/usr/bin/env bash
# One-time setup of an AlmaLinux (or Rocky / RHEL) 9 server for the Capsula API.
# Run as root:
#
#   bash setup.sh
#
# It installs Docker, opens the web ports, and creates the "capsula" user that
# releases deploy as, with the app in /opt/capsula. It's safe to run again.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then echo "Run as root (sudo bash setup.sh)" >&2; exit 1; fi

here="$(cd "$(dirname "$0")" && pwd)"
dir=/opt/capsula

echo "== Updates and Docker"
dnf -y upgrade --refresh
dnf -y install dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable --now docker

echo "== Automatic security updates"
dnf -y install dnf-automatic
sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' \
  /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer

echo "== Firewall: SSH, HTTP, HTTPS"
dnf -y install firewalld
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=443/udp
firewall-cmd --reload

echo "== Deploy user"
if ! id capsula >/dev/null 2>&1; then useradd --create-home capsula; fi
usermod -aG docker capsula
install -d -m 700 -o capsula -g capsula /home/capsula/.ssh
touch /home/capsula/.ssh/authorized_keys
chown capsula:capsula /home/capsula/.ssh/authorized_keys
chmod 600 /home/capsula/.ssh/authorized_keys
restorecon -R /home/capsula/.ssh 2>/dev/null || true

echo "== App folder"
install -d -m 750 -o capsula -g capsula "$dir" "$dir/secrets"
chmod 700 "$dir/secrets"
for f in compose.yaml Caddyfile deploy.sh env.example; do
  install -m 640 -o capsula -g capsula "$here/$f" "$dir/$f"
done
chmod 750 "$dir/deploy.sh"
if [ ! -f "$dir/.env" ]; then
  install -m 600 -o capsula -g capsula "$here/env.example" "$dir/.env"
fi

cat <<NEXT

Done. Next:
  1. Edit $dir/.env (at least API_DOMAIN).
  2. Copy the Firebase service account key to $dir/secrets/service-account.json, then:
       chown capsula: $dir/secrets/service-account.json
       chmod 600 $dir/secrets/service-account.json
  3. Add the deploy public key to /home/capsula/.ssh/authorized_keys.
  4. Release the API (push a tag api-v<version>). The workflow
     deploys it here. To start it by hand instead: sudo -u capsula $dir/deploy.sh <version>
NEXT
