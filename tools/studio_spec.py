"""Run a pure-Luau *.spec.luau inside Roblox Studio when no luau CLI exists.

Loads every module in <game>/src/shared and <game>/tests (non-spec) as ModuleScripts in a temp folder,
rewrites the spec's string requires to point at them, wraps the spec itself as a ModuleScript (no
loadstring in the MCP context) and requires it under pcall. Prints are collected and returned.
Usage (from the repo root, with a Studio attached over MCP):
    PYTHONIOENCODING=utf-8 py -3 tools/studio_spec.py <game_dir> <game_dir>/tests/X.spec.luau
    DM=Server ...   when Studio is in Play mode (the Edit datamodel does not answer then)

Written on the night of 2026-10-09, when no luau CLI was on the machine. It runs PURE specs only (no files,
no robloxemu checks): those still need the CLI. A spec that hangs Studio hangs the MCP queue too; restart
Studio with tools/studio_open.ps1 (never kill StudioMCP.exe).
"""
import json, os, re, subprocess, sys

game, spec = sys.argv[1], sys.argv[2]
mods = {}
for d in ("src/shared", "tests"):
    p = os.path.join(game, d)
    for f in os.listdir(p):
        if f.endswith(".luau") and not f.endswith(".spec.luau"):
            mods[f[:-5]] = open(os.path.join(p, f), encoding="utf-8").read()

def rewrite(src):
    return re.sub(r'require\("(?:\.\./src/shared/|\./)([A-Za-z0-9_]+)"\)', r'require(__F.\1)', src)

def lit(s):
    n = 0
    while ("]" + "=" * n + "]") in s:
        n += 1
    return "[" + "=" * n + "[" + s + "]" + "=" * n + "]"

for k, v in list(mods.items()):
    if k == "__Spec":
        continue
    r = rewrite(v)
    if r != v:
        mods[k] = 'local __F = game:GetService("ServerStorage"):WaitForChild("__SpecRun")\n' + r
body = rewrite(open(spec, encoding="utf-8").read())
prelude = ('local __F = game:GetService("ServerStorage"):WaitForChild("__SpecRun")\n'
           'local print = function(...) local t = table.pack(...); for i = 1, t.n do t[i] = tostring(t[i]) end; '
           'table.insert(_G.__specOut, table.concat(t, " ")) end\n')
mods["__Spec"] = prelude + body + "\nreturn true\n"

parts = ['local SS = game:GetService("ServerStorage")',
         'local old = SS:FindFirstChild("__SpecRun"); if old then old:Destroy() end',
         'local __F = Instance.new("Folder"); __F.Name = "__SpecRun"',
         'local function add(n, s) local m = Instance.new("ModuleScript"); m.Name = n; m.Source = s; m.Parent = __F end']
for name, src in mods.items():
    parts.append("add(%s, %s)" % (json.dumps(name), lit(src)))
parts += ["__F.Parent = SS",
          "_G.__specOut = {}",
          "local ok, err = pcall(require, __F.__Spec)",
          "__F:Destroy()",
          'return table.concat(_G.__specOut, "\\n") .. "\\nOK=" .. tostring(ok) .. (ok and "" or (" ERR=" .. tostring(err)))']
tmp = os.path.join(os.environ.get("TEMP", "."), "_studio_spec_payload.luau")
open(tmp, "w", encoding="utf-8").write("\n".join(parts))
r = subprocess.run(["py", "-3", "tools/studio_mcp.py", "luau", "--file", tmp, "--datamodel", os.environ.get("DM", "Edit")],
                   cwd="D:/Claude/Roblox", capture_output=True, text=True, encoding="utf-8", errors="replace")
print(r.stdout[-6000:], r.stderr[-2000:])
