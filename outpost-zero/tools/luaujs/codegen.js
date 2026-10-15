'use strict';
// AST -> JavaScript source. Every Luau function becomes a JS generator function so coroutines can
// yield from any depth (yield* delegation). Locals become uniquely named `let`s; upvalues are JS
// closures. Multiple results travel as arrays.

const CMP = new Set(['==', '~=', '<', '<=', '>', '>=']);
const ARITH = { '+': '$add', '-': '$sub', '*': '$mul', '/': '$div', '//': '$idiv', '%': '$mod', '^': '$pow', '..': '$concat' };

class Scope {
  constructor(parent) { this.parent = parent; this.vars = new Map(); this.hoist = null; }
  find(n) { for (let s = this; s; s = s.parent) { const v = s.vars.get(n); if (v) return v; } return null; }
}

class FuncState {
  constructor(parent, vararg) { this.parent = parent; this.vararg = vararg; this.ntemps = 0; this.loops = []; }
  temp() { this.ntemps++; return '$t' + this.ntemps; }
}

function generate(ast, opts) {
  opts = opts || {};
  const written = opts.written || new Set(); // globals assigned anywhere in this chunk (pass 1 result)
  const noImports = !!opts.noImports;
  const imports = new Map(); // "a.b.c" -> index
  const importPaths = [];
  let uid = 0;
  let scope = null;
  let fs = null;
  let labelId = 0;

  const mangle = (n) => { uid++; return 'L' + uid + '_' + n; };
  const declare = (n) => {
    const js = mangle(n);
    scope.vars.set(n, js);
    return js;
  };
  const pushScope = () => { scope = new Scope(scope); };
  const popScope = () => { scope = scope.parent; };

  // Luau resolves an "import" (a global not written in this chunk, optionally followed by up to two
  // constant `.name` keys) once, when the chunk is loaded into a safe environment, and reads the cached
  // value afterwards. A nil result falls back to a dynamic lookup at run time.
  function importOf(e) {
    if (noImports) return null;
    const path = [];
    let cur = e;
    while (cur.k === 'index') {
      if (cur.key.k !== 'str' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(cur.key.v)) return null;
      path.unshift(cur.key.v);
      cur = cur.obj;
    }
    if (cur.k !== 'name' || scope.find(cur.name) || written.has(cur.name)) return null;
    path.unshift(cur.name);
    if (path.length > 3) return null;
    const key = path.join('.');
    let i = imports.get(key);
    if (i === undefined) { i = importPaths.length; imports.set(key, i); importPaths.push(path); }
    return `$I[${i}]`;
  }
  const isMulti = (e) => e.k === 'call' || e.k === 'method' || e.k === 'vararg';

  // ------------------------------------------------------------------ expressions
  function callArgs(args) { return list(args); }
  function list(exprs) {
    if (exprs.length === 0) return '$E';
    const parts = [];
    for (let i = 0; i < exprs.length; i++) {
      const e = exprs[i];
      if (i === exprs.length - 1 && isMulti(e)) parts.push('...' + multi(e));
      else parts.push(expr(e));
    }
    return '[' + parts.join(', ') + ']';
  }
  function dispatch(tf, ta) {
    return `(${tf} instanceof $LF ? (yield* ${tf}.g(${ta})) : (${tf} instanceof $NF && ${tf}.gy === null) ? ${tf}.f(${ta}) : (yield* $callx(${tf}, ${ta})))`;
  }
  function multi(e) { // JS expr producing an array
    if (e.k === 'vararg') {
      if (!fs.vararg) throw new Error('cannot use ... outside a vararg function');
      return '$va';
    }
    if (e.k === 'call') {
      if (e.fn.k === 'name' && e.fn.name === 'require' && !scope.find('require')) {
        return `(yield* $req(${expr(e.fn)}, $CN, ${callArgs(e.args)}))`;
      }
      const tf = fs.temp(), ta = fs.temp();
      return `(${tf} = ${expr(e.fn)}, ${ta} = ${callArgs(e.args)}, ${dispatch(tf, ta)})`;
    }
    if (e.k === 'method') {
      const to = fs.temp(), tf = fs.temp(), ta = fs.temp();
      const argsJs = list(e.args);
      const argsExpr = argsJs === '$E' ? `[${to}]` : `[${to}, ${argsJs.slice(1)}`;
      return `(${to} = ${expr(e.obj)}, ${tf} = $method(${to}, ${JSON.stringify(e.name)}), ${ta} = ${argsExpr}, ${dispatch(tf, ta)})`;
    }
    throw new Error('not a multi expression');
  }
  function str(v) { return JSON.stringify(v); }
  function num(v) {
    if (Number.isNaN(v)) return 'NaN';
    if (v === Infinity) return 'Infinity';
    return String(v);
  }
  function cond(e) { // JS boolean expression
    switch (e.k) {
      case 'true': return 'true';
      case 'false': case 'nil': return 'false';
      case 'and': return `(${cond(e.a)} && ${cond(e.b)})`;
      case 'or': return `(${cond(e.a)} || ${cond(e.b)})`;
      case 'un': if (e.op === 'not') return `!${cond(e.a)}`; break;
      case 'bin': if (CMP.has(e.op)) return expr(e); break;
      case 'paren': return cond(e.e);
    }
    return `$tr(${expr(e)})`;
  }
  function expr(e) {
    switch (e.k) {
      case 'nil': return 'undefined';
      case 'true': return 'true';
      case 'false': return 'false';
      case 'num': return num(e.v);
      case 'str': return str(e.v);
      case 'vararg': return '$va[0]';
      case 'paren': return expr(e.e);
      case 'func': return func(e);
      case 'name': {
        const v = scope.find(e.name);
        if (v) return v;
        const dyn = `$gget($ENV, ${str(e.name)})`;
        const imp = importOf(e);
        return imp ? `(${imp} !== undefined ? ${imp} : ${dyn})` : dyn;
      }
      case 'index': {
        const dyn = `$idx(${expr(e.obj)}, ${expr(e.key)})`;
        const imp = importOf(e);
        return imp ? `(${imp} !== undefined ? ${imp} : ${dyn})` : dyn;
      }
      case 'call': case 'method': return `${multi(e)}[0]`;
      case 'and': { const t = fs.temp(); return `((${t} = ${expr(e.a)}) === undefined || ${t} === false ? ${t} : ${expr(e.b)})`; }
      case 'or': { const t = fs.temp(); return `((${t} = ${expr(e.a)}) === undefined || ${t} === false ? ${expr(e.b)} : ${t})`; }
      case 'un':
        if (e.op === 'not') return `!${cond(e.a)}`;
        if (e.op === '-') {
          if (e.a.k === 'num') return '(-' + num(e.a.v) + ')';
          return `$unm(${expr(e.a)})`;
        }
        return `$len(${expr(e.a)})`;
      case 'bin': {
        const a = expr(e.a), b = expr(e.b);
        switch (e.op) {
          case '==': return `$eq(${a}, ${b})`;
          case '~=': return `!$eq(${a}, ${b})`;
          case '<': return `$lt(${a}, ${b})`;
          case '<=': return `$le(${a}, ${b})`;
          case '>': return `$gt(${a}, ${b})`;
          case '>=': return `$ge(${a}, ${b})`;
        }
        return `${ARITH[e.op]}(${a}, ${b})`;
      }
      case 'ifexp': {
        let out = expr(e.els);
        for (let i = e.conds.length - 1; i >= 0; i--) out = `(${cond(e.conds[i][0])} ? ${expr(e.conds[i][1])} : ${out})`;
        return out;
      }
      case 'interp': {
        const parts = e.parts.map((p, i) => (i % 2 === 0 ? str(p) : expr(p)));
        return `$interp([${parts.join(', ')}])`;
      }
      case 'table': {
        const pos = [], kv = [];
        const posItems = e.items.filter((it) => it.type === 'pos');
        for (const it of e.items) {
          if (it.type === 'pos') {
            if (it === posItems[posItems.length - 1] && isMulti(it.e)) pos.push('...' + multi(it.e));
            else pos.push(expr(it.e));
          } else {
            kv.push(expr(it.key), expr(it.val));
          }
        }
        if (kv.length === 0) return `$mktab([${pos.join(', ')}])`;
        return `$mktab([${pos.join(', ')}], [${kv.join(', ')}])`;
      }
    }
    throw new Error('codegen: unknown expression ' + e.k);
  }

  // ------------------------------------------------------------------ functions
  function func(f) {
    const outerFs = fs;
    fs = new FuncState(outerFs, f.vararg);
    pushScope();
    const params = f.params.map((p) => declare(p));
    const body = blockStmts(f.body);
    popScope();
    let head = '';
    if (params.length) head += 'let ' + params.map((p, i) => `${p} = A[${i}]`).join(', ') + ';';
    if (f.vararg) head += ` const $va = A.length > ${params.length} ? A.slice(${params.length}) : $E;`;
    const temps = [];
    for (let i = 1; i <= fs.ntemps; i++) temps.push('$t' + i);
    const tdecl = temps.length ? `let ${temps.join(', ')};` : '';
    fs = outerFs;
    return `$mkfn(function* (A) { ${head} let $ln = ${f.line}; ${tdecl}\ntry {\n${body}\nreturn $E;\n} catch ($e) { throw $rt($e, $CN, $ln); } }, ${str(f.name)}, $CN, ${f.line}, ${params.length}, ${f.vararg})`;
  }

  // ------------------------------------------------------------------ statements
  function blockStmts(stats) {
    const out = [];
    for (const s of stats) out.push(stmt(s));
    return out.join('\n');
  }
  function block(stats) {
    pushScope();
    const b = blockStmts(stats);
    popScope();
    return b;
  }
  function assignTo(target, valueJs) {
    if (target.k === 'name') {
      const v = scope.find(target.name);
      if (v) return `${v} = ${valueJs};`;
      written.add(target.name);
      return `$setidx($ENV, ${str(target.name)}, ${valueJs});`;
    }
    return `$setidx(${expr(target.obj)}, ${expr(target.key)}, ${valueJs});`;
  }
  function localDecl(names, valuesJs) { // valuesJs: array of js exprs (same length as names)
    const hoist = scope.hoist;
    const js = names.map((n) => declare(n));
    if (hoist) {
      hoist.push(...js);
      return js.map((n, i) => `${n} = ${valuesJs[i]};`).join(' ');
    }
    return 'let ' + js.map((n, i) => `${n} = ${valuesJs[i]}`).join(', ') + ';';
  }
  function stmt(s) {
    const ln = `$ln = ${s.line || 0}; `;
    switch (s.k) {
      case 'local': {
        const n = s.names.length, m = s.exprs.length;
        const pre = [];
        const vals = [];
        if (m > 0 && m < n && isMulti(s.exprs[m - 1])) {
          for (let i = 0; i < m - 1; i++) vals.push(expr(s.exprs[i]));
          const t = fs.temp();
          pre.push(`${t} = ${multi(s.exprs[m - 1])};`);
          for (let i = m - 1; i < n; i++) vals.push(`${t}[${i - (m - 1)}]`);
          // values before the multi call must be evaluated first: use temps for them
          const tv = [];
          for (let i = 0; i < m - 1; i++) { const tt = fs.temp(); tv.push(`${tt} = ${vals[i]};`); vals[i] = tt; }
          return ln + tv.join(' ') + ' ' + pre.join(' ') + ' ' + localDecl(s.names, vals);
        }
        for (let i = 0; i < n; i++) vals.push(i < m ? expr(s.exprs[i]) : 'undefined');
        const extra = [];
        for (let i = n; i < m; i++) extra.push((isMulti(s.exprs[i]) ? multi(s.exprs[i]) : expr(s.exprs[i])) + ';');
        if (extra.length) {
          // evaluate in order: names' values into temps, then the extras, then bind
          const tv = vals.map((v) => { const tt = fs.temp(); pre.push(`${tt} = ${v};`); return tt; });
          return ln + pre.join(' ') + ' ' + extra.join(' ') + ' ' + localDecl(s.names, tv);
        }
        return ln + localDecl(s.names, vals);
      }
      case 'localfunc': {
        const hoist = scope.hoist;
        const js = declare(s.name);
        const f = func(s.func);
        if (hoist) { hoist.push(js); return `${ln}${js} = ${f};`; }
        return `${ln}let ${js}; ${js} = ${f};`;
      }
      case 'assign': {
        if (s.targets.length === 1 && s.exprs.length === 1) {
          const t = s.targets[0];
          const v = s.exprs[0];
          if (t.k === 'index') {
            return `${ln}$setidx(${expr(t.obj)}, ${expr(t.key)}, ${expr(v)});`;
          }
          return ln + assignTo(t, expr(v));
        }
        // general: evaluate target objects/keys, then values, then assign left to right
        const pre = [];
        const targets = s.targets.map((t) => {
          if (t.k === 'index') {
            const o = fs.temp(), k = fs.temp();
            pre.push(`${o} = ${expr(t.obj)}; ${k} = ${expr(t.key)};`);
            return { k: 'idx', o, key: k };
          }
          return t;
        });
        const vt = fs.temp();
        pre.push(`${vt} = ${list(s.exprs)};`);
        const asg = targets.map((t, i) => {
          if (t.k === 'idx') return `$setidx(${t.o}, ${t.key}, ${vt}[${i}]);`;
          return assignTo(t, `${vt}[${i}]`);
        });
        return ln + pre.join(' ') + ' ' + asg.join(' ');
      }
      case 'compound': {
        const fn = ARITH[s.op];
        const t = s.target;
        if (t.k === 'name') {
          const cur = expr(t);
          return ln + assignTo(t, `${fn}(${cur}, ${expr(s.e)})`);
        }
        const o = fs.temp(), k = fs.temp();
        return `${ln}${o} = ${expr(t.obj)}; ${k} = ${expr(t.key)}; $setidx(${o}, ${k}, ${fn}($idx(${o}, ${k}), ${expr(s.e)}));`;
      }
      case 'callstat': return ln + multi(s.call) + ';';
      case 'do': return `{\n${block(s.body)}\n}`;
      case 'while': {
        fs.loops.push('while');
        const b = block(s.body);
        fs.loops.pop();
        return `${ln}while (${cond(s.cond)}) {\n${b}\n}`;
      }
      case 'repeat': {
        const label = '$c' + (++labelId);
        fs.loops.push(label);
        pushScope();
        scope.hoist = [];
        const b = blockStmts(s.body);
        const c = cond(s.cond);
        const hoisted = scope.hoist;
        popScope();
        fs.loops.pop();
        const decl = hoisted.length ? `let ${hoisted.join(', ')};` : '';
        return `${ln}do { ${decl} ${label}: {\n${b}\n} $ln = ${s.line}; if (${c}) break; } while (true);`;
      }
      case 'if': {
        let out = '';
        s.clauses.forEach(([c, b], i) => {
          out += (i === 0 ? `${ln}if (` : ` else if (`) + cond(c) + `) {\n${block(b)}\n}`;
        });
        if (s.els) out += ` else {\n${block(s.els)}\n}`;
        return out;
      }
      case 'numfor': {
        const start = expr(s.start), stop = expr(s.stop);
        const stepLit = s.step === null ? 1 : (s.step.k === 'num' ? s.step.v : null);
        fs.loops.push('for');
        pushScope();
        const v = declare(s.v);
        const b = blockStmts(s.body);
        popScope();
        fs.loops.pop();
        if (stepLit !== null && stepLit > 0) {
          return `${ln}{ const $fs = $fornum(${start}, 'initial'), $fe = $fornum(${stop}, 'limit');\nfor (let $fi = $fs; $fi <= $fe; $fi += ${num(stepLit)}) { let ${v} = $fi;\n${b}\n} }`;
        }
        const step = s.step === null ? '1' : expr(s.step);
        return `${ln}{ const $fs = $fornum(${start}, 'initial'), $fe = $fornum(${stop}, 'limit'), $fst = $fornum(${step}, 'step');\nfor (let $fi = $fs; $fst > 0 ? $fi <= $fe : $fi >= $fe; $fi += $fst) { let ${v} = $fi;\n${b}\n} }`;
      }
      case 'genfor': {
        const init = list(s.exprs);
        fs.loops.push('for');
        pushScope();
        const names = s.names.map((n) => declare(n));
        const b = blockStmts(s.body);
        popScope();
        fs.loops.pop();
        const binds = names.map((n, i) => `${n} = $r[${i}]`).join(', ');
        return `${ln}{ const $it = $iter(${init}); let $r;\nfor (;;) { if ($it.fast) { if (!$it.step()) break; $r = $it.kv; } else { $r = (yield* $callx($it.f, [$it.s, $it.c])); if ($r[0] === undefined) break; $it.c = $r[0]; }\nlet ${binds};\n${b}\n} }`;
      }
      case 'return': {
        if (s.exprs.length === 1 && isMulti(s.exprs[0])) return `${ln}return ${multi(s.exprs[0])};`;
        return `${ln}return ${list(s.exprs)};`;
      }
      case 'break': return 'break;';
      case 'continue': {
        const l = fs.loops[fs.loops.length - 1];
        if (l && l.startsWith('$c')) return `break ${l};`;
        return 'continue;';
      }
    }
    throw new Error('codegen: unknown statement ' + s.k);
  }

  // the main chunk is a vararg function
  scope = null;
  pushScope();
  const main = func(ast);
  return { js: main, importPaths, written };
}

// Two passes: the first finds every global this chunk writes (those never become imports), the second
// emits code. A chunk that mentions getfenv/setfenv gets no imports at all, as in Luau.
function generateChunk(ast) {
  const first = generate(ast, { noImports: true });
  const usesFenv = /\$gget\(\$ENV, "(getfenv|setfenv)"\)/.test(first.js);
  return generate(ast, { written: first.written, noImports: usesFenv });
}

module.exports = { generate, generateChunk };
