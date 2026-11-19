#!/bin/bash
# Installs the skills listed in skills.tsv from their public GitHub repos, and the cloud rules.
# Used as the first step of Claude Code cloud jobs. Nothing private lives here.
# Each source repo is fetched shallow and sparse: only the listed skill folders are downloaded.
set -u
SRC="$(cd "$(dirname "$0")" && pwd)"
CACHE="$HOME/.cache/skill-src"; mkdir -p "$CACHE"
n=0
for repo in $(grep -v '^#' "$SRC/skills.tsv" | cut -f2 | sort -u); do
  dir="$CACHE/$(echo "$repo" | sed -E 's#https://github.com/##; s#\.git$##; s#/#__#')"
  paths=$(awk -F'\t' -v r="$repo" '$2==r {print $3}' "$SRC/skills.tsv")
  if [ ! -d "$dir/.git" ]; then
    git clone -q --depth 1 --filter=blob:none --no-checkout "$repo" "$dir" 2>/dev/null || { echo "skip $repo (clone failed)"; continue; }
    git -C "$dir" sparse-checkout set --no-cone $(printf '/%s/\n' $paths) >/dev/null 2>&1
    git -C "$dir" checkout -q 2>/dev/null
  fi
  while IFS=$'\t' read -r name r path; do
    [ "$r" = "$repo" ] || continue
    [ -f "$dir/$path/SKILL.md" ] || { echo "skip $name (no SKILL.md)"; continue; }
    for root in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
      mkdir -p "$root"; [ -e "$root/$name" ] || ln -s "$dir/$path" "$root/$name"
    done
    n=$((n+1))
  done < <(grep -v '^#' "$SRC/skills.tsv")
done
# Revyl (cloud iOS/Android/web devices): CLI + its skills, in every cloud session. Public, no secret here:
# it signs in only when the environment holds OP_SERVICE_ACCOUNT_TOKEN (read-only on the 1Password vault
# cloud-agents), with the key op://cloud-agents/Revyl API/credential. Never fails the session.
RV_DIR=/usr/local/bin; [ -w "$RV_DIR" ] || RV_DIR="$HOME/.local/bin"; mkdir -p "$RV_DIR"
RV_LOG=/tmp/revyl-install.log
if ! command -v revyl >/dev/null 2>&1 && [ ! -x "$RV_DIR/revyl" ]; then
  # 1. Revyl's installer; 2. the release binary straight from GitHub; 3. the PyPI package. Details in $RV_LOG.
  { curl -fsSL https://raw.githubusercontent.com/RevylAI/revyl-cli/main/scripts/install.sh \
      | REVYL_INSTALL_DIR="$RV_DIR" REVYL_NO_MODIFY_PATH=1 sh; } >"$RV_LOG" 2>&1
  if [ ! -x "$RV_DIR/revyl" ]; then
    rv_arch=$(uname -m); case $rv_arch in x86_64|amd64) rv_arch=amd64 ;; aarch64|arm64) rv_arch=arm64 ;; esac
    rv_tag=$(curl -fsSL https://api.github.com/repos/RevylAI/revyl-cli/releases/latest 2>>"$RV_LOG" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    echo "direct download: tag=$rv_tag arch=$rv_arch" >>"$RV_LOG"
    [ -n "$rv_tag" ] && curl -fsSL -o "$RV_DIR/revyl" "https://github.com/RevylAI/revyl-cli/releases/download/$rv_tag/revyl-linux-$rv_arch" >>"$RV_LOG" 2>&1 \
      && chmod +x "$RV_DIR/revyl" || rm -f "$RV_DIR/revyl"
  fi
  if [ ! -x "$RV_DIR/revyl" ] && ! command -v revyl >/dev/null 2>&1; then
    echo "pip fallback" >>"$RV_LOG"
    { pip install -q revyl || pip install -q --break-system-packages revyl; } >>"$RV_LOG" 2>&1
  fi
  command -v revyl >/dev/null 2>&1 || [ -x "$RV_DIR/revyl" ] || echo "revyl: CLI install failed (see $RV_LOG)"
fi
RV=$(command -v revyl 2>/dev/null || echo "$RV_DIR/revyl")
if [ -x "$RV" ]; then
  "$RV" skill install --claude --cli --global --force --yes >>"$RV_LOG" 2>&1 && echo "revyl: CLI and skills installed" || echo "revyl: skill install failed"
  if [ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && ! "$RV" auth status >/dev/null 2>&1; then
    if ! command -v op >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      a=$(dpkg --print-architecture)
      { curl -fsS https://downloads.1password.com/linux/keys/1password.asc | gpg --batch --yes --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg \
        && echo "deb [arch=$a signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$a stable main" > /etc/apt/sources.list.d/1password.list \
        && apt-get update -qq -o Dir::Etc::sourcelist=sources.list.d/1password.list -o Dir::Etc::sourceparts=- \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq 1password-cli; } >/dev/null 2>&1 || echo "revyl: 1Password CLI install failed"
    fi
    REVYL_API_KEY="op://cloud-agents/Revyl API/credential" op run -- "$RV" auth persist-cloud-env >/dev/null 2>&1 \
      && echo "revyl: signed in (cloud-agents key)" || echo "revyl: sign-in failed"
  fi
fi
mkdir -p "$HOME/.claude"
[ -s "$HOME/.claude/CLAUDE.md" ] || cp "$SRC/cloud-rules.md" "$HOME/.claude/CLAUDE.md"
echo "agent-skills-public: $n skills installed"
