#!/usr/bin/env bash
# diagnosticgpt.sh — Ultra-comprehensive Arch Linux diagnostic snapshot (DE-aware)
# Usage:
#   chmod +x diagnosticgpt.sh
#   sudo ./diagnosticgpt.sh                # best (read-most)
#   ./diagnosticgpt.sh --fast              # skip heavy scans
#   ./diagnosticgpt.sh --since '7 days ago'
#   ./diagnosticgpt.sh -o /path/to/output
#   ./diagnosticgpt.sh --redact
#   ./diagnosticgpt.sh --summary           # write compact summary for pasting
#   ./diagnosticgpt.sh --split-mb 200      # split archive into 200MB parts
#
# Output:
#   /tmp/diagnosticgpt-<host>-<timestamp>/ ... + matching .zip (or split parts)
#
# Notes:
# - Collects sensitive data (IPs, MACs, usernames, installed packages, logs, configs).
# - Read-only; avoids changes. Some commands may not exist; all optional.
# - Desktop Environment coverage aligned with ArchWiki list; falls back gracefully.
# - Wayland/Xorg, GNOME/KDE/Xfce/Cinnamon/MATE/LXQt/LXDE/Budgie/Pantheon/Deepin/
#   Enlightenment/UKUI/Phosh/COSMIC/Cutefish/GNOME Flashback/Trinity/Lumina/
#   Moksha/CDE/Liri/Maui/theDesk/Plasma Mobile.

set -u -o pipefail

PROGRAM_NAME="diagnosticgpt"

SINCE="${SINCE:-14 days ago}"
OUTDIR=""
FAST=0
REDACT=0
WRITE_SUMMARY=0
SPLIT_MB=""
TIMEOUT_SECS="${TIMEOUT_SECS:-30}"
HOST="$(hostname -s 2>/dev/null || echo unknown)"
TS="$(date +%Y%m%d-%H%M%S)"
BASE="/tmp/${PROGRAM_NAME}-${HOST}-${TS}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) shift; SINCE="${1:-14 days ago}";;
    -o|--output) shift; OUTDIR="${1:-}";;
    --fast) FAST=1;;
    --redact) REDACT=1;;
    --summary) WRITE_SUMMARY=1;;
    --split-mb) shift; SPLIT_MB="${1:-}";;
    -h|--help)
      sed -n '1,200p' "$0"; exit 0;;
  esac
  shift || true
done

if [[ -n "${OUTDIR}" ]]; then BASE="${OUTDIR%/}"; fi
mkdir -p "$BASE"

have() { command -v "$1" >/dev/null 2>&1; }
SUDO=()
if [[ $EUID -ne 0 ]]; then
  if have sudo && sudo -n true 2>/dev/null; then SUDO=(sudo -n); fi
fi

twrap() { if have timeout; then timeout "${TIMEOUT_SECS}s" "$@"; else "$@"; fi; }

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER" 2>/dev/null || echo "$UID")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" || ! -d "${TARGET_HOME}" ]]; then TARGET_HOME="$HOME"; fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
section() { mkdir -p "$BASE/$1"; }
save() { local path="$BASE/$1"; shift; { echo "### $(date -Is) :: $*"; echo; "$@" 2>&1 || true; } > "$path"; }
save_if() { local of="$1" cmd="$2"; shift 2; if have "$cmd"; then save "$of" "$@"; fi; }
copy_if() {
  local src="$1" destrel="$2"
  if [[ -r "$src" ]]; then
    mkdir -p "$(dirname "$BASE/$destrel")"
    "${SUDO[@]}" cp -a --no-preserve=ownership "$src" "$BASE/$destrel" 2>/dev/null || true
  fi
}
copy_user() { local rel="$1"; copy_if "$TARGET_HOME/$rel" "11_desktop/user${rel}"; }
grepcp() { local pat="$1" src="$2" dest="$3"; if [[ -r "$src" ]]; then mkdir -p "$(dirname "$BASE/$dest")"; grep -E "$pat" "$src" > "$BASE/$dest" 2>/dev/null || true; fi; }

redact_file_inplace() {
  local h_esc u_esc
  h_esc="${HOST//\//\\/}"; h_esc="${h_esc//&/\\&}"
  u_esc="${TARGET_USER//\//\\/}"; u_esc="${u_esc//&/\\&}"
  sed -E -i \
    -e "s/([0-9]{1,3}\.){3}[0-9]{1,3}/<IP_REDACTED>/g" \
    -e "s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<MAC_REDACTED>/g" \
    -e "s/${h_esc}/<HOST_REDACTED>/g" \
    -e "s/${u_esc}/<USER_REDACTED>/g" \
    "$1" 2>/dev/null || true
}

for d in 00_system 01_boot 02_hardware 03_graphics 04_audio 05_network 06_packages 07_services 08_logs 09_security 10_perf 11_desktop 12_containers 13_flatpak_snap 14_misc; do
  section "$d"
done

log "System basics… (${PROGRAM_NAME})"
save "00_system/00-uname.txt" uname -a
save "00_system/01-os-release.txt" bash -lc 'cat /etc/os-release 2>/dev/null || true'
save "00_system/02-kernel-cmdline.txt" bash -lc 'cat /proc/cmdline 2>/dev/null || true'
save "00_system/03-locale-env.txt" bash -lc 'locale; echo; env | sort'
save "00_system/04-time.txt" twrap timedatectl
save "00_system/05-sysctl-selected.txt" bash -lc 'sysctl -a 2>/dev/null | egrep -i "kernel|fs\.|vm\.|net\." || true'
save "00_system/06-limits.txt" bash -lc 'ulimit -a 2>/dev/null || true'
save "00_system/07-cgroups.txt" bash -lc 'cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true'
save "00_system/08-filesystems.txt" bash -lc "df -hT; echo; ${SUDO[*]} mount; echo; cat /etc/fstab 2>/dev/null || true"
save "00_system/09-swap.txt" bash -lc 'swapon --show --bytes --output=NAME,TYPE,SIZE,USED,PRIO 2>/dev/null || true'
save_if "00_system/10-zramctl.txt" zramctl zramctl
# shellcheck disable=SC2016
save "00_system/11-pressures.txt" bash -lc 'for r in cpu io memory; do echo "== $r =="; cat /proc/pressure/$r 2>/dev/null || true; echo; done'
save "00_system/12-boot-loader.txt" bash -lc 'bootctl status 2>/dev/null || efibootmgr -v 2>/dev/null || true'
save "00_system/13-virt.txt" systemd-detect-virt
save "00_system/14-users-groups.txt" bash -lc 'getent passwd; echo; getent group'

log "Boot & journal…"
save_if "01_boot/00-systemd-analyze.txt" systemd-analyze systemd-analyze
save_if "01_boot/01-blame.txt" systemd-analyze systemd-analyze blame
save_if "01_boot/02-critical-chain.txt" systemd-analyze systemd-analyze critical-chain
if have systemd-analyze; then twrap systemd-analyze plot > "$BASE/01_boot/boot.svg" 2>/dev/null || true; fi
save "01_boot/03-last-boot-errors.txt" bash -lc "journalctl -b -p 3..4 --no-pager"
save "01_boot/04-ooms.txt" bash -lc "journalctl -k --since '$SINCE' --no-pager | egrep -i 'Out of memory|oom-killer' || true"

log "Hardware…"
save "02_hardware/00-cpu.txt" lscpu
save "02_hardware/01-mem.txt" bash -lc 'grep -E "Mem(Total|Free|Available)|Swap(Total|Free)" /proc/meminfo'
save "02_hardware/02-block.txt" bash -lc 'lsblk -e7 -o NAME,TYPE,RM,SIZE,RO,MODEL,SERIAL,TRAN,MOUNTPOINTS'
save "02_hardware/03-pci.txt" bash -lc 'lspci -nnk 2>/dev/null || true'
save_if "02_hardware/04-usb.txt" lsusb lsusb -vt
save_if "02_hardware/05-dmi.txt" dmidecode "${SUDO[@]}" dmidecode
save_if "02_hardware/06-sensors.txt" sensors sensors
if have smartctl; then
  while read -r dev type; do
    case "$type" in disk|rom|ssd) save "02_hardware/smart-${dev}.txt" "${SUDO[@]}" smartctl -a "/dev/$dev";; esac
  done < <(lsblk -ndo NAME,TYPE 2>/dev/null)
fi

SESSION_ID=
if have loginctl; then
  SESSION_ID=$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$TARGET_USER" '$3==u {print $1; exit}')
  [[ -z "${SESSION_ID}" && -n "${XDG_SESSION_ID:-}" ]] && SESSION_ID="$XDG_SESSION_ID"
fi

log "Graphics/Display…"
save "03_graphics/00-session.txt" bash -lc "echo 'XDG_SESSION_TYPE='\"${XDG_SESSION_TYPE-}\"; echo 'XDG_CURRENT_DESKTOP='\"${XDG_CURRENT_DESKTOP-}\"; echo 'DESKTOP_SESSION='\"${DESKTOP_SESSION-}\"; { loginctl show-session ${SESSION_ID:-} 2>/dev/null || true; }; echo; echo 'DISPLAY='\"${DISPLAY-}\" 'WAYLAND_DISPLAY='\"${WAYLAND_DISPLAY-}\""
save "03_graphics/01-kms-dmesg.txt" bash -lc 'dmesg -T | egrep -i "drm|i915|amdgpu|radeon|nouveau|nvidia" || true'
save_if "03_graphics/02-glxinfo.txt" glxinfo glxinfo -B
save_if "03_graphics/03-vulkan.txt" vulkaninfo vulkaninfo --summary
save_if "03_graphics/04-nvidia-smi.txt" nvidia-smi nvidia-smi -q
copy_if "/var/log/Xorg.0.log" "03_graphics/Xorg.0.log"
copy_if "$TARGET_HOME/.local/share/xorg/Xorg.0.log" "03_graphics/user-Xorg.0.log"
grepcp "^\(EE\)|^\(WW\)" "/var/log/Xorg.0.log" "03_graphics/Xorg.0.errors_warnings.txt"
save "03_graphics/05-dm-logs.txt" bash -lc "journalctl -u gdm -u sddm -u lightdm --since '$SINCE' --no-pager || true"

log "Audio (PipeWire/Pulse)…"
save_if "04_audio/00-pipewire-ver.txt" pipewire pipewire --version
save "04_audio/01-audio-summary.txt" bash -lc 'systemctl --user status pipewire pipewire-pulse wireplumber 2>&1 || true'
save_if "04_audio/02-pw-dump.json" pw-dump pw-dump
save_if "04_audio/03-pactl-info.txt" pactl pactl info
save_if "04_audio/04-pactl-list.txt" pactl pactl list short
save_if "04_audio/05-aplay.txt" aplay aplay -l
save_if "04_audio/06-arecord.txt" arecord arecord -l

log "Network…"
save "05_network/00-ip.txt" bash -lc 'ip addr; echo; ip link; echo; ip route'
copy_if "/etc/resolv.conf" "05_network/resolv.conf"
save_if "05_network/01-nmcli.txt" nmcli nmcli -o general status
save_if "05_network/02-nmcli-dev.txt" nmcli nmcli -o device show
save_if "05_network/03-systemd-resolved.txt" resolvectl resolvectl status
save "05_network/04-sockets.txt" bash -lc 'ss -tulpen'
save_if "05_network/05-nft.txt" nft "${SUDO[@]}" nft list ruleset
save_if "05_network/06-iptables-save.txt" iptables "${SUDO[@]}" iptables-save
save_if "05_network/07-ufw-status.txt" ufw "${SUDO[@]}" ufw status verbose
copy_if "/etc/hosts" "05_network/hosts"
copy_if "/etc/nsswitch.conf" "05_network/nsswitch.conf"
save "05_network/08-ssh.txt" bash -lc "journalctl -u sshd --since '$SINCE' --no-pager 2>/dev/null || true"
copy_if "/etc/ssh/sshd_config" "05_network/sshd_config"

log "Packages…"
save "06_packages/00-pacman-ver.txt" pacman -V
save "06_packages/01-pacman-conf.txt" bash -lc 'cat /etc/pacman.conf 2>/dev/null || true'
copy_if "/etc/pacman.d/mirrorlist" "06_packages/mirrorlist"
save "06_packages/02-installed.txt" pacman -Q
save "06_packages/03-explicit.txt" pacman -Qet
save "06_packages/04-native.txt" pacman -Qen
save "06_packages/05-foreign-AUR.txt" pacman -Qm
save "06_packages/06-orphans.txt" bash -lc 'pacman -Qdt 2>/dev/null || true'
save "06_packages/07-owned-binaries.txt" bash -lc 'pacman -Qo /usr/bin/* 2>/dev/null | sort -u || true'
save "06_packages/08-db-check.txt" bash -lc "${SUDO[*]} pacman -Dk 2>&1 || true"
if [[ $FAST -eq 0 ]]; then save "06_packages/09-integrity-Qkk.txt" bash -lc "${SUDO[*]} pacman -Qkk --noprogressbar 2>&1 || true"; fi
save_if "06_packages/10-checkupdates.txt" checkupdates checkupdates
save_if "06_packages/11-yay-updates.txt" yay yay -Qua

log "Services & timers…"
save "07_services/00-running.txt" systemctl list-units --type=service --state=running
save "07_services/01-failed.txt" systemctl --failed
save "07_services/02-timers.txt" systemctl list-timers
save "07_services/03-unit-files.txt" systemctl list-unit-files
save "07_services/04-sockets.txt" systemctl list-sockets
save "07_services/05-user-services.txt" bash -lc 'XDG_RUNTIME_DIR="/run/user/'"$TARGET_UID"'" systemctl --user --machine='"$TARGET_USER"@' list-units --type=service 2>/dev/null || systemctl --user list-units --type=service 2>/dev/null || true'

log "Logs & crashes…"
save "08_logs/00-dmesg.txt" dmesg -T
save "08_logs/01-kernel-errors.txt" bash -lc "journalctl -k -p 3 --since '$SINCE' --no-pager"
save "08_logs/02-journal-summary.txt" bash -lc "journalctl -p 3..4 --since '$SINCE' --no-pager | head -n 1000"
copy_if "/var/log/pacman.log" "08_logs/pacman.log"
save_if "08_logs/03-coredumps-list.txt" coredumpctl coredumpctl list --since "$SINCE"
if have coredumpctl; then
  mapfile -t CORES < <(coredumpctl --no-pager list --since "$SINCE" | awk 'NR>1{print $1}' | tail -n 5)
  idx=0; for c in "${CORES[@]}"; do save "08_logs/core-$((idx++)).txt" bash -lc "coredumpctl info $c"; done
fi

log "Security / hardening / IOC…"
# shellcheck disable=SC2016
save "09_security/00-vulns-sysfs.txt" bash -lc 'for f in /sys/devices/system/cpu/vulnerabilities/*; do echo "## $f"; cat "$f" 2>/dev/null; echo; done'
save "09_security/01-sysctl-hardening.txt" bash -lc 'sysctl -a 2>/dev/null | egrep "kernel\.kptr_restrict|kernel\.yama\.ptrace_scope|kernel\.unprivileged_(bpf_disabled|userns_clone)|fs\.protected_(hardlinks|symlinks|regular)" || true'
save "09_security/02-auth-logins.txt" bash -lc 'last -a 2>/dev/null | head -n 200; echo; test -r /var/log/btmp && lastb -a 2>/dev/null | head -n 200 || true'
save "09_security/03-sudoers.txt" bash -lc "ls -l /etc/sudoers /etc/sudoers.d 2>/dev/null; echo; ${SUDO[*]} cat /etc/sudoers 2>/dev/null || true; echo; ${SUDO[*]} ls -l /etc/sudoers.d 2>/dev/null || true"
save "09_security/04-suid-sgid.txt" bash -lc 'find /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -xdev \( -perm -4000 -o -perm -2000 \) -type f -printf "%M %u:%g %p\n" 2>/dev/null | sort'
save_if "09_security/05-capabilities.txt" getcap getcap -r /bin /sbin /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin 2>/dev/null
save "09_security/06-cron.txt" bash -lc "ls -la /etc/cron* 2>/dev/null; echo; ${SUDO[*]} ls -la /var/spool/cron 2>/dev/null || true"
save_if "09_security/07-rkhunter.txt" rkhunter "${SUDO[@]}" rkhunter --versioncheck --sk --report-warnings-only
save_if "09_security/08-chkrootkit.txt" chkrootkit "${SUDO[@]}" chkrootkit -q
# shellcheck disable=SC2016
save "09_security/09-open-listeners.txt" bash -lc 'ss -tulpen | awk "{print $1, $2, $5, $6, $7}"'
save "09_security/10-new-users-last30.txt" bash -lc "getent passwd | awk -F: '\$3>=1000{print \$1":"\$3":"\$6":"\$7}' | sort"

log "Performance snapshots…"
save "10_perf/00-free.txt" free -h
save "10_perf/01-top.txt" bash -lc 'COLUMNS=512 top -b -n1 | head -n 80'
save "10_perf/02-ps-cpu.txt" bash -lc 'ps -eo pid,ppid,comm,%cpu,%mem,ni,pri,stat,start,time --sort=-%cpu | head -n 200'
save "10_perf/03-ps-mem.txt" bash -lc 'ps -eo pid,ppid,comm,%mem,%cpu,rss --sort=-%mem | head -n 200'
save_if "10_perf/04-iostat.txt" iostat iostat -xz 1 3
save_if "10_perf/05-vmstat.txt" vmstat vmstat 1 5
save_if "10_perf/06-iotop.txt" iotop iotop -ao -b -n 3

save "11_desktop/00-user-journal.txt" bash -lc "journalctl _UID=$TARGET_UID --since '$SINCE' --no-pager 2>/dev/null || true"

split_words() {
  local s="$*"
  echo "${s//[;:]/ }"
}

detect_desktops() {
  local hits=()
  local envs
  envs="$(split_words "${XDG_CURRENT_DESKTOP:-}") $(split_words "${DESKTOP_SESSION:-}")"
  envs="$(tr '[:upper:]' '[:lower:]' <<<"$envs")"
  for w in $envs; do
    case "$w" in
      gnome|unity|gnome-flashback) hits+=("gnome");;
      kde|plasma|plasmawayland|plasma-x11) hits+=("plasma");;
      xfce|xfce4) hits+=("xfce");;
      cinnamon) hits+=("cinnamon");;
      mate) hits+=("mate");;
      lxqt) hits+=("lxqt");;
      lxde) hits+=("lxde");;
      budgie) hits+=("budgie");;
      pantheon) hits+=("pantheon");;
      deepin|dde) hits+=("deepin");;
      enlightenment|e) hits+=("enlightenment");;
      ukui) hits+=("ukui");;
      phosh) hits+=("phosh");;
      cosmic) hits+=("cosmic");;
      cutefish) hits+=("cutefish");;
      trinity|tde) hits+=("trinity");;
      lumina) hits+=("lumina");;
      moksha) hits+=("moksha");;
      cde|dt) hits+=("cde");;
      liri) hits+=("liri");;
      maui|maui-shell) hits+=("maui");;
      thedesk|thedeskde) hits+=("thedesk");;
      *) :;;
    esac
  done
  pgrep -fa gnome-shell >/dev/null && hits+=("gnome")
  pgrep -fa plasmashell >/dev/null && hits+=("plasma")
  pgrep -fa xfce4-session >/dev/null && hits+=("xfce")
  pgrep -fa cinnamon >/dev/null && hits+=("cinnamon")
  pgrep -fa mate-session >/dev/null && hits+=("mate")
  pgrep -fa lxqt-session >/dev/null && hits+=("lxqt")
  pgrep -fa lxsession >/dev/null && hits+=("lxde")
  pgrep -fa budgie-desktop >/dev/null && hits+=("budgie")
  pgrep -fa gala >/dev/null && hits+=("pantheon")
  pgrep -fa dde-desktop >/dev/null && hits+=("deepin")
  pgrep -fa enlightenment >/dev/null && hits+=("enlightenment")
  pgrep -fa ukui-session >/dev/null && hits+=("ukui")
  pgrep -fa phosh >/dev/null && hits+=("phosh")
  pgrep -fa cosmic >/dev/null && hits+=("cosmic")
  pgrep -fa cutefish-session >/dev/null && hits+=("cutefish")
  pgrep -fa gnome-flashback >/dev/null && hits+=("gnome")
  pgrep -fa tdeinit >/dev/null && hits+=("trinity")
  pgrep -fa lumina-desktop >/dev/null && hits+=("lumina")
  pgrep -fa moksha >/dev/null && hits+=("moksha")
  pgrep -fa dtwm >/dev/null && hits+=("cde")
  pgrep -fa liri-shell >/dev/null && hits+=("liri")
  pgrep -fa maui-shell >/dev/null && hits+=("maui")
  pgrep -fa thedesk >/dev/null && hits+=("thedesk")
  printf "%s\n" "${hits[@]}" | awk '!seen[$0]++'
}

DE_DIR="11_desktop"
de_save() { local de="$1" f="$2"; shift 2; save "${DE_DIR}/${de}/${f}" "$@"; }
de_copy_user() { local de="$1" rel="$2"; copy_if "$TARGET_HOME/$rel" "${DE_DIR}/${de}/user${rel}"; }

collect_gnome() {
  local de=gnome; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'gnome-shell --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/extensions.txt" gnome-extensions gnome-extensions list
  save_if "${DE_DIR}/${de}/gsettings.txt" gsettings gsettings list-recursively
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_save $de "journal.txt" bash -lc "journalctl --user-unit gnome-shell --since '$SINCE' --no-pager 2>/dev/null || true"
  de_copy_user $de "/.config/dconf/user"
  de_copy_user $de "/.local/share/gnome-shell/extensions"
}

collect_plasma() {
  local de=plasma; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'plasmashell --version 2>/dev/null || true; kwin_wayland --version 2>/dev/null || kwin_x11 --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/kwin-support.txt" qdbus qdbus org.kde.KWin /KWin supportInformation
  de_save $de "journal.txt" bash -lc "journalctl --user -g kwin --since '$SINCE' --no-pager 2>/dev/null || true"
  for f in /.config/kdeglobals /.config/kwinrc /.config/plasmarc /.config/plasma* /.config/kglobalshortcutsrc; do de_copy_user $de "$f"; done
}

collect_xfce() {
  local de=xfce; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'xfce4-session --version 2>/dev/null || true; xfwm4 --version 2>/dev/null || true'
  if have xfconf-query; then
    de_save $de "xfconf-channels.txt" xfconf-query -l
    while read -r ch; do de_save $de "xfconf-${ch}.txt" xfconf-query -c "$ch" -lv; done < <(xfconf-query -l 2>/dev/null || true)
  fi
  de_copy_user $de "/.config/xfce4"
}

collect_cinnamon() {
  local de=cinnamon; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'cinnamon --version 2>/dev/null || true; muffin --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/gsettings.txt" gsettings gsettings list-recursively
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.cinnamon"
  de_copy_user $de "/.config/cinnamon"
}

collect_mate() {
  local de=mate; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'mate-session --version 2>/dev/null || true; marco --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/gsettings.txt" gsettings gsettings list-recursively
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.config/mate"
  de_copy_user $de "/.config/marco"
}

collect_lxqt() {
  local de=lxqt; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'lxqt-session -v 2>/dev/null || lxqt-config -v 2>/dev/null || true'
  de_copy_user $de "/.config/lxqt"
  de_copy_user $de "/.config/openbox"
}

collect_lxde() {
  local de=lxde; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'lxsession -v 2>/dev/null || openbox --version 2>/dev/null || true'
  de_copy_user $de "/.config/lxsession"
  de_copy_user $de "/.config/openbox"
}

collect_budgie() {
  local de=budgie; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'budgie-desktop --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/gsettings.txt" gsettings gsettings list-recursively
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.config/budgie-desktop"
}

collect_pantheon() {
  local de=pantheon; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'gala --version 2>/dev/null || true; wingpanel --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.config/dconf/user"
}

collect_deepin() {
  local de=deepin; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'dde-desktop --version 2>/dev/null || dde-control-center --version 2>/dev/null || dde-kwin --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.config/deepin"
}

collect_enlightenment() {
  local de=enlightenment; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'enlightenment -version 2>/dev/null || enlightenment_info -version 2>/dev/null || true'
  de_copy_user $de "/.e"
}

collect_ukui() {
  local de=ukui; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'ukui-session --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
  de_copy_user $de "/.config/ukui"
}

collect_phosh() {
  local de=phosh; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'phosh --version 2>/dev/null || true; phoc --version 2>/dev/null || true; squeekboard --version 2>/dev/null || true'
  save_if "${DE_DIR}/${de}/gsettings.txt" gsettings gsettings list-recursively
  save_if "${DE_DIR}/${de}/dconf-dump.conf" dconf dconf dump /
}

collect_cosmic() {
  local de=cosmic; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'cosmic-comp --version 2>/dev/null || cosmic-session --version 2>/dev/null || true'
  de_copy_user $de "/.config/cosmic"
}

collect_cutefish() {
  local de=cutefish; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'cutefish-session --version 2>/dev/null || true'
  de_copy_user $de "/.config/cutefish"
}

collect_trinity() {
  local de=trinity; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'tde-config --version 2>/dev/null || tdeinit --version 2>/dev/null || true'
  de_copy_user $de "/.trinity"
}

collect_lumina() {
  local de=lumina; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'lumina-desktop -v 2>/dev/null || true'
  de_copy_user $de "/.config/lumina-desktop"
  de_copy_user $de "/.lumina"
}

collect_moksha() {
  local de=moksha; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'moksha -v 2>/dev/null || true'
  de_copy_user $de "/.e"
}

collect_cde() {
  local de=cde; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'dtwm -v 2>/dev/null || true'
  de_copy_user $de "/.dt"
}

collect_liri() {
  local de=liri; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'liri-shell --version 2>/dev/null || true'
  de_copy_user $de "/.config/liri"
}

collect_maui() {
  local de=maui; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'maui-shell --version 2>/dev/null || true'
  de_copy_user $de "/.config/maui-shell"
}

collect_thedesk() {
  local de=thedesk; section "${DE_DIR}/${de}"
  de_save $de "version.txt" bash -lc 'thedesk --version 2>/dev/null || true'
  de_copy_user $de "/.config/thedesk"
}

log "Desktop Environment detection…"
mapfile -t DE_LIST < <(detect_desktops)
{ echo "Detected DE hints: ${DE_LIST[*]:-(none)}"; } > "$BASE/11_desktop/DE-detection.txt"

for de in "${DE_LIST[@]}"; do
  case "$de" in
    gnome) collect_gnome ;;
    plasma) collect_plasma ;;
    xfce) collect_xfce ;;
    cinnamon) collect_cinnamon ;;
    mate) collect_mate ;;
    lxqt) collect_lxqt ;;
    lxde) collect_lxde ;;
    budgie) collect_budgie ;;
    pantheon) collect_pantheon ;;
    deepin) collect_deepin ;;
    enlightenment) collect_enlightenment ;;
    ukui) collect_ukui ;;
    phosh) collect_phosh ;;
    cosmic) collect_cosmic ;;
    cutefish) collect_cutefish ;;
    trinity) collect_trinity ;;
    lumina) collect_lumina ;;
    moksha) collect_moksha ;;
    cde) collect_cde ;;
    liri) collect_liri ;;
    maui) collect_maui ;;
    thedesk) collect_thedesk ;;
    *) : ;;
  esac
done

if [[ ${#DE_LIST[@]} -eq 0 ]]; then
  save_if "11_desktop/fallback-gsettings.txt" gsettings gsettings list-recursively
  save_if "11_desktop/fallback-dconf.conf" dconf dconf dump /
  if have xfconf-query; then
    save "11_desktop/fallback-xfconf-channels.txt" xfconf-query -l
    while read -r ch; do save "11_desktop/fallback-xfconf-${ch}.txt" xfconf-query -c "$ch" -lv; done < <(xfconf-query -l 2>/dev/null || true)
  fi
fi

log "Containers / virtualization layers…"
save_if "12_containers/00-docker.txt" docker docker ps -a
save_if "12_containers/01-docker-info.txt" docker docker info
save_if "12_containers/02-podman.txt" podman podman ps -a
save_if "12_containers/03-k8s.txt" kubectl kubectl get pods -A
save_if "12_containers/04-virt-host.txt" virsh virsh list --all

log "Flatpak / Snap / AppImages…"
save_if "13_flatpak_snap/00-flatpak-list.txt" flatpak flatpak list --app --columns=application,version,branch,origin
save_if "13_flatpak_snap/01-snap-list.txt" snap snap list
save "13_flatpak_snap/02-appimages.txt" bash -lc "fd -HI '\\.AppImage$' \"$TARGET_HOME\" 2>/dev/null || find \"$TARGET_HOME\" -type f -name '*.AppImage' 2>/dev/null || true"

log "Misc…"
save "14_misc/00-large-logs.txt" bash -lc 'du -ah /var/log 2>/dev/null | sort -hr | head -n 100'
save "14_misc/01-paccache.txt" bash -lc 'paccache -v 2>/dev/null || true'
save "14_misc/02-kernel-tainted.txt" bash -lc 'echo -n "tainted="; cat /proc/sys/kernel/tainted 2>/dev/null || true'
save "14_misc/03-kmods.txt" lsmod
save "14_misc/04-loaded-bpf.txt" bash -lc 'bpftool prog show 2>/dev/null || true'

if [[ $FAST -eq 0 ]]; then
  log "Heavy filesystem checks…"
  save "09_security/11-world-writable-dirs.txt" bash -lc 'find / -xdev -type d -perm -0002 2>/dev/null | sort | head -n 5000'
fi

for f in \
  /etc/systemd/journald.conf /etc/systemd/logind.conf /etc/systemd/coredump.conf \
  /etc/security/limits.conf /etc/mkinitcpio.conf /etc/mkinitcpio.d/* \
  /etc/makepkg.conf /etc/default/grub /etc/modprobe.d/*.conf /etc/sysctl.conf /etc/sysctl.d/*.conf \
  /etc/pipewire/*.conf /etc/pipewire/pipewire.conf.d/*.conf /etc/wireplumber/*.conf.lua \
  /etc/X11/xorg.conf /etc/X11/xorg.conf.d/*.conf /etc/environment \
  /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/conf.d/*.conf \
  /etc/pacman.d/hooks/*.hook /etc/containers/registries.conf \
  ; do copy_if "$f" "configs/${f#/etc/}"; done

if [[ $REDACT -eq 1 ]]; then
  log "Applying light redaction…"
  while IFS= read -r -d '' file; do
    redact_file_inplace "$file"
  done < <(find "$BASE" -type f -name '*.txt' -print0)
fi

log "Creating archive…"
ARCHIVE="${BASE}.zip"
( cd "$(dirname "$BASE")" && zip -r -q "$(basename "$BASE").zip" "$(basename "$BASE")" )


if [[ -n "${SPLIT_MB}" ]]; then
  if have split; then
    split -b "${SPLIT_MB}M" -d -a 3 "$ARCHIVE" "${ARCHIVE}.part-" && rm -f "$ARCHIVE"
    ARCHIVE_LIST=$(ls -1 "${ARCHIVE}.part-"* 2>/dev/null || true)
  fi
fi

if [[ ${WRITE_SUMMARY} -eq 1 ]]; then
  SUM_FILE="$BASE/DIAGNOSTICGPT_SUMMARY.md"
  {
    echo "# diagnosticgpt summary"
    echo "host: $HOST"
    echo "timestamp: $TS"
    echo "kernel: $(uname -r 2>/dev/null || true)"
    echo "de: $(sed 's/^Detected DE hints: //;t;d' "$BASE/11_desktop/DE-detection.txt" 2>/dev/null || echo unknown)"
    echo "packages: $(wc -l < "$BASE/06_packages/02-installed.txt" 2>/dev/null || echo 0)"
    echo "failed_services: $(systemctl --failed --no-legend 2>/dev/null | wc -l || echo 0)"
    echo "coredumps_since: $SINCE => $(coredumpctl --no-pager list --since "$SINCE" 2>/dev/null | awk 'NR>1' | wc -l || echo 0)"
    echo "oom_events: $(journalctl -k --since "$SINCE" 2>/dev/null | grep -ci 'Out of memory\|oom-killer' || true)"
    echo
    echo "Top warnings/errors (journal, since $SINCE):"
    journalctl -p 3..4 --since "$SINCE" --no-pager 2>/dev/null | head -n 50 || true
  } > "$SUM_FILE"
fi

INSTR="$BASE/UPLOAD_INSTRUCTIONS.txt"
{
  echo "Files ready for ChatGPT upload:"
  if [[ -n "${SPLIT_MB}" && -n "${ARCHIVE_LIST:-}" ]]; then
    echo "$ARCHIVE split into:"
    for f in $ARCHIVE_LIST; do echo "  $f"; done
  else
    echo "  $ARCHIVE"
  fi
  if [[ ${WRITE_SUMMARY} -eq 1 ]]; then
    echo "  $SUM_FILE"
  fi
} > "$INSTR"

echo "Snapshot directory: $BASE"
echo "Archive: ${ARCHIVE:-split parts}"

