#!/usr/bin/env bash
# Install the Octaweave skill into a coding agent.
#
#   ./install.sh            OMP     -> ~/.omp/agent/skills/octaweave
#   ./install.sh claude     Claude  -> ~/.claude/skills/octaweave
#   ./install.sh codex      Codex   -> ~/.codex/prompts/octaweave.md (+ prints the AGENTS.md line)
#
# Symlinks, not copies, so `git pull` updates them in place. Restart the agent
# afterwards so skill discovery runs again.
#
# The Metalcraft Agent pack is not installed from here — it is published to the pack
# registry. See metalcraft-agent/README.md.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-omp}"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "refusing to replace a real file: $dst" >&2
    exit 1
  fi
  ln -sfn "$src" "$dst"
  echo "$dst -> $src"
}

case "$target" in
  omp)
    link "$here/omp/skills/octaweave" "$HOME/.omp/agent/skills/octaweave"
    ;;
  claude)
    link "$here/claude/skills/octaweave" "$HOME/.claude/skills/octaweave"
    ;;
  codex)
    link "$here/codex/prompts/octaweave.md" "$HOME/.codex/prompts/octaweave.md"
    echo
    echo "Codex has no skill discovery. Add the instructions to a project's AGENTS.md:"
    echo "  cat $here/codex/AGENTS.md >> ./AGENTS.md"
    echo "or to every project, via ~/.codex/AGENTS.md."
    ;;
  *)
    echo "usage: $0 [omp|claude|codex]" >&2
    exit 2
    ;;
esac

echo
echo "Set your key before using it:  export OCTAWEAVE_API_KEY=owk_live_…"
