#!/usr/bin/env bash
# Requirement 2 (Git side): connect the project's GitHub repo to the VM with a self-hosted runner.
# Usage: sudo bash 3-install-runner.sh project.env
# Needs a runner registration token from: Repo > Settings > Actions > Runners > New self-hosted runner.
# Optional pinning: set RUNNER_VERSION and RUNNER_SHA256 in project.env.
# shellcheck source=/dev/null
source "$(dirname "$0")/common.sh"

repo_url="${REPO_URL:-}"
repo_url="${repo_url%.git}"
if [[ ! "$repo_url" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "REPO_URL must look like https://github.com/ORG/REPO" >&2
    exit 1
fi
if [[ "$(uname -m)" != x86_64 ]]; then
    echo "Only x86_64 VMs are supported." >&2
    exit 1
fi
if [[ ! -f "/etc/systemd/system/${SERVICE}" ]]; then
    echo "Run 1-create-project.sh and 2-create-service.sh first." >&2
    exit 1
fi

project="$PROJECT"
group="$GROUP"
ci_user="$CI_USER"
runner_dir="/home/${ci_user}/actions-runner"
command -v git >/dev/null || apt-get install -y git

# Dedicated deploy account per project: no login shell, member of only this project's group.
if ! id "$ci_user" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "/home/${ci_user}" --shell /usr/sbin/nologin "$ci_user"
fi
usermod -aG "$group" "$ci_user"
chmod 700 "/home/${ci_user}"

if [[ -e "$runner_dir/.runner" ]]; then
    echo "A runner is already registered for $project in $runner_dir." >&2
    exit 1
fi

if [[ -z "${RUNNER_VERSION:-}" ]]; then
    release_json="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
    RUNNER_VERSION="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))' <<<"$release_json")"
    RUNNER_SHA256="$(python3 -c 'import json,re,sys; b=json.load(sys.stdin)["body"]; print(re.search(r"BEGIN SHA linux-x64 -->([0-9a-f]{64})", b).group(1))' <<<"$release_json")"
fi
if [[ ! "$RUNNER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "${RUNNER_SHA256:-}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "Invalid RUNNER_VERSION / RUNNER_SHA256." >&2
    exit 1
fi

archive="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
sudo -u "$ci_user" mkdir -p "$runner_dir"
cd "$runner_dir" || exit 1
sudo -u "$ci_user" curl -fL --retry 3 -o "$archive" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${archive}"
echo "${RUNNER_SHA256}  ${archive}" | sha256sum --check
sudo -u "$ci_user" tar -xzf "$archive"
rm -f "$archive"
./bin/installdependencies.sh

read -rsp "Paste the runner registration token (hidden): " token
echo
sudo -u "$ci_user" ./config.sh --unattended --url "$repo_url" --token "$token" \
    --name "${project}-$(hostname -s)" --labels "$project" --work _work
unset token

./svc.sh install "$ci_user"
./svc.sh start

echo
echo "Runner for '$project' is online (label: $project)."
echo "Next: tell the developer PROJECT=$project; they run developer-kit/setup-cicd in their repo."
