#!/usr/bin/env bash
# Developer: create or update the CI/CD files in your project repo (Linux, macOS, WSL, Git Bash).
# Usage: bash setup-cicd.sh PROJECT [REPO_DIR]   (PROJECT name is given by the VM admin)
# Safe to rerun: deploy.yml is refreshed, existing .cicd/*.sh files are never overwritten.
set -euo pipefail

project="${1:-}"
repo_dir="${2:-.}"
if [[ ! "$project" =~ ^[a-z][a-z0-9-]{0,29}$ ]]; then
    echo "Usage: bash $0 PROJECT [REPO_DIR]   (PROJECT: name given by the VM admin, e.g. project1)" >&2
    exit 1
fi
templates="$(cd "$(dirname "$0")" && pwd)/templates"
if ! root="$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "$repo_dir is not inside a Git repository." >&2
    exit 1
fi
cd "$root"

mkdir -p .github/workflows .cicd
sed "s/__PROJECT__/${project}/g" "$templates/deploy.yml" >.github/workflows/deploy.yml
echo "Wrote   .github/workflows/deploy.yml (project: $project)"

for file in start.sh test.sh post-deploy.sh; do
    if [[ -e ".cicd/$file" ]]; then
        echo "Kept    .cicd/$file"
    else
        cp "$templates/$file" ".cicd/$file"
        echo "Created .cicd/$file"
    fi
done

# Windows line endings break shell scripts on the VM.
if ! grep -qxF '*.sh text eol=lf' .gitattributes 2>/dev/null; then
    echo '*.sh text eol=lf' >>.gitattributes
    echo "Updated .gitattributes"
fi

cat <<EOF

Next:
  1. Edit .cicd/start.sh so it starts your app on \$PORT (and test.sh / post-deploy.sh if needed).
  2. git add .github .cicd .gitattributes
     git commit -m "Add CI/CD"
     git push origin main
  3. Watch the run in GitHub > Actions.
EOF
