# Platform Support

## Supported Platforms

| Platform | Status | Bash Source | Notes |
|---|---|---|---|
| MacOS 12+ (Monterey) | Full support | Homebrew (`brew install bash`) | Ships with bash 3.2; bash 4+ required |
| Ubuntu 20.04+ | Full support | System default | bash 5.0+ standard |
| Debian 11+ | Full support | System default | bash 5.1+ standard |
| Fedora 36+ | Full support | System default | bash 5.1+ standard |
| Arch Linux | Full support | System default | Rolling release, always current |
| Alpine Linux | Full support | `apk add bash` | Default shell is ash; bash must be installed |
| Windows 10+ via WSL2 | Full support | WSL distro default | Recommended Windows path |
| Windows 10+ via Git Bash | Supported with caveats | Bundled with Git for Windows | See limitations below |

## Required Tools

| Tool | Minimum Version | Purpose |
|---|---|---|
| bash | 4.0+ | Script execution (associative arrays, `${!var}`) |
| python3 (or python) | 3.8+ | Inline JSON operations, syntax validation, graph building |
| git | 2.20+ | Worktree management, branch operations |
| jq | 1.6+ (optional) | JSON parsing (falls back to python3 if absent) |

## Per-Platform Setup

### MacOS

```bash
# Install bash 4+ (MacOS ships with bash 3.2)
brew install bash

# Verify
bash --version  # Should show 4.x or 5.x

# Python 3 (usually pre-installed on MacOS 12+)
python3 --version

# Optional: GNU coreutils for timeout, gstat, etc.
brew install coreutils
```

### Ubuntu / Debian

```bash
# bash 4+ is pre-installed
bash --version

# Python 3 (usually pre-installed)
sudo apt install python3  # if missing

# Optional: jq
sudo apt install jq
```

### Fedora / RHEL

```bash
sudo dnf install bash python3 jq
```

### Arch Linux

```bash
sudo pacman -S bash python jq
```

### Windows (WSL2 -- Recommended)

```bash
# Install WSL2 (from PowerShell as admin)
wsl --install

# Inside WSL (Ubuntu default):
sudo apt install bash python3 jq git

# Verify
bash --version
python3 --version
```

### Windows (Git Bash)

```bash
# Install Git for Windows (includes bash 4+)
# Download: https://git-scm.com/download/win
# Or via scoop: scoop install git

# Install Python
# Via scoop: scoop install python
# Via winget: winget install Python.Python.3
# Or download: https://www.python.org/downloads/windows/

# Verify
bash --version
python3 --version  # or python --version
```

## Known Limitations

### Git Bash (MSYS2)

1. **No `flock` command.** All forge scripts use mkdir-based lock fallback when `flock` is unavailable. No user action needed.
2. **No `fcntl` Python module.** Forge uses `msvcrt` fallback for file locking in inline Python. No user action needed.
3. **Temp directory.** Set `TMPDIR`, `TMP`, or `TEMP` environment variable. Git Bash typically sets `TMP` and `TEMP` but not `TMPDIR`. Forge handles all three.
4. **`sleep` fractional seconds.** Git Bash supports `sleep 0.1` via MSYS2 coreutils. Minimal MSYS environments without coreutils may not; forge falls back to `sleep 1` where needed.
5. **`timeout` command.** Git Bash may not include GNU timeout. Forge falls back to running without timeout (via `portable_timeout`).
6. **Path separators.** Forge uses forward slashes throughout. Git Bash translates automatically. Paths stored in `.forge/state.json` always use forward slashes.
7. **Docker.** Docker Desktop for Windows must be running. WSL2 backend recommended.
8. **Line endings.** Clone the repo with `git config core.autocrlf input` to avoid `\r\n` in shell scripts.

### WSL2

1. **Docker access.** Requires Docker Desktop with WSL2 backend enabled, or Docker Engine installed inside WSL.
2. **File system performance.** Store the project inside the WSL filesystem (`/home/...`), not on a Windows mount (`/mnt/c/...`), for acceptable I/O performance.
3. **`/proc/version` detection.** Forge detects WSL via `/proc/version` containing "microsoft" or "wsl". Custom kernels that remove this marker will be detected as plain Linux.

### MacOS

1. **Default bash is 3.2.** Must install bash 4+ via Homebrew. Forge's `check-prerequisites.sh` detects and advises.
2. **BSD `stat` and `date`.** Forge handles BSD/GNU differences via cascading fallbacks in `portable_file_date()` and `state-integrity.sh`.

## Configuration

```yaml
platform:
  windows_mode: auto  # auto | wsl | gitbash
```

- `auto` (default): Forge detects the environment via `detect_os()` and `is_wsl()`.
- `wsl`: Force WSL-specific behavior (useful when auto-detection fails).
- `gitbash`: Force Git Bash-specific behavior (disable `/proc` checks, prefer `msvcrt` lock path).

This setting is read during PREFLIGHT and stored in `state.json` as `platform.detected_os` and `platform.windows_mode`.

## CI Matrix

Recommended GitHub Actions matrix for cross-platform validation:

| Runner | OS | Shell | Purpose |
|---|---|---|---|
| `macos-latest` | MacOS 14+ (Sonoma) | Homebrew bash | Primary dev platform |
| `ubuntu-latest` | Ubuntu 24.04 LTS | System bash | Linux baseline |
| `windows-latest` | Windows Server 2022 | Git Bash | Git Bash compatibility |

WSL2 is functionally identical to Ubuntu for bash script testing. WSL-specific OS detection is validated via unit tests that check `/proc/version` parsing.
