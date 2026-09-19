#!/usr/bin/env bash
# shepard.sh - install the terminal agent stack: WezTerm + herdr + pi + pi-subagents.
# Safe to re-run: every step is skipped if already present.
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
  if ! have brew; then
    echo "Homebrew is required. Install it first:"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    exit 1
  fi
  ok "homebrew $(brew --version | head -1)"
elif [ "$OS" != "Linux" ]; then
  echo "This script supports macOS and Linux only (herdr requires one of them)."; exit 1
fi

if ! have node; then
  if [ "$OS" = "Darwin" ]; then brew install node; else
    echo "Install Node $NODE_MIN+ with your package manager, then re-run."; exit 1
  fi
fi
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [ "$NODE_MAJOR" -lt "$NODE_MIN" ]; then
  warn "node $NODE_MAJOR is too old; pi needs $NODE_MIN+."
  [ "$OS" = "Darwin" ] && brew upgrade node || { echo "Upgrade node and re-run."; exit 1; }
fi
ok "node $(node --version)"

# ------------------------------------------------------------- 2. terminal
if [ "$WEZTERM" = 1 ]; then
  say "wezterm (terminal)"
  if have wezterm || [ -d "/Applications/WezTerm.app" ]; then ok "already installed"
  elif [ "$OS" = "Darwin" ]; then brew install --cask wezterm; ok "installed"
  else warn "install WezTerm from https://wezterm.org (or keep your terminal) - skipping"; fi
fi

# --------------------------------------------------------- 3. herdr (muxer)
say "herdr (agent multiplexer)"
if have herdr; then ok "already installed: $(herdr --version 2>&1 | head -1)"
elif [ "$OS" = "Darwin" ]; then brew install herdr
else curl -fsSL https://herdr.dev/install.sh | sh; fi
have herdr || { warn "herdr not on PATH; open a new shell and re-run"; exit 1; }

# ------------------------------------------------------------ 4. pi (agent)
say "pi (coding agent)"
if have pi; then ok "already installed: $(pi --version 2>&1 | head -1)"
else npm install -g @earendil-works/pi-coding-agent; fi
have pi || { warn "pi not on PATH. Add npm's global bin: export PATH=\"\$(npm prefix -g)/bin:\$PATH\""; exit 1; }

# ------------------------------------------------- 5. pi-subagents package
say "pi-subagents (so pi can spawn subagents)"
if pi list 2>/dev/null | grep -q "npm:pi-subagents"; then ok "already installed"
else pi install npm:pi-subagents; fi

# --------------------------------------------- 6. herdr <-> pi integration
say "herdr integration for pi (accurate pane status)"
herdr integration install pi || warn "integration install failed; run 'herdr integration install pi' by hand"

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