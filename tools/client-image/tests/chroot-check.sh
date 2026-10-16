#!/bin/bash
# Small chroot check (no image build): runs browser.sh + verify-browser.sh in a minimal Ubuntu arm64 rootfs
# exported from the docker image, under qemu-aarch64-static. Checks policies, held package, no Google repo,
# start page, home-Engine unit and the one IDEA shortcut.
# Usage: sudo tests/chroot-check.sh [--chrome-deb FILE] [--ubuntu 26.04] [--apt-proxy http://127.0.0.1:3128]   (~1.5 GB disk, low RAM)
set -euo pipefail
H="$(cd "$(dirname "$0")/.." && pwd)"; . "$H/client-image.conf"
DEB="$H/work/$CHROME_DEB"; UB=26.04; PROXY=""
while [ $# -gt 0 ]; do case "$1" in --chrome-deb) DEB="$2"; shift 2;; --ubuntu) UB="$2"; shift 2;; --apt-proxy) PROXY="$2"; shift 2;; *) exit 2;; esac; done
echo "$CHROME_DEB_SHA256  $DEB" | sha256sum -c --quiet
R=$(mktemp -d /var/tmp/idea-chroot.XXXX); trap 'for m in proc dev; do umount -l "$R/$m" 2>/dev/null; done; rm -rf "$R"' EXIT
docker pull -q --platform linux/arm64 ubuntu:$UB >/dev/null
cid=$(docker create --platform linux/arm64 ubuntu:$UB); docker export "$cid" | tar -x -C "$R"; docker rm "$cid" >/dev/null
[ "$(uname -m)" = aarch64 ] || cp /usr/bin/qemu-aarch64-static "$R/usr/bin/"; cp -L /etc/resolv.conf "$R/etc/resolv.conf"
mount --bind /proc "$R/proc"; mount --bind /dev "$R/dev"
B="$R/root/.idea-build"; mkdir -p "$B"; cp -r "$H/files" "$B/"; cp "$H/browser.sh" "$H/verify-browser.sh" "$B/"; cp "$DEB" "$B/$CHROME_DEB"
[ -z "$PROXY" ] || echo "Acquire::http::Proxy \"$PROXY\";" > "$R/etc/apt/apt.conf.d/00proxy"
chroot "$R" /bin/bash -c "set -e; export DEBIAN_FRONTEND=noninteractive; printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d
  apt-get update -q >/dev/null; apt-get install -y -q --no-install-recommends systemd python3 >/dev/null
  useradd -m learner; B=/root/.idea-build BROWSER=chrome CHROME_DEB=$CHROME_DEB; . \$B/browser.sh >/dev/null
  echo \"browser.sh done (desktop=\$BROWSER_DESKTOP)\""
chroot "$R" /bin/bash -c "BROWSER=chrome; fail=0; . /root/.idea-build/verify-browser.sh; google-chrome-stable --version; exit \$fail"
