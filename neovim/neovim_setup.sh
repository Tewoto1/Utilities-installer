#!/usr/bin/env bash
#
# TerminalEditor.sh — Neovim as a LaTeX editor with VSCode-style IDE features.
#
# ============================================================================
# SUPPORTED PLATFORMS
# ============================================================================
#   macOS            Homebrew        ~/.config/nvim
#   Windows          winget          %LOCALAPPDATA%\nvim
#                    Run from Git Bash or MSYS2, NOT from cmd.exe/PowerShell.
#                    Git Bash ships with Git for Windows:
#                      winget install --id Git.Git -e
#   Arch / WSL-Arch  pacman          ~/.config/nvim
#   Debian / Ubuntu  apt             ~/.config/nvim
#
# ============================================================================
# FLAGS
# ============================================================================
#   --dry-run       print every command, change nothing
#   --config-only   skip package installs, write config only
#   --no-tex        skip the TeX distribution (it is a multi-GB download)
#   --check         run prerequisite checks only, then exit
#   --uninstall     print removal commands (prints only, runs nothing)
#
# ============================================================================
# PREREQUISITE FAILURE MODES — see fix_hint() for the runtime text.
# Every check below is also documented inline at its call site.
# ============================================================================
#
#   MISSING: brew (macOS)          HARD FAIL. Nothing else can proceed.
#     Fix:  /bin/bash -c "$(curl -fsSL \
#             https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
#           Then follow the "Next steps" it prints to add brew to PATH.
#           Apple Silicon installs to /opt/homebrew, Intel to /usr/local.
#
#   MISSING: winget (Windows)      HARD FAIL. Ships as "App Installer".
#     Fix:  Install "App Installer" from the Microsoft Store, or grab
#           Microsoft.DesktopAppInstaller from
#           https://github.com/microsoft/winget-cli/releases
#           Verify with: winget --version
#           Note: winget requires Windows 10 1809+ or Windows 11.
#
#   MISSING: git                   HARD FAIL. lazy.nvim clones plugins over git.
#     Fix:  macOS    brew install git   (or: xcode-select --install)
#           Windows  winget install --id Git.Git -e
#           Arch     sudo pacman -S git
#           Debian   sudo apt install git
#
#   MISSING: curl                  HARD FAIL. Used to fetch release tarballs.
#     Fix:  macOS    preinstalled; if absent: brew install curl
#           Windows  preinstalled on Win10 1803+; else winget install cURL.cURL
#           Arch     sudo pacman -S curl
#           Debian   sudo apt install curl
#
#   MISSING: C compiler + make     SOFT FAIL. Without these, two things break:
#                                  nvim-treesitter cannot compile parsers, and
#                                  LuaSnip's jsregexp (needed by regex-trigger
#                                  snippets like x1 -> x_{1}) will not build.
#                                  Everything else still works.
#     Fix:  macOS    xcode-select --install
#           Windows  winget install --id MSYS2.MSYS2 -e
#                    then in the MSYS2 shell:
#                      pacman -S mingw-w64-ucrt-x86_64-gcc make
#                    and add C:\msys64\ucrt64\bin to PATH.
#                    Alternative: winget install --id Microsoft.VisualStudio \
#                      .2022.BuildTools -e   (then enable "C++ build tools")
#           Arch     sudo pacman -S base-devel
#           Debian   sudo apt install build-essential
#
#   MISSING: nvim >= 0.11          HARD FAIL. This config calls vim.lsp.config()
#                                  and vim.lsp.enable(), added in 0.11. On 0.10
#                                  and earlier nvim starts but LSP never
#                                  attaches, with no obvious error.
#     Fix:  macOS    brew install neovim
#           Windows  winget install --id Neovim.Neovim -e
#           Arch     sudo pacman -S neovim
#           Debian   apt's version lags badly. Use the official tarball:
#                      curl -fLO https://github.com/neovim/neovim/releases/\
#                        latest/download/nvim-linux-x86_64.tar.gz
#                      tar xzf nvim-linux-x86_64.tar.gz
#                      mv nvim-linux-x86_64 ~/.local/nvim
#                      export PATH="$HOME/.local/nvim/bin:$PATH"
#                    This script does that automatically on Debian.
#
#   MISSING: latexmk               SOFT FAIL. VimTeX's compiler backend. Without
#                                  it, editing/LSP work but ,ll does nothing.
#     Fix:  macOS    brew install --cask mactex-no-gui      (~5GB)
#                    then: eval "$(/usr/libexec/path_helper)"
#                    Binaries live in /Library/TeX/texbin.
#           Windows  winget install --id MiKTeX.MiKTeX -e
#                    MiKTeX bundles latexmk. It needs Perl; MiKTeX ships one,
#                    but if latexmk still errors "perl not found":
#                      winget install --id StrawberryPerl.StrawberryPerl -e
#                    Open a NEW shell afterward so PATH refreshes.
#           Arch     sudo pacman -S texlive-basic texlive-binextra
#                    (texlive-binextra is the package that contains latexmk;
#                     texlive-basic alone does NOT include it)
#           Debian   sudo apt install latexmk texlive-latex-recommended
#
#   MISSING: texlab                SOFT FAIL. LaTeX LSP: diagnostics, hover on
#                                  \cite, goto-def on \ref. VimTeX compilation
#                                  and all snippets work without it.
#     Fix:  macOS    brew install texlab
#           Arch     sudo pacman -S texlab
#           Windows  NOT on winget. No official package manager entry.
#           Debian   NOT in apt.
#                    For both: download a precompiled binary from
#                      https://github.com/latex-lsp/texlab/releases
#                    (assets cover Windows, Linux and macOS) and put it on PATH.
#                    This script fetches the right asset automatically.
#                    Building from source instead:
#                      cargo install --git https://github.com/latex-lsp/texlab \
#                        --locked --tag v5.26.0
#                    Do NOT use `cargo install texlab` — upstream stopped
#                    publishing to crates.io, so that installs a stale version.
#                    On Windows texlab may also need the MSVC 2015
#                    redistributable: winget install --id \
#                      Microsoft.VCRedist.2015+.x64 -e
#
#   MISSING: ripgrep / fd          SOFT FAIL. Telescope's live_grep falls back
#                                  to a much slower path; find_files still works.
#     Fix:  macOS    brew install ripgrep fd
#           Windows  winget install --id BurntSushi.ripgrep.MSVC -e
#                    winget install --id sharkdp.fd -e
#           Arch     sudo pacman -S ripgrep fd
#           Debian   sudo apt install ripgrep fd-find
#                    (Debian names the binary `fdfind`; symlink it:
#                     ln -s "$(which fdfind)" ~/.local/bin/fd)
#
#   MISSING: PDF viewer            SOFT FAIL. No forward/inverse search. The
#                                  PDF still builds; open it however you like.
#     Fix:  macOS    brew install --cask skim
#           Windows  winget install --id SumatraPDF.SumatraPDF -e
#           Linux    sudo pacman -S zathura zathura-pdf-mupdf
#                    sudo apt install zathura
#
# ============================================================================

set -euo pipefail

DRY_RUN=0
CONFIG_ONLY=0
WANT_TEX=1
CHECK_ONLY=0
UNINSTALL=0

TEXLAB_TAG="v5.26.0"   # pinned; bump deliberately, not automatically

# ------------------------------------------------------------------ arg parse

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    --no-tex)      WANT_TEX=0 ;;
    --check)       CHECK_ONLY=1 ;;
    --uninstall)   UNINSTALL=1 ;;
    -h|--help)     sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------- plumbing

if [ -t 1 ]; then
  c_bold=$'\033[1m';  c_red=$'\033[31m';   c_yellow=$'\033[33m'
  c_green=$'\033[32m'; c_dim=$'\033[2m';   c_off=$'\033[0m'
else
  c_bold=""; c_red=""; c_yellow=""; c_green=""; c_dim=""; c_off=""
fi

say()  { printf '%s==>%s %s\n' "$c_bold" "$c_off" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
ok()   { printf '%s  ok  %s %s\n' "$c_green" "$c_off" "$*"; }
die()  { printf '%s[fatal]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  $ %s%s\n' "$c_dim" "$*" "$c_off"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

SOFT_FAILURES=""

# --------------------------------------------------------- platform detection

PLATFORM=""; PKG=""; SUDO="sudo"

detect_platform() {
  case "$(uname -s)" in
    Darwin) PLATFORM="macos"; PKG="brew" ;;
    MINGW*|MSYS*|CYGWIN*)
      # Native Windows under Git Bash / MSYS2. No sudo; winget elevates itself.
      PLATFORM="windows"; PKG="winget"; SUDO=""
      ;;
    Linux)
      if [ ! -r /etc/os-release ]; then
        die "cannot read /etc/os-release — unrecognised Linux. Install the package list by hand (see the header of this file), then rerun with --config-only."
      fi
      # shellcheck disable=SC1091
      . /etc/os-release
      case "${ID:-}${ID_LIKE:-}" in
        *arch*)            PLATFORM="arch";   PKG="pacman" ;;
        *debian*|*ubuntu*) PLATFORM="debian"; PKG="apt" ;;
        *) die "unsupported distro '${ID:-unknown}'. Install the package list from this file's header by hand, then rerun with --config-only." ;;
      esac
      ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac

  if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    say "running under WSL (${WSL_DISTRO_NAME})"
  fi
}

# ------------------------------------------------------------- config paths
# Windows Neovim reads %LOCALAPPDATA%\nvim, not ~/.config/nvim. Under Git Bash
# $LOCALAPPDATA is a Windows-style path, so convert it with cygpath.

set_paths() {
  if [ "$PLATFORM" = "windows" ]; then
    local base
    if have cygpath && [ -n "${LOCALAPPDATA:-}" ]; then
      base="$(cygpath -u "$LOCALAPPDATA")"
    else
      base="${HOME}/AppData/Local"
      warn "cygpath or \$LOCALAPPDATA unavailable; assuming ${base}"
    fi
    NVIM_CONFIG="${base}/nvim"
    NVIM_DATA="${base}/nvim-data"
    NVIM_STATE="${base}/nvim-data"
    NVIM_CACHE="${base}/Temp/nvim"
  else
    NVIM_CONFIG="${HOME}/.config/nvim"
    NVIM_DATA="${HOME}/.local/share/nvim"
    NVIM_STATE="${HOME}/.local/state/nvim"
    NVIM_CACHE="${HOME}/.cache/nvim"
  fi
}

# =========================================================================
# fix_hint <tool> — verified, per-platform remediation. Printed in full on
# any prerequisite failure, so the user never has to go looking. Mirrors the
# header block above; keep the two in sync when editing.
# =========================================================================

fix_hint() {
  local tool="$1"
  printf '\n  %sHow to install %s on %s:%s\n' "$c_bold" "$tool" "$PLATFORM" "$c_off"
  case "${tool}:${PLATFORM}" in

    brew:macos)
      cat <<'H'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  Then run the "Next steps" commands it prints — they add brew to PATH.
  Apple Silicon installs under /opt/homebrew, Intel under /usr/local.
  Verify with:  brew --version
H
      ;;

    winget:windows)
      cat <<'H'
  winget ships as the "App Installer" package.

    1. Install "App Installer" from the Microsoft Store, or download
       Microsoft.DesktopAppInstaller from
       https://github.com/microsoft/winget-cli/releases
    2. Open a NEW shell and check:  winget --version

  Requires Windows 10 1809+ or Windows 11. If you are on an older build,
  use WSL2 instead:  wsl --install -d archlinux
  then run this script inside it.
H
      ;;

    git:macos)   echo "    brew install git          # or: xcode-select --install" ;;
    git:windows) echo "    winget install --id Git.Git -e" ;;
    git:arch)    echo "    sudo pacman -S git" ;;
    git:debian)  echo "    sudo apt install git" ;;

    curl:macos)   echo "    brew install curl         # normally preinstalled" ;;
    curl:windows) echo "    winget install --id cURL.cURL -e   # preinstalled on Win10 1803+" ;;
    curl:arch)    echo "    sudo pacman -S curl" ;;
    curl:debian)  echo "    sudo apt install curl" ;;

    compiler:macos) cat <<'H'
    xcode-select --install

  Needed by: nvim-treesitter parser compilation, and LuaSnip's jsregexp
  (which powers regex-trigger snippets like x1 -> x_{1}).
H
      ;;
    compiler:windows) cat <<'H'
    winget install --id MSYS2.MSYS2 -e

  Then in the MSYS2 shell:
    pacman -S mingw-w64-ucrt-x86_64-gcc make
  and add C:\msys64\ucrt64\bin to your PATH.

  Alternative (heavier, but integrates with Visual Studio):
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e
  then enable the "Desktop development with C++" workload.

  Needed by: nvim-treesitter parser compilation, and LuaSnip's jsregexp
  (which powers regex-trigger snippets like x1 -> x_{1}).
  Without it, nvim still runs — those two features degrade.
H
      ;;
    compiler:arch)   echo "    sudo pacman -S base-devel" ;;
    compiler:debian) echo "    sudo apt install build-essential" ;;

    nvim:macos)   echo "    brew install neovim" ;;
    nvim:windows) echo "    winget install --id Neovim.Neovim -e" ;;
    nvim:arch)    echo "    sudo pacman -S neovim" ;;
    nvim:debian)  cat <<'H'
  apt's neovim is usually too old (this config needs 0.11+). Use the tarball:

    curl -fLO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    tar xzf nvim-linux-x86_64.tar.gz
    mv nvim-linux-x86_64 ~/.local/nvim
    rm nvim-linux-x86_64.tar.gz

  Then add to ~/.bashrc:
    export PATH="$HOME/.local/nvim/bin:$PATH"
H
      ;;

    latexmk:macos) cat <<'H'
    brew install --cask mactex-no-gui        # ~5GB download

  Then make the binaries visible to your shell:
    eval "$(/usr/libexec/path_helper)"
  Add that line to ~/.zshrc to make it stick. Binaries: /Library/TeX/texbin
H
      ;;
    latexmk:windows) cat <<'H'
    winget install --id MiKTeX.MiKTeX -e

  MiKTeX bundles latexmk and installs missing LaTeX packages on demand.
  Open a NEW shell afterward so PATH refreshes.

  latexmk is a Perl script. MiKTeX ships a Perl, but if you still see
  "perl not found":
    winget install --id StrawberryPerl.StrawberryPerl -e
H
      ;;
    latexmk:arch) cat <<'H'
    sudo pacman -S texlive-basic texlive-binextra

  Note: latexmk lives in texlive-binextra, NOT texlive-basic. Installing
  only texlive-basic is the usual reason latexmk is missing on Arch.
H
      ;;
    latexmk:debian) echo "    sudo apt install latexmk texlive-latex-recommended" ;;

    texlab:macos) echo "    brew install texlab" ;;
    texlab:arch)  echo "    sudo pacman -S texlab" ;;
    texlab:windows|texlab:debian) cat <<H
  texlab is not on winget and not in apt. Two options.

  1. Precompiled binary (recommended) — pick your platform's asset from
       https://github.com/latex-lsp/texlab/releases
     and put it somewhere on PATH. This script does that for you; if it
     failed, the release page has the full asset list.

  2. Build from source (needs Rust from https://rustup.rs):
       cargo install --git https://github.com/latex-lsp/texlab --locked --tag ${TEXLAB_TAG}

  Do NOT run \`cargo install texlab\`. Upstream stopped publishing to
  crates.io, so that command installs a stale version.

  On Windows texlab may also need the MSVC 2015 redistributable:
    winget install --id Microsoft.VCRedist.2015+.x64 -e

  texlab is optional: it provides diagnostics, hover on \\cite and
  goto-definition on \\ref. Compilation and snippets work without it.
H
      ;;

    ripgrep:macos)   echo "    brew install ripgrep fd" ;;
    ripgrep:windows) cat <<'H'
    winget install --id BurntSushi.ripgrep.MSVC -e
    winget install --id sharkdp.fd -e
H
      ;;
    ripgrep:arch)    echo "    sudo pacman -S ripgrep fd" ;;
    ripgrep:debian)  cat <<'H'
    sudo apt install ripgrep fd-find

  Debian installs the fd binary as `fdfind`. Symlink it so plugins find it:
    mkdir -p ~/.local/bin
    ln -s "$(command -v fdfind)" ~/.local/bin/fd
H
      ;;

    viewer:macos)   echo "    brew install --cask skim" ;;
    viewer:windows) echo "    winget install --id SumatraPDF.SumatraPDF -e" ;;
    viewer:arch)    echo "    sudo pacman -S zathura zathura-pdf-mupdf" ;;
    viewer:debian)  echo "    sudo apt install zathura zathura-pdf-poppler" ;;

    *) echo "    (no recorded instructions for ${tool} on ${PLATFORM})" ;;
  esac
  echo
}

# require_hard <tool> <label> [hint_key] — abort with instructions.
# hint_key defaults to <tool>; pass it when the binary name and the fix_hint
# registry key differ (binary `rg` vs key `ripgrep`).
require_hard() {
  if have "$1"; then ok "$2 -> $(command -v "$1")"; return 0; fi
  printf '%s[fatal]%s %s is required and was not found.\n' "$c_red" "$c_off" "$2" >&2
  fix_hint "${3:-$1}"
  exit 1
}

# require_soft <tool> <label> <consequence> [hint_key] — warn, record, continue
require_soft() {
  if have "$1"; then ok "$2 -> $(command -v "$1")"; return 0; fi
  printf '%s[warn]%s %s not found — %s\n' "$c_yellow" "$c_off" "$2" "$3" >&2
  fix_hint "${4:-$1}"
  SOFT_FAILURES="${SOFT_FAILURES}${2}
"
  return 0
}

# ---------------------------------------------------------------- uninstaller

do_uninstall() {
  cat <<UNINST

Nothing has been removed. Run these yourself, in order.

  rm -rf ${NVIM_CONFIG}
  rm -rf ${NVIM_DATA}
  rm -rf ${NVIM_STATE}
  rm -rf ${NVIM_CACHE}

Those four hold, respectively: your config, downloaded plugins, shada and
undo history, and compiled treesitter parsers. Clear them together — deleting
only the config leaves a stale plugin tree that half-loads on next start.

UNINST
  case "$PLATFORM" in
    macos) cat <<'U'
  brew uninstall neovim texlab ripgrep fd
  brew uninstall --cask skim mactex-no-gui

  # MacTeX leaves these behind
  rm -rf /usr/local/texlive
  rm -rf ~/Library/texlive
  rm -rf /Library/TeX
U
    ;;
    windows) cat <<'U'
  winget uninstall --id Neovim.Neovim
  winget uninstall --id MiKTeX.MiKTeX
  winget uninstall --id SumatraPDF.SumatraPDF
  winget uninstall --id BurntSushi.ripgrep.MSVC
  winget uninstall --id sharkdp.fd

  # texlab was installed by hand, so remove it by hand:
  rm -f ~/bin/texlab.exe
U
    ;;
    arch) echo "  sudo pacman -Rns neovim texlab ripgrep fd zathura zathura-pdf-mupdf texlive-basic texlive-binextra texlive-latexextra texlive-mathscience texlive-fontsrecommended biber" ;;
    debian) cat <<'U'
  sudo apt purge neovim ripgrep fd-find zathura latexmk \
    texlive-latex-recommended texlive-latex-extra texlive-science biber
  sudo apt autoremove

  # if the tarball path was used:
  rm -rf ~/.local/nvim
  rm -f  ~/.local/bin/texlab
U
    ;;
  esac
  echo
}

# ------------------------------------------------------- texlab binary fetch
# Windows and Debian have no packaged texlab. Pull the release asset that
# matches this machine. If anything here fails it is a SOFT failure: texlab is
# optional, so we warn with instructions and carry on.

fetch_texlab() {
  local dest="$1" asset="" os="" arch="" url="" tmp=""
  case "$PLATFORM" in
    windows) os="windows" ;;
    *)       os="linux" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) warn "unknown architecture $(uname -m); cannot pick a texlab asset"
       fix_hint texlab; return 1 ;;
  esac

  # Asset names follow a fixed scheme: texlab-<arch>-<os>.{tar.gz,zip}.
  # Building the URL directly avoids the GitHub API, which rate-limits
  # unauthenticated callers to 60 requests/hour per IP and returns 403 —
  # a confusing failure if you happen to be behind a busy NAT.
  case "$os" in
    windows) asset="texlab-${arch}-windows.zip" ;;
    *)       asset="texlab-${arch}-${os}.tar.gz" ;;
  esac
  url="https://github.com/latex-lsp/texlab/releases/download/${TEXLAB_TAG}/${asset}"

  say "fetching ${asset} (${TEXLAB_TAG})"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  $ curl -fsSL %s | extract to %s%s\n' "$c_dim" "$url" "$dest" "$c_off"
    return 0
  fi

  # Confirm the asset exists before committing to a download, so a renamed
  # or missing asset produces a clear message instead of a broken archive.
  if ! curl -sIL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null | grep -q '^200$'; then
    warn "texlab asset not found: ${url}"
    warn "the release page lists every asset: https://github.com/latex-lsp/texlab/releases"
    fix_hint texlab
    SOFT_FAILURES="${SOFT_FAILURES}texlab
"
    return 1
  fi

  tmp=$(mktemp -d)
  mkdir -p "$dest"
  if ! curl -fsSL -o "${tmp}/texlab.archive" "$url"; then
    warn "download failed: $url"
    fix_hint texlab
    rm -rf "$tmp"
    SOFT_FAILURES="${SOFT_FAILURES}texlab
"
    return 1
  fi

  case "$url" in
    *.zip)    (cd "$tmp" && unzip -oq texlab.archive) ;;
    *.tar.gz) (cd "$tmp" && tar xzf texlab.archive) ;;
    *)        warn "unrecognised archive type: $url"; rm -rf "$tmp"; return 1 ;;
  esac

  if [ -f "${tmp}/texlab.exe" ]; then
    mv "${tmp}/texlab.exe" "${dest}/texlab.exe"
  elif [ -f "${tmp}/texlab" ]; then
    mv "${tmp}/texlab" "${dest}/texlab"
    chmod +x "${dest}/texlab"
  else
    warn "archive did not contain a texlab binary"
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"

  ok "texlab installed to ${dest}"
  case ":${PATH}:" in
    *":${dest}:"*) ;;
    *) warn "${dest} is not on PATH. Add it:  export PATH=\"${dest}:\$PATH\"" ;;
  esac
}

# --------------------------------------------------------- package installers

install_macos() {
  # HARD: Homebrew. Every other macOS step goes through it.
  require_hard brew "homebrew"

  say "installing formulae"
  for f in neovim ripgrep fd git texlab; do
    if brew list --formula "$f" >/dev/null 2>&1; then
      ok "$f already installed, skipping"
    else
      run brew install "$f"
    fi
  done

  # SOFT: Skim. Only forward/inverse search depends on it.
  if [ -d "/Applications/Skim.app" ]; then
    ok "Skim already installed, skipping"
  else
    run brew install --cask skim
  fi

  # SOFT: TeX. Large; --no-tex skips it deliberately.
  if [ "$WANT_TEX" -eq 1 ]; then
    if have latexmk; then
      ok "latexmk already on PATH, skipping TeX install"
    else
      say "installing MacTeX (no GUI) — ~5GB"
      run brew install --cask mactex-no-gui
      warn "add TeX to PATH in a new shell:  eval \"\$(/usr/libexec/path_helper)\""
    fi
  fi

  # SOFT: command line tools. treesitter + jsregexp need a compiler.
  if ! xcode-select -p >/dev/null 2>&1; then
    warn "Xcode command line tools missing — treesitter parsers and LuaSnip's jsregexp will not compile"
    fix_hint compiler
    SOFT_FAILURES="${SOFT_FAILURES}xcode command line tools
"
  fi
}

install_windows() {
  # HARD: winget. Nothing installs without it.
  require_hard winget "winget"

  local wg="winget install --disable-interactivity --accept-package-agreements --accept-source-agreements -e --id"

  say "installing via winget"
  # shellcheck disable=SC2086
  for id in Git.Git Neovim.Neovim SumatraPDF.SumatraPDF BurntSushi.ripgrep.MSVC sharkdp.fd; do
    run $wg "$id" || warn "winget failed for ${id} (may already be installed)"
  done

  # SOFT: MiKTeX. Bundles latexmk; needs a new shell for PATH.
  if [ "$WANT_TEX" -eq 1 ]; then
    if have latexmk; then
      ok "latexmk already on PATH, skipping MiKTeX"
    else
      # shellcheck disable=SC2086
      run $wg MiKTeX.MiKTeX || warn "MiKTeX install failed"
      warn "open a NEW shell so PATH picks up MiKTeX before running latexmk"
    fi
  fi

  # SOFT: texlab — no winget package exists, so fetch the release binary.
  if have texlab; then
    ok "texlab already on PATH"
  else
    fetch_texlab "${HOME}/bin" || true
  fi

  # SOFT: compiler. No good winget one-liner that also lands on PATH, so
  # this only ever warns with instructions.
  if ! have cc && ! have gcc && ! have clang; then
    warn "no C compiler found — treesitter parsers and LuaSnip's jsregexp will not build"
    fix_hint compiler
    SOFT_FAILURES="${SOFT_FAILURES}C compiler
"
  fi
}

install_arch() {
  local pkgs="neovim texlab ripgrep fd git base-devel zathura zathura-pdf-mupdf unzip"
  # texlive-binextra is what actually contains latexmk. texlive-basic alone
  # does not, which is the usual cause of "latexmk: command not found" on Arch.
  if [ "$WANT_TEX" -eq 1 ]; then
    pkgs="$pkgs texlive-basic texlive-binextra texlive-latexextra texlive-mathscience texlive-fontsrecommended biber"
  fi
  say "installing via pacman"
  printf '%s  %s%s\n' "$c_dim" "$pkgs" "$c_off"
  # shellcheck disable=SC2086
  run $SUDO pacman -S --needed $pkgs
}

install_debian() {
  local pkgs="ripgrep fd-find git build-essential zathura curl unzip"
  if [ "$WANT_TEX" -eq 1 ]; then
    pkgs="$pkgs latexmk texlive-latex-recommended texlive-latex-extra texlive-science texlive-fonts-recommended biber"
  fi
  say "installing via apt"
  run $SUDO apt update
  # shellcheck disable=SC2086
  run $SUDO apt install -y $pkgs

  # HARD-ish: apt's neovim lags. Install the official tarball if too old.
  # Refuses to clobber an existing ~/.local/nvim; prints the rm to run.
  if have nvim && nvim --version | head -1 | grep -qE 'v0\.(1[1-9]|[2-9][0-9])|v[1-9]\.'; then
    ok "neovim new enough"
  else
    warn "apt's neovim is older than 0.11; installing the official tarball"
    if [ -e "${HOME}/.local/nvim" ]; then
      die "${HOME}/.local/nvim exists. Remove it yourself first:  rm -rf ~/.local/nvim"
    fi
    run mkdir -p "${HOME}/.local"
    run curl -fLo /tmp/nvim-linux.tar.gz \
      https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    run tar xzf /tmp/nvim-linux.tar.gz -C /tmp
    run mv /tmp/nvim-linux-x86_64 "${HOME}/.local/nvim"
    run rm -f /tmp/nvim-linux.tar.gz
    warn "add to ~/.bashrc:  export PATH=\"\$HOME/.local/nvim/bin:\$PATH\""
  fi

  # SOFT: texlab is not in apt. Fetch the release binary.
  if have texlab; then
    ok "texlab already on PATH"
  else
    fetch_texlab "${HOME}/.local/bin" || true
  fi

  # SOFT: Debian names fd's binary fdfind. Plugins look for `fd`.
  if have fdfind && ! have fd; then
    warn "Debian installs fd as 'fdfind'. Symlinking to ~/.local/bin/fd"
    run mkdir -p "${HOME}/.local/bin"
    run ln -sf "$(command -v fdfind)" "${HOME}/.local/bin/fd"
  fi
}

# -------------------------------------------------------------- config guard

check_existing_config() {
  [ -e "$NVIM_CONFIG" ] || return 0
  warn "${NVIM_CONFIG} already exists — not touching it."
  cat <<EXISTING

  For a clean install, remove the old tree yourself first:

    rm -rf ${NVIM_CONFIG}
    rm -rf ${NVIM_DATA}
    rm -rf ${NVIM_STATE}
    rm -rf ${NVIM_CACHE}

  Then rerun this script.

EXISTING
  exit 1
}

# ------------------------------------------------------------ config writing

write_config() {
  local viewer_block
  case "$PLATFORM" in
    macos)
      viewer_block='vim.g.vimtex_view_method = "skim"
      vim.g.vimtex_view_skim_sync = 1
      vim.g.vimtex_view_skim_activate = 1
      vim.g.vimtex_view_skim_reading_bar = 1'
      ;;
    windows)
      # VimTeX has no dedicated sumatra backend; "general" plus these flags is
      # the documented way. -reuse-instance avoids a new window per build.
      viewer_block='vim.g.vimtex_view_method = "general"
      vim.g.vimtex_view_general_viewer = "SumatraPDF"
      vim.g.vimtex_view_general_options = "-reuse-instance -forward-search @tex @line @pdf"'
      ;;
    *)
      viewer_block='vim.g.vimtex_view_method = "zathura"
      vim.g.vimtex_view_zathura_check_libsynctex = 1'
      ;;
  esac

  say "writing ${NVIM_CONFIG}"
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  (dry run) would write init.lua, lua/plugins/{tex,lsp,ide}.lua, luasnippets/tex/math.lua%s\n' "$c_dim" "$c_off"
    return 0
  fi

  mkdir -p "${NVIM_CONFIG}/lua/plugins" "${NVIM_CONFIG}/luasnippets/tex"

  cat > "${NVIM_CONFIG}/init.lua" <<'LUA'
-- Leader must be set before lazy.nvim loads, or plugin keymaps bind to the
-- wrong prefix. localleader is what VimTeX hangs all its commands off.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    error("failed to clone lazy.nvim — is git installed and on PATH?\n" .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.signcolumn = "yes"
vim.opt.undofile = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.updatetime = 250

-- conceallevel 2 renders \alpha as the glyph; VimTeX drives this.
vim.opt.conceallevel = 2

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    vim.keymap.set({ "n", "v" }, "j", "gj", { buffer = true })
    vim.keymap.set({ "n", "v" }, "k", "gk", { buffer = true })
  end,
})

require("lazy").setup("plugins", { change_detection = { notify = false } })
LUA

  cat > "${NVIM_CONFIG}/lua/plugins/tex.lua" <<LUA
return {
  {
    "lervag/vimtex",
    lazy = false, -- VimTeX does its own lazy loading; do not wrap it
    init = function()
      ${viewer_block}

      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_compiler_latexmk = {
        aux_dir = "build",
        out_dir = "build",
        callback = 1,
        continuous = 1,
        options = {
          "-shell-escape",
          "-verbose",
          "-file-line-error",
          "-synctex=1",
          "-interaction=nonstopmode",
        },
      }

      -- 0 = never open quickfix automatically. LaTeX warnings are noisy;
      -- open it deliberately with <localleader>le when a build fails.
      vim.g.vimtex_quickfix_mode = 0
      vim.g.vimtex_quickfix_ignore_filters = {
        "Underfull \\\\\\\\hbox",
        "Overfull \\\\\\\\hbox",
        "LaTeX Warning: .\\\\+ float specifier changed to",
        "Package hyperref Warning: Token not allowed in a PDF string",
      }

      vim.g.vimtex_mappings_prefix = "<localleader>"
      vim.g.vimtex_syntax_conceal = {
        accents = 1, ligatures = 1, cites = 1, fancy = 1,
        greek = 1, math_bounds = 0, math_delimiters = 1,
        math_fracs = 1, math_super_sub = 1, math_symbols = 1,
        sections = 0, styles = 1,
      }
      vim.g.vimtex_indent_on_ampersands = 0
    end,
  },

  {
    "L3MON4D3/LuaSnip",
    -- jsregexp powers regex-trigger snippets (x1 -> x_{1}). It needs make and
    -- a C compiler. If the build fails, LuaSnip still loads and every
    -- non-regex snippet works; only the regex triggers go quiet.
    build = "make install_jsregexp",
    config = function()
      local ls = require("luasnip")
      ls.setup({
        enable_autosnippets = true,
        store_selection_keys = "<Tab>",
        update_events = "TextChanged,TextChangedI",
      })
      require("luasnip.loaders.from_lua").load({
        paths = vim.fn.stdpath("config") .. "/luasnippets",
      })

      vim.keymap.set({ "i", "s" }, "<C-k>", function()
        if ls.expand_or_jumpable() then ls.expand_or_jump() end
      end, { desc = "snippet: next hole" })
      vim.keymap.set({ "i", "s" }, "<C-j>", function()
        if ls.jumpable(-1) then ls.jump(-1) end
      end, { desc = "snippet: previous hole" })

      vim.keymap.set("n", "<leader>rs", function()
        require("luasnip.loaders.from_lua").load({
          paths = vim.fn.stdpath("config") .. "/luasnippets",
        })
        vim.notify("snippets reloaded")
      end, { desc = "reload snippets" })
    end,
  },
}
LUA

  cat > "${NVIM_CONFIG}/lua/plugins/lsp.lua" <<'LUA'
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- vim.lsp.config / vim.lsp.enable need Neovim 0.11+. On older versions
      -- these are nil and LSP silently never attaches, so fail loudly instead.
      if vim.fn.has("nvim-0.11") == 0 then
        vim.notify(
          "This config needs Neovim 0.11+ for LSP. texlab will not attach.\n" ..
          "Everything else (VimTeX, snippets, telescope) still works.",
          vim.log.levels.WARN)
        return
      end

      -- Build is off here because VimTeX owns compilation; two latexmk
      -- processes on the same file fight over the aux files.
      vim.lsp.config("texlab", {
        settings = {
          texlab = {
            build = { onSave = false },
            chktex = { onOpenAndSave = true, onEdit = false },
            diagnosticsDelay = 300,
            latexFormatter = "latexindent",
            latexindent = { modifyLineBreaks = false },
          },
        },
      })

      if vim.fn.executable("texlab") == 1 then
        vim.lsp.enable({ "texlab" })
      else
        vim.notify("texlab not on PATH — no LaTeX diagnostics or \\ref navigation.",
          vim.log.levels.WARN)
      end

      vim.diagnostic.config({
        virtual_text = { spacing = 2, prefix = "-" },
        severity_sort = true,
        float = { border = "rounded", source = true },
      })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local function map(k, fn, desc)
            vim.keymap.set("n", k, fn, { buffer = ev.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "goto definition")
          map("gr", vim.lsp.buf.references, "references")
          map("K", vim.lsp.buf.hover, "hover")
          map("<leader>rn", vim.lsp.buf.rename, "rename")
          map("<leader>ca", vim.lsp.buf.code_action, "code action")
          map("<leader>e", vim.diagnostic.open_float, "line diagnostics")
          map("[d", function() vim.diagnostic.jump({ count = -1 }) end, "prev diagnostic")
          map("]d", function() vim.diagnostic.jump({ count = 1 }) end, "next diagnostic")
          map("<leader>f", function() vim.lsp.buf.format({ async = true }) end, "format")
        end,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    version = "*",
    dependencies = { "L3MON4D3/LuaSnip" },
    opts = {
      keymap = { preset = "default" },
      snippets = { preset = "luasnip" },
      completion = {
        documentation = { auto_show = true, auto_show_delay_ms = 200 },
      },
      sources = { default = { "lsp", "snippets", "path", "buffer" } },
    },
  },
}
LUA

  cat > "${NVIM_CONFIG}/lua/plugins/ide.lua" <<'LUA'
-- The parts VSCode gives you out of the box.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    -- Parser compilation needs a C compiler. Without one, :TSUpdate fails and
    -- highlighting falls back to regex syntax — degraded, not broken.
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "latex", "bibtex", "lua", "vim", "vimdoc", "markdown", "python" },
        highlight = {
          enable = true,
          -- VimTeX's own syntax engine handles math zones and conceal better
          -- than the treesitter latex parser; let it win inside tex.
          disable = { "latex" },
        },
        indent = { enable = true },
      })
    end,
  },

  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",  desc = "grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",    desc = "buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",  desc = "help" },
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "symbols" },
    },
    opts = {
      defaults = {
        layout_strategy = "flex",
        file_ignore_patterns = { "build/", "%.aux", "%.fls", "%.fdb_latexmk", "%.synctex%.gz" },
      },
    },
  },

  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = { { "<leader>t", "<cmd>NvimTreeToggle<cr>", desc = "file tree" } },
    opts = { view = { width = 30 }, filters = { custom = { "^%.git$" } } },
  },

  { "lewis6991/gitsigns.nvim", event = "BufReadPre",  opts = {} },
  { "folke/which-key.nvim",    event = "VeryLazy",    opts = {} },
  { "windwp/nvim-autopairs",   event = "InsertEnter", opts = {} },
  { "numToStr/Comment.nvim",   event = "VeryLazy",    opts = {} },
  { "lukas-reineke/indent-blankline.nvim", main = "ibl", event = "BufReadPre", opts = {} },

  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      require("catppuccin").setup({ flavour = "mocha" })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  { "nvim-lualine/lualine.nvim", event = "VeryLazy", opts = { options = { theme = "catppuccin" } } },
}
LUA

  cat > "${NVIM_CONFIG}/luasnippets/tex/math.lua" <<'LUA'
-- LaTeX math autosnippets. These fire without a trigger key, but only inside
-- math mode, so ordinary prose is untouched. This is the main reason to use
-- Neovim over VSCode for heavy math typing.
--
-- Regex-trigger snippets (the x1 -> x_{1} and RR -> \mathbb{R} ones) need
-- LuaSnip's jsregexp, which needs make and a C compiler at install time.
-- If those are missing, the literal-trigger snippets below still work.

local ls = require("luasnip")
local s  = ls.snippet
local t  = ls.text_node
local i  = ls.insert_node
local f  = ls.function_node
local fmta = require("luasnip.extras.fmt").fmta
local rep  = require("luasnip.extras").rep

-- True when the cursor sits inside $...$, \[...\], align, etc.
-- VimTeX exposes this; it is the whole trick.
local function math()
  return vim.fn["vimtex#syntax#in_mathzone"]() == 1
end
local function not_math()
  return vim.fn["vimtex#syntax#in_mathzone"]() ~= 1
end

local auto = { condition = math, snippetType = "autosnippet" }
local cap  = function(n) return f(function(_, snip) return snip.captures[n] end) end

return {
  -- entering math ------------------------------------------------------
  s({ trig = "mk", snippetType = "autosnippet", condition = not_math },
    fmta("$<>$<>", { i(1), i(2) })),
  s({ trig = "dm", snippetType = "autosnippet", condition = not_math },
    fmta("\\[\n  <>\n\\]\n<>", { i(1), i(2) })),

  -- structures ---------------------------------------------------------
  s({ trig = "beg", snippetType = "autosnippet" },
    fmta("\\begin{<>}\n  <>\n\\end{<>}", { i(1), i(2), rep(1) })),
  s({ trig = "ali", snippetType = "autosnippet" },
    fmta("\\begin{align*}\n  <>\n\\end{align*}", { i(1) })),

  -- fractions, powers, subscripts --------------------------------------
  s({ trig = "//", wordTrig = false }, fmta("\\frac{<>}{<>}", { i(1), i(2) }), auto),
  s({ trig = "sr", wordTrig = false }, t("^{2}"), auto),
  s({ trig = "cb", wordTrig = false }, t("^{3}"), auto),
  s({ trig = "td", wordTrig = false }, fmta("^{<>}", { i(1) }), auto),
  s({ trig = "__", wordTrig = false }, fmta("_{<>}", { i(1) }), auto),
  s({ trig = "ee", wordTrig = false }, fmta("e^{<>}", { i(1) }), auto),
  s({ trig = "sq", wordTrig = false }, fmta("\\sqrt{<>}", { i(1) }), auto),

  -- x1 -> x_{1}  (needs jsregexp)
  s({ trig = "([%a])(%d)", regTrig = true, wordTrig = false },
    fmta("<>_{<>}", { cap(1), cap(2) }), auto),

  -- big operators ------------------------------------------------------
  s({ trig = "sum", wordTrig = false },
    fmta("\\sum_{<>}^{<>} <>", { i(1, "i=1"), i(2, "n"), i(3) }), auto),
  s({ trig = "prod", wordTrig = false },
    fmta("\\prod_{<>}^{<>} <>", { i(1, "i=1"), i(2, "n"), i(3) }), auto),
  s({ trig = "int", wordTrig = false },
    fmta("\\int_{<>}^{<>} <> \\, d<>", { i(1), i(2), i(3), i(4, "x") }), auto),
  s({ trig = "lim", wordTrig = false },
    fmta("\\lim_{<> \\to <>}", { i(1, "n"), i(2, "\\infty") }), auto),

  -- delimiters ---------------------------------------------------------
  s({ trig = "lr(", wordTrig = false }, fmta("\\left( <> \\right)", { i(1) }), auto),
  s({ trig = "lr[", wordTrig = false }, fmta("\\left[ <> \\right]", { i(1) }), auto),
  s({ trig = "lr{", wordTrig = false }, fmta("\\left\\{ <> \\right\\}", { i(1) }), auto),
  s({ trig = "abs", wordTrig = false }, fmta("\\left| <> \\right|", { i(1) }), auto),
  s({ trig = "norm", wordTrig = false }, fmta("\\left\\lVert <> \\right\\rVert", { i(1) }), auto),

  -- relations and arrows ----------------------------------------------
  s({ trig = "!=",    wordTrig = false }, t("\\neq"),      auto),
  s({ trig = "<=",    wordTrig = false }, t("\\leq"),      auto),
  s({ trig = ">=",    wordTrig = false }, t("\\geq"),      auto),
  s({ trig = "->",    wordTrig = false }, t("\\to"),       auto),
  s({ trig = "=>",    wordTrig = false }, t("\\implies"),  auto),
  s({ trig = "=<",    wordTrig = false }, t("\\impliedby"), auto),
  s({ trig = "iff",   wordTrig = false }, t("\\iff"),      auto),
  s({ trig = "inn",   wordTrig = false }, t("\\in"),       auto),
  s({ trig = "notin", wordTrig = false }, t("\\notin"),    auto),
  s({ trig = "sub",   wordTrig = false }, t("\\subseteq"), auto),
  s({ trig = "cup",   wordTrig = false }, t("\\cup"),      auto),
  s({ trig = "cap",   wordTrig = false }, t("\\cap"),      auto),
  s({ trig = "xx",    wordTrig = false }, t("\\times"),    auto),
  s({ trig = "ooo",   wordTrig = false }, t("\\infty"),    auto),

  -- RR -> \mathbb{R}, ZZ -> \mathbb{Z}, ...  (needs jsregexp)
  s({ trig = "([A-Z])([A-Z])", regTrig = true, wordTrig = false,
      condition = function(_, matched)
        return math() and matched:sub(1, 1) == matched:sub(2, 2)
      end, snippetType = "autosnippet" },
    fmta("\\mathbb{<>}", { cap(1) })),

  -- greek ---------------------------------------------------------------
  s({ trig = ";a", snippetType = "autosnippet" }, t("\\alpha")),
  s({ trig = ";b", snippetType = "autosnippet" }, t("\\beta")),
  s({ trig = ";g", snippetType = "autosnippet" }, t("\\gamma")),
  s({ trig = ";d", snippetType = "autosnippet" }, t("\\delta")),
  s({ trig = ";e", snippetType = "autosnippet" }, t("\\varepsilon")),
  s({ trig = ";t", snippetType = "autosnippet" }, t("\\theta")),
  s({ trig = ";l", snippetType = "autosnippet" }, t("\\lambda")),
  s({ trig = ";m", snippetType = "autosnippet" }, t("\\mu")),
  s({ trig = ";s", snippetType = "autosnippet" }, t("\\sigma")),
  s({ trig = ";f", snippetType = "autosnippet" }, t("\\varphi")),
  s({ trig = ";o", snippetType = "autosnippet" }, t("\\omega")),
  s({ trig = ";D", snippetType = "autosnippet" }, t("\\Delta")),
  s({ trig = ";S", snippetType = "autosnippet" }, t("\\Sigma")),
  s({ trig = ";O", snippetType = "autosnippet" }, t("\\Omega")),

  -- theorem environments (outside math) --------------------------------
  s({ trig = "thm", condition = not_math },
    fmta("\\begin{theorem}[<>]\n  <>\n\\end{theorem}", { i(1), i(2) })),
  s({ trig = "prf", condition = not_math },
    fmta("\\begin{proof}\n  <>\n\\end{proof}", { i(1) })),
  s({ trig = "lem", condition = not_math },
    fmta("\\begin{lemma}\n  <>\n\\end{lemma}", { i(1) })),
}
LUA

  ok "config written"
}

# --------------------------------------------------------------- final checks

# run_checks <mode>
#   strict — standalone --check. A missing hard requirement is fatal.
#   post   — straight after installing. A hard requirement can be missing
#            simply because PATH has not refreshed in THIS shell: winget and
#            MacTeX both put binaries somewhere the current process cannot
#            see until it restarts. Dying here would report failure after a
#            successful install, so downgrade to a warning that says so.
run_checks() {
  local mode="${1:-strict}"
  say "prerequisite check"

  _need() { # <tool> <label> [hint_key]
    if have "$1"; then ok "$2 -> $(command -v "$1")"; return 0; fi
    if [ "$mode" = "post" ]; then
      printf '%s[warn]%s %s not visible in this shell.\n' "$c_yellow" "$c_off" "$2" >&2
      printf '       If it was just installed, open a NEW terminal and rerun:  %s --check\n' "$0" >&2
      printf '       If it is genuinely absent:\n' >&2
      fix_hint "${3:-$1}"
      SOFT_FAILURES="${SOFT_FAILURES}${2} (not on PATH in this shell)
"
      return 0
    fi
    printf '%s[fatal]%s %s is required and was not found.\n' "$c_red" "$c_off" "$2" >&2
    fix_hint "${3:-$1}"
    exit 1
  }

  # HARD — lazy.nvim clones every plugin over git.
  _need git "git"
  # HARD — used to fetch neovim and texlab tarballs.
  _need curl "curl"
  # HARD — this config calls vim.lsp.config(), added in Neovim 0.11.
  _need nvim "neovim"

  if have nvim; then
    local ver; ver=$(nvim --version | head -1)
    case "$ver" in
      *v0.1[1-9]*|*v0.[2-9][0-9]*|*v[1-9].*) ok "$ver" ;;
      *)
        # Version too old is never a PATH problem — always fatal.
        printf '%s[fatal]%s %s is too old. This config needs 0.11+ (vim.lsp.config).\n' \
          "$c_red" "$c_off" "$ver" >&2
        fix_hint nvim
        exit 1
        ;;
    esac
  fi

  # SOFT — VimTeX compilation. Editing and LSP work without it.
  require_soft latexmk "latexmk" "VimTeX cannot compile; ,ll will do nothing"
  # SOFT — diagnostics, hover on \cite, goto-def on \ref.
  require_soft texlab  "texlab"  "no LaTeX diagnostics or \\ref navigation"
  # SOFT — Telescope live_grep falls back to a slow path.
  require_soft rg      "ripgrep" "Telescope live_grep will be slow" ripgrep
}

# ---------------------------------------------------------------------- main

main() {
  detect_platform
  set_paths
  say "platform: ${PLATFORM} (${PKG})"
  say "config target: ${NVIM_CONFIG}"

  if [ "$UNINSTALL" -eq 1 ]; then do_uninstall; exit 0; fi
  if [ "$CHECK_ONLY" -eq 1 ]; then run_checks strict; exit 0; fi
  if [ "$DRY_RUN" -eq 1 ]; then warn "dry run — nothing will be installed or written"; fi

  check_existing_config

  if [ "$CONFIG_ONLY" -eq 0 ]; then
    case "$PLATFORM" in
      macos)   install_macos ;;
      windows) install_windows ;;
      arch)    install_arch ;;
      debian)  install_debian ;;
    esac
  else
    say "skipping package installs (--config-only)"
  fi

  write_config
  run_checks post

  if [ -n "$SOFT_FAILURES" ]; then
    printf '\n%s==>%s Installed, with these optional pieces missing:\n' "$c_bold" "$c_off"
    printf '%s' "$SOFT_FAILURES" | sed 's/^/      - /'
    printf '    Instructions for each were printed above. Neovim will start regardless.\n'
  fi

  case "$PLATFORM" in
    macos) cat <<'NOTE'

  Skim needs one manual step for inverse search (click PDF -> jump to source):

    Skim > Settings > Sync
      [x] Check for file changes
      PDF-TeX Sync support:
        Preset:    Custom
        Command:   nvim
        Arguments: --headless -c "VimtexInverseSearch %line '%file'"

  If GUI apps cannot see nvim, use the absolute path from `which nvim`.
NOTE
    ;;
    windows) cat <<'NOTE'

  SumatraPDF needs one manual step for inverse search:

    Settings > Options > "Set inverse search command-line":
      nvim --headless -c "VimtexInverseSearch %l \"%f\""

  If that box is not visible, open a PDF first — Sumatra hides it otherwise.

  Two Windows notes:
    - Open a NEW shell after install so PATH picks up MiKTeX and Neovim.
    - Neovim reads %LOCALAPPDATA%\nvim here, NOT ~/.config/nvim.
NOTE
    ;;
    *) cat <<'NOTE'

  Zathura needs no configuration; VimTeX passes the synctex flags itself.
  Inverse search is ctrl+click in the PDF.

  Under WSL, zathura needs an X server. WSLg (Windows 11) works out of the
  box. On Windows 10, point VimTeX at SumatraPDF on the Windows side instead:
    vim.g.vimtex_view_method = "general"
    vim.g.vimtex_view_general_viewer = "/mnt/c/Users/YOU/AppData/Local/SumatraPDF/SumatraPDF.exe"
NOTE
    ;;
  esac

  cat <<'NEXT'

  Next:

    1. nvim                 # lazy.nvim bootstraps and installs plugins
    2. :Lazy                # watch it finish, press q
    3. :checkhealth vimtex  # should be all green
    4. Restart nvim.

  Try it:

    mkdir -p ~/tex/scratch && cd ~/tex/scratch && nvim main.tex

  Then, in insert mode:

    \documentclass{article}
    \usepackage{amsmath,amssymb}
    \begin{document}
    dm     -> display math block      sum  -> \sum_{i=1}^{n}
    ;a     -> \alpha                  //   -> \frac{}{}
    \end{document}

  Keys (localleader is the comma):

    ,ll  start continuous compile    ,lk  stop compile
    ,lv  jump PDF to cursor          ,le  open error list
    ,lc  clean aux files             ,lt  table of contents
    dse  delete surrounding env      cse  change surrounding env
    ]]   next section                [[   previous section
    vie  select inside environment   vae  select around it

    <space>ff find files   <space>fg grep   <space>t file tree
    gd goto definition (on \ref)     K hover (on \cite)

  Build artifacts land in ./build/. Add it to .gitignore.

  Re-check prerequisites later:  ./TerminalEditor.sh --check
  Remove everything:             ./TerminalEditor.sh --uninstall

NEXT
}

main