#!/usr/bin/env bash
# Requirement 2 (VM side): systemd service that runs the app on PORT (plus optional PORT_2, PORT_3)
# and lets the pipeline restart it.
# Usage: sudo bash 2-create-service.sh project.env   (safe to rerun, e.g. after changing ports)
# shellcheck source=/dev/null
source "$(dirname "$0")/common.sh"

ports=()
for name in PORT PORT_2 PORT_3; do
    value="${!name:-}"
    if [[ -z "$value" ]]; then
        [[ "$name" == PORT ]] && { echo "PORT is required." >&2; exit 1; }
        continue
    fi
    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1024 || value > 65535 )); then
        echo "$name must be a number between 1024 and 65535." >&2
        exit 1
    fi
    for used in "${ports[@]}"; do
        if (( used == value )); then
            echo "$name duplicates another port of this project ($value)." >&2
            exit 1
        fi
    done
    ports+=("$value")
done
if [[ ! -d "$FOLDER" ]]; then
    echo "Run 1-create-project.sh first." >&2
    exit 1
fi
for p in "${ports[@]}"; do
    conflict="$(grep -lxE "PORT(_[23])?=${p}" /etc/projects/*.env 2>/dev/null | grep -vx "$RUNTIME_ENV" || true)"
    if [[ -n "$conflict" ]]; then
        echo "Port $p is already assigned in: $conflict" >&2
        exit 1
    fi
done

read -ra packages <<<"${PACKAGES:-}"
for pkg in "${packages[@]}"; do
    if [[ ! "$pkg" =~ ^[a-z0-9][a-z0-9.+-]*$ ]]; then
        echo "Invalid package name in PACKAGES: $pkg" >&2
        exit 1
    fi
done
if (( ${#packages[@]} )); then
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${packages[@]}"
fi

# The app runs as its own account, separate from the runner account that holds GitHub credentials.
if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin \
        --gid "$GROUP" "$APP_USER"
fi

install -d -o root -g root -m 0755 /etc/projects
if [[ -f "$RUNTIME_ENV" ]]; then
    sed -i "s/^PORT=.*/PORT=${PORT}/" "$RUNTIME_ENV"
else
    printf 'PROJECT=%s\nPORT=%s\n' "$PROJECT" "$PORT" >"$RUNTIME_ENV"
fi
sed -i -E '/^(API_PORT|PORT_2|PORT_3)=/d' "$RUNTIME_ENV"
for name in PORT_2 PORT_3; do
    if [[ -n "${!name:-}" ]]; then
        printf '%s=%s\n' "$name" "${!name}" >>"$RUNTIME_ENV"
    fi
done
chown root:"$GROUP" "$RUNTIME_ENV"
chmod 0640 "$RUNTIME_ENV"

cat >"/etc/systemd/system/${SERVICE}" <<EOF
[Unit]
Description=${PROJECT} application (port ${PORT})
After=network.target

[Service]
User=${APP_USER}
Group=${GROUP}
UMask=0007
EnvironmentFile=${RUNTIME_ENV}
WorkingDirectory=${FOLDER}/current
ExecStart=/bin/bash ${FOLDER}/current/.cicd/start.sh
Restart=on-failure
RestartSec=3
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

sudoers="$(mktemp)"
printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl restart %s\n' "$CI_USER" "$SERVICE" >"$sudoers"
visudo -cf "$sudoers" >/dev/null
install -o root -g root -m 0440 "$sudoers" "/etc/sudoers.d/project-${PROJECT}"
rm -f "$sudoers"

systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
if [[ -e "$FOLDER/current" ]]; then
    systemctl restart "$SERVICE"
fi

echo "Service: $SERVICE (port $PORT, runs as $APP_USER)"
echo "Settings file: $RUNTIME_ENV (add app variables here; readable by $GROUP)"
echo "The pipeline starts it on the first deploy."
