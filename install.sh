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
# Revyl (cloud iOS/Android/web devices): CLI + its skills + 1Password CLI, in every cloud session. Public, no secret
# here. The environment's OP_SERVICE_ACCOUNT_TOKEN (read-only on the 1Password vault cloud-agents) reaches the session
# only after this setup runs, so `revyl` on PATH is a small wrapper: on first use it signs in with
# op://cloud-agents/Revyl API/credential, then runs the real CLI. Never fails the session. Details in /tmp/revyl-install.log.
RV_DIR=/usr/local/bin; [ -w "$RV_DIR" ] || RV_DIR="$HOME/.local/bin"; mkdir -p "$RV_DIR"
RV_REAL="$HOME/.revyl/bin/revyl"; RV_LOG=/tmp/revyl-install.log; RV_MARK="agent-skills-public revyl wrapper"
mkdir -p "$(dirname "$RV_REAL")"
# an older setup put the real binary on PATH: move it behind the wrapper
if [ -x "$RV_DIR/revyl" ] && ! grep -q "$RV_MARK" "$RV_DIR/revyl" 2>/dev/null && [ ! -x "$RV_REAL" ]; then mv "$RV_DIR/revyl" "$RV_REAL"; fi
if [ ! -x "$RV_REAL" ]; then
  # 1. Revyl's installer; 2. the release binary straight from GitHub; 3. the PyPI package
  { curl -fsSL https://raw.githubusercontent.com/RevylAI/revyl-cli/main/scripts/install.sh \
      | REVYL_INSTALL_DIR="$(dirname "$RV_REAL")" REVYL_NO_MODIFY_PATH=1 sh; } >"$RV_LOG" 2>&1
  if [ ! -x "$RV_REAL" ]; then
    rv_arch=$(uname -m); case $rv_arch in x86_64|amd64) rv_arch=amd64 ;; aarch64|arm64) rv_arch=arm64 ;; esac
    rv_tag=$(curl -fsSL https://api.github.com/repos/RevylAI/revyl-cli/releases/latest 2>>"$RV_LOG" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
    echo "direct download: tag=$rv_tag arch=$rv_arch" >>"$RV_LOG"
    [ -n "$rv_tag" ] && curl -fsSL -o "$RV_REAL" "https://github.com/RevylAI/revyl-cli/releases/download/$rv_tag/revyl-linux-$rv_arch" >>"$RV_LOG" 2>&1 \
      && chmod +x "$RV_REAL" || rm -f "$RV_REAL"
  fi
  if [ ! -x "$RV_REAL" ]; then
    echo "pip fallback" >>"$RV_LOG"
    { pip install -q revyl || pip install -q --break-system-packages revyl; } >>"$RV_LOG" 2>&1
    p=$(command -v revyl 2>/dev/null); [ -n "$p" ] && [ "$p" != "$RV_DIR/revyl" ] && ln -sf "$p" "$RV_REAL"
  fi
fi
if ! command -v op >/dev/null 2>&1 && [ ! -x "$RV_DIR/op" ]; then
  # 1Password CLI from 1Password's download server (no apt, gpg or unzip needed)
  op_v=$(curl -fsSL https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N 2>>"$RV_LOG" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
  op_a=$(uname -m); case $op_a in x86_64|amd64) op_a=amd64 ;; aarch64|arm64) op_a=arm64 ;; esac
  echo "op download: v=$op_v arch=$op_a" >>"$RV_LOG"
  [ -n "$op_v" ] && curl -fsSL -o /tmp/op.zip "https://cache.agilebits.com/dist/1P/op2/pkg/v$op_v/op_linux_${op_a}_v$op_v.zip" >>"$RV_LOG" 2>&1 \
    && python3 -c "import zipfile,sys; zipfile.ZipFile('/tmp/op.zip').extract('op', sys.argv[1])" "$RV_DIR" >>"$RV_LOG" 2>&1 \
    && chmod +x "$RV_DIR/op"; rm -f /tmp/op.zip
fi
if [ -x "$RV_REAL" ]; then
  cat > "$RV_DIR/revyl" <<WRAP
#!/bin/sh
# $RV_MARK: signs in with the cloud-agents key on first use, then runs the real CLI.
REAL="$RV_REAL"
if [ -z "\${REVYL_API_KEY:-}" ] && [ -n "\${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ ! -s "\${REVYL_AUTH_DIRECTORY:-\$HOME/.revyl}/credentials.json" ]; then
  OP=\$(command -v op 2>/dev/null || echo "$RV_DIR/op")
  [ -x "\$OP" ] && REVYL_API_KEY="op://cloud-agents/Revyl API/credential" "\$OP" run -- "\$REAL" auth persist-cloud-env >/dev/null 2>&1
fi
exec "\$REAL" "\$@"
WRAP
  chmod +x "$RV_DIR/revyl"
  "$RV_REAL" skill install --claude --cli --global --force --yes >>"$RV_LOG" 2>&1 && echo "revyl: CLI, skills and sign-in wrapper installed" || echo "revyl: skill install failed (see $RV_LOG)"
else
  echo "revyl: CLI install failed (see $RV_LOG)"
fi
mkdir -p "$HOME/.claude"
[ -s "$HOME/.claude/CLAUDE.md" ] || cp "$SRC/cloud-rules.md" "$HOME/.claude/CLAUDE.md"
echo "agent-skills-public: $n skills installed"
