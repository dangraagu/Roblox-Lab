#!/usr/bin/env bash
# mutate_obby.sh — the mutation gate for REVIEW-4's new assertions.
#
#   bash mutate_obby.sh
#
# Every assertion added for the obby is only worth what it CATCHES. This applies each mutation to
# the real source, runs the whole suite, records which specs noticed, and puts the file back —
# then verifies the tree is byte-identical to the baseline it started from.
#
# Two CONTROLS are included on purpose. A sweep that kills everything proves the harness is
# broken, not that the tests are good. 13 mutations, 12 killed, 2 controls survived, as of
# REVIEW-4.md §7 — and the survivor is disclosed there rather than fitted around.
set -u
cd "$(dirname "$0")"
LUAU="/c/Users/BAHS_A~1/AppData/Local/Temp/claude/C--Users-bahs-admin/ecae86a3-0220-4a1c-84bc-1986788bfefa/scratchpad/luau/luau.exe"
FILES="src/shared/Config.luau src/shared/VaultPath.luau src/shared/VaultFloor.luau src/shared/Ascent.luau src/server/Main.server.luau"

BASE=$(mktemp -d)
for f in $FILES; do mkdir -p "$BASE/$(dirname "$f")"; cp "$f" "$BASE/$f"; done
sha256sum $FILES > "$BASE/sha.txt"

restore() { for f in $FILES; do cp "$BASE/$f" "$f"; done
  (cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau >/dev/null 2>&1); }

# A kill mid-sweep must not leave the tree mutated.
trap restore EXIT INT TERM

# run every suite, print the names of the ones that failed
run_all() {
  local out=""
  for f in tests/*.spec.luau; do
    local n; n=$("$LUAU" "$f" 2>&1 | grep -oE "[0-9]+ failed" | head -1 | grep -oE "^[0-9]+")
    if [ -z "$n" ]; then n="ERR"; fi
    if [ "$n" != "0" ]; then out="$out $(basename "$f" .spec.luau)($n)"; fi
  done
  local n; n=$("$LUAU" check_vaultrunners.luau 2>&1 | grep -oE "[0-9]+ failed" | head -1 | grep -oE "^[0-9]+")
  if [ -z "$n" ]; then n="ERR"; fi
  if [ "$n" != "0" ]; then out="$out headless($n)"; fi
  if [ -z "$out" ]; then echo "SURVIVED — nothing noticed"; else echo "killed by:$out"; fi
}

mutate() { # name, then a sed-style python edit already applied by the caller
  printf '%-62s ' "$1"
  (cd ../robloxemu && py -3 wrap.py --game ../vault-runners --out build/vault-runners.luau >/dev/null 2>&1)
  run_all
  restore
}

echo "== baseline"
printf '%-62s ' "no mutation at all (the harness itself)"
run_all
echo ""
echo "== mutations"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tStepSize = 3,","\tStepSize = 5,",1).replace("\tStepReach = 8,","\tStepReach = 6,",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "v1's staircase restored (StepSize 5, StepReach 6)"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tCrumbleSeconds = 1.1,","\tCrumbleSeconds = 1e9,",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the pads never crumble (CrumbleSeconds 1e9)"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tRespawnSeconds = 3,","\tRespawnSeconds = 1e9,",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the pads never come back (RespawnSeconds 1e9)"

python - <<'EOF'
import io
p='src/shared/Ascent.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tif t0 == nil or now < t0 or now - t0 >= span then state.touchedAt[k] = now end",
            "\tstate.touchedAt[k] = now",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "standing on a pad renews it (a rug, not a crumbling platform)"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tModelMissChance = 0.04,","\tModelMissChance = 0,",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the budget stops paying for the obby (ModelMissChance 0)"

python - <<'EOF'
import io
p='src/shared/VaultPath.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\t\tif s < model.storeys - 1 then dt += climbBase end",
            "\t\tif s < model.storeys - 1 then dt += climb end",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the retry leaks into the walk demand (slack pays a premium on it)"

python - <<'EOF'
import io
p='src/shared/VaultPath.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\treturn attempts, p * attempts","\treturn attempts, attempts - n",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "E[misses] = attempts - n (the closed form's own first bug)"

python - <<'EOF'
import io
p='src/shared/VaultPath.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\t\tobbyBy[s + 1] = (s + 1) * climbRetry","\t\tobbyBy[s + 1] = 0",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the falls are not charged to the storey they land on"

python - <<'EOF'
import io
p='src/shared/VaultPath.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\t\tlocal w, o = m.walkDemandAt[s + 1] / frac, m.obbyBy[s + 1] / frac",
            "\t\tlocal w, o = m.walkDemandAt[s + 1] / frac, 0",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "...nor to the per-storey deadline"

python - <<'EOF'
import io
p='src/server/Main.server.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\t\t\tpart.CanCollide = ch.solid\n","\t\t\tpart.CanCollide = true\n",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the SERVER never actually removes a pad (pure logic, no effect)"

python - <<'EOF'
import io
p='src/server/Main.server.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\t\tif onPad ~= nil then Ascent.touch(Config, a.ascent, onStorey, onPad, now) end\n","",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the server never notices a runner standing on a pad"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace('\tStandRadius = 3,','\tStandRadius = 5,',1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the whole shaft reads as one platform (StandRadius 5)"

python - <<'EOF'
import io
p='src/shared/Ascent.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace('local dy = (pos.y - cfg.Run.RunnerRootHeight) - pad.y','local dy = pos.y - pad.y',1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "the stand test reads the ROOT, not the feet (pad 1 crumbles from the floor)"

echo ""
echo "== CONTROLS (nothing may notice)"

python - <<'EOF'
import io
p='src/shared/Config.luau'; s=io.open(p,encoding='utf-8').read()
s=s.replace("\tAccentColor = { r = 255, g = 196, b = 92 },","\tAccentColor = { r = 255, g = 0, b = 255 },",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "CONTROL: the HUD accent repainted magenta"

python - <<'EOF'
import io
p='src/shared/Ascent.luau'; s=io.open(p,encoding='utf-8').read()
# model.shafts is dense over storeys 0..storeys-2, so this guard can never fire.
s=s.replace("""		local sh: any = model.shafts[s + 1]
		if sh ~= nil then
			for _, p in ipairs(sh.pads :: { any }) do pads[#pads + 1] = { storey = s, index = p.index } end
		end""",
"""		local sh: any = model.shafts[s + 1]
		for _, p in ipairs(sh.pads :: { any }) do pads[#pads + 1] = { storey = s, index = p.index } end""",1)
io.open(p,'w',encoding='utf-8',newline='').write(s)
EOF
mutate "CONTROL: an unreachable nil-guard deleted from Ascent.new"

echo ""
echo "== the tree is back where it started"
sha256sum -c "$BASE/sha.txt"
# ...and stand the trap down before the backup goes, or its own restore prints five cp errors.
trap - EXIT INT TERM
rm -rf "$BASE"
