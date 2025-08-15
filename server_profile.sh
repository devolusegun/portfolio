#!/usr/bin/env bash
# server_profile.sh — print a complete, read-only profile of this Linux server

# ---- Helpers ---------------------------------------------------------------
divider(){ printf "\n%s\n" "===================================================================="; }
section(){ divider; printf "## %s\n" "$1"; }
have(){ command -v "$1" >/dev/null 2>&1; }
try(){ # run a command; if sudo is available, prefer passwordless sudo
  if have sudo && sudo -n true 2>/dev/null; then
    sudo bash -lc "$*"
  else
    bash -lc "$*"
  fi
}
kv(){ printf "%-22s %s\n" "$1" "$2"; }

# ---- Header ----------------------------------------------------------------
section "SERVER PROFILE"
kv "Generated at" "$(date -Is)"
kv "Hostname" "$(hostname 2>/dev/null)"
kv "FQDN" "$(hostname -f 2>/dev/null || echo 'n/a')"
kv "Uptime" "$(uptime -p 2>/dev/null || echo 'n/a')"
kv "Load (1/5/15)" "$(cut -d' ' -f1-3 </proc/loadavg 2>/dev/null)"

# ---- OS / Kernel -----------------------------------------------------------
section "OS / KERNEL"
if have hostnamectl; then hostnamectl; fi
[ -r /etc/os-release ] && cat /etc/os-release
uname -a

# Detect virtualization/container
if have systemd-detect-virt; then
  kv "Virtualization" "$(systemd-detect-virt 2>/dev/null || echo unknown)"
fi
[ -f /proc/1/cgroup ] && { kv "Container cgroup" "$(sed -n '1p' /proc/1/cgroup)"; }

# ---- CPU / Memory ----------------------------------------------------------
section "CPU"
if have lscpu; then lscpu; else grep -m1 "model name" /proc/cpuinfo || true; fi

section "MEMORY"
if have free; then free -h; fi
[ -r /proc/meminfo ] && awk 'NR<=5{print}' /proc/meminfo

# ---- Storage ---------------------------------------------------------------
section "STORAGE: Block Devices"
if have lsblk; then
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL,UUID
fi

section "STORAGE: Filesystems"
df -hT 2>/dev/null || true

section "STORAGE: RAID/LVM (if any)"
try "mdadm --detail --scan 2>/dev/null || true"
try "pvs 2>/dev/null || true"
try "vgs 2>/dev/null || true"
try "lvs 2>/dev/null || true"

# ---- Network ---------------------------------------------------------------
section "NETWORK: Addresses"
if have ip; then ip -br a; else ifconfig -a 2>/dev/null || true; fi

section "NETWORK: Routing"
ip route 2>/dev/null || route -n 2>/dev/null || true

section "NETWORK: DNS"
if have resolvectl; then resolvectl status 2>/dev/null || true; fi
[ -r /etc/resolv.conf ] && { echo "--- /etc/resolv.conf"; cat /etc/resolv.conf; }

section "NETWORK: Listening Ports"
# Prefer ss; try privileged view first, then fallback
if have ss; then
  try "ss -tulpen 2>/dev/null || ss -tuln"
elif have netstat; then
  try "netstat -tulpen 2>/dev/null || netstat -tuln"
fi

# ---- Users / Sessions ------------------------------------------------------
section "USERS & SESSIONS"
who 2>/dev/null || true
echo
echo "--- Recent logins (last 10)"
last -n 10 2>/dev/null || true

# ---- Services / Init -------------------------------------------------------
section "SERVICES"
if have systemctl; then
  systemctl list-units --type=service --state=running --no-pager --all
else
  service --status-all 2>/dev/null || chkconfig --list 2>/dev/null || true
fi

section "SYSTEMD TIMERS (if systemd)"
if have systemctl; then systemctl list-timers --all --no-pager; fi

# ---- Packages & Updates ----------------------------------------------------
section "PACKAGES / UPDATES"
# Show package manager and pending updates count, best-effort
if have apt; then
  kv "Package Manager" "apt (Debian/Ubuntu)"
  try "apt -qq update >/dev/null 2>&1 || true"
  echo "Upgradable packages:"; try "apt -qq list --upgradable 2>/dev/null | sed 's#/now.*##' || true"
elif have dnf; then
  kv "Package Manager" "dnf (RHEL/CentOS/Fedora)"
  echo "Available updates (names):"; try "dnf -q check-update 2>/dev/null | awk 'NF==3{print \$1}' || true"
elif have yum; then
  kv "Package Manager" "yum (RHEL/CentOS)"
  echo "Available updates (names):"; try "yum -q check-update 2>/dev/null | awk 'NF==3{print \$1}' || true"
elif have zypper; then
  kv "Package Manager" "zypper (SUSE)"
  echo "Available updates:"; try "zypper lu 2>/dev/null || true"
else
  kv "Package Manager" "unknown"
fi

# ---- Firewall --------------------------------------------------------------
section "FIREWALL"
if have ufw; then kv "UFW status" "$(try "ufw status 2>/dev/null" | tr '\n' ' ' )"
fi
if have firewall-cmd; then
  echo "--- firewalld:"; try "firewall-cmd --state 2>/dev/null; firewall-cmd --list-all 2>/dev/null || true"
fi
try "iptables -S 2>/dev/null || true"
try "nft list ruleset 2>/dev/null || true"

# ---- Processes -------------------------------------------------------------
section "TOP PROCESSES"
echo "--- By CPU"
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%cpu | head -n 15
echo
echo "--- By MEM"
ps -eo pid,ppid,cmd,%cpu,%mem --sort=-%mem | head -n 15

# ---- Scheduled Tasks -------------------------------------------------------
section "CRON / SCHEDULED TASKS"
echo "--- System crontab (/etc/crontab):"
[ -r /etc/crontab ] && cat /etc/crontab || echo "n/a"
echo
echo "--- Cron directories:"
for d in /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
  [ -d "$d" ] && { echo "$d:"; ls -1 "$d" || true; }
done
echo
echo "--- User crontab (current user):"
crontab -l 2>/dev/null || echo "none or no permission"

# ---- Containers / Runtime --------------------------------------------------
section "CONTAINERS (if present)"
if have docker; then
  kv "Docker" "installed"
  try "docker info 2>/dev/null | sed -n '1,40p' || true"
  try "docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true"
fi
if have podman; then
  kv "Podman" "installed"
  try "podman ps --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true"
fi

# ---- Misc ------------------------------------------------------------------
section "TIME SYNC"
if have timedatectl; then timedatectl status; fi

section "KERNEL PARAMETERS (short)"
sysctl -a 2>/dev/null | egrep '^(net\.|vm\.|fs\.|kernel\.)' | head -n 100 || true

section "DONE"
kv "Completed at" "$(date -Is)"
divider
