'use strict';
// Luau runtime for luaujs: values, tables, metatables, calls, coroutines, errors.
// Value mapping: nil=undefined, boolean, number (double), string (byte string), LuaTable, LF/NF (functions),
// Coroutine (thread), Userdata.

const $E = Object.freeze([]);
const DEBUG = !!process.env.LUAUJS_DEBUG;

// ------------------------------------------------------------------------------------- errors
class LuaError {
  constructor(value, pending) { this.value = value; this.pending = pending | 0; this.trace = []; }
}
function rtError(msg) { return new LuaError(msg, 1); }

const displayCache = new Map();
function chunkDisplay(cn) {
  let d = displayCache.get(cn);
  if (d !== undefined) return d;
  if (cn[0] === '@' || cn[0] === '=') d = cn.slice(1);
  else {
    let first = cn.split('\n')[0];
    if (first.length > 40 || cn.includes('\n')) first = first.slice(0, 40) + '...';
    d = `[string "${first}"]`;
  }
  displayCache.set(cn, d);
  return d;
}
let LuaSyntaxErrorClass = null;
function fromJsError(e) {
  if (e instanceof LuaError) return e;
  if (e instanceof RangeError && /call stack/i.test(e.message)) return new LuaError('stack overflow', 1);
  if (LuaSyntaxErrorClass && e instanceof LuaSyntaxErrorClass) return new LuaError(e.message, 0);
  const stack = (e && e.stack) ? String(e.stack).split('\n').slice(0, DEBUG ? 30 : 6).join('\n') : String(e);
  const le = new LuaError('luaujs internal error: ' + stack, 1);
  le.internal = true;
  return le;
}
function $rt(e, cn, ln) {
  if (!(e instanceof LuaError)) e = fromJsError(e);
  if (e.pending > 0) {
    e.pending--;
    if (e.pending === 0 && typeof e.value === 'string') e.value = chunkDisplay(cn) + ':' + ln + ': ' + e.value;
  }
  if (e.trace.length < 40) e.trace.push(chunkDisplay(cn) + ':' + ln);
  return e;
}

// ------------------------------------------------------------------------------------- tables
let nextId = 1;
class LuaTable {
  constructor() {
    this.arr = []; this.hm = null; this.hk = null; this.hv = null; this.dead = 0;
    this.mt = undefined; this.frozen = false; this.id = 0;
  }
  get(k) {
    if (typeof k === 'number') {
      const a = this.arr;
      if ((k | 0) === k && k >= 1 && k <= a.length) return a[k - 1];
    }
    const m = this.hm;
    if (m === null) return undefined;
    const s = m.get(k);
    return s === undefined ? undefined : this.hv[s];
  }
  set(k, v) {
    if (this.frozen) throw rtError('attempt to modify a readonly table');
    if (typeof k === 'number') {
      if ((k | 0) === k && k >= 1) {
        const a = this.arr, n = a.length;
        if (k <= n) {
          a[k - 1] = v;
          if (v === undefined && k === n) {
            let m = n - 1;
            while (m > 0 && a[m - 1] === undefined) m--;
            a.length = m;
          }
          return;
        }
        if (k === n + 1) {
          if (v === undefined) { if (this.hm !== null) this.hset(k, v); return; }
          a.push(v);
          if (this.hm !== null && this.hm.size > this.dead) this.migrate();
          return;
        }
      } else if (k !== k) throw rtError('table index is NaN');
    } else if (k === undefined) throw rtError('table index is nil');
    this.hset(k, v);
  }
  hset(k, v) {
    let m = this.hm;
    if (m === null) {
      if (v === undefined) return;
      m = this.hm = new Map(); this.hk = []; this.hv = [];
    }
    const s = m.get(k);
    if (s !== undefined) {
      const old = this.hv[s];
      this.hv[s] = v;
      if (v === undefined) { if (old !== undefined) this.dead++; }
      else if (old === undefined) this.dead--;
      return;
    }
    if (v === undefined) return;
    // compact() replaces this.hm: re-read it, or the new key lands in the dropped map (REVIEW-1 round 2, B5;
    // tests/Runtime.spec.luau)
    if (this.dead > 32 && this.dead * 2 > this.hk.length) { this.compact(); m = this.hm; }
    m.set(k, this.hk.length); this.hk.push(k); this.hv.push(v);
  }
  migrate() {
    const m = this.hm, a = this.arr;
    for (;;) {
      const k = a.length + 1;
      const s = m.get(k);
      if (s === undefined) return;
      const v = this.hv[s];
      if (v === undefined) return;
      m.delete(k); this.hv[s] = undefined; this.hk[s] = undefined; this.dead++;
      a.push(v);
    }
  }
  compact() {
    const hk = this.hk, hv = this.hv, m = new Map(), nk = [], nv = [];
    for (let i = 0; i < hk.length; i++) {
      if (hv[i] !== undefined) { m.set(hk[i], nk.length); nk.push(hk[i]); nv.push(hv[i]); }
    }
    this.hm = m; this.hk = nk; this.hv = nv; this.dead = 0;
  }
  length() { return this.arr.length; }
  next(k) { // -> [k, v] or undefined
    const a = this.arr;
    let i = -1;
    if (k === undefined) i = 0;
    else if (typeof k === 'number' && (k | 0) === k && k >= 1 && k <= a.length) i = k;
    if (i >= 0) {
      for (; i < a.length; i++) if (a[i] !== undefined) return [i + 1, a[i]];
      return this.hnext(0);
    }
    const m = this.hm;
    const s = m === null ? undefined : m.get(k);
    if (s === undefined) throw rtError("invalid key to 'next'");
    return this.hnext(s + 1);
  }
  hnext(s) {
    const hk = this.hk, hv = this.hv;
    if (hk === null) return undefined;
    for (; s < hk.length; s++) if (hv[s] !== undefined) return [hk[s], hv[s]];
    return undefined;
  }
  clear() { this.arr = []; this.hm = null; this.hk = null; this.hv = null; this.dead = 0; }
  maxn() {
    let mx = this.arr.length;
    if (this.hk !== null) for (let i = 0; i < this.hk.length; i++) {
      const k = this.hk[i];
      if (typeof k === 'number' && this.hv[i] !== undefined && k > mx) mx = k;
    }
    return mx;
  }
}

class Userdata { constructor() { this.mt = undefined; this.id = 0; } }

// ------------------------------------------------------------------------------------- functions
class LF { constructor(g, name, cn, line, np, va) { this.g = g; this.name = name; this.cn = cn; this.line = line; this.np = np; this.va = va; this.id = 0; } }
class NF { constructor(f, name, gy) { this.f = f; this.name = name; this.gy = gy || null; this.id = 0; } }
function $mkfn(g, name, cn, line, np, va) { return new LF(g, name, cn, line, np, va); }

class Coroutine {
  constructor(f, gt) { this.f = f; this.gen = null; this.status = 'suspended'; this.thread = { gt, co: this }; this.id = 0; }
}
const MAIN = { gt: undefined, co: null };
let current = MAIN;

function typeName(v) {
  switch (typeof v) {
    case 'undefined': return 'nil';
    case 'boolean': return 'boolean';
    case 'number': return 'number';
    case 'string': return 'string';
  }
  if (v instanceof LuaTable) return 'table';
  if (v instanceof LF || v instanceof NF) return 'function';
  if (v instanceof Coroutine) return 'thread';
  if (v instanceof Userdata) return 'userdata';
  return 'userdata';
}

let STRING_META = undefined; // set by stdlib
function rawmeta(o) {
  if (o instanceof LuaTable || o instanceof Userdata) return o.mt;
  if (typeof o === 'string') return STRING_META;
  return undefined;
}
function getmm(o, ev) { const mt = rawmeta(o); return mt === undefined ? undefined : mt.get(ev); }

function* $callx(f, args) {
  if (f instanceof LF) return yield* f.g(args);
  if (f instanceof NF) { if (f.gy !== null) return yield* f.gy(args); return f.f(args); }
  const mm = getmm(f, '__call');
  if (mm === undefined) throw rtError(`attempt to call a ${typeName(f)} value`);
  return yield* $callx(mm, [f, ...args]);
}
function callSync(f, args) {
  if (f instanceof NF && f.gy === null) return f.f(args);
  const g = (f instanceof LF) ? f.g(args) : $callx(f, args);
  const r = g.next();
  if (!r.done) throw rtError('attempt to yield across metamethod/C-call boundary');
  return r.value;
}

// ------------------------------------------------------------------------------------- indexing
function keyDesc(k) { return typeof k === 'string' ? `'${k}'` : typeName(k); }
function idxErr(o, k) { return rtError(`attempt to index ${typeName(o)} with ${keyDesc(k)}`); }
function idxMeta(o, k) {
  for (let loop = 0; loop < 100; loop++) {
    const h = o.mt.get('__index');
    if (h === undefined) return undefined;
    if (h instanceof LF || h instanceof NF) return callSync(h, [o, k])[0];
    if (h instanceof LuaTable) {
      const v = h.get(k);
      if (v !== undefined || h.mt === undefined) return v;
      o = h; continue;
    }
    return $idx(h, k);
  }
  throw rtError("'__index' chain too long; possible loop");
}
let STRING_LIB = null;
function $idx(o, k) {
  if (o instanceof LuaTable) {
    const v = o.get(k);
    if (v !== undefined || o.mt === undefined) return v;
    return idxMeta(o, k);
  }
  if (typeof o === 'string') return STRING_LIB.get(k);
  if (o instanceof Userdata && o.mt !== undefined) return idxMeta(o, k);
  throw idxErr(o, k);
}
function $method(o, name) {
  const f = $idx(o, name);
  if (f === undefined) throw rtError(`attempt to call missing method '${name}' of ${typeName(o)}`);
  return f;
}
function $setidx(o, k, v) {
  if (o instanceof LuaTable) {
    const mt = o.mt;
    if (mt === undefined) { o.set(k, v); return; }
    const h = mt.get('__newindex');
    if (h === undefined || o.get(k) !== undefined) { o.set(k, v); return; }
    if (h instanceof LF || h instanceof NF) { callSync(h, [o, k, v]); return; }
    $setidx(h, k, v); return;
  }
  if (o instanceof Userdata && o.mt !== undefined) {
    const h = o.mt.get('__newindex');
    if (h instanceof LF || h instanceof NF) { callSync(h, [o, k, v]); return; }
    if (h !== undefined) { $setidx(h, k, v); return; }
  }
  throw idxErr(o, k);
}
function $gget(env, name) {
  const v = env.get(name);
  if (v !== undefined || env.mt === undefined) return v;
  return idxMeta(env, name);
}

// ------------------------------------------------------------------------------------- numbers
const f64 = new Float64Array(1), u32 = new Uint32Array(f64.buffer);
function fmtNum(n) {
  if (Number.isInteger(n)) {
    if (n === 0) return (1 / n < 0) ? '-0' : '0';
    if (n < 1e21 && n > -1e21) return String(n);
  }
  if (n !== n) { f64[0] = n; return (u32[1] >>> 31) ? '-nan' : 'nan'; }
  if (n === Infinity) return 'inf';
  if (n === -Infinity) return '-inf';
  const e = n.toExponential();
  const m = /^(-?)(\d)(?:\.(\d+))?e([+-]\d+)$/.exec(e);
  const sign = m[1], digits = m[2] + (m[3] || ''), exp = parseInt(m[4], 10);
  const dot = exp + 1;
  if (dot <= -5 || dot > 21) {
    let mant = digits[0];
    if (digits.length > 1) mant += '.' + digits.slice(1);
    const ae = Math.abs(exp);
    return sign + mant + 'e' + (exp < 0 ? '-' : '+') + (ae < 10 ? '0' + ae : String(ae));
  }
  return String(n);
}
const WS = /^[ \t\n\r\v\f]+|[ \t\n\r\v\f]+$/g;
function str2number(s) {
  const t = s.replace(WS, '');
  if (t === '') return undefined;
  let m = /^([+-]?)0[xX]([0-9a-fA-F]+)$/.exec(t);
  if (m) { const v = m[2].length <= 13 ? parseInt(m[2], 16) : Number(BigInt('0x' + m[2])); return m[1] === '-' ? -v : v; }
  m = /^([+-]?)0[bB]([01]+)$/.exec(t);
  if (m) { const v = parseInt(m[2], 2); return m[1] === '-' ? -v : v; }
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return Number(t);
  m = /^([+-]?)(inf|infinity|nan)$/i.exec(t);
  if (m) { if (m[2].toLowerCase() === 'nan') return NaN; return m[1] === '-' ? -Infinity : Infinity; }
  return undefined;
}
function tonum(v) { if (typeof v === 'number') return v; if (typeof v === 'string') return str2number(v); return undefined; }

const OPNAMES = { __add: 'add', __sub: 'sub', __mul: 'mul', __div: 'div', __idiv: 'idiv', __mod: 'mod', __pow: 'pow', __unm: 'unm' };
function arith(a, b, ev) {
  const na = tonum(a), nb = tonum(b);
  if (na !== undefined && nb !== undefined) {
    switch (ev) {
      case '__add': return na + nb;
      case '__sub': return na - nb;
      case '__mul': return na * nb;
      case '__div': return na / nb;
      case '__idiv': return Math.floor(na / nb);
      case '__mod': return luaMod(na, nb);
      case '__pow': return Math.pow(na, nb);
    }
  }
  let h = getmm(a, ev);
  if (h === undefined) h = getmm(b, ev);
  if (h !== undefined) return callSync(h, [a, b])[0];
  const bad = (na === undefined) ? a : b;
  const ta = typeName(a), tb = typeName(b);
  void bad;
  if (ta === tb) throw rtError(`attempt to perform arithmetic (${OPNAMES[ev]}) on ${ta}`);
  throw rtError(`attempt to perform arithmetic (${OPNAMES[ev]}) on ${ta} and ${tb}`);
}
function luaMod(a, b) {
  const r = a - Math.floor(a / b) * b;
  return r;
}
function $add(a, b) { return (typeof a === 'number' && typeof b === 'number') ? a + b : arith(a, b, '__add'); }
function $sub(a, b) { return (typeof a === 'number' && typeof b === 'number') ? a - b : arith(a, b, '__sub'); }
function $mul(a, b) { return (typeof a === 'number' && typeof b === 'number') ? a * b : arith(a, b, '__mul'); }
function $div(a, b) { return (typeof a === 'number' && typeof b === 'number') ? a / b : arith(a, b, '__div'); }
function $idiv(a, b) { return (typeof a === 'number' && typeof b === 'number') ? Math.floor(a / b) : arith(a, b, '__idiv'); }
function $mod(a, b) { return (typeof a === 'number' && typeof b === 'number') ? luaMod(a, b) : arith(a, b, '__mod'); }
function $pow(a, b) { return (typeof a === 'number' && typeof b === 'number') ? Math.pow(a, b) : arith(a, b, '__pow'); }
function $unm(a) {
  if (typeof a === 'number') return -a;
  const n = tonum(a);
  if (n !== undefined) return -n;
  const h = getmm(a, '__unm');
  if (h !== undefined) return callSync(h, [a, a])[0];
  throw rtError(`attempt to perform arithmetic (unm) on ${typeName(a)}`);
}
function $concat(a, b) {
  const ta = typeof a, tb = typeof b;
  if ((ta === 'string' || ta === 'number') && (tb === 'string' || tb === 'number')) {
    return (ta === 'string' ? a : fmtNum(a)) + (tb === 'string' ? b : fmtNum(b));
  }
  let h = getmm(a, '__concat');
  if (h === undefined) h = getmm(b, '__concat');
  if (h !== undefined) return callSync(h, [a, b])[0];
  throw rtError(`attempt to concatenate ${typeName(a)} with ${typeName(b)}`);
}
function $len(o) {
  if (typeof o === 'string') return o.length;
  if (o instanceof LuaTable) {
    if (o.mt !== undefined) { const h = o.mt.get('__len'); if (h !== undefined) return callSync(h, [o])[0]; }
    return o.arr.length;
  }
  const h = getmm(o, '__len');
  if (h !== undefined) return callSync(h, [o])[0];
  throw rtError(`attempt to get length of a ${typeName(o)} value`);
}
function $eq(a, b) {
  if (a === b) return true;
  if ((a instanceof LuaTable && b instanceof LuaTable) || (a instanceof Userdata && b instanceof Userdata)) {
    const ma = a.mt, mb = b.mt;
    if (ma === undefined || mb === undefined) return false;
    const h1 = ma.get('__eq');
    if (h1 === undefined) return false;
    if (ma !== mb) { const h2 = mb.get('__eq'); if (h1 !== h2) return false; }
    const r = callSync(h1, [a, b])[0];
    return r !== undefined && r !== false;
  }
  return false;
}
function cmpMeta(a, b, ev, op) {
  const ta = typeName(a), tb = typeName(b);
  if (ta === tb && (ta === 'table' || ta === 'userdata')) {
    const h1 = getmm(a, ev), h2 = getmm(b, ev);
    if (h1 !== undefined && h1 === h2) { const r = callSync(h1, [a, b])[0]; return r !== undefined && r !== false; }
  }
  throw rtError(`attempt to compare ${ta} ${op} ${tb}`);
}
function $lt(a, b) {
  if ((typeof a === 'number' && typeof b === 'number') || (typeof a === 'string' && typeof b === 'string')) return a < b;
  return cmpMeta(a, b, '__lt', '<');
}
function $le(a, b) {
  if ((typeof a === 'number' && typeof b === 'number') || (typeof a === 'string' && typeof b === 'string')) return a <= b;
  return cmpMeta(a, b, '__le', '<=');
}
function $gt(a, b) {
  if ((typeof a === 'number' && typeof b === 'number') || (typeof a === 'string' && typeof b === 'string')) return a > b;
  return cmpMeta(b, a, '__lt', '<');
}
function $ge(a, b) {
  if ((typeof a === 'number' && typeof b === 'number') || (typeof a === 'string' && typeof b === 'string')) return a >= b;
  return cmpMeta(b, a, '__le', '<=');
}
function $tr(v) { return v !== undefined && v !== false; }
function $fornum(v, what) {
  if (typeof v === 'number') return v;
  const n = typeof v === 'string' ? str2number(v) : undefined;
  if (n !== undefined) return n;
  throw rtError(`invalid 'for' ${what} value (number expected, got ${typeName(v)})`);
}

// ------------------------------------------------------------------------------------- tostring
const ids = new WeakMap();
function addr(v) {
  let id = ids.get(v);
  if (id === undefined) { id = nextId++; ids.set(v, id); }
  return (0x10000000 + id * 16).toString(16).padStart(16, '0');
}
function tostr(v) {
  switch (typeof v) {
    case 'string': return v;
    case 'number': return fmtNum(v);
    case 'boolean': return v ? 'true' : 'false';
    case 'undefined': return 'nil';
  }
  const h = getmm(v, '__tostring');
  if (h !== undefined) {
    const r = callSync(h, [v])[0];
    if (typeof r !== 'string') throw rtError("'__tostring' must return a string");
    return r;
  }
  if (v instanceof NF) return 'function: builtin: 0x' + addr(v);
  return typeName(v) + ': 0x' + addr(v);
}
function $interp(parts) {
  let s = '';
  for (let i = 0; i < parts.length; i++) s += (i % 2 === 0) ? parts[i] : tostr(parts[i]);
  return s;
}

// ------------------------------------------------------------------------------------- constructors
function $mktab(pos, kv) {
  const t = new LuaTable();
  let n = pos.length;
  while (n > 0 && pos[n - 1] === undefined) n--;
  if (n !== pos.length) pos.length = n;
  t.arr = pos;
  if (kv !== undefined) {
    for (let i = 0; i < kv.length; i += 2) {
      const k = kv[i];
      if (k === undefined) throw rtError('table index is nil');
      if (typeof k === 'number' && (k | 0) === k && k >= 1 && k <= t.arr.length && t.arr[k - 1] !== undefined) continue;
      t.set(k, kv[i + 1]);
    }
  }
  return t;
}

// ------------------------------------------------------------------------------------- iteration
class TIter {
  constructor(t) { this.t = t; this.i = 0; this.h = 0; this.kv = [undefined, undefined]; this.fast = true; }
  step() {
    const t = this.t, a = t.arr;
    while (this.i < a.length) {
      const v = a[this.i++];
      if (v !== undefined) { this.kv[0] = this.i; this.kv[1] = v; return true; }
    }
    const hk = t.hk;
    if (hk === null) return false;
    const hv = t.hv;
    while (this.h < hk.length) {
      const s = this.h++;
      const v = hv[s];
      if (v !== undefined) { this.kv[0] = hk[s]; this.kv[1] = v; return true; }
    }
    return false;
  }
}
class IIter {
  constructor(t) { this.t = t; this.i = 0; this.kv = [0, undefined]; this.fast = true; }
  step() {
    const v = this.t.get(this.i + 1);
    if (v === undefined) return false;
    this.i++; this.kv[0] = this.i; this.kv[1] = v; return true;
  }
}
class GIter { constructor(f, s, c) { this.f = f; this.s = s; this.c = c; this.fast = false; } }
let NEXT_FN = null, INEXT_FN = null;
function $iter(L) {
  const f = L[0], s = L[1], c = L[2];
  if (f instanceof LF || f instanceof NF) {
    if (f === NEXT_FN && s instanceof LuaTable && c === undefined) return new TIter(s);
    if (f === INEXT_FN && s instanceof LuaTable && c === 0) return new IIter(s);
    return new GIter(f, s, c);
  }
  if (f instanceof LuaTable || f instanceof Userdata) {
    const mt = f.mt;
    if (mt !== undefined) {
      const it = mt.get('__iter');
      if (it !== undefined) { const r = callSync(it, [f]); return new GIter(r[0], r[1], r[2]); }
      if (mt.get('__call') !== undefined) return new GIter(f, s, c);
    }
    if (f instanceof LuaTable) return new TIter(f);
  }
  throw rtError(`attempt to iterate over a ${typeName(f)} value`);
}

// ------------------------------------------------------------------------------------- coroutines
function resume(co, args) {
  if (co.status === 'dead') return [false, 'cannot resume dead coroutine'];
  if (co.status !== 'suspended') return [false, 'cannot resume non-suspended coroutine'];
  const prev = current;
  if (prev.co !== null) prev.co.status = 'normal';
  co.status = 'running';
  current = co.thread;
  try {
    let r;
    if (co.gen === null) { co.gen = $callx(co.f, args); r = co.gen.next(); }
    else r = co.gen.next(args);
    if (r.done) { co.status = 'dead'; return [true, ...r.value]; }
    co.status = 'suspended';
    return [true, ...r.value];
  } catch (e) {
    co.status = 'dead';
    const le = fromJsError(e);
    co.err = le;
    return [false, le.value];
  } finally {
    current = prev;
    if (prev.co !== null) prev.co.status = 'running';
  }
}
function* yieldGen(args) {
  if (current.co === null) throw rtError('attempt to yield from outside a coroutine');
  const r = yield args;
  return r;
}

module.exports = {
  $E, DEBUG, LuaError, rtError, chunkDisplay, fromJsError, $rt, LuaTable, Userdata, LF, NF, $mkfn, Coroutine,
  get current() { return current; }, set current(v) { current = v; }, MAIN,
  typeName, rawmeta, getmm, $callx, callSync, $idx, $method, $setidx, $gget, idxMeta,
  fmtNum, str2number, tonum, luaMod, $add, $sub, $mul, $div, $idiv, $mod, $pow, $unm, $concat, $len, $eq,
  $lt, $le, $gt, $ge, $tr, $fornum, tostr, addr, $interp, $mktab, TIter, IIter, GIter, $iter, resume, yieldGen,
  setStringMeta(meta, lib) { STRING_META = meta; STRING_LIB = lib; },
  setIterFns(next, inext) { NEXT_FN = next; INEXT_FN = inext; },
  setSyntaxErrorClass(c) { LuaSyntaxErrorClass = c; },
};
