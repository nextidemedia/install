#!/bin/bash
# macOS 14+ on Apple silicon; works from a clone or via curl | bash.
set -euo pipefail

fail() { printf 'FIX   %s\n' "$*" >&2; exit 1; }
step() {
    local label=$1
    shift
    "$@" >/dev/null 2>&1 || fail "$label failed. See the manual setup in START_HERE.md, then rerun."
    printf 'ok    %s\n' "$label"
}
ask() {
    [[ -t 1 && -r /dev/tty ]] || fail 'Open Terminal and rerun, or use --non-interactive with --agent skip.'
    printf '%s: ' "$1" >/dev/tty
    IFS= read -r answer </dev/tty || fail 'No answer received. Rerun when ready.'
}
check_folder() {
    case "$1/" in
        *'/OneDrive/'*|*'/OneDrive - '*|*'/iCloud Drive/'*|*'/iCloudDrive/'*|*'/Library/Mobile Documents/'*|*'/Library/CloudStorage/'*)
            fail 'Choose a folder outside OneDrive or iCloud Drive with VIDEO_MAKER_DIR or --dir.' ;;
    esac
}

dir=${VIDEO_MAKER_DIR:-"$HOME/video-maker"}
ref=main
agent=
noninteractive=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir|--ref|--agent)
            [[ $# -ge 2 && -n $2 ]] || fail "$1 needs a value."
            case "$1" in --dir) dir=$2;; --ref) ref=$2;; --agent) agent=$2;; esac
            shift 2 ;;
        --non-interactive) noninteractive=true; shift ;;
        *) fail "Unknown option: $1" ;;
    esac
done
case "$agent" in ''|claude|codex|skip) ;; *) fail 'Choose --agent claude, codex, or skip.';; esac
[[ $(uname -s) == Darwin ]] || fail 'This installer needs macOS 14 or newer on Apple silicon.'
[[ $(uname -m) == arm64 ]] || fail 'Use an Apple-silicon Mac and Terminal without Rosetta.'
[[ $(sw_vers -productVersion | cut -d. -f1) -ge 14 ]] || fail 'Update to macOS 14 or newer first.'
printf 'ok    Supported Mac\n'

repo=
if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
    candidate=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
    if [[ -f $candidate/tools/doctor.py && -e $candidate/.git ]]; then repo=$candidate; fi
fi
if [[ -z $repo && -f tools/doctor.py && -e .git ]]; then repo=$(pwd -P); fi
if [[ -n $repo ]]; then check_folder "$repo"; else
    # Resolve existing symlink parents without requiring the clone to exist yet.
    parent=$dir
    tail=
    while [[ ! -d $parent ]]; do
        [[ ! -e $parent ]] || fail 'Choose another --dir; this path is not a folder.'
        tail="/$(basename "$parent")$tail"
        parent=$(dirname "$parent")
    done
    dir="$(cd "$parent" && pwd -P)$tail"
    check_folder "$dir"
fi

export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1
if [[ ! -x /opt/homebrew/bin/brew ]]; then
    $noninteractive && fail 'Install Homebrew interactively from brew.sh, then rerun.'
    printf 'fix   Install Homebrew (enter your Mac password if asked)\n'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
profile="$HOME/.zprofile"
[[ ${SHELL:-} != */bash ]] || profile="$HOME/.bash_profile"
line='eval "$(/opt/homebrew/bin/brew shellenv)"'
if ! grep -Fqx "$line" "$profile" 2>/dev/null; then
    printf '\n%s\n' "$line" >> "$profile"
    printf 'ok    Homebrew available in new terminals\n'
fi
require_tool() {
    if command -v "$1" >/dev/null; then printf 'skip  %s already installed\n' "$1"
    else step "Install $1" brew install "$1"; fi
}
require_tool git
require_tool gh

if [[ -z $repo ]]; then
    if [[ ! -e $dir ]]; then
        if ! gh auth status --hostname github.com >/dev/null 2>&1; then
            $noninteractive && fail 'Sign in with gh auth login, then rerun.'
            printf 'fix   Sign in to GitHub in your browser\n'
            gh auth login --hostname github.com --git-protocol https --web </dev/tty
        fi
        step 'Download video-maker' gh repo clone nextidemedia/video-maker "$dir" -- --branch "$ref"
    else printf 'skip  Existing folder (no update)\n'; fi
    origin=$(git -C "$dir" remote get-url origin 2>/dev/null) || fail 'Choose another --dir; this folder is not a video-maker clone.'
    [[ $origin =~ github\.com[:/]nextidemedia/video-maker(\.git)?$ && -f $dir/install.sh ]] ||
        fail 'Choose another --dir; this folder is not a video-maker clone with the installer.'
    args=(--dir "$dir") # macOS Bash 3.2 treats an empty array as unset under set -u.
    [[ -z $agent ]] || args+=(--agent "$agent")
    $noninteractive && args+=(--non-interactive)
    exec /bin/bash "$dir/install.sh" "${args[@]}"
fi

cd "$repo"
require_tool uv
require_tool node
if brew list --versions ffmpeg-full >/dev/null 2>&1; then printf 'skip  FFmpeg already installed\n'
else step 'Install FFmpeg' brew install ffmpeg-full; fi
export PATH="$(brew --prefix ffmpeg-full)/bin:$PATH"
line='export PATH="$(brew --prefix ffmpeg-full)/bin:$PATH"'
for ffprofile in "$HOME/.zprofile" "$profile"; do
    if ! grep -Fqx "$line" "$ffprofile" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$ffprofile"
        printf 'ok    FFmpeg available in new terminals\n'
    fi
done
chrome=${CHROME:-'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'}
if [[ -f $chrome ]]; then printf 'skip  Google Chrome already installed\n'
else step 'Install Google Chrome' brew install --cask google-chrome; fi
step 'Enable long file names' git config --global core.longpaths true
for key in user.name user.email; do
    if [[ -z $(git config "$key" || true) ]]; then
        $noninteractive && fail "Set git config --global $key before running without prompts."
        if [[ $key == user.name ]]; then ask 'Your name for Git'; else ask 'Your email for Git (saved locally)'; fi
        [[ -n $answer ]] || fail 'A name and email are needed for Git. Rerun when ready.'
        step 'Save Git identity locally' git config --global "$key" "$answer"
    fi
done
step 'Install the video toolkit' uv sync --locked
check=$(uv run python tools/doctor.py 2>&1) || true
if [[ $check == *'FIX   Node:'* ]]; then
    if brew list --versions node >/dev/null 2>&1; then step 'Update Node (doctor requires it)' brew upgrade node
    else step 'Install supported Node (doctor requires it)' brew install node; fi
    export PATH="$(brew --prefix node)/bin:$PATH"
    hash -r
fi
if [[ $check == *'FIX   ffmpeg:'* ]]; then step 'Update FFmpeg (doctor requires it)' brew upgrade ffmpeg-full; fi
projects=$(git ls-files -- 'projects/*/package.json') || fail 'Cannot find the sample projects. Check this clone and rerun.'
while IFS= read -r file; do
    [[ -n $file ]] || continue
    (cd "$(dirname "$file")" && step "Prepare $(basename "$(dirname "$file")")" npm ci --no-audit --no-fund)
done <<< "$projects"

if [[ -z $agent ]]; then
    if $noninteractive; then agent=skip
    elif command -v claude >/dev/null; then agent=claude
    elif command -v codex >/dev/null; then agent=codex
    else
        ask 'Claude Code, Codex, or skip? [claude]'
        agent=$(printf '%s' "${answer:-claude}" | tr '[:upper:]' '[:lower:]')
        [[ $agent != 'claude code' ]] || agent=claude
    fi
fi
case "$agent" in claude|codex|skip) ;; *) fail 'Choose claude, codex, or skip, then rerun.';; esac
if [[ $agent != skip ]]; then
    if ! command -v "$agent" >/dev/null; then
        package=@anthropic-ai/claude-code
        [[ $agent != codex ]] || package=@openai/codex
        before=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)
        step "Install $agent" npm install -g "$package@*" "--before=$before" --no-audit --no-fund
    else printf 'skip  %s already installed\n' "$agent"; fi
    if "$agent" mcp get nextide >/dev/null 2>&1; then printf 'skip  Nextide already configured\n'
    elif [[ $agent == claude ]]; then
        step 'Connect Nextide data' claude mcp add --transport http --scope user nextide https://mcp.nextide.io/mcp
    else step 'Connect Nextide data' codex mcp add nextide --url https://mcp.nextide.io/mcp; fi
    if [[ $agent == claude ]]; then printf 'next  In Claude Code, use /mcp to sign in with your Nextide Google account.\n'
    else printf 'next  Run codex mcp login nextide to sign in with your Nextide Google account.\n'; fi
else printf 'skip  Agent setup; connect Nextide later using START_HERE.md.\n'; fi

uv run python tools/doctor.py || fail 'Fix the items above, then rerun the installer.'
printf 'next  Open your agent in %s and say what you want.\n' "$repo"
