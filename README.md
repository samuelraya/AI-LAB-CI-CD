# AILab Group-Folder CI/CD: End-To-End Guide

Every project gets its own Linux group, folder, port, and CI/CD pipeline on one
VM. When code is pushed or a pull request is merged to `main` in the project's
GitHub repo, it is tested, copied into the project folder, and the application
is started/restarted on its port.

The repository has two kits for two audiences. You download them and send
them as folders; nobody needs to clone or access this repository.

| Folder | Given to | Runs on | Purpose |
| --- | --- | --- | --- |
| [admin-kit/](admin-kit/) | VM administrator | The VM (`sudo`) | Group, folder, members, app service/port, runner |
| [developer-kit/](developer-kit/) | Developers / project teams | Their laptop, inside their project repo | Create and maintain the CI/CD pipeline files |

```text
 VM ADMIN (admin-kit, once per project)          DEVELOPER (developer-kit, in own repo)
 --------------------------------------          ---------------------------------
 1-create-project.sh  group + folder + members   setup-cicd  -> .github/workflows/deploy.yml
 2-create-service.sh  app service on 1-3 ports              -> .cicd/start.sh, test.sh, post-deploy.sh
 3-install-runner.sh  connect repo to VM         git push / merge to main
                                                        |
                                                        v
            GitHub runs .cicd/test.sh -> runner on VM deploys to
            /srv/projects/<project>/current -> app restarted on its port(s)
            (if the app does not come up, the previous release is restored)
```

| Item | Example for `project1` |
| --- | --- |
| Linux group | `grp_project1` |
| Folder | `/srv/projects/project1` (`root:grp_project1`, mode `2770`) |
| Application service | `app-project1.service`, runs as `app-project1` |
| Application ports | `PORT=8001`, optional `PORT_2`, `PORT_3` (set by the admin) |
| Runtime settings | `/etc/projects/project1.env` |
| Deploy account | `ci-project1` (runner; may only restart `app-project1`) |
| Live code | `/srv/projects/project1/current` |

| Who | Logs in as | Where | Does |
| --- | --- | --- | --- |
| VM admin | Admin account (e.g. `ailabadmin`, pem key or Entra) | VM | Runs admin-kit with `sudo` |
| Developer | Own Entra account, e.g. `pankaj.singla@coforge.com` | Laptop (VM only to look) | Runs developer-kit, pushes to `main` |
| Pipeline | `ci-<project>` (automatic) | VM | Deploys and restarts the app |
| Application | `app-<project>` (automatic) | VM | Runs `.cicd/start.sh` |

Developers never use the admin account or its key. Deployments happen through GitHub.

Contents:

0. [Download And Send The Kits](#0-download-and-send-the-kits)
1. [Quick Start](#1-quick-start)
2. [Part A: VM Administrator (admin-kit)](#2-part-a-vm-administrator-admin-kit)
3. [Part B: Developer (developer-kit)](#3-part-b-developer-developer-kit)
4. [Part C: Testing Both Kits](#4-part-c-testing-both-kits)
5. [Day-To-Day Behaviour](#5-day-to-day-behaviour)
6. [Operations](#6-operations)
7. [Troubleshooting](#7-troubleshooting)
8. [Repository Contents](#8-repository-contents)

## 0. Download And Send The Kits

1. On GitHub open this repository and switch to branch
   `feature/group-folder-cicd`.
2. Click **Code > Download ZIP** and extract it.
3. From the extracted folder take:
   - `admin-kit/` -> zip it and send to the **VM administrator**;
   - `developer-kit/` -> zip it and send to **each project team**.
   - `README.md` (this guide) -> send to both.

Windows PowerShell, from the extracted folder:

```powershell
Compress-Archive -Path .\admin-kit -DestinationPath .\admin-kit.zip
Compress-Archive -Path .\developer-kit -DestinationPath .\developer-kit.zip
```

The kits are self-contained: everything they need is inside the folder.

## 1. Quick Start

| # | Who | Where | Do |
| --- | --- | --- | --- |
| 1 | VM admin | VM | Copy `admin-kit/` to the VM, create `project1.env` |
| 2 | VM admin | VM | `sudo bash 1-create-project.sh project1.env` |
| 3 | VM admin | VM | `sudo bash 2-create-service.sh project1.env` |
| 4 | Repo owner | GitHub | **Settings > Actions > Runners > New self-hosted runner**: copy the token, give it to the VM admin (valid 1 hour) |
| 5 | VM admin | VM | `sudo bash 3-install-runner.sh project1.env`, paste token |
| 6 | VM admin | — | Tell the developer the project name (`project1`) and port(s) |
| 7 | Developer | Laptop | Run `developer-kit/setup-cicd` in the project repo, edit `.cicd/start.sh`, push to `main` |
| 8 | Anyone | GitHub / VM | **Actions** run is green; `curl http://127.0.0.1:8001/` responds |

### Laptop vs VM

| | Windows laptop | VM bash session |
| --- | --- | --- |
| Prompt | `C:\Users\...>` or `PS C:\...>` | `user@vm-ailab-01:~$` |
| Commands | `ssh`, `scp`, `az`, `git`, PowerShell | `ls`, `sudo`, `systemctl`, `nano` |
| Files | `C:\...` | `/home/...`, `/srv/...` |

- Check the prompt before pasting. Linux commands on Windows give `The system cannot find the path specified`; PowerShell commands in bash give `syntax error near unexpected token '&'` or `az: command not found`.
- `exit` leaves the VM. Do not type the prompt character (`>ssh ...` in Command Prompt writes to a file named `ssh`).
- nano: save with **Ctrl+O**, **Enter**; exit with **Ctrl+X**.

## 2. Part A: VM Administrator (admin-kit)

### A.1 Prerequisites

- Ubuntu 22.04/24.04 **x86_64** VM with outbound HTTPS to `github.com`
  (no inbound port needed for CI/CD).
- An admin account on the VM with `sudo`.
- Members must already exist on the VM. Microsoft Entra users exist only after
  they have logged in once with `az ssh vm`.

Log in as the admin (Windows, Command Prompt or PowerShell):

```powershell
ssh -i C:\path\to\key.pem ADMIN_USER@VM_ADDRESS
# or with Entra (roles: Virtual Machine Administrator Login + Reader on the resource group)
az login
az ssh vm --resource-group RG-AILAB --name vm-ailab-01 --prefer-private-ip
```

- Use the VM's real IP (Azure Portal > VM > **Overview**); private `10.x` addresses need the company network/VPN.
- `UNPROTECTED PRIVATE KEY FILE`: `icacls C:\path\to\key.pem /inheritance:r /grant:r "%USERNAME%:R"`.
- `sudo` asks for an unknown password: Azure Portal > VM > **Help > Reset password**, mode
  **Reset password**, admin user, new password, **Update**; wait 1-2 minutes and run `sudo -v`.
  Without portal access an Azure admin runs
  `az vm user update -g RG-AILAB -n vm-ailab-01 -u ADMIN_USER -p "<new-password>"`.

### A.2 Copy admin-kit onto the VM

Extract `admin-kit.zip` on your laptop, then copy the folder to the VM.

With Microsoft Entra login (Windows PowerShell, from the folder that contains
`admin-kit`):

```powershell
az ssh config --resource-group RG-AILAB --name vm-ailab-01 --prefer-private-ip --file .\vm-ssh-config
scp -F .\vm-ssh-config -r .\admin-kit RG-AILAB-vm-ailab-01:~/
az ssh vm --resource-group RG-AILAB --name vm-ailab-01 --prefer-private-ip
```

With a normal SSH account:

```bash
scp -r admin-kit ADMIN_USER@VM_ADDRESS:~/
ssh ADMIN_USER@VM_ADDRESS
```

Then on the VM:

```bash
cd ~/admin-kit
sed -i 's/\r$//' *.sh *.env      # remove Windows line endings
```

A GUI tool such as WinSCP works too. The scripts are started with `bash`, so
no execute permission is needed after copying.

### A.3 Edit the env file (one per project)

```bash
cp project.env project1.env
nano project1.env
```

```bash
PROJECT=project1
MEMBERS="pankaj.singla@coforge.com mahi@coforge.com"
PORT=8001
PORT_2=8002          # optional
PORT_3=              # optional
PACKAGES="python3-venv nodejs npm"
REPO_URL=https://github.com/ORG/project1-repo
```

| Setting | Meaning |
| --- | --- |
| `PROJECT` | Lowercase letters, digits, `-`. Gives `grp_<PROJECT>` and `/srv/projects/<PROJECT>`. Must equal the developer's `-Project` value |
| `MEMBERS` | Linux users to add to the group, space separated |
| `PORT` | Port the app listens on, 1024-65535, unique on the VM |
| `PORT_2`, `PORT_3` | Optional extra ports (1 to 3 per project), e.g. backend API; the app receives them as `$PORT_2`, `$PORT_3`. Leave empty if unused |
| `PACKAGES` | Optional: Ubuntu packages the app needs, installed VM-wide by script 2 (see [B.3](#b3-customise-the-cicd-files)) |
| `REPO_URL` | Exact GitHub repo URL (e.g. `https://github.com/ORG/REPO`) |
| `RUNNER_VERSION`, `RUNNER_SHA256` | Optional: pin the runner version instead of latest |

### A.4 Script 1: group, folder, members

```bash
sudo bash 1-create-project.sh project1.env
```

Runs exactly:

```bash
sudo groupadd grp_project1
sudo mkdir -p /srv/projects/project1
sudo chown root:grp_project1 /srv/projects/project1
sudo chmod 2770 /srv/projects/project1
sudo usermod -aG grp_project1 pankaj.singla@coforge.com
sudo usermod -aG grp_project1 mahi@coforge.com
```

`2770` = access only for root and the group; the `2` (setgid) makes new files
belong to the group. The script also removes hand-added ACLs (e.g. `group::--x`)
that would block the group. Safe to rerun after adding names to `MEMBERS`.

The admin is not a group member: browse projects with `sudo ls /srv/projects/project1`
or `sudo -i` (`sudo cd` does not work).

### A.5 Script 2: application service and port

```bash
sudo bash 2-create-service.sh project1.env
```

- Refuses ports already assigned to another project, or repeated within the project.
- Installs `PACKAGES` (if set).
- Creates `app-project1` (runs the app, group `grp_project1`).
- Writes `/etc/projects/project1.env` with `PORT` (and `PORT_2`, `PORT_3`); the app
  receives them as environment variables. Add other app variables here.
- Creates and enables `app-project1.service`, which runs
  `/srv/projects/project1/current/.cicd/start.sh`, restarts it on crash and
  after reboot.
- Allows `ci-project1` to run only `systemctl restart app-project1.service`.

To change ports: edit them, rerun the script, tell the developer.

App-specific settings and secrets go into `/etc/projects/<project>.env`
(readable only by root and the project group). Example: keep a SQLite database
outside the release folders so it survives deploys:

```bash
echo 'AILAB_DATABASE_URL=sqlite:////srv/projects/deployment/ailab.db' | sudo tee -a /etc/projects/deployment.env
sudo systemctl restart app-deployment
```

### A.6 Script 3: connect the project repo

1. Get a runner token: in the project repo **Settings > Actions > Runners >
   New self-hosted runner**, choose **Linux x64** and copy only the token from
   the `./config.sh ... --token XXXX` line. **Do not run GitHub's commands**;
   the script does that. This needs repo admin rights; usually the repo owner
   sends it to you. Valid for 1 hour.
2. On the VM:

   ```bash
   sudo bash 3-install-runner.sh project1.env
   ```

   Paste the token when asked (hidden).

It creates `ci-project1`, downloads the latest runner and verifies its SHA256,
registers it with the label `project1`, and installs it as a service. The
runner shows as **Idle** on the GitHub Runners page. The message
`Package 'libicu75' has no installation candidate` is harmless.

### A.7 Hand-off to the developer

Send the developer: `developer-kit.zip`, this `README.md`, the project name
(`project1`), and the port(s) (`PORT=8001`, `PORT_2=8002`). Never send the
admin key or password.

## 3. Part B: Developer (developer-kit)

The developer never needs VM access, or access to this platform repository, to
set up or maintain CI/CD. VM access (B.0) is only for looking at the running app.

### B.0 Optional: VM access with your own account

1. Azure admin grants **Virtual Machine User Login** on the VM and **Reader** on
   the resource group.
2. First login (creates your Linux user), then `exit`:

   ```powershell
   az login
   az ssh vm --resource-group RG-AILAB --name vm-ailab-01 --prefer-private-ip
   ```

3. The VM admin adds you to `MEMBERS` and reruns script 1; log out and in again.
   `id` must list `grp_<project>`.

### B.1 Create the pipeline files

Extract `developer-kit.zip` anywhere (e.g. `C:\tools\developer-kit`). Then run
the script inside your project's local working copy (the folder where you
normally edit and push your project code):

Windows PowerShell:

```powershell
cd C:\src\project1-repo
powershell -ExecutionPolicy Bypass -File C:\tools\developer-kit\setup-cicd.ps1 -Project project1
```

Linux / macOS / WSL / Git Bash:

```bash
cd ~/src/project1-repo
bash ~/tools/developer-kit/setup-cicd.sh project1
```

Output:

```text
Wrote   .github/workflows/deploy.yml (project: project1)
Created .cicd/start.sh
Created .cicd/test.sh
Created .cicd/post-deploy.sh
Updated .gitattributes
```

### B.2 Edit the .cicd files

The pipeline (`.github/workflows/deploy.yml`) is the same for every project; do
not edit it. All app-specific behaviour lives in three files:

| File | Required | Runs | When | Default |
| --- | --- | --- | --- | --- |
| `.cicd/test.sh` | No | GitHub's Ubuntu machine | Every push and pull request; failure stops the deploy | Prints "No tests configured" |
| `.cicd/post-deploy.sh` | No | VM, as `ci-<project>`, inside the new release folder | Each deploy, before going live; failure stops the deploy | Does nothing |
| `.cicd/start.sh` | **Yes** | VM, as `app-<project>`, by `app-<project>.service` | Each (re)start | Fails with "Edit .cicd/start.sh" until edited |

Rules for `start.sh`:

- Run in the **foreground**; use `exec` for a single process (no `nohup`,
  `pm2`, `docker -d`, or `&` without `wait`).
- Listen on `"$PORT"` (and `"$PORT_2"`, `"$PORT_3"` if assigned). Never hard-code
  numbers: `"$8801"` is read by bash as `$8` followed by `801`.
- Bind to `0.0.0.0` to be reachable from outside the VM, `127.0.0.1` for internal-only.
- Prefer production servers (gunicorn, uvicorn, `vite preview`, `next start`)
  over dev servers (`npm run dev`, `flask run`, `manage.py runserver`).
- Paths are relative to the repo root (the release folder); use `cd subfolder` in monorepos.
- Settings and secrets come from `/etc/projects/<project>.env` (ask the VM
  admin). Never commit secrets.
- Data that must survive deploys (SQLite, uploads) goes in
  `/srv/projects/<project>/data`, not inside the release.

### B.3 Customise the CI/CD files

**Ports (1 to 3 per project).** Ask the VM admin; they set them in `project.env`
and rerun script 2. Do that **before** pushing a `start.sh` that needs them.

| Ports | Admin sets | App receives | Typical use |
| --- | --- | --- | --- |
| 1 | `PORT=8001` | `$PORT` | One app (Flask, Django, FastAPI, Node, static site) |
| 2 | `PORT`, `PORT_2=8002` | `$PORT`, `$PORT_2` | Frontend + backend API |
| 3 | `PORT`, `PORT_2`, `PORT_3=8003` | `$PORT`, `$PORT_2`, `$PORT_3` | Frontend + API + admin UI / second service |

The deploy waits up to 30 seconds until **every** assigned port is listening,
otherwise it restores the previous release.

**VM packages** (admin sets `PACKAGES` in `project.env`):

| Stack | `PACKAGES` |
| --- | --- |
| Static HTML | none (`python3` is preinstalled) |
| Python (Flask, FastAPI, Django) | `python3-venv` |
| Node.js, React, Next.js | `nodejs npm` |
| Python + Node | `python3-venv nodejs npm` |

**Recipes, 1 port.** Put the lines into `.cicd/post-deploy.sh` and
`.cicd/start.sh` below `#!/usr/bin/env bash` and `set -euo pipefail`. Adjust
folder, module and file names to your repo.

| App | `post-deploy.sh` | `start.sh` |
| --- | --- | --- |
| Static HTML (files in `site/`) | nothing | `exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory site` |
| React (Vite) / SPA | `npm ci && npm run build` | `exec node_modules/.bin/vite preview --host 0.0.0.0 --port "$PORT" --strictPort` |
| React (Create React App) | `npm ci && npm run build` | `exec npx --yes serve -s build -l "tcp://0.0.0.0:$PORT"` |
| Next.js | `npm ci && npm run build` | `exec node_modules/.bin/next start -H 0.0.0.0 -p "$PORT"` |
| Node.js (Express) | `npm ci --omit=dev` | `exec node server.js` (uses `process.env.PORT`) |
| Python script | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `exec .venv/bin/python main.py` (reads `os.environ["PORT"]`) |
| Flask | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt gunicorn` | `exec .venv/bin/gunicorn -w 2 -b "0.0.0.0:$PORT" app:app` |
| FastAPI | `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt` | `exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "$PORT"` |
| Django | see below | `exec .venv/bin/gunicorn -w 2 -b "0.0.0.0:$PORT" mysite.wsgi` |

Django `post-deploy.sh`:

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt gunicorn whitenoise
.venv/bin/python manage.py migrate --noinput
.venv/bin/python manage.py collectstatic --noinput
```

Django also needs `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, `DJANGO_DEBUG=False`
and a database path outside the release in `/etc/projects/<project>.env`, read
in `settings.py`, plus `whitenoise.middleware.WhiteNoiseMiddleware` for static files.

**Recipes, 2 or 3 ports.** Start each process in the background and end with
`wait -n` and `exit 1`: if one process stops, systemd restarts all of them.

React frontend + Python backend (2 ports):

```bash
# .cicd/post-deploy.sh
cd backend
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cd ../frontend
npm ci
npm run build

# .cicd/start.sh
: "${PORT_2:?PORT_2 must be assigned by the VM admin}"
export API_PORT="$PORT_2"
(cd backend && exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "$PORT_2") &
(cd frontend && exec node_modules/.bin/vite preview --host 0.0.0.0 --port "$PORT" --strictPort) &
wait -n
exit 1
```

Backend alternatives: Flask `exec .venv/bin/gunicorn -b "0.0.0.0:$PORT_2" app:app`;
Django `exec .venv/bin/gunicorn -b "0.0.0.0:$PORT_2" mysite.wsgi`;
Node `PORT="$PORT_2" exec node server.js`.

The frontend must reach the API. Either forward `/api` to the backend in
`vite.config.js` so the browser only needs `PORT`:

```js
const apiTarget = `http://127.0.0.1:${process.env.API_PORT || 8000}`;
export default defineConfig({
  plugins: [react()],
  server: { port: 5173, proxy: { "/api": apiTarget } },
  preview: { proxy: { "/api": apiTarget } },
});
```

or build the frontend with the API URL (e.g. `VITE_API_URL=http://<vm-ip>:$PORT_2 npm run build`)
and allow that origin in the backend's CORS settings.

Three ports (web + API + admin UI):

```bash
: "${PORT_2:?}" "${PORT_3:?}"
(cd api && exec .venv/bin/uvicorn main:app --host 0.0.0.0 --port "$PORT_2") &
(cd admin && exec .venv/bin/gunicorn -b "0.0.0.0:$PORT_3" admin.wsgi) &
(cd web && exec node server.js) &
wait -n
exit 1
```

**`test.sh` examples** (GitHub's machine has Python and Node):

```bash
python3 -m pip install -r requirements.txt pytest && python3 -m pytest -q   # Python
python3 -m pip install -r requirements.txt && python3 manage.py test         # Django
npm ci && npm test --if-present && npm run build                             # Node / React
```

**Checklist** after changing `.cicd` files: ports assigned on the VM
(`grep PORT /etc/projects/<project>.env`), runtimes installed
(`python3 --version; node --version`), optionally test on Linux/WSL with
`bash .cicd/post-deploy.sh && PORT=8001 PORT_2=8002 bash .cicd/start.sh`, then push.

### B.4 Commit and push

```bash
git add .github .cicd .gitattributes
git commit -m "Add CI/CD"
git push origin main
```

GitHub > **Actions**: `test` then `deploy` must be green.

### B.5 Maintenance

Rerun `setup-cicd` any time (e.g. when you receive a newer `developer-kit`) to
refresh `.github/workflows/deploy.yml`. Your `.cicd/*.sh` files are never
overwritten. Commit and push the result.

## 4. Part C: Testing Both Kits

Use a throwaway project named `demo` on port `8099`. Replace `ORG` and your
Linux user name.

### C.1 Automatic checks (no VM needed)

Every pull request and push to `main` in this repository runs [ci.yml](.github/workflows/ci.yml):
`shellcheck` on all scripts, and runs both `setup-cicd.sh` and
`setup-cicd.ps1` on empty repos and checks they produce identical files.

Local quick test of the developer script on Windows (no VM, no GitHub; creates
an empty local Git folder just for the test):

```powershell
$t = Join-Path $env:TEMP "cicd-test"; git init -q $t
powershell -ExecutionPolicy Bypass -File C:\tools\developer-kit\setup-cicd.ps1 -Project demo -RepoDir $t
Get-ChildItem -Recurse -Force $t\.cicd, $t\.github
Select-String -Path $t\.github\workflows\deploy.yml -Pattern 'demo'
Remove-Item -Recurse -Force $t
```

Expected: `deploy.yml` and three `.cicd/*.sh` files; `deploy.yml` contains
`runs-on: [self-hosted, Linux, demo]` and `/srv/projects/demo`.

### C.2 Prepare a test repo (developer, GitHub)

Create a **private** repo `ORG/demo-app` with a README (so `main` exists) and
open its local working copy the way you normally work on code (VS Code,
GitHub Desktop, etc.).

### C.3 Test admin-kit (VM admin, on the VM)

Copy `admin-kit` to the VM as in [A.2](#a2-copy-admin-kit-onto-the-vm), then:

```bash
cd ~/admin-kit
cat > demo.env <<'EOF'
PROJECT=demo
MEMBERS="YOUR_LINUX_USER"
PORT=8099
REPO_URL=https://github.com/ORG/demo-app
EOF
```

Script 1:

```bash
sudo bash 1-create-project.sh demo.env
getent group grp_demo                       # expect: grp_demo:x:<id>:YOUR_LINUX_USER
stat -c '%A %U:%G' /srv/projects/demo       # expect: drwxrws--- root:grp_demo
sudo -u nobody ls /srv/projects/demo        # expect: Permission denied
```

Log out and in again, then as `YOUR_LINUX_USER`:

```bash
touch /srv/projects/demo/hello && ls -l /srv/projects/demo/hello   # group: grp_demo
rm /srv/projects/demo/hello
```

Script 2:

```bash
sudo bash 2-create-service.sh demo.env
systemctl is-enabled app-demo               # expect: enabled
systemctl cat app-demo                      # User=app-demo, .cicd/start.sh
sudo cat /etc/projects/demo.env             # expect: PROJECT=demo, PORT=8099
sudo cat /etc/sudoers.d/project-demo        # expect: ci-demo ... restart app-demo.service
```

Script 3 (get a runner token for `ORG/demo-app` first, see A.6):

```bash
sudo bash 3-install-runner.sh demo.env
systemctl list-units 'actions.runner.*'     # expect: active (running)
sudo -l -U ci-demo                          # expect: only systemctl restart app-demo.service
```

In GitHub `demo-app` **Settings > Actions > Runners** shows the runner **Idle**.

Negative tests (each must stop with a clear error and change nothing):

| Change in `demo.env` | Run | Expected |
| --- | --- | --- |
| `MEMBERS="no-such-user"` | script 1 | `User not found: no-such-user` |
| `PROJECT=Demo` | any script | `PROJECT must be lowercase ...` |
| `PORT=80` | script 2 | `PORT must be a number between 1024 and 65535` |
| `PORT` of another project | script 2 | `Port ... is already assigned` |
| Run script 3 again | script 3 | `A runner is already registered` |

Rerunning scripts 1 and 2 with the original values must succeed (idempotent).

### C.4 Test developer-kit and the pipeline (developer, laptop)

1. Generate the files in the test repo:

   ```powershell
   cd C:\src\demo-app
   powershell -ExecutionPolicy Bypass -File C:\tools\developer-kit\setup-cicd.ps1 -Project demo
   ```

2. Make a tiny app (Python standard library only, nothing to install):

   ```bash
   mkdir public
   echo "version 1" > public/index.html
   ```

   Replace `.cicd/start.sh` with:

   ```bash
   #!/usr/bin/env bash
   exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory public
   ```

3. Push:

   ```bash
   git add .
   git commit -m "Add CI/CD"
   git push origin main
   ```

4. Verify:

   | Test | How | Expected |
   | --- | --- | --- |
   | First deploy | GitHub **Actions** | `test` and `deploy` green |
   | App on port | VM: `curl http://127.0.0.1:8099/` | `version 1` |
   | Service | VM: `systemctl status app-demo` | `active (running)` |
   | Update | Change to `version 2`, push | `curl` shows `version 2`; 2 folders in `/srv/projects/demo/releases` |
   | Merge triggers deploy | Change on a branch, open PR, merge | PR run: only `test`; after merge: `test` + `deploy` |
   | Failing tests block deploy | `.cicd/test.sh`: add `exit 1`, push | `deploy` skipped; `curl` unchanged |
   | Rollback | Restore `test.sh`; `.cicd/start.sh`: `exit 1`, push | `deploy` fails with "rolled back"; `curl` still shows previous version |
   | Maintenance rerun | Run `setup-cicd` again | `Kept .cicd/...`; `git status` shows no change |

Fix `start.sh` and push again to end with a healthy deployment.

### C.5 Clean up the test

Remove the runner in GitHub **Settings > Actions > Runners > runner > Remove**
(copy the removal token), then on the VM:

```bash
cd /home/ci-demo/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh uninstall
sudo -u ci-demo ./config.sh remove --token <REMOVAL_TOKEN>
cd /
sudo systemctl disable --now app-demo
sudo rm -f /etc/systemd/system/app-demo.service /etc/sudoers.d/project-demo /etc/projects/demo.env
sudo systemctl daemon-reload
sudo userdel -r ci-demo
sudo userdel app-demo
sudo rm -rf /srv/projects/demo
sudo groupdel grp_demo
```

Delete the `ORG/demo-app` repo in GitHub. The same commands retire a real
project.

## 5. Day-To-Day Behaviour

| Action | Result |
| --- | --- |
| Open / update a pull request | Tests only, nothing deployed |
| Merge a pull request into `main`, or push to `main` | Tests, deploy, app restarted on its port |
| **Actions > CI/CD > Run workflow** | Redeploy `main` manually |

The deploy waits up to 30 seconds for the app to listen on all its ports. If tests or
`post-deploy.sh` fail, nothing changes. If the new version does not start, the
previous release is restored and the run is marked failed. The last 5 releases
are kept.

## 6. Operations

Check the app (on the VM):

| Command | Admin | Developer (own login) |
| --- | --- | --- |
| `systemctl status app-project1 --no-pager` | yes | yes |
| `grep PORT /etc/projects/project1.env` | with `sudo` | yes (group-readable) |
| `curl http://localhost:8001/` | yes | yes |
| `journalctl -u app-project1 -n 50 --no-pager` | with `sudo` | no |
| `ls -l /srv/projects/project1/current` | with `sudo` | yes |

Open the app from a laptop:

- SSH tunnel (no Azure change; window shows no output while it runs, Ctrl+C to stop):

  ```powershell
  ssh -i C:\path\to\key.pem -N -L 8001:127.0.0.1:8001 -L 8002:127.0.0.1:8002 ADMIN_USER@VM_ADDRESS
  # developer: az ssh vm --resource-group RG-AILAB --name vm-ailab-01 --prefer-private-ip -- -N -L 8001:127.0.0.1:8001
  ```

  Then browse `http://localhost:8001/`.
- Direct: Azure Portal > VM > **Networking > Create port rule > Inbound**, port
  `8001` (and other ports), source = office/VPN IP range only, never "Any". If
  `sudo ufw status` is active: `sudo ufw allow 8001/tcp`. Browse `http://VM_ADDRESS:8001/`.
- For real users put HTTPS (nginx or Application Gateway) in front and open only 443.

Inspect the VM:

```bash
getent passwd | cut -d: -f1                         # users
getent group | cut -d: -f1,4                        # groups + members
sudo ls -la /srv/projects /etc/projects             # project folders and settings
ls /etc/systemd/system | grep -E 'actions.runner|app-'
ss -tln                                             # listening ports
```

Members (admin):

```bash
sudo bash 1-create-project.sh project1.env        # after adding names to MEMBERS
sudo gpasswd -d user@coforge.com grp_project1     # remove
```

Members must log out and back in (or `newgrp grp_project1`) for changes to apply.

Service (admin):

```bash
sudo systemctl restart app-project1
sudo systemctl stop app-project1
journalctl -u app-project1 -f
```

Manual rollback (admin):

```bash
ls -1 /srv/projects/project1/releases
sudo ln -sfn /srv/projects/project1/releases/<older-release> /srv/projects/project1/current
sudo systemctl restart app-project1
```

Runner restart (admin):

```bash
cd /home/ci-project1/actions-runner
sudo ./svc.sh stop && sudo ./svc.sh start
```

Retire a project: same as [C.5](#c5-clean-up-the-test) with `project1`.

Bulk clean-up by name: [admin-kit/cleanup-ailab.sh](admin-kit/cleanup-ailab.sh) removes
services, users, groups, sudoers files and files/folders whose **name** matches
`ailab|demo` (edit `PATTERN`). It always keeps the admin account (`KEEP`) and only
searches `/srv /opt /home /root /etc /var /tmp`.

```bash
sudo bash cleanup-ailab.sh          # dry run: lists what would be removed
sudo bash cleanup-ailab.sh --yes    # delete (cannot be undone)
```

## 7. Troubleshooting

| Symptom | Fix |
| --- | --- |
| Push to `main` starts no run | `.github/workflows/deploy.yml` must be on `main`; Actions enabled in repo settings |
| `deploy` stuck on "Waiting for a runner" | Runner offline (restart it), or wrong project name given to `setup-cicd` |
| `User not found` in script 1 | Entra user must log in once with `az ssh vm` first |
| `Port ... already assigned` | Choose another `PORT` |
| Token rejected in script 3 | Tokens expire after 1 hour; create a new one |
| `A runner is already registered` | Already done; to redo, remove the runner first (C.5) |
| `Missing .cicd/start.sh` | Run `setup-cicd` and edit `.cicd/start.sh` |
| `Edit .cicd/start.sh ...` in logs | `start.sh` still has the template content |
| `App did not start on port ...` | `journalctl -u app-project1`; `start.sh` must listen on `$PORT` (and `$PORT_2`, `$PORT_3`) |
| `$'\r': command not found` | Windows line endings: rerun `setup-cicd` (adds `.gitattributes`), recommit the `.sh` files |
| `sudo: a password is required` in deploy | Admin reruns script 2 |
| `running scripts is disabled` (PowerShell) | Use `powershell -ExecutionPolicy Bypass -File ...` as shown |
| Member gets `Permission denied` | Not in `grp_project1`, or must log out and back in |
| Admin gets `Permission denied` on a project folder | Expected; use `sudo ls ...` or `sudo -i` |
| `AuthorizationFailed ... networkInterfaces/read` from `az ssh vm` | Needs **Reader** on the resource group, or use `az ssh vm --ip`, or SSH with a key |
| `Connection timed out` (SSH) | Wrong IP, private IP without VPN, VM stopped, or port 22 blocked |
| `Permission denied (publickey)` | Wrong user name or key; fix key permissions with `icacls` |
| `[sudo] password for ...` unknown | Azure Portal **Reset password** (A.1) |
| Script 3: `404 Not Found ... runner-registration` | `REPO_URL` wrong (e.g. still `ORG/...`) or token from another repo |
| Deploy: `mkdir ... releases: Permission denied` | Hand-added ACL on the folder: rerun script 1, then re-run the failed job |
| Deploy fails right after adding `PORT_2`/`PORT_3` to `start.sh` | Admin must assign the port and rerun script 2 first |
| Browser `ERR_CONNECTION_RESET` through a tunnel | Nothing listens on that VM port: check `PORT` and `systemctl status` |
| Data lost after each deploy | Database inside the release folder; point it to `/srv/projects/<project>/data` via `/etc/projects/<project>.env` |

## 8. Repository Contents

| File | Purpose |
| --- | --- |
| [admin-kit/project.env](admin-kit/project.env) | Settings the admin edits per project |
| [admin-kit/1-create-project.sh](admin-kit/1-create-project.sh) | Group, folder, members, access |
| [admin-kit/2-create-service.sh](admin-kit/2-create-service.sh) | Packages, app service on 1-3 ports, restart permission for the pipeline |
| [admin-kit/3-install-runner.sh](admin-kit/3-install-runner.sh) | Connect the project repo to the VM |
| [admin-kit/common.sh](admin-kit/common.sh) | Shared env-file loading |
| [admin-kit/cleanup-ailab.sh](admin-kit/cleanup-ailab.sh) | Optional bulk clean-up by name (dry run by default) |
| [developer-kit/setup-cicd.ps1](developer-kit/setup-cicd.ps1) | Developer script, Windows |
| [developer-kit/setup-cicd.sh](developer-kit/setup-cicd.sh) | Developer script, Linux/macOS/WSL/Git Bash |
| [developer-kit/templates/](developer-kit/templates/) | Pipeline (`deploy.yml`) and `.cicd/*.sh` templates |
| [.github/workflows/ci.yml](.github/workflows/ci.yml) | Checks and tests both kits on every push |
