#!/usr/bin/env bash
# Removes every service, user, group, sudoers entry and file/folder whose name matches ailab or demo.
# Dry run by default; pass --yes to actually delete.
set -euo pipefail

PATTERN="ailab|demo"
# VM admin accounts that match PATTERN but must never be removed.
KEEP="ailabadmin"
# Only these roots are searched so OS/package files (e.g. /usr/share/**/demo) are never touched.
SEARCH_ROOTS=(/srv /opt /home /root /etc /var /tmp)
PRUNE_PATHS=(/var/lib/dpkg /var/lib/apt /var/cache /var/lib/snapd /var/lib/waagent /etc/alternatives)

APPLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo." >&2
    exit 1
fi

run() {
    if $APPLY; then
        echo "+ $*"
        "$@" || echo "  (failed, continuing)" >&2
    else
        echo "[dry-run] $*"
    fi
}

me="${SUDO_USER:-$(whoami)}"
KEEP="^(${KEEP}|${me})$"

echo "=== Services ==="
mapfile -t units < <(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -iE "$PATTERN" || true)
for u in "${units[@]}"; do
    run systemctl disable --now "$u"
    run rm -f "/etc/systemd/system/$u"
done

echo "=== Users ==="
mapfile -t users < <(getent passwd | cut -d: -f1 | grep -iE "$PATTERN" | grep -vE "$KEEP" || true)
for u in "${users[@]}"; do
    home="$(getent passwd "$u" | cut -d: -f6)"
    if [[ -x "$home/actions-runner/svc.sh" ]]; then
        run bash -c "cd '$home/actions-runner' && ./svc.sh stop && ./svc.sh uninstall"
    fi
    run pkill -u "$u"
    run userdel -r "$u"
done

echo "=== Groups ==="
mapfile -t groups_ < <(getent group | cut -d: -f1 | grep -iE "$PATTERN" | grep -vE "$KEEP" || true)
for g in "${groups_[@]}"; do
    run groupdel "$g"
done

echo "=== Sudoers ==="
mapfile -t sudoers < <(find /etc/sudoers.d -maxdepth 1 -type f -regextype posix-extended -iregex ".*/[^/]*(${PATTERN})[^/]*" 2>/dev/null || true)
for f in "${sudoers[@]}"; do
    run rm -f "$f"
done

echo "=== Files and folders ==="
prune_expr=()
for p in "${PRUNE_PATHS[@]}"; do
    prune_expr+=(-path "$p" -o)
done
unset 'prune_expr[${#prune_expr[@]}-1]'

roots=()
for r in "${SEARCH_ROOTS[@]}"; do
    [[ -d "$r" ]] && roots+=("$r")
done

mapfile -t paths < <(find "${roots[@]}" -xdev \( "${prune_expr[@]}" \) -prune \
    -o -regextype posix-extended -iregex ".*/[^/]*(${PATTERN})[^/]*" -print 2>/dev/null | sort -r)
for p in "${paths[@]}"; do
    [[ "$(basename "$p")" =~ $KEEP ]] && continue
    [[ -e "$p" ]] && run rm -rf "$p"
done

run systemctl daemon-reload
run systemctl reset-failed

if ! $APPLY; then
    echo
    echo "Dry run only. Review the list above, then re-run with: sudo bash $0 --yes"
fi
