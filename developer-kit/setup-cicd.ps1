# Developer: create or update the CI/CD files in your project repo (Windows PowerShell).
# Usage: powershell -ExecutionPolicy Bypass -File setup-cicd.ps1 -Project project1 [-RepoDir C:\src\project1-repo]
# Safe to rerun: deploy.yml is refreshed, existing .cicd/*.sh files are never overwritten.
param(
    [Parameter(Mandatory = $true)][string]$Project,
    [string]$RepoDir = '.'
)

if ($Project -cnotmatch '^[a-z][a-z0-9-]{0,29}$') {
    Write-Error 'Project must be the name given by the VM admin (lowercase letters, digits, "-"), e.g. project1.'
    exit 1
}
$root = git -C $RepoDir rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -ne 0 -or -not $root) {
    Write-Error "$RepoDir is not inside a Git repository."
    exit 1
}
$ErrorActionPreference = 'Stop'
$templates = Join-Path $PSScriptRoot 'templates'

function Write-LfFile([string]$Path, [string]$Text) {
    # LF endings and no BOM, because these files run on Linux.
    [IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
}

New-Item -ItemType Directory -Force (Join-Path $root '.github/workflows'), (Join-Path $root '.cicd') | Out-Null
$workflow = (Get-Content -Raw (Join-Path $templates 'deploy.yml')).Replace('__PROJECT__', $Project)
Write-LfFile (Join-Path $root '.github/workflows/deploy.yml') $workflow
Write-Output "Wrote   .github/workflows/deploy.yml (project: $Project)"

foreach ($file in 'start.sh', 'test.sh', 'post-deploy.sh') {
    $destination = Join-Path $root ".cicd/$file"
    if (Test-Path $destination) {
        Write-Output "Kept    .cicd/$file"
    } else {
        Write-LfFile $destination (Get-Content -Raw (Join-Path $templates $file))
        Write-Output "Created .cicd/$file"
    }
}

$attributes = Join-Path $root '.gitattributes'
if (-not ((Test-Path $attributes) -and (Get-Content $attributes) -contains '*.sh text eol=lf')) {
    Add-Content -Path $attributes -Value '*.sh text eol=lf' -Encoding ascii
    Write-Output 'Updated .gitattributes'
}

Write-Output @'

Next:
  1. Edit .cicd/start.sh so it starts your app on $PORT (and test.sh / post-deploy.sh if needed).
  2. git add .github .cicd .gitattributes
     git commit -m "Add CI/CD"
     git push origin main
  3. Watch the run in GitHub > Actions.
'@
