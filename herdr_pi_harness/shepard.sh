#!/usr/bin/env bash
# shepard.sh - install the terminal agent stack: WezTerm + herdr + pi + pi-subagents.
# macOS and Linux (including WSL2). On native Windows use shepard.ps1 instead.
# Safe to re-run: every step is skipped if already present.
# Every failure path below carries a comment saying what failed and how to fix it by hand.
#   bash shepard.sh              full install
#   bash shepard.sh --no-wezterm skip the terminal (keep your current one)
#   bash shepard.sh --check      report versions only, install nothing
set -euo pipefail

WEZTERM=1; CHECK=0
for a in "$@"; do
  case "$a" in
    --no-wezterm) WEZTERM=0 ;;
    --check) CHECK=1 ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { printf '   ok: %s\n' "$*"; }
warn() { printf '   !! %s\n' "$*"; }

OS="$(uname -s)"
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    # FAILS HERE: this is Git Bash / MSYS on native Windows. brew, apt and the herdr
    # shell installer do not apply, and npm's global bin lands elsewhere.
    # FIX: run the PowerShell version instead, in the same folder:
    #   powershell -ExecutionPolicy Bypass -File .\shepard.ps1
    # Or install WSL2 (wsl --install) and run this script inside it.
    echo "Native Windows detected (Git Bash/MSYS)."
    echo "Run:  powershell -ExecutionPolicy Bypass -File .\\shepard.ps1"
    echo "Or install WSL2 with 'wsl --install' and run this script inside WSL."
    exit 1 ;;
esac
NODE_MIN=20

report() {
  say "versions"
  for c in wezterm herdr node npm pi; do
    if have "$c"; then printf '   %-8s %s\n' "$c" "$("$c" --version 2>&1 | head -1)"
    else printf '   %-8s MISSING\n' "$c"; fi
  done
  if have pi; then
    printf '   pi packages:\n'
    pi list 2>/dev/null | sed 's/^/     /' || true
  fi
}

if [ "$CHECK" = 1 ]; then report; exit 0; fi

# ---------------------------------------------------------------- 1. prereqs
say "prerequisites"
if [ "$OS" = "Darwin" ]; then
  # FAILS IF: Homebrew is missing. Every macOS install step below uses it.
  # FIX (manual): run the install line printed here, then reopen the terminal so
  # /opt/homebrew/bin is on PATH (Apple Silicon) and re-run this script.
  # Or install by hand: WezTerm https://wezterm.org/install/macos.html,
  # herdr `curl -fsSL https://herdr.dev/install.sh | sh`, Node https://nodejs.org.
  if ! have brew; then
    echo "Homebrew is required. Install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  ok "homebrew $(brew --version | head -1)"
elif [ "$OS" != "Linux" ]; then
  # FAILS IF: some other kernel (BSD, Solaris). herdr ships Linux, macOS and a Windows
  # preview only, so there is no supported path here.
  # FIX: none - use macOS, Linux, WSL2, or native Windows with shepard.ps1.
  echo "This script supports macOS and Linux only (herdr requires one of them)."; exit 1
fi

# FAILS IF: node is missing on Linux (no single correct package manager to guess).
# FIX (manual), pick one:
#   Debian/Ubuntu: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs
#   Fedora:        sudo dnf install -y nodejs
#   Arch:          sudo pacman -S nodejs npm
#   any distro:    install nvm (https://github.com/nvm-sh/nvm), then: nvm install 22
# Then re-run this script.
if ! have node; then
  if [ "$OS" = "Darwin" ]; then brew install node; else
    echo "Install Node $NODE_MIN+ with your package manager, then re-run."
    echo "  Debian/Ubuntu: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"
    echo "  Fedora: sudo dnf install -y nodejs   |   Arch: sudo pacman -S nodejs npm"
    echo "  Or nvm: https://github.com/nvm-sh/nvm  then: nvm install 22"
    exit 1
  fi
fi
# FAILS IF: node is older than 20, which pi requires.
# FIX (manual): macOS `brew upgrade node`; Linux `nvm install 22 && nvm use 22`,
# or reinstall from your distro's current nodejs package. Then re-run.
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt "$NODE_MIN" ]; then
  warn "node $NODE_MAJOR is too old; pi needs $NODE_MIN+."
  if [ "$OS" = "Darwin" ]; then brew upgrade node
  else echo "Upgrade node (nvm install 22, or your distro's nodejs package) and re-run."; exit 1; fi
fi
ok "node $(node --version)"

# ------------------------------------------------------------- 2. terminal
if [ "$WEZTERM" = 1 ]; then
  say "wezterm (terminal)"
  # FAILS IF: on Linux there is no one packaging path for WezTerm (AppImage, flatpak,
  # distro package). WezTerm is optional; any terminal runs herdr.
  # FIX (manual): https://wezterm.org/install/linux.html, e.g.
  #   flatpak install flathub org.wezfurlong.wezterm
  # or just skip it and re-run with --no-wezterm.
  if have wezterm || [ -d "/Applications/WezTerm.app" ]; then ok "already installed"
  elif [ "$OS" = "Darwin" ]; then brew install --cask wezterm; ok "installed"
  else warn "install WezTerm from https://wezterm.org/install/linux.html (or keep your terminal) - skipping"; fi
fi

# --------------------------------------------------------- 3. herdr (muxer)
say "herdr (agent multiplexer)"
if have herdr; then ok "already installed: $(herdr --version 2>&1 | head -1)"
elif [ "$OS" = "Darwin" ]; then brew install herdr
else curl -fsSL https://herdr.dev/install.sh | sh; fi
# FAILS IF: the installer ran but herdr is not on PATH (its bin dir, usually
# ~/.local/bin, is not in PATH), or the download was blocked.
# FIX (manual): export PATH="$HOME/.local/bin:$PATH" in ~/.zshrc, or download the
# binary from https://github.com/herdrdev/herdr/releases and put it on PATH.
# Nothing else in this script depends on herdr except step 6.
have herdr || { warn "herdr not on PATH; add \$HOME/.local/bin to PATH (or see https://herdr.dev/docs/install), open a new shell and re-run"; exit 1; }

# ------------------------------------------------------------ 4. pi (agent)
say "pi (coding agent)"
if have pi; then ok "already installed: $(pi --version 2>&1 | head -1)"
else npm install -g @earendil-works/pi-coding-agent; fi
# FAILS IF: npm installed pi but its global bin dir is not on PATH, or the global
# install needed root (a system node install).
# FIX (manual): add npm's global bin to PATH:
#   echo 'export PATH="$(npm prefix -g)/bin:$PATH"' >> ~/.zshrc && exec zsh
# If npm refused with EACCES, do not use sudo; point npm at a user prefix:
#   npm config set prefix ~/.npm-global   then re-run this script.
have pi || { warn "pi not on PATH. Add npm's global bin: export PATH=\"\$(npm prefix -g)/bin:\$PATH\""; exit 1; }

# ------------------------------------------------- 5. pi-subagents package
say "pi-subagents (so pi can spawn subagents)"
if pi list 2>/dev/null | grep -q "npm:pi-subagents"; then ok "already installed"
else pi install npm:pi-subagents; fi

# --------------------------------------------- 6. herdr <-> pi integration
say "herdr integration for pi (accurate pane status)"
# FAILS IF: herdr is missing or its integration subcommand changed. Consequence is
# cosmetic-ish: herdr guesses pane status from screen output instead of reading pi's
# reported state, so "blocked/working/done" gets less reliable.
# FIX (manual): herdr integration install pi     (see https://herdr.dev/docs/integrations)
if have herdr; then
  herdr integration install pi || warn "integration install failed; run 'herdr integration install pi' by hand"
else
  warn "herdr missing, skipping integration"
fi

report

cat <<'EOF'

Next:
  1. Open WezTerm (or your terminal) and run:  herdr
     Start herdr from a normal shell, not from launchd/brew services:
     under launchd it gets a stripped PATH with no node and spawned pi panes die silently.
  2. In a herdr pane:  cd <project> && pi
  3. First run only:  /login   (pick your provider)
  4. Ask pi for work in parallel, e.g.
       "Use a background subagent to write tests for billing.py."
     Watch them in FleetView / /subagents-fleet; stop them with /subagents-stop.

Cost note: background subagents run in a detached process and can outlive pi.
Stop them before quitting, and check afterwards with:
  ps -axo pid,etime,command | grep -iE 'pi-subagents|herdr' | grep -v grep
EOF