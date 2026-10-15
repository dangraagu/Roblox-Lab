#!/usr/bin/env bash
# Outpost Zero — every gate, in order, judged by exit code. Run from anywhere:
#   bash outpost-zero/tools/gates.sh            # with the native luau CLI if LUAU is set, else tools/luaujs
#   LUAU=/path/to/luau.exe bash outpost-zero/tools/gates.sh
# Prints one line per gate (its last output line) and a final tally; exits 1 if any gate failed.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
EMU="$HERE/../robloxemu"
if [ -n "${LUAU:-}" ]; then RUN=("$LUAU"); else RUN=(node "$HERE/tools/luaujs/luau.js"); fi

ok=0; bad=0
gate() { # dir file [runner...]
  local dir="$1" file="$2" out code
  shift 2
  local run=("${RUN[@]}")
  if [ $# -gt 0 ]; then run=("$@"); fi
  out="$(cd "$dir" && "${run[@]}" "$file" 2>&1)"; code=$?
  local last; last="$(printf '%s\n' "$out" | grep -v '^\s*$' | tail -1)"
  if [ $code -eq 0 ]; then ok=$((ok+1)); printf 'PASS  %-40s %s\n' "$file" "$last"
  else bad=$((bad+1)); printf 'FAIL  %-40s %s\n' "$file" "$last"; printf '%s\n' "$out" | grep -E 'FAIL|error' | head -5; fi
}

for t in "$HERE"/tests/*.spec.luau; do gate "$HERE" "tests/$(basename "$t")"; done
# the place settings (default.project.json) are not in the bundle, so a Python check reads them (REVIEW-1 F8)
gate "$HERE" "tests/project_check.py" py -3
(cd "$EMU" && py -3 wrap.py --game ../outpost-zero --out build/outpost-zero.luau >/dev/null) || { echo "wrap.py failed"; exit 1; }
for c in check_outpostzero.luau check_outpostzero_save.luau check_outpostzero_board.luau check_outpostzero_sky.luau \
         check_outpostzero_hazards.luau check_outpostzero_airship.luau check_outpostzero_hud.luau check_outpostzero_compile.luau \
         check_outpostzero_latency.luau check_outpostzero_start.luau check_outpostzero_handover.luau; do
  gate "$EMU" "$c"
done
gate "$HERE" "tests/walk.luau"
echo "gates: $ok passed, $bad failed"
[ $bad -eq 0 ]
