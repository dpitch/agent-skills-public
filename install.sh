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
mkdir -p "$HOME/.claude"
[ -s "$HOME/.claude/CLAUDE.md" ] || cp "$SRC/cloud-rules.md" "$HOME/.claude/CLAUDE.md"
echo "agent-skills-public: $n skills installed"
