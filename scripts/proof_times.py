#!/usr/bin/env python3
"""Time every theorem in Lean files of this project.

    python3 scripts/proof_times.py StellarLean/SorobanAmmAnswers.lean [more files] [--runs N]

Each file is elaborated `N` times (default 5) with Lean's profiler and with
asynchronous proof elaboration turned off (otherwise proofs run in background
tasks and their time is not attributed to the theorem). For each theorem the
median time is printed, in milliseconds: statement plus proof, measured by
Lean itself, without process start-up and imports. Imports must be built
(`lake build`) first.
"""

import re
import statistics
import subprocess
import sys

TOP = re.compile(r"^\[Elab\.command\] \[([0-9.]+)\] \S+ ?(.*)$")
NAME = re.compile(r"\b(?:theorem|lemma)\s+([^\s:({\[]+)")


def run_once(path):
    out = subprocess.run(
        ["lake", "env", "lean", "-DElab.async=false", "-Dtrace.profiler=true",
         "-Dtrace.profiler.threshold=0", path],
        capture_output=True, text=True).stdout
    times, current = {}, None
    for line in out.splitlines():
        m = TOP.match(line)
        if m:
            current = [float(m.group(1)), None]
            n = NAME.search(m.group(2))
            if n:
                current[1] = n.group(1)
                times[n.group(1)] = current[0] * 1000
            continue
        # The command's text continues on the following lines, up to its first child.
        if current and current[1] is None and not line.lstrip().startswith("["):
            n = NAME.search(line)
            if n:
                current[1] = n.group(1)
                times[n.group(1)] = current[0] * 1000
        elif line.lstrip().startswith("["):
            current = None if current and current[1] else current
    if "error" in out and re.search(r":\d+:\d+: error", out):
        sys.exit(f"{path} has errors:\n{out[:2000]}")
    return times


def main():
    args = sys.argv[1:]
    runs = 5
    if "--runs" in args:
        i = args.index("--runs")
        runs = int(args[i + 1])
        del args[i:i + 2]
    for path in args:
        samples = [run_once(path) for _ in range(runs)]
        names = list(samples[0])
        print(f"\n{path}  (median of {runs} runs, ms)")
        total = 0.0
        for n in names:
            t = statistics.median(s[n] for s in samples)
            total += t
            print(f"  {t:9.1f}  {n}")
        print(f"  {total:9.1f}  total")


if __name__ == "__main__":
    main()
