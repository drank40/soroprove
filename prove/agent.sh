#!/usr/bin/env bash
# agent.sh [-r ROUNDS] [-t TURNS] [-m MODEL]: let a Claude agent prove Spec/Invariants.lean.
# The agent works in a throwaway copy (runs/<time>/ws) and only its Solution.lean is kept;
# after each round verify.sh checks it against the locked spec and the verdict is fed back.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
rounds=3 turns=60 model=
while getopts r:t:m: o; do case $o in r) rounds=$OPTARG;; t) turns=$OPTARG;; m) model=$OPTARG;; *) exit 2;; esac; done

run="$here/runs/$(date +%Y%m%d-%H%M%S)"
ws="$run/ws"
mkdir -p "$ws"
cp -r "$here"/{lean-toolchain,lakefile.lean,Gen,Spec} "$ws"/
cp "$here/Spec/Invariants.lean" "$ws/Solution.lean"   # the stub: locked statements with `sorry`
(cd "$ws" && lake build -q Spec >/dev/null 2>&1)

task="Prove every theorem in Solution.lean, replacing each \`sorry\`.
The contract model is Gen/Model.lean; the statements' definitions are in Spec/Defs.lean.
Rules (a checker enforces them; breaking one means rejection):
- Do not change any theorem's name or statement. They are compared against a locked copy.
- Do not edit anything except Solution.lean. Solution.lean may import only Gen.Model and Spec.Defs.
- You may add your own lemmas and definitions (e.g. a stronger inductive invariant).
- No sorry, axiom, native_decide, #eval, macros or set_option debug.*: only the standard axioms are accepted.
Check your work with: lake build Solution"

prompt=$task
claude_args=(--max-turns "$turns" --permission-mode acceptEdits
  --allowedTools "Read,Edit,Write,Glob,Grep,Bash(lake build:*),Bash(lake env lean:*)"
  --disallowedTools "WebFetch,WebSearch")
[ -n "$model" ] && claude_args+=(--model "$model")

for ((i = 1; i <= rounds; i++)); do
  echo "== round $i"
  (cd "$ws" && env -u CLAUDECODE GLIBC_TUNABLES= LD_LIBRARY_PATH= claude -p "$prompt" "${claude_args[@]}") \
    > "$run/agent-$i.log" 2>&1
  cp "$ws/Solution.lean" "$run/Solution-$i.lean"
  if verdict=$("$here/verify.sh" "$run/Solution-$i.lean" 2>&1); then
    echo "$verdict"; cp "$run/Solution-$i.lean" "$run/Solution.lean"; echo "accepted: $run/Solution.lean"; exit 0
  fi
  echo "$verdict" | tail -5
  prompt="$task

The checker rejected your current Solution.lean:
$verdict
Fix it."
done
echo "not proved after $rounds rounds: $run"; exit 1
