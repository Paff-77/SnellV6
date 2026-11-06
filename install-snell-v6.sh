#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
umask 077

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help ]]; then
    printf 'Usage: sudo bash %s [port for first install]\n' "$0"
    exit 0
fi
(( $# <= 1 )) || die "Pass at most one argument, the first-install TCP port."
port=${1:-31777}
[[ $port =~ ^[1-9][0-9]{0,4}$ ]] && (( port >= 1024 && port <= 65535 )) ||
    die "Use a TCP port from 1024 to 65535."
(( EUID == 0 )) || die "Run this script with sudo or as root."
[[ -d /run/systemd/system ]] || die "This installer requires a systemd host."

case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    i386|i486|i586|i686) arch=i386 ;;
    aarch64|arm64) arch=aarch64 ;;
    *) die "No supported Snell v6 package for $(uname -m)." ;;
esac

exec 9>/run/lock/install-snell-v6.lock
flock -n 9 || die "Another Snell installer is running."

if ! command -v curl >/dev/null || ! command -v unzip >/dev/null ||
   ! command -v openssl >/dev/null || [[ ! -s /etc/ssl/certs/ca-certificates.crt ]]; then
    apt-get update
    apt-get install -y ca-certificates curl openssl unzip
fi

binary=/usr/local/bin/snell-server
config=/etc/snell/snell-server.conf
unit=/etc/systemd/system/snell.service
releases=https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md
download=(curl --disable --fail --silent --show-error --location --proto '=https'
          --proto-redir '=https' --connect-timeout 10 --max-time 90 --retry 2)

install -d -m 0755 /usr/local/bin
work=$(mktemp -d /usr/local/bin/.snell-install.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT

"${download[@]}" -H 'Cache-Control: no-cache' -o "$work/releases" "$releases" ||
    die "Could not fetch the official release list."
# The official Markdown page lists the package URLs one per line.
url_pattern="https://dl\.nssurge\.com/snell/snell-server-v6\.[0-9]+\.[0-9]+-linux-${arch}\.zip"
if ! url=$(tr -d '\r' < "$work/releases" | grep -Ex "$url_pattern" | sort -V | tail -n 1); then
    die "No official Snell v6 stable package found for $arch."
fi
version=${url##*/snell-server-}
version=${version%-linux-*}
printf 'Latest official Snell version for %s: %s\n' "$arch" "$version"

"${download[@]}" -o "$work/snell.zip" "$url" || die "Could not download $url."
unzip -p "$work/snell.zip" snell-server > "$work/snell-server" ||
    die "The official archive could not be extracted."
chmod 0755 "$work/snell-server"
reported=$("$work/snell-server" -v 2>&1) || die "The downloaded binary failed its version check."
# Some official builds log the version with a timestamp and build date.
version_pattern='(^|[[:blank:]])snell-server[[:blank:]]+(v6\.[0-9]+\.[0-9]+)([[:blank:]]+\([^)]*\))?[[:blank:]]*$'
detected_version=
while IFS= read -r line; do
    if [[ $line =~ $version_pattern ]]; then
        detected_version=${BASH_REMATCH[2]}
        break
    fi
done <<< "$reported"
[[ $detected_version == "$version" ]] ||
    die "Unexpected version from the downloaded binary: $reported"

if ! getent group snell >/dev/null; then
    groupadd --system snell
fi
if ! id -u snell >/dev/null 2>&1; then
    useradd --system --gid snell --home-dir /var/lib/snell --shell /usr/sbin/nologin snell
fi
install -d -m 0750 -o snell -g snell /var/lib/snell

if [[ ! -e $config ]]; then
    install -d -m 0750 -o root -g snell /etc/snell
    psk=$(openssl rand -hex 16)
    config_tmp=$(mktemp /etc/snell/.snell-server.conf.XXXXXXXX)
    printf '[snell-server]\nlisten = 0.0.0.0:%s,[::]:%s\npsk = %s\nmode = default\n' \
        "$port" "$port" "$psk" > "$config_tmp"
    chown root:snell "$config_tmp"
    chmod 0640 "$config_tmp"
    mv -T -- "$config_tmp" "$config"
    unset psk
else
    printf 'Using existing configuration at %s.\n' "$config"
fi
runuser -u snell -- test -r "$config" ||
    die "The snell user cannot read $config. Check its ownership and permissions."

if [[ ! -e $unit ]]; then
    cat > "$work/snell.service" <<'UNIT'
[Unit]
Description=Snell Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=snell
Group=snell
WorkingDirectory=/var/lib/snell
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/lib/snell

[Install]
WantedBy=multi-user.target
UNIT
    install -m 0644 "$work/snell.service" "$unit"
fi
systemctl daemon-reload

running_pid() {
    local pid
    pid=$(systemctl show --property=MainPID --value snell.service) || return 1
    [[ $pid =~ ^[1-9][0-9]*$ && /proc/$pid/exe -ef $binary ]] || return 1
    systemctl is-active --quiet snell.service || return 1
    printf '%s\n' "$pid"
}

wait_for_startup() {
    local attempt pid
    for attempt in {1..5}; do
        if pid=$(running_pid); then
            sleep 3
            [[ $(running_pid) == "$pid" ]]
            return
        fi
        sleep 1
    done
    return 1
}

was_active=false
if systemctl is-active --quiet snell.service; then
    was_active=true
fi
changed=false
if ! cmp -s "$work/snell-server" "$binary"; then
    if [[ -e $binary ]]; then
        cp -p -- "$binary" "$work/previous"
    fi
    mv -T -- "$work/snell-server" "$binary"
    changed=true
fi

if ! running_pid >/dev/null; then
    if systemctl restart snell.service && wait_for_startup; then
        printf 'Snell %s is running.\n' "$version"
    else
        journalctl -u snell.service -n 20 --no-pager >&2 || true
        if "$changed"; then
            if [[ -e $work/previous ]]; then
                mv -T -- "$work/previous" "$binary"
                printf 'Restored the previous binary.\n' >&2
            else
                rm -f -- "$binary"
            fi
        fi
        if "$was_active"; then
            systemctl restart snell.service || die "Could not restart the previous service."
        else
            systemctl stop snell.service || true
        fi
        die "Snell $version failed its startup check."
    fi
else
    printf 'Snell %s is already running.\n' "$version"
fi

systemctl enable snell.service
printf '\nSnell server configuration (%s)\n' "$config"
cat -- "$config"
