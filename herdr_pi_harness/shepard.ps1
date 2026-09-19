# shepard.ps1 - install the terminal agent stack on Windows: WezTerm + herdr + pi + pi-subagents.
# Run in PowerShell (not cmd):
#   powershell -ExecutionPolicy Bypass -File .\shepard.ps1
#   powershell -ExecutionPolicy Bypass -File .\shepard.ps1 -Check
#   powershell -ExecutionPolicy Bypass -File .\shepard.ps1 -NoWezterm
#   powershell -ExecutionPolicy Bypass -File .\shepard.ps1 -NoAuto     # print commands, install nothing automatically
# Safe to re-run: every step is skipped if already present.
# There is no Homebrew on Windows; winget (the built-in Windows package manager) is
# used instead for Node and WezTerm, and herdr uses its own install.ps1.
# NOTE: herdr on Windows is a preview/beta build. If it misbehaves, run this stack
# inside WSL2 with shepard.sh instead - that path is the well-tested one.
param([switch]$NoWezterm, [switch]$Check, [switch]$NoAuto)

$ErrorActionPreference = 'Stop'
$NodeMin = 22   # pi's package.json requires node >= 22.19

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }
function Say($m)  { Write-Host "`n== $m" -ForegroundColor White }
function Ok($m)   { Write-Host "   ok: $m" }
function Warn($m) { Write-Host "   !! $m" -ForegroundColor Yellow }

function Report {
  Say 'versions'
  foreach ($c in 'wezterm', 'herdr', 'node', 'npm', 'pi') {
    if (Have $c) { "   {0,-8} {1}" -f $c, (& $c --version 2>&1 | Select-Object -First 1) | Write-Host }
    else { "   {0,-8} MISSING" -f $c | Write-Host }
  }
  if (Have pi) { Write-Host '   pi packages:'; (pi list 2>&1) | ForEach-Object { "     $_" } }
}

if ($Check) { Report; exit 0 }

# ------------------------------------------------------------------ 1. winget
# FAILS IF: winget (App Installer) is missing. It ships with Windows 11 and recent
# Windows 10, but not on older builds or stripped images.
# FIX: install "App Installer" from the Microsoft Store
#      (https://apps.microsoft.com/detail/9nblggh4nns1), then reopen PowerShell.
#      Or install each tool by hand: WezTerm from https://wezterm.org/install/windows.html,
#      Node LTS from https://nodejs.org, herdr from https://herdr.dev/docs/install.
Say 'prerequisites'
if (-not (Have winget)) {
  # winget cannot be installed from a script: it ships as the Store app "App Installer".
  Warn 'winget is MISSING and cannot be auto-installed (it comes from the Microsoft Store).' 
  Warn 'winget not found. Install "App Installer" from the Microsoft Store, then reopen PowerShell.'
  Warn 'Manual alternative: wezterm.org/install/windows.html, nodejs.org, herdr.dev/docs/install'
  exit 1
}
Ok "winget $(winget --version)"

# ------------------------------------------------------------------- 2. node
# FAILS IF: node is missing or older than 20 (pi needs 20+).
# FIX (manual): winget install --id OpenJS.NodeJS.LTS -e     then open a NEW PowerShell
#      window so PATH refreshes. If node is installed but not found, add
#      C:\Program Files\nodejs to PATH.
if (-not (Have node)) {
  if ($NoAuto) { Warn 'node is MISSING. Run: winget install --id OpenJS.NodeJS.LTS -e'; exit 1 }
  Write-Host 'node is MISSING -> installing it now (pi needs node 22+; herdr and WezTerm do not).'
  Write-Host '  winget install --id OpenJS.NodeJS.LTS -e'
  winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
  # winget does not refresh PATH in the running shell; add the default location for this run.
  $nodeDir = 'C:\Program Files\nodejs'
  if (Test-Path $nodeDir) { $env:Path = "$nodeDir;$env:Path" }
  if (-not (Have node)) {
    Warn 'Node installed but not on PATH here. Close this window, open a new PowerShell, and re-run.'
    exit 0
  }
}
$nodeMajor = [int]((node -p 'process.versions.node.split(".")[0]'))
if ($nodeMajor -lt $NodeMin) {
  Warn "node $nodeMajor is too old; pi needs $NodeMin+. Run: winget upgrade --id OpenJS.NodeJS.LTS -e"
  exit 1
}
Ok "node $(node --version)"

# ---------------------------------------------------------------- 3. wezterm
# FAILS IF: the winget package id changed or the install is blocked by policy.
# FIX (manual): download the setup.exe from https://wezterm.org/install/windows.html,
#      or use scoop (scoop bucket add extras; scoop install wezterm).
#      WezTerm is optional - Windows Terminal works too; skip with -NoWezterm.
if (-not $NoWezterm) {
  Say 'wezterm (terminal)'
  if (Have wezterm) { Ok 'already installed' }
  elseif ($NoAuto) { Warn 'wezterm is MISSING. Run: winget install --id wez.wezterm -e' }
  else {
    Write-Host 'wezterm is MISSING -> installing it now.'
    try { winget install --id wez.wezterm -e --accept-package-agreements --accept-source-agreements; Ok 'installed' }
    catch { Warn "winget failed: $($_.Exception.Message)"; Warn 'Install manually: https://wezterm.org/install/windows.html' }
  }
}

# ------------------------------------------------------------------ 4. herdr
# FAILS IF: the installer is blocked by endpoint protection / SmartScreen, or the
# herdr binary does not land on PATH.
# FIX (manual): download the Windows binary from https://github.com/herdrdev/herdr/releases,
#      put herdr.exe in a folder on PATH, and reopen PowerShell. Windows support is
#      preview-grade; if it is unusable, use WSL2 + shepard.sh instead.
Say 'herdr (agent multiplexer, Windows preview)'
if (Have herdr) { Ok "already installed: $(herdr --version)" }
elseif ($NoAuto) { Warn 'herdr is MISSING. Run: irm https://herdr.dev/install.ps1 | iex' }
else {
  Write-Host 'herdr is MISSING -> installing it now (irm https://herdr.dev/install.ps1 | iex).'
  try { Invoke-RestMethod https://herdr.dev/install.ps1 | Invoke-Expression }
  catch { Warn "herdr install failed: $($_.Exception.Message)" }
}
if (-not (Have herdr)) {
  Warn 'herdr is not on PATH. Open a new PowerShell and re-run; if it still fails, grab the'
  Warn 'binary from https://github.com/herdrdev/herdr/releases and add it to PATH.'
}

# --------------------------------------------------------------------- 5. pi
# FAILS IF: npm global installs are blocked, or npm's global bin is not on PATH.
# FIX (manual): npm install -g @earendil-works/pi-coding-agent
#      then add the folder printed by `npm prefix -g` to PATH and reopen PowerShell.
Say 'pi (coding agent)'
if (Have pi) { Ok "already installed: $(pi --version)" }
else {
  Write-Host 'pi is MISSING -> npm install -g --ignore-scripts @earendil-works/pi-coding-agent'
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent
}
if (-not (Have pi)) {
  Warn "pi is not on PATH. Add this to PATH and reopen PowerShell: $(npm prefix -g)"
  exit 1
}

# ------------------------------------------------------------ 6. pi-subagents
# FAILS IF: the npm registry is unreachable, or pi cannot write ~/.pi/agent/settings.json.
# FIX (manual): pi install npm:pi-subagents
#      Check it landed with: pi list
Say 'pi-subagents (so pi can spawn subagents)'
if ((pi list 2>&1) -match 'npm:pi-subagents') { Ok 'already installed' }
else { pi install npm:pi-subagents }

# --------------------------------------------- 7. herdr <-> pi integration
# FAILS IF: herdr is missing (see step 4). Without this, herdr guesses pane status
# from screen output instead of reading pi's reported state.
# FIX (manual): herdr integration install pi
if (Have herdr) {
  Say 'herdr integration for pi'
  try { herdr integration install pi } catch { Warn "run 'herdr integration install pi' by hand" }
}

Report

Write-Host @'

Next:
  1. Open WezTerm (or Windows Terminal) and run:  herdr
  2. In a herdr pane:  cd <project>; pi
  3. First run only:  /login
  4. Ask pi for parallel work, e.g.
       "Use a background subagent to write tests for billing.py."
     Watch with /subagents-fleet; stop runs with /subagents-stop.

Windows notes:
  - Alt+Enter is fullscreen in Windows Terminal; remap it if you want pi's follow-up key.
  - herdr on Windows is preview-grade. If panes or session restore misbehave,
    install WSL2 (wsl --install) and run shepard.sh inside it.

Cost note: background subagents run in a detached process and can outlive pi.
Stop them before quitting; afterwards check with:
  Get-Process node | Where-Object { $_.Path } | Format-Table Id, StartTime, Path
'@