#!/usr/bin/env node
'use strict';
// luaujs: a Luau runner for this repo's specs and robloxemu checks, used while the native luau CLI is
// unavailable on this machine. Usage: node luau.js <script.luau> [args...]
// Exit code 0 on success, 1 on an uncaught error or a syntax error (like the luau CLI).
const { Worker, isMainThread } = require('worker_threads');

if (isMainThread && !process.env.LUAUJS_NO_WORKER) {
  const w = new Worker(__filename, {
    argv: process.argv.slice(2),
    env: { ...process.env, LUAUJS_NO_WORKER: '1' },
    resourceLimits: { stackSizeMb: 256, maxOldGenerationSizeMb: 8192 },
    stdout: false, stderr: false,
  });
  w.on('error', (e) => { console.error('luaujs worker error:', e); process.exitCode = 1; });
  w.on('exit', (code) => { if (process.exitCode === undefined) process.exitCode = code; });
} else {
  main();
}

function main() {
  const fs = require('fs');
  const path = require('path');
  const R = require('./runtime');
  const { parse, LuaSyntaxError } = require('./parser');
  const { generateChunk } = require('./codegen');
  const STD = require('./stdlib');
  R.setSyntaxErrorClass(LuaSyntaxError);

  const PRELUDE = '"use strict"; const {$LF, $NF, $E, $idx, $method, $setidx, $gget, $add, $sub, $mul, $div, $idiv, $mod, $pow, ' +
    '$unm, $concat, $len, $eq, $lt, $le, $gt, $ge, $tr, $fornum, $interp, $mktab, $iter, $callx, $mkfn, $rt, $req} = $R;\n';
  const RT = {
    $LF: R.LF, $NF: R.NF, $E: R.$E, $idx: R.$idx, $method: R.$method, $setidx: R.$setidx, $gget: R.$gget,
    $add: R.$add, $sub: R.$sub, $mul: R.$mul, $div: R.$div, $idiv: R.$idiv, $mod: R.$mod, $pow: R.$pow,
    $unm: R.$unm, $concat: R.$concat, $len: R.$len, $eq: R.$eq, $lt: R.$lt, $le: R.$le, $gt: R.$gt, $ge: R.$ge,
    $tr: R.$tr, $fornum: R.$fornum, $interp: R.$interp, $mktab: R.$mktab, $iter: R.$iter, $callx: R.$callx,
    $mkfn: R.$mkfn, $rt: R.$rt, $req: null,
  };

  const compileCache = new Map();
  function compile(src, chunkname) {
    const key = chunkname + '\u0000' + src;
    let factory = compileCache.get(key);
    if (!factory) {
      let ast;
      try { ast = parse(src, R.chunkDisplay(chunkname)); }
      catch (e) { if (e instanceof LuaSyntaxError) throw new R.LuaError(e.message, 0); throw e; }
      const g = generateChunk(ast);
      if (process.env.LUAUJS_DUMP) fs.writeFileSync(process.env.LUAUJS_DUMP + '/' + chunkname.replace(/[^A-Za-z0-9_.-]/g, '_').slice(-80) + '.js', g.js);
      const fn = new Function('$R', '$ENV', '$CN', '$I', PRELUDE + 'return ' + g.js + ';');
      factory = { fn, paths: g.importPaths };
      if (compileCache.size < 500) compileCache.set(key, factory);
    }
    return (env) => factory.fn(RT, env, chunkname, resolveImports(env, factory.paths));
  }
  // Load-time import resolution (luau_load's resolveImportSafe): nil anywhere -> nil, errors -> nil.
  function resolveImports(env, paths) {
    const out = new Array(paths.length);
    for (let i = 0; i < paths.length; i++) {
      const p = paths[i];
      let v;
      try {
        v = R.$gget(env, p[0]);
        for (let k = 1; k < p.length && v !== undefined; k++) v = R.$idx(v, p[k]);
      } catch (e) { v = undefined; }
      out[i] = v;
    }
    return out;
  }

  function sandboxEnv(base) {
    const t = new R.LuaTable();
    const mt = new R.LuaTable();
    mt.set('__index', base);
    mt.frozen = true;
    t.mt = mt;
    return t;
  }

  const modCache = new Map();
  let BASE;
  const cwd = process.cwd();
  function displayPath(p) {
    const rel = path.relative(cwd, p);
    const use = (!rel.startsWith('..') && !path.isAbsolute(rel)) ? rel : p;
    return use.replace(/\\/g, '/');
  }
  function builtinRequire(cn, args) {
    const name = args[0];
    if (typeof name !== 'string') throw R.rtError(`invalid argument #1 to 'require' (string expected, got ${R.typeName(name)})`);
    let dir = cwd;
    if (cn && cn[0] === '@') dir = path.dirname(path.resolve(cwd, cn.slice(1)));
    if (!(name.startsWith('./') || name.startsWith('../'))) throw R.rtError(`require path must start with a valid prefix: ./, ../ (got "${name}")`);
    const base = path.resolve(dir, name);
    const cands = [base + '.luau', base + '.lua', path.join(base, 'init.luau'), path.join(base, 'init.lua')];
    let file = null;
    for (const c of cands) { try { if (fs.statSync(c).isFile()) { file = c; break; } } catch (e) { /* next */ } }
    if (!file) throw R.rtError(`could not resolve require path "${name}" from ${dir}`);
    const key = path.resolve(file).toLowerCase();
    if (modCache.has(key)) {
      const v = modCache.get(key);
      if (v === LOADING) throw R.rtError(`cyclic module dependency on ${displayPath(file)}`);
      return [v];
    }
    modCache.set(key, LOADING);
    const src = fs.readFileSync(file, 'latin1');
    const env = sandboxEnv(BASE);
    const fn = compile(src, '@' + displayPath(file))(env);
    const prev = R.current;
    R.current = { gt: env, co: null };
    let r;
    try { r = R.callSync(fn, R.$E); }
    catch (e) { modCache.delete(key); throw e; }
    finally { R.current = prev; }
    if (r.length === 0 || r[0] === undefined) { modCache.delete(key); throw R.rtError(`module ${displayPath(file)} must return a value`); }
    modCache.set(key, r[0]);
    return [r[0]];
  }
  const LOADING = Symbol('loading');
  const host = { compile, require: builtinRequire };
  BASE = STD.makeBase(host);
  const REQUIRE = BASE.get('require');
  RT.$req = function* (f, cn, args) {
    if (f === REQUIRE) return builtinRequire(cn, args);
    return yield* R.$callx(f, args);
  };

  const file = process.argv[2];
  if (!file) { STD.writeErr('usage: luau.js <script.luau>\n'); process.exit(2); }
  let code = 0;
  try {
    const src = fs.readFileSync(file, 'latin1');
    const env = sandboxEnv(BASE);
    R.MAIN.gt = env;
    const cn = '@' + file.replace(/\\/g, '/');
    const fn = compile(src, cn)(env);
    R.callSync(fn, process.argv.slice(3));
  } catch (e) {
    const le = R.fromJsError(e);
    let msg = typeof le.value === 'string' ? le.value : (typeof le.value === 'number' ? R.fmtNum(le.value) : `(error object is a ${R.typeName(le.value)} value)`);
    if (le.trace.length) msg += '\nstacktrace:\n' + le.trace.join('\n');
    STD.writeErr(msg + '\n');
    code = 1;
  }
  STD.flushOut();
  process.exit(code);
}
