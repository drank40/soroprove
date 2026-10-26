#!/usr/bin/env bash
# agent.sh CONTRACT [-r ROUNDS] [-t TURNS] [-m MODEL]: let a Claude agent prove the
# contract's Spec/Invariants.lean. The agent works in a throwaway copy
# (runs/CONTRACT-<time>/ws) and only its Solution.lean is kept; after each round verify.sh
# checks it against the locked spec and the verdict is fed back.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
shift
rounds=3 turns=60 model=
while getopts r:t:m: o; do case $o in r) rounds=$OPTARG;; t) turns=$OPTARG;; m) model=$OPTARG;; *) exit 2;; esac; done

run="$here/runs/$contract-$(date +%Y%m%d-%H%M%S)"
ws="$run/ws"
mkdir -p "$ws"
assemble "$ws"
rm "$ws/Check.lean"
cp "$cdir/Spec/Invariants.lean" "$ws/Solution.lean"   # the stub: locked statements with `sorry`
(cd "$ws" && lake build -q Spec >/dev/null 2>&1)

task="Prove every theorem in Solution.lean, replacing each \`sorry\`.
The contract model is Gen/Model.lean (emitted from the contract's bytecode); the statements'
definitions are in Spec/Common.lean and Spec/Defs.lean.
Rules (a checker enforces them; breaking one means rejection):
- Do not change any theorem's name or statement. They are compared against a locked copy.
- Do not edit anything except Solution.lean. Solution.lean may import only Gen.Model,
  Spec.Common and Spec.Defs.
- You may add your own lemmas and definitions (e.g. a stronger inductive invariant).
- No sorry, axiom, native_decide, #eval, macros or set_option debug.*: only the standard axioms are accepted.
- If a theorem is false for this model, leave it as \`sorry\` and instead prove
  \`theorem <name>_false : ¬ (<its exact statement>)\` next to it; say why in a comment.
Check your work with: lake build Solution"

prompt=$task
# --safe-mode: no user settings, memory, hooks, plugins or connectors; --strict-mcp-config:
# no MCP servers. The agent edits files in its workspace and runs lake, nothing else.
claude_args=(--max-turns "$turns" --permission-mode acceptEdits --safe-mode --strict-mcp-config
  --allowedTools "Read,Edit,Write,Glob,Grep,Bash(lake build:*),Bash(lake env lean:*)"
  --disallowedTools "WebFetch,WebSearch")
[ -n "$model" ] && claude_args+=(--model "$model")

for ((i = 1; i <= rounds; i++)); do
  echo "== $contract round $i"
  (cd "$ws" && env -u CLAUDECODE GLIBC_TUNABLES= LD_LIBRARY_PATH= claude -p "$prompt" "${claude_args[@]}") \
    > "$run/agent-$i.log" 2>&1
  cp "$ws/Solution.lean" "$run/Solution-$i.lean"
  verdict=$("$here/verify.sh" "$contract" "$run/Solution-$i.lean" 2>&1); ok=$?
  echo "$verdict" | grep -E 'PROVED|DISPROVED|REJECT|locked theorems'
  cp "$run/Solution-$i.lean" "$run/Solution.lean"
  echo "$verdict" > "$run/verdict.txt"
  [ $ok -eq 0 ] && { echo "accepted: $run/Solution.lean"; exit 0; }
  # Stop once every theorem is settled (proved or disproved): more rounds won't help.
  grep -q '^REJECT' <<<"$verdict" || { echo "settled (some disproved): $run/Solution.lean"; exit 1; }
  prompt="$task

The checker's verdict on your current Solution.lean:
$verdict
Fix the rejected ones."
done
echo "not settled after $rounds rounds: $run"; exit 1
