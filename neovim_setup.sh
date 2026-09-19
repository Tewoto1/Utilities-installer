#!/usr/bin/env bash
#
# TerminalEditor.sh — set up Neovim as a LaTeX editor with VSCode-style IDE features.
#
# Supports: macOS (Homebrew), Arch Linux / WSL-Arch (pacman), Debian/Ubuntu (apt).
#
# Installs:
#   neovim, texlab (LaTeX LSP), a TeX distribution, a SyncTeX-capable PDF viewer,
#   ripgrep + fd (telescope deps), git, make, a C compiler (treesitter/luasnip builds)
#
# Writes:
#   ~/.config/nvim/init.lua
#   ~/.config/nvim/lua/plugins/{tex,lsp,ide}.lua
#   ~/.config/nvim/luasnippets/tex/math.lua
#
# It will NOT overwrite an existing ~/.config/nvim. If one is there, the script
# stops and prints the exact rm commands so you can clear it out yourself.
#
# Usage:
#   ./TerminalEditor.sh                 # install packages + write config
#   ./TerminalEditor.sh --dry-run       # print every command, change nothing
#   ./TerminalEditor.sh --config-only   # skip package installs, write config only
#   ./TerminalEditor.sh --no-tex        # skip the TeX distribution (it's big)
#   ./TerminalEditor.sh --uninstall     # print removal commands (does not run them)

set -euo pipefail

NVIM_CONFIG="${HOME}/.config/nvim"
NVIM_DATA="${HOME}/.local/share/nvim"
NVIM_STATE="${HOME}/.local/state/nvim"
NVIM_CACHE="${HOME}/.cache/nvim"

DRY_RUN=0
CONFIG_ONLY=0
WANT_TEX=1

# ---------------------------------------------------------------- arg parsing

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    --no-tex)      WANT_TEX=0 ;;
    --uninstall)   UNINSTALL=1 ;;
    -h|--help)     sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------- plumbing

c_bold=$'\033[1m'; c_red=$'\033[31m'; c_yellow=$'\033[33m'
c_green=$'\033[32m'; c_dim=$'\033[2m'; c_off=$'\033[0m'

say()  { printf '%s==>%s %s\n' "$c_bold" "$c_off" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }
ok()   { printf '%s  ok%s %s\n' "$c_green" "$c_off" "$*"; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  $ %s%s\n' "$c_dim" "$*" "$c_off"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------- platform detection

PLATFORM=""
PKG=""

detect_platform() {
  case "$(uname -s)" in
    Darwin)
      PLATFORM="macos"; PKG="brew"
      ;;
    Linux)
      if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-}${ID_LIKE:-}" in
          *arch*)          PLATFORM="arch";   PKG="pacman" ;;
          *debian*|*ubuntu*) PLATFORM="debian"; PKG="apt" ;;
          *) die "unsupported Linux distro: ${ID:-unknown}. Install the package list by hand, then rerun with --config-only." ;;
        esac
      else
        die "cannot read /etc/os-release"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      die "native Windows shell detected. Use WSL2 (wsl --install -d archlinux) and run this inside it, or install via winget by hand. See the notes at the bottom of this file."
      ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
  if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    say "running under WSL (${WSL_DISTRO_NAME})"
  fi
}

# ---------------------------------------------------------------- uninstaller

if [ -n "${UNINSTALL:-}" ]; then
  detect_platform
  cat <<UNINST

Nothing has been removed. Run these yourself, in order.

  # Neovim config, plugins, state, cache
  rm -rf ${NVIM_CONFIG}
  rm -rf ${NVIM_DATA}
  rm -rf ${NVIM_STATE}
  rm -rf ${NVIM_CACHE}

UNINST
  case "$PLATFORM" in
    macos)  cat <<'UNINST'
  # packages
  brew uninstall neovim texlab ripgrep fd
  brew uninstall --cask skim mactex-no-gui

  # MacTeX leaves these behind
  rm -rf /usr/local/texlive
  rm -rf ~/Library/texlive
  rm -rf /Library/TeX
UNINST
    ;;
    arch)   echo "  sudo pacman -Rns neovim texlab ripgrep fd zathura zathura-pdf-mupdf texlive-basic texlive-latexextra texlive-mathscience texlive-fontsrecommended biber" ;;
    debian) echo "  sudo apt purge neovim ripgrep fd-find zathura texlive-latex-recommended texlive-latex-extra texlive-science latexmk biber && sudo apt autoremove" ;;
  esac
  echo
  exit 0
fi

# ------------------------------------------------------------- safety: config

check_existing_config() {
  if [ -e "$NVIM_CONFIG" ]; then
    printf '\n'
    warn "${NVIM_CONFIG} already exists. Not touching it."
    cat <<EXISTING

If you want a clean install, remove the old tree yourself first:

  rm -rf ${NVIM_CONFIG}
  rm -rf ${NVIM_DATA}
  rm -rf ${NVIM_STATE}
  rm -rf ${NVIM_CACHE}

(The last three hold downloaded plugins, shada/undo history, and compiled
treesitter parsers. Leaving them while deleting the config gives you a
half-stale plugin dir, so clear all four together.)

Then rerun this script.

EXISTING
    exit 1
  fi
}

# --------------------------------------------------------- package installers

install_macos() {
  have brew || die "Homebrew not found. Install it from https://brew.sh first, then rerun."

  say "installing formulae"
  for f in neovim texlab ripgrep fd git; do
    if have "$f" || brew list --formula "$f" >/dev/null 2>&1; then
      ok "$f already present, skipping"
    else
      run brew install "$f"
    fi
  done

  say "installing Skim (PDF viewer with inverse search)"
  if [ -d "/Applications/Skim.app" ]; then
    ok "Skim already present, skipping"
  else
    run brew install --cask skim
  fi

  if [ "$WANT_TEX" -eq 1 ]; then
    if have latexmk; then
      ok "latexmk already on PATH, skipping TeX install"
    else
      say "installing MacTeX (no GUI apps) — this is a ~5GB download"
      run brew install --cask mactex-no-gui
      warn "add /Library/TeX/texbin to PATH if latexmk is not found in a new shell:"
      printf '    echo '\''eval "$(/usr/libexec/path_helper)"'\'' >> ~/.zshrc\n'
    fi
  fi
}

install_arch() {
  local pkgs="neovim texlab ripgrep fd git base-devel zathura zathura-pdf-mupdf"
  if [ "$WANT_TEX" -eq 1 ]; then pkgs="$pkgs texlive-basic texlive-latexextra texlive-mathscience texlive-fontsrecommended texlive-binextra biber"; fi

  say "installing via pacman"
  printf '%s  %s%s\n' "$c_dim" "$pkgs" "$c_off"
  # shellcheck disable=SC2086
  run sudo pacman -S --needed $pkgs
}

install_debian() {
  local pkgs="ripgrep fd-find git build-essential zathura curl"
  if [ "$WANT_TEX" -eq 1 ]; then pkgs="$pkgs texlive-latex-recommended texlive-latex-extra texlive-science texlive-fonts-recommended latexmk biber"; fi

  say "installing via apt"
  run sudo apt update
  # shellcheck disable=SC2086
  run sudo apt install -y $pkgs

  # Debian's neovim is usually too old for vim.lsp.config (needs 0.11+)
  if have nvim && nvim --version | head -1 | grep -qE 'v0\.(1[1-9]|[2-9][0-9])'; then
    ok "neovim new enough, skipping"
  else
    warn "apt's neovim is too old. Installing the official tarball to ~/.local/nvim instead."
    if [ -e "${HOME}/.local/nvim" ]; then
      die "~/.local/nvim exists. Remove it yourself first:  rm -rf ~/.local/nvim"
    fi
    run mkdir -p "${HOME}/.local"
    run curl -fLo /tmp/nvim-linux.tar.gz \
      https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
    run tar xzf /tmp/nvim-linux.tar.gz -C /tmp
    run mv /tmp/nvim-linux-x86_64 "${HOME}/.local/nvim"
    run rm -f /tmp/nvim-linux.tar.gz
    warn "add to your shell rc:  export PATH=\"\$HOME/.local/nvim/bin:\$PATH\""
  fi

  have texlab || warn "texlab is not in apt. Install it by hand:  cargo install --git https://github.com/latex-lsp/texlab --locked"
}

# ------------------------------------------------------------ config writing

write_config() {
  local viewer viewer_extra
  case "$PLATFORM" in
    macos) viewer="skim"
           viewer_extra='vim.g.vimtex_view_skim_sync = 1
      vim.g.vimtex_view_skim_activate = 1
      vim.g.vimtex_view_skim_reading_bar = 1' ;;
    *)     viewer="zathura"
           viewer_extra='vim.g.vimtex_view_zathura_check_libsynctex = 1' ;;
  esac

  say "writing ${NVIM_CONFIG}"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '%s  (dry run) would write init.lua, lua/plugins/{tex,lsp,ide}.lua, luasnippets/tex/math.lua%s\n' "$c_dim" "$c_off"
    return
  fi

  mkdir -p "${NVIM_CONFIG}/lua/plugins"
  mkdir -p "${NVIM_CONFIG}/luasnippets/tex"

  # ---------------------------------------------------------------- init.lua
  cat > "${NVIM_CONFIG}/init.lua" <<'LUA'
-- Leader must be set before lazy.nvim loads, or plugin keymaps bind to the
-- wrong prefix. localleader is what VimTeX hangs all its commands off.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
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

-- Prose settings, scoped to tex/markdown only.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "tex", "markdown" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_us"
    -- move by visual line so wrapped paragraphs behave
    vim.keymap.set({ "n", "v" }, "j", "gj", { buffer = true })
    vim.keymap.set({ "n", "v" }, "k", "gk", { buffer = true })
  end,
})

require("lazy").setup("plugins", {
  change_detection = { notify = false },
})
LUA

  # ----------------------------------------------------------------- tex.lua
  cat > "${NVIM_CONFIG}/lua/plugins/tex.lua" <<LUA
return {
  {
    "lervag/vimtex",
    lazy = false, -- VimTeX does its own lazy loading; do not wrap it
    init = function()
      vim.g.vimtex_view_method = "${viewer}"
      ${viewer_extra}

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

      -- reload snippets without restarting nvim
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

  # ----------------------------------------------------------------- lsp.lua
  cat > "${NVIM_CONFIG}/lua/plugins/lsp.lua" <<'LUA'
return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- texlab: diagnostics, hover on \cite, goto-definition on \ref.
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
      vim.lsp.enable({ "texlab" })

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
      sources = {
        default = { "lsp", "snippets", "path", "buffer" },
      },
    },
  },
}
LUA

  # ----------------------------------------------------------------- ide.lua
  cat > "${NVIM_CONFIG}/lua/plugins/ide.lua" <<'LUA'
-- The parts VSCode gives you out of the box.
return {
  {
    "nvim-treesitter/nvim-treesitter",
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
      { "<leader>ff", "<cmd>Telescope find_files<cr>",  desc = "find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",   desc = "grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>",     desc = "buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",   desc = "help" },
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
    opts = {
      view = { width = 30 },
      filters = { custom = { "^%.git$" } },
    },
  },

  { "lewis6991/gitsigns.nvim", event = "BufReadPre", opts = {} },
  { "folke/which-key.nvim",    event = "VeryLazy",   opts = {} },
  { "windwp/nvim-autopairs",   event = "InsertEnter", opts = {} },
  { "numToStr/Comment.nvim",   event = "VeryLazy",   opts = {} },
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

  # ------------------------------------------------------ luasnippets/tex/math.lua
  cat > "${NVIM_CONFIG}/luasnippets/tex/math.lua" <<'LUA'
-- LaTeX math autosnippets. These fire without a trigger key, but only inside
-- math mode, so ordinary prose is untouched. This is the main reason to use
-- Neovim over VSCode for heavy math typing.
--
-- Add your own as you go: the set you build over a semester is worth more
-- than any preset someone else shipped.

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
  s({ trig = "//", wordTrig = false },
    fmta("\\frac{<>}{<>}", { i(1), i(2) }), auto),

  s({ trig = "sr", wordTrig = false }, t("^{2}"), auto),
  s({ trig = "cb", wordTrig = false }, t("^{3}"), auto),
  s({ trig = "td", wordTrig = false }, fmta("^{<>}", { i(1) }), auto),
  s({ trig = "__", wordTrig = false }, fmta("_{<>}", { i(1) }), auto),
  s({ trig = "ee", wordTrig = false }, fmta("e^{<>}", { i(1) }), auto),
  s({ trig = "sq", wordTrig = false }, fmta("\\sqrt{<>}", { i(1) }), auto),

  -- x1 -> x_{1}, a2 -> a_{2}
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
  s({ trig = "lr(", wordTrig = false },
    fmta("\\left( <> \\right)", { i(1) }), auto),
  s({ trig = "lr[", wordTrig = false },
    fmta("\\left[ <> \\right]", { i(1) }), auto),
  s({ trig = "lr{", wordTrig = false },
    fmta("\\left\\{ <> \\right\\}", { i(1) }), auto),
  s({ trig = "abs", wordTrig = false },
    fmta("\\left| <> \\right|", { i(1) }), auto),
  s({ trig = "norm", wordTrig = false },
    fmta("\\left\\lVert <> \\right\\rVert", { i(1) }), auto),

  -- relations and arrows ----------------------------------------------
  s({ trig = "!=", wordTrig = false },  t("\\neq"),     auto),
  s({ trig = "<=", wordTrig = false },  t("\\leq"),     auto),
  s({ trig = ">=", wordTrig = false },  t("\\geq"),     auto),
  s({ trig = "->", wordTrig = false },  t("\\to"),      auto),
  s({ trig = "=>", wordTrig = false },  t("\\implies"), auto),
  s({ trig = "=<", wordTrig = false },  t("\\impliedby"), auto),
  s({ trig = "iff", wordTrig = false }, t("\\iff"),     auto),
  s({ trig = "inn", wordTrig = false }, t("\\in"),      auto),
  s({ trig = "notin", wordTrig = false }, t("\\notin"), auto),
  s({ trig = "sub", wordTrig = false }, t("\\subseteq"), auto),
  s({ trig = "cup", wordTrig = false }, t("\\cup"),     auto),
  s({ trig = "cap", wordTrig = false }, t("\\cap"),     auto),
  s({ trig = "xx",  wordTrig = false }, t("\\times"),   auto),
  s({ trig = "ooo", wordTrig = false }, t("\\infty"),   auto),

  -- blackboard bold: RR -> \mathbb{R}, and friends ---------------------
  s({ trig = "([A-Z])([A-Z])", regTrig = true, wordTrig = false,
      condition = function(line_to_cursor, matched)
        return math() and matched:sub(1, 1) == matched:sub(2, 2)
      end, snippetType = "autosnippet" },
    fmta("\\mathbb{<>}", { cap(1) })),

  -- greek: ;a -> \alpha, ;b -> \beta, ... -------------------------------
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

# ------------------------------------------------------------- viewer wiring

viewer_notes() {
  case "$PLATFORM" in
    macos)
      cat <<'NOTE'

  Skim needs one manual step for inverse search (click in PDF -> jump to source):

    Skim > Settings > Sync
      [x] Check for file changes
      PDF-TeX Sync support:
        Preset:    Custom
        Command:   nvim
        Arguments: --headless -c "VimtexInverseSearch %line '%file'"

  If nvim is not on the default PATH that GUI apps see, use the absolute path
  from `which nvim` instead of the bare `nvim`.
NOTE
      ;;
    *)
      cat <<'NOTE'

  Zathura needs no configuration; VimTeX passes the synctex flags itself.
  Inverse search is ctrl+click in the PDF.

  Under WSL: zathura needs an X server. WSLg (Windows 11) works out of the box.
  On Windows 10, either install VcXsrv, or set the viewer to SumatraPDF on the
  Windows side instead:
      vim.g.vimtex_view_method = "general"
      vim.g.vimtex_view_general_viewer = "/mnt/c/Users/YOU/AppData/Local/SumatraPDF/SumatraPDF.exe"
NOTE
      ;;
  esac
}

# ---------------------------------------------------------------------- main

main() {
  detect_platform
  say "platform: ${PLATFORM} (${PKG})"
  if [ "$DRY_RUN" -eq 1 ]; then
    warn "dry run — nothing will be installed or written"
  fi

  check_existing_config

  if [ "$CONFIG_ONLY" -eq 0 ]; then
    case "$PLATFORM" in
      macos)  install_macos ;;
      arch)   install_arch ;;
      debian) install_debian ;;
    esac
  else
    say "skipping package installs (--config-only)"
  fi

  write_config

  # sanity check
  say "checking tools"
  for tool in nvim latexmk texlab rg git; do
    if have "$tool"; then
      ok "$tool -> $(command -v "$tool")"
    else
      warn "$tool not found on PATH"
    fi
  done

  if have nvim; then
    ver=$(nvim --version | head -1)
    case "$ver" in
      *v0.1[1-9]*|*v0.[2-9][0-9]*|*v[1-9].*) ok "$ver" ;;
      *) warn "$ver — this config uses vim.lsp.config(), which needs 0.11+. Upgrade Neovim." ;;
    esac
  fi

  viewer_notes

  cat <<'NEXT'

  Next:

    1. nvim                      # lazy.nvim bootstraps and installs plugins
    2. :Lazy                     # watch it finish, press q
    3. :checkhealth vimtex       # should be all green
    4. Restart nvim.

  Try it:

    mkdir -p ~/tex/scratch && cd ~/tex/scratch
    nvim main.tex

  Then type, in insert mode:

    \documentclass{article}
    \usepackage{amsmath,amssymb}
    \begin{document}
    dm          -> expands to a display math block
    sum         -> \sum_{i=1}^{n}
    ;a          -> \alpha
    //          -> \frac{}{}
    \end{document}

  Keys (localleader is the comma):

    ,ll   start continuous compile     ,lk   stop compile
    ,lv   jump PDF to cursor           ,le   open error list
    ,lc   clean aux files              ,lt   table of contents
    dse   delete surrounding env       cse   change surrounding env
    ]]    next section                 [[    previous section
    vie   select inside environment    vae   select around it

    <space>ff  find files   <space>fg  grep   <space>t  file tree
    gd  goto definition (works on \ref)   K  hover (works on \cite)

  Build artifacts land in ./build/ so your source directory stays clean.
  Add build/ to .gitignore.

  To undo everything:  ./TerminalEditor.sh --uninstall   (prints commands, runs nothing)

NEXT
}

main