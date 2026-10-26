#!/usr/bin/env bash
# Requirement 1: create the group and folder, add members, grant the group access to the folder.
# Usage: sudo bash 1-create-project.sh project.env   (safe to rerun, e.g. after adding MEMBERS)
# shellcheck source=/dev/null
source "$(dirname "$0")/common.sh"

read -ra members <<<"${MEMBERS:-}"
for user in "${members[@]}"; do
    if ! id "$user" >/dev/null 2>&1; then
        echo "User not found: $user (Entra users must SSH into the VM once before being added)." >&2
        exit 1
    fi
done

getent group "$GROUP" >/dev/null || groupadd "$GROUP"

install -d -o root -g root -m 0755 /srv/projects
mkdir -p "$FOLDER"
chown root:"$GROUP" "$FOLDER"
# ACLs added by hand (e.g. group::--x) override the mode and block the group; chmod after clearing them.
if command -v setfacl >/dev/null; then
    setfacl -b /srv/projects
    setfacl -R -b "$FOLDER"
fi
chmod 0755 /srv/projects
chmod 2770 "$FOLDER"

for user in "${members[@]}"; do
    usermod -aG "$GROUP" "$user"
done

echo "Group:   $(getent group "$GROUP")"
echo "Folder:  $(stat -c '%A %U:%G %n' "$FOLDER")"
echo "Members must log out and back in for the new group to apply."
