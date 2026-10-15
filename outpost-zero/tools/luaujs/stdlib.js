'use strict';
// Luau standard library for luaujs.
const R = require('./runtime');
const S = require('./lstrlib');
const { LuaTable, LF, NF, Coroutine, Userdata, LuaError, rtError, typeName, tostr, fmtNum, callSync, $callx,
  $idx, $setidx, $eq, $lt, $E, fromJsError } = R;
const { checkstr, checknum, checkint, optint, posrelat, argErr } = S;

function nf(name, f) { return new NF(f, name); }
function lib(entries) {
  const t = new LuaTable();
  for (const [k, v] of Object.entries(entries)) t.set(k, (typeof v === 'function') ? nf(k, v) : v);
  return t;
}
function checktab(v, n, fname) {
  if (v instanceof LuaTable) return v;
  throw argErr(n, fname, `table expected, got ${v === undefined ? 'no value' : typeName(v)}`);
}
const truthy = (v) => v !== undefined && v !== false;

// ------------------------------------------------------------------------------------- output
let outBuf = [], outLen = 0;
const fs = require('fs');
function writeOut(s) {
  outBuf.push(s); outLen += s.length;
  if (outLen > 1 << 16) flushOut();
}
function flushOut() {
  if (outBuf.length === 0) return;
  const s = outBuf.join('');
  outBuf = []; outLen = 0;
  const b = Buffer.from(s, 'latin1');
  let off = 0;
  while (off < b.length) {
    try { off += fs.writeSync(1, b, off, b.length - off); }
    catch (e) { if (e.code === 'EAGAIN') continue; throw e; }
  }
}
function writeErr(s) {
  flushOut();
  const b = Buffer.from(s, 'latin1');
  let off = 0;
  while (off < b.length) {
    try { off += fs.writeSync(2, b, off, b.length - off); }
    catch (e) { if (e.code === 'EAGAIN') continue; throw e; }
  }
}

// ------------------------------------------------------------------------------------- base
function makeBase(host) {
  const G = new LuaTable();
  const set = (k, f) => G.set(k, typeof f === 'function' ? nf(k, f) : f);

  set('print', (a) => {
    const parts = new Array(a.length);
    for (let i = 0; i < a.length; i++) parts[i] = tostr(a[i]);
    writeOut(parts.join('\t') + '\n');
    return $E;
  });
  set('type', (a) => { if (a.length === 0) throw argErr(1, 'type', 'value expected'); return [typeName(a[0])]; });
  set('typeof', (a) => {
    if (a.length === 0) throw argErr(1, 'typeof', 'value expected');
    const v = a[0];
    if (v instanceof Userdata && v.mt !== undefined) { const t = v.mt.get('__type'); if (typeof t === 'string') return [t]; }
    return [typeName(v)];
  });
  set('tostring', (a) => { if (a.length === 0) throw argErr(1, 'tostring', 'value expected'); return [tostr(a[0])]; });
  set('tonumber', (a) => {
    const v = a[0], base = a[1];
    if (base === undefined) {
      if (typeof v === 'number') return [v];
      if (typeof v === 'string') return [R.str2number(v)];
      if (a.length === 0) throw argErr(1, 'tonumber', 'value expected');
      return [undefined];
    }
    const b = checkint(base, 2, 'tonumber');
    if (b < 2 || b > 36) throw argErr(2, 'tonumber', 'base out of range');
    const s = checkstr(v, 1, 'tonumber').replace(/^[ \t\n\r\v\f]+|[ \t\n\r\v\f]+$/g, '').toLowerCase();
    let neg = false, t = s;
    if (t[0] === '-') { neg = true; t = t.slice(1); }
    if (t === '') return [undefined];
    let n = 0;
    for (const ch of t) {
      const d = ch >= '0' && ch <= '9' ? ch.charCodeAt(0) - 48 : ch >= 'a' && ch <= 'z' ? ch.charCodeAt(0) - 87 : 99;
      if (d >= b) return [undefined];
      n = n * b + d;
    }
    return [neg ? -n : n];
  });
  set('ipairs', (a) => {
    if (a.length === 0) throw argErr(1, 'ipairs', 'table expected, got no value');
    return [INEXT, a[0], 0];
  });
  const INEXT = nf('inext', (a) => {
    const t = checktab(a[0], 1, 'inext');
    const i = checkint(a[1], 2, 'inext') + 1;
    const v = t.get(i);
    return v === undefined ? $E : [i, v];
  });
  const NEXT = nf('next', (a) => {
    const t = checktab(a[0], 1, 'next');
    const r = t.next(a[1]);
    return r === undefined ? [undefined] : r;
  });
  G.set('next', NEXT);
  set('pairs', (a) => { checktab(a[0], 1, 'pairs'); return [NEXT, a[0], undefined]; });
  R.setIterFns(NEXT, INEXT);
  set('rawget', (a) => [checktab(a[0], 1, 'rawget').get(a[1])]);
  set('rawset', (a) => { checktab(a[0], 1, 'rawset').set(a[1], a[2]); return [a[0]]; });
  set('rawequal', (a) => [a[0] === a[1]]);
  set('rawlen', (a) => {
    const v = a[0];
    if (v instanceof LuaTable) return [v.arr.length];
    if (typeof v === 'string') return [v.length];
    throw argErr(1, 'rawlen', 'table or string expected');
  });
  set('setmetatable', (a) => {
    const t = checktab(a[0], 1, 'setmetatable');
    const mt = a[1];
    if (mt !== undefined && !(mt instanceof LuaTable)) throw argErr(2, 'setmetatable', 'nil or table expected');
    if (t.mt !== undefined && t.mt.get('__metatable') !== undefined) throw rtError('cannot change a protected metatable');
    if (t.frozen) throw rtError('attempt to modify a readonly table');
    t.mt = mt;
    return [t];
  });
  set('getmetatable', (a) => {
    const mt = R.rawmeta(a[0]);
    if (mt === undefined) return [undefined];
    const p = mt.get('__metatable');
    return [p !== undefined ? p : mt];
  });
  set('assert', (a) => {
    if (a.length === 0) throw argErr(1, 'assert', 'value expected');
    if (truthy(a[0])) return a;
    if (a.length >= 2 && typeof a[1] !== 'string') throw new LuaError(a[1], 0);
    throw new LuaError(a.length >= 2 ? a[1] : 'assertion failed!', 1);
  });
  set('error', (a) => {
    const level = a[1] === undefined ? 1 : checkint(a[1], 2, 'error');
    throw new LuaError(a[0], typeof a[0] === 'string' ? level : 0);
  });
  G.set('pcall', new NF((a) => runGenSync(pcallGen(a)), 'pcall', pcallGen));
  G.set('xpcall', new NF((a) => runGenSync(xpcallGen(a)), 'xpcall', xpcallGen));
  set('select', (a) => {
    const n = a[0];
    if (n === '#') return [a.length - 1];
    let i = checkint(n, 1, 'select');
    if (i < 0) { i = a.length - 1 + i; if (i < 0) throw argErr(1, 'select', 'index out of range'); return a.slice(i + 1); }
    if (i === 0) throw argErr(1, 'select', 'index out of range');
    return a.slice(i);
  });
  const unpack = (a) => {
    const t = checktab(a[0], 1, 'unpack');
    const i = optint(a[1], 2, 'unpack', 1);
    const j = a[2] === undefined ? t.arr.length : checkint(a[2], 3, 'unpack');
    if (i > j) return $E;
    const n = j - i + 1;
    if (n >= 8000) throw rtError('too many results to unpack');
    if (i === 1 && j === t.arr.length) return t.arr.slice();
    const out = new Array(n);
    for (let k = 0; k < n; k++) out[k] = t.get(i + k);
    return out;
  };
  set('unpack', unpack);
  set('newproxy', (a) => { const u = new Userdata(); if (truthy(a[0])) u.mt = new LuaTable(); return [u]; });
  set('gcinfo', () => [Math.floor(process.memoryUsage().heapUsed / 1024)]);
  set('collectgarbage', (a) => {
    const opt = a[0] === undefined ? 'collect' : a[0];
    if (opt === 'count') return [process.memoryUsage().heapUsed / 1024];
    return [0];
  });
  set('loadstring', (a) => {
    const src = checkstr(a[0], 1, 'loadstring');
    const name = a[1] === undefined ? src : checkstr(a[1], 2, 'loadstring');
    try {
      const fn = host.compile(src, name)(R.current.gt);
      return [fn];
    } catch (e) {
      if (e instanceof LuaError) return [undefined, e.value];
      return [undefined, String(e.message || e)];
    }
  });
  set('getfenv', () => [R.current.gt]);
  set('setfenv', () => { throw rtError('setfenv is not supported by luaujs'); });
  set('require', (a) => host.require(undefined, a));
  G.set('_G', G);
  G.set('_VERSION', 'Luau');

  // ----------------------------------------------------------------------------- string
  const strlib = lib({
    len: (a) => [checkstr(a[0], 1, 'len').length],
    sub: (a) => {
      const s = checkstr(a[0], 1, 'sub');
      const l = s.length;
      let st = posrelat(checkint(a[1], 2, 'sub'), l);
      let en = posrelat(optint(a[2], 3, 'sub', -1), l);
      if (st < 1) st = 1;
      if (en > l) en = l;
      return [st <= en ? s.slice(st - 1, en) : ''];
    },
    upper: (a) => [checkstr(a[0], 1, 'upper').replace(/[a-z]+/g, (m) => m.toUpperCase())],
    lower: (a) => [checkstr(a[0], 1, 'lower').replace(/[A-Z]+/g, (m) => m.toLowerCase())],
    rep: (a) => {
      const s = checkstr(a[0], 1, 'rep');
      const n = checkint(a[1], 2, 'rep');
      if (n <= 0) return [''];
      if (s.length * n > 1e9) throw rtError('resulting string too large');
      return [s.repeat(n)];
    },
    reverse: (a) => [checkstr(a[0], 1, 'reverse').split('').reverse().join('')],
    byte: (a) => {
      const s = checkstr(a[0], 1, 'byte');
      const l = s.length;
      let i = posrelat(optint(a[1], 2, 'byte', 1), l);
      let j = posrelat(a[2] === undefined ? i : checkint(a[2], 3, 'byte'), l);
      if (i < 1) i = 1;
      if (j > l) j = l;
      const out = [];
      for (let k = i; k <= j; k++) out.push(s.charCodeAt(k - 1));
      return out;
    },
    char: (a) => {
      let s = '';
      for (let i = 0; i < a.length; i++) {
        const c = checkint(a[i], i + 1, 'char');
        if (c < 0 || c > 255) throw argErr(i + 1, 'char', 'invalid value');
        s += String.fromCharCode(c);
      }
      return [s];
    },
    format: S.strFormat,
    find: (a) => S.strFindAux(a, true),
    match: (a) => S.strFindAux(a, false),
    gmatch: S.gmatch,
    gsub: S.gsub,
    split: (a) => {
      const h = checkstr(a[0], 1, 'split');
      const nd = a[1] === undefined ? ',' : checkstr(a[1], 2, 'split');
      const out = [];
      let spanStart = 0;
      let begin = 0;
      if (nd.length === 0) begin++;
      for (let it = begin; it <= h.length - nd.length; it++) {
        if (h.substr(it, nd.length) === nd) {
          out.push(h.slice(spanStart, it));
          spanStart = it + nd.length;
          if (nd.length > 0) it += nd.length - 1;
        }
      }
      if (nd.length > 0) out.push(h.slice(spanStart));
      const t = new LuaTable();
      t.arr = out;
      return [t];
    },
  });
  strlib.frozen = true;
  G.set('string', strlib);
  const strMeta = new LuaTable();
  strMeta.set('__index', strlib);
  strMeta.frozen = true;
  R.setStringMeta(strMeta, strlib);

  // ----------------------------------------------------------------------------- table
  const tablib = lib({
    insert: (a) => {
      const t = checktab(a[0], 1, 'insert');
      const n = t.arr.length;
      if (a.length === 2) { t.set(n + 1, a[1]); return $E; }
      if (a.length !== 3) throw rtError("wrong number of arguments to 'insert'");
      const pos = checkint(a[1], 2, 'insert');
      if (pos < 1 || pos > n + 1) throw argErr(2, 'insert', 'position out of bounds');
      if (t.frozen) throw rtError('attempt to modify a readonly table');
      if (pos === n + 1) { t.set(pos, a[2]); return $E; }
      t.arr.splice(pos - 1, 0, a[2]);
      if (t.hm !== null) t.migrate();
      return $E;
    },
    remove: (a) => {
      const t = checktab(a[0], 1, 'remove');
      const size = t.arr.length;
      let pos = a[1] === undefined ? size : checkint(a[1], 2, 'remove');
      if (a[1] !== undefined && size + 1 === pos) { const v = t.get(pos); t.set(pos, undefined); return [v]; }
      if (pos !== size && (pos < 1 || pos > size + 1)) throw argErr(2, 'remove', 'position out of bounds');
      if (size === 0) return [t.get(pos)];
      if (t.frozen) throw rtError('attempt to modify a readonly table');
      const v = t.arr[pos - 1];
      t.arr.splice(pos - 1, 1);
      let m = t.arr.length;
      while (m > 0 && t.arr[m - 1] === undefined) m--;
      t.arr.length = m;
      return [v];
    },
    concat: (a) => {
      const t = checktab(a[0], 1, 'concat');
      const sep = a[1] === undefined ? '' : checkstr(a[1], 2, 'concat');
      const i = optint(a[2], 3, 'concat', 1);
      const j = a[3] === undefined ? t.arr.length : checkint(a[3], 4, 'concat');
      const parts = [];
      for (let k = i; k <= j; k++) {
        const v = t.get(k);
        if (typeof v === 'string') parts.push(v);
        else if (typeof v === 'number') parts.push(fmtNum(v));
        else throw rtError(`invalid value (at index ${k}) in table for 'concat'`);
      }
      return [parts.join(sep)];
    },
    sort: (a) => {
      const t = checktab(a[0], 1, 'sort');
      if (t.frozen) throw rtError('attempt to modify a readonly table');
      const comp = a[1];
      if (comp !== undefined && !(comp instanceof LF || comp instanceof NF)) throw argErr(2, 'sort', 'function expected');
      const arr = t.arr;
      for (let i = 0; i < arr.length; i++) if (arr[i] === undefined) throw rtError('attempt to compare nil with ' + typeName(arr[i === 0 ? 1 : 0]));
      let lt;
      if (comp === undefined) lt = (x, y) => $lt(x, y);
      else if (comp instanceof NF && comp.gy === null) lt = (x, y) => truthy(comp.f([x, y])[0]);
      else lt = (x, y) => truthy(callSync(comp, [x, y])[0]);
      arr.sort((x, y) => (lt(x, y) ? -1 : (lt(y, x) ? 1 : 0)));
      return $E;
    },
    unpack,
    pack: (a) => { const t = new LuaTable(); t.arr = a.slice(); let n = t.arr.length; while (n > 0 && t.arr[n - 1] === undefined) n--; t.arr.length = n; t.set('n', a.length); return [t]; },
    find: (a) => {
      const t = checktab(a[0], 1, 'find');
      const init = optint(a[2], 3, 'find', 1);
      if (init < 1) throw argErr(3, 'find', 'index out of range');
      for (let i = init; ; i++) {
        const v = t.get(i);
        if (v === undefined) return [undefined];
        if (v === a[1]) return [i];
      }
    },
    clear: (a) => { const t = checktab(a[0], 1, 'clear'); if (t.frozen) throw rtError('attempt to modify a readonly table'); t.clear(); return $E; },
    clone: (a) => {
      const t = checktab(a[0], 1, 'clone');
      if (t.mt !== undefined && t.mt.get('__metatable') !== undefined) throw argErr(1, 'clone', 'table has a protected metatable');
      const c = new LuaTable();
      c.arr = t.arr.slice();
      if (t.hm !== null) {
        c.hm = new Map(); c.hk = []; c.hv = [];
        for (let i = 0; i < t.hk.length; i++) if (t.hv[i] !== undefined) { c.hm.set(t.hk[i], c.hk.length); c.hk.push(t.hk[i]); c.hv.push(t.hv[i]); }
      }
      c.mt = t.mt;
      return [c];
    },
    freeze: (a) => {
      const t = checktab(a[0], 1, 'freeze');
      if (t.mt !== undefined && t.mt.get('__metatable') !== undefined) throw argErr(1, 'freeze', 'table has a protected metatable');
      t.frozen = true; return [t];
    },
    isfrozen: (a) => [checktab(a[0], 1, 'isfrozen').frozen],
    create: (a) => {
      const n = checkint(a[0], 1, 'create');
      if (n < 0) throw argErr(1, 'create', 'size out of range');
      const t = new LuaTable();
      if (a[1] !== undefined) { t.arr = new Array(n).fill(a[1]); }
      return [t];
    },
    move: (a) => {
      const a1 = checktab(a[0], 1, 'move');
      const f = checkint(a[1], 2, 'move'), e = checkint(a[2], 3, 'move'), tpos = checkint(a[3], 4, 'move');
      const a2 = a[4] === undefined ? a1 : checktab(a[4], 5, 'move');
      if (e >= f) {
        if (tpos > e || tpos <= f || a1 !== a2) for (let i = 0; i <= e - f; i++) a2.set(tpos + i, a1.get(f + i));
        else for (let i = e - f; i >= 0; i--) a2.set(tpos + i, a1.get(f + i));
      }
      return [a2];
    },
    maxn: (a) => [checktab(a[0], 1, 'maxn').maxn()],
    getn: (a) => [checktab(a[0], 1, 'getn').arr.length],
    foreach: (a) => {
      const t = checktab(a[0], 1, 'foreach');
      for (let r = t.next(undefined); r !== undefined; r = t.next(r[0])) {
        const v = callSync(a[1], r)[0];
        if (v !== undefined) return [v];
      }
      return $E;
    },
    foreachi: (a) => {
      const t = checktab(a[0], 1, 'foreachi');
      const n = t.arr.length;
      for (let i = 1; i <= n; i++) { const v = callSync(a[1], [i, t.get(i)])[0]; if (v !== undefined) return [v]; }
      return $E;
    },
  });
  tablib.frozen = true;
  G.set('table', tablib);

  // ----------------------------------------------------------------------------- math
  const MASK64 = (1n << 64n) - 1n;
  let rng = 0n;
  function pcg32() {
    const old = rng;
    rng = (old * 6364136223846793005n + 105n) & MASK64;
    const xorshifted = Number((((old >> 18n) ^ old) >> 27n) & 0xffffffffn);
    const rot = Number(old >> 59n);
    return ((xorshifted >>> rot) | (xorshifted << ((-rot) & 31))) >>> 0;
  }
  function pcgSeed(seed) { rng = 0n; pcg32(); rng = (rng + BigInt.asUintN(64, BigInt(seed))) & MASK64; pcg32(); }
  pcgSeed(Math.floor(Math.random() * 2147483647) ^ (Date.now() & 0x7fffffff));
  const mathlib = lib({
    abs: (a) => [Math.abs(checknum(a[0], 1, 'abs'))],
    ceil: (a) => [Math.ceil(checknum(a[0], 1, 'ceil'))],
    floor: (a) => [Math.floor(checknum(a[0], 1, 'floor'))],
    sqrt: (a) => [Math.sqrt(checknum(a[0], 1, 'sqrt'))],
    sin: (a) => [Math.sin(checknum(a[0], 1, 'sin'))],
    cos: (a) => [Math.cos(checknum(a[0], 1, 'cos'))],
    tan: (a) => [Math.tan(checknum(a[0], 1, 'tan'))],
    asin: (a) => [Math.asin(checknum(a[0], 1, 'asin'))],
    acos: (a) => [Math.acos(checknum(a[0], 1, 'acos'))],
    atan: (a) => [Math.atan(checknum(a[0], 1, 'atan'))],
    atan2: (a) => [Math.atan2(checknum(a[0], 1, 'atan2'), checknum(a[1], 2, 'atan2'))],
    sinh: (a) => [Math.sinh(checknum(a[0], 1, 'sinh'))],
    cosh: (a) => [Math.cosh(checknum(a[0], 1, 'cosh'))],
    tanh: (a) => [Math.tanh(checknum(a[0], 1, 'tanh'))],
    exp: (a) => [Math.exp(checknum(a[0], 1, 'exp'))],
    log10: (a) => [Math.log10(checknum(a[0], 1, 'log10'))],
    log: (a) => {
      const x = checknum(a[0], 1, 'log');
      if (a[1] === undefined) return [Math.log(x)];
      const b = checknum(a[1], 2, 'log');
      if (b === 2) return [Math.log2(x)];
      if (b === 10) return [Math.log10(x)];
      return [Math.log(x) / Math.log(b)];
    },
    pow: (a) => [Math.pow(checknum(a[0], 1, 'pow'), checknum(a[1], 2, 'pow'))],
    fmod: (a) => [checknum(a[0], 1, 'fmod') % checknum(a[1], 2, 'fmod')],
    modf: (a) => {
      const x = checknum(a[0], 1, 'modf');
      const ip = x >= 0 ? Math.floor(x) : Math.ceil(x);
      const fp = Number.isFinite(x) ? x - ip : 0;
      return [ip, fp];
    },
    frexp: (a) => {
      const x = checknum(a[0], 1, 'frexp');
      if (x === 0 || !Number.isFinite(x)) return [x, 0];
      let e = Math.max(-1073, Math.floor(Math.log2(Math.abs(x))) + 1);
      let m = x * Math.pow(2, -e);
      while (Math.abs(m) < 0.5) { m *= 2; e--; }
      while (Math.abs(m) >= 1) { m /= 2; e++; }
      return [m, e];
    },
    ldexp: (a) => [checknum(a[0], 1, 'ldexp') * Math.pow(2, checkint(a[1], 2, 'ldexp'))],
    deg: (a) => [checknum(a[0], 1, 'deg') * (180 / Math.PI)],
    rad: (a) => [checknum(a[0], 1, 'rad') * (Math.PI / 180)],
    max: (a) => {
      let m = checknum(a[0], 1, 'max');
      for (let i = 1; i < a.length; i++) { const v = checknum(a[i], i + 1, 'max'); if (v > m) m = v; }
      return [m];
    },
    min: (a) => {
      let m = checknum(a[0], 1, 'min');
      for (let i = 1; i < a.length; i++) { const v = checknum(a[i], i + 1, 'min'); if (v < m) m = v; }
      return [m];
    },
    clamp: (a) => {
      const v = checknum(a[0], 1, 'clamp'), mn = checknum(a[1], 2, 'clamp'), mx = checknum(a[2], 3, 'clamp');
      if (mn > mx) throw argErr(3, 'clamp', 'max must be greater than or equal to min');
      let r = v < mn ? mn : v;
      r = r > mx ? mx : r;
      return [r];
    },
    sign: (a) => { const x = checknum(a[0], 1, 'sign'); return [x > 0 ? 1 : x < 0 ? -1 : 0]; },
    round: (a) => { const x = checknum(a[0], 1, 'round'); return [x < 0 ? -Math.round(-x) : Math.round(x)]; },
    lerp: (a) => { const x = checknum(a[0], 1, 'lerp'), y = checknum(a[1], 2, 'lerp'), t = checknum(a[2], 3, 'lerp'); return [t === 1 ? y : x + (y - x) * t]; },
    map: (a) => {
      const x = checknum(a[0], 1, 'map'), i0 = checknum(a[1], 2, 'map'), i1 = checknum(a[2], 3, 'map'), o0 = checknum(a[3], 4, 'map'), o1 = checknum(a[4], 5, 'map');
      return [o0 + (x - i0) * (o1 - o0) / (i1 - i0)];
    },
    isnan: (a) => [Number.isNaN(checknum(a[0], 1, 'isnan'))],
    isinf: (a) => { const x = checknum(a[0], 1, 'isinf'); return [x === Infinity || x === -Infinity]; },
    isfinite: (a) => [Number.isFinite(checknum(a[0], 1, 'isfinite'))],
    noise: () => { throw rtError('math.noise is not implemented by luaujs'); },
    random: (a) => {
      if (a.length === 0) {
        const rl = pcg32(), rh = pcg32();
        return [(rl + rh * 4294967296) * Math.pow(2, -64)];
      }
      if (a.length === 1) {
        const u = checkint(a[0], 1, 'random') | 0;
        if (u < 1) throw argErr(1, 'random', 'interval is empty');
        const x = BigInt(u >>> 0) * BigInt(pcg32());
        return [1 + Number(x >> 32n)];
      }
      const l = checkint(a[0], 1, 'random') | 0, u = checkint(a[1], 2, 'random') | 0;
      if (l > u) throw argErr(2, 'random', 'interval is empty');
      const ul = ((u >>> 0) - (l >>> 0)) >>> 0;
      if (ul >= 4294967295) throw argErr(2, 'random', 'interval is too large');
      const x = BigInt(ul + 1) * BigInt(pcg32());
      return [(l + Number(x >> 32n)) | 0];
    },
    randomseed: (a) => { pcgSeed(checkint(a[0], 1, 'randomseed') | 0); return $E; },
  });
  mathlib.set('pi', Math.PI);
  mathlib.set('huge', Infinity);
  mathlib.frozen = true;
  G.set('math', mathlib);

  // ----------------------------------------------------------------------------- os
  const t0 = performance.now();
  const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const p2 = (n) => String(n).padStart(2, '0');
  const oslib = lib({
    time: (a) => {
      if (a[0] === undefined) return [Math.floor(Date.now() / 1000)];
      const t = checktab(a[0], 1, 'time');
      const field = (k, d) => { const v = t.get(k); if (v === undefined) { if (d === undefined) throw rtError(`field '${k}' missing in date table`); return d; } return checkint(v, 1, 'time'); };
      const ms = Date.UTC(field('year'), field('month') - 1, field('day'), field('hour', 12), field('min', 0), field('sec', 0));
      return [Math.floor(ms / 1000)];
    },
    clock: () => [(performance.now() - t0) / 1000],
    difftime: (a) => [checknum(a[0], 1, 'difftime') - (a[1] === undefined ? 0 : checknum(a[1], 2, 'difftime'))],
    date: (a) => {
      let fmt = a[0] === undefined ? '%c' : checkstr(a[0], 1, 'date');
      const time = a[1] === undefined ? Date.now() / 1000 : checknum(a[1], 2, 'date');
      let utc = false;
      if (fmt[0] === '!') { utc = true; fmt = fmt.slice(1); }
      const d = new Date(time * 1000);
      const g = utc
        ? { Y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), H: d.getUTCHours(), M: d.getUTCMinutes(), S: d.getUTCSeconds(), w: d.getUTCDay() }
        : { Y: d.getFullYear(), m: d.getMonth() + 1, d: d.getDate(), H: d.getHours(), M: d.getMinutes(), S: d.getSeconds(), w: d.getDay() };
      const start = utc ? Date.UTC(g.Y, 0, 1) : new Date(g.Y, 0, 1).getTime();
      const yday = Math.floor((d.getTime() - start) / 86400000) + 1;
      if (fmt.startsWith('*t')) {
        const t = new LuaTable();
        t.set('year', g.Y); t.set('month', g.m); t.set('day', g.d); t.set('hour', g.H); t.set('min', g.M);
        t.set('sec', g.S); t.set('wday', g.w + 1); t.set('yday', yday); t.set('isdst', false);
        return [t];
      }
      const out = fmt.replace(/%(.)/g, (m, c) => {
        switch (c) {
          case 'Y': return String(g.Y);
          case 'y': return p2(g.Y % 100);
          case 'm': return p2(g.m);
          case 'd': return p2(g.d);
          case 'H': return p2(g.H);
          case 'I': return p2(((g.H + 11) % 12) + 1);
          case 'M': return p2(g.M);
          case 'S': return p2(g.S);
          case 'p': return g.H < 12 ? 'AM' : 'PM';
          case 'A': return DAYS[g.w];
          case 'a': return DAYS[g.w].slice(0, 3);
          case 'B': return MONTHS[g.m - 1];
          case 'b': return MONTHS[g.m - 1].slice(0, 3);
          case 'j': return String(yday).padStart(3, '0');
          case 'c': return `${DAYS[g.w].slice(0, 3)} ${MONTHS[g.m - 1].slice(0, 3)} ${String(g.d).padStart(2, ' ')} ${p2(g.H)}:${p2(g.M)}:${p2(g.S)} ${g.Y}`;
          case 'x': return `${p2(g.m)}/${p2(g.d)}/${p2(g.Y % 100)}`;
          case 'X': return `${p2(g.H)}:${p2(g.M)}:${p2(g.S)}`;
          case '%': return '%';
          default: throw rtError(`invalid conversion specifier '%${c}'`);
        }
      });
      return [out];
    },
  });
  oslib.frozen = true;
  G.set('os', oslib);

  // ----------------------------------------------------------------------------- coroutine
  const colib = lib({
    create: (a) => {
      const f = a[0];
      if (!(f instanceof LF || f instanceof NF)) throw argErr(1, 'create', 'function expected');
      return [new Coroutine(f, R.current.gt)];
    },
    resume: (a) => {
      const co = a[0];
      if (!(co instanceof Coroutine)) throw argErr(1, 'resume', 'coroutine expected');
      return R.resume(co, a.slice(1));
    },
    status: (a) => {
      const co = a[0];
      if (!(co instanceof Coroutine)) throw argErr(1, 'status', 'coroutine expected');
      return [co.status];
    },
    running: () => [R.current.co === null ? undefined : R.current.co],
    isyieldable: () => [R.current.co !== null],
    wrap: (a) => {
      const f = a[0];
      if (!(f instanceof LF || f instanceof NF)) throw argErr(1, 'wrap', 'function expected');
      const co = new Coroutine(f, R.current.gt);
      return [nf('wrap', (args) => {
        const r = R.resume(co, args);
        if (r[0] === false) {
          if (typeof r[1] === 'string') throw new LuaError(r[1], 1);
          throw new LuaError(r[1], 0);
        }
        return r.slice(1);
      })];
    },
    close: (a) => {
      const co = a[0];
      if (!(co instanceof Coroutine)) throw argErr(1, 'close', 'coroutine expected');
      if (co.status === 'suspended' || co.status === 'dead') {
        const err = co.err;
        co.status = 'dead';
        if (co.gen) { try { co.gen.return(undefined); } catch (e) { /* ignore */ } }
        if (err) return [false, err.value];
        return [true];
      }
      throw rtError(`cannot close ${co.status} coroutine`);
    },
  });
  colib.set('yield', new NF(() => { throw rtError('attempt to yield across metamethod/C-call boundary'); }, 'yield', R.yieldGen));
  colib.frozen = true;
  G.set('coroutine', colib);

  // ----------------------------------------------------------------------------- bit32
  const u = (v, n, f) => checknum(v, n, f) >>> 0;
  const bitlib = lib({
    band: (a) => { let r = 0xffffffff; for (let i = 0; i < a.length; i++) r &= u(a[i], i + 1, 'band'); return [r >>> 0]; },
    bor: (a) => { let r = 0; for (let i = 0; i < a.length; i++) r |= u(a[i], i + 1, 'bor'); return [r >>> 0]; },
    bxor: (a) => { let r = 0; for (let i = 0; i < a.length; i++) r ^= u(a[i], i + 1, 'bxor'); return [r >>> 0]; },
    btest: (a) => { let r = 0xffffffff; for (let i = 0; i < a.length; i++) r &= u(a[i], i + 1, 'btest'); return [r !== 0]; },
    bnot: (a) => [(~u(a[0], 1, 'bnot')) >>> 0],
    lshift: (a) => { const x = u(a[0], 1, 'lshift'), d = checkint(a[1], 2, 'lshift'); return [shift(x, d)]; },
    rshift: (a) => { const x = u(a[0], 1, 'rshift'), d = checkint(a[1], 2, 'rshift'); return [shift(x, -d)]; },
    arshift: (a) => {
      const x = u(a[0], 1, 'arshift'), d = checkint(a[1], 2, 'arshift');
      if (d < 0 || !(x & 0x80000000)) return [shift(x, -d)];
      if (d >= 32) return [0xffffffff];
      return [(x >> d) >>> 0];
    },
    lrotate: (a) => { const x = u(a[0], 1, 'lrotate'); const d = ((checkint(a[1], 2, 'lrotate') % 32) + 32) % 32; return [((x << d) | (x >>> ((32 - d) & 31))) >>> 0]; },
    rrotate: (a) => { const x = u(a[0], 1, 'rrotate'); const d = ((-checkint(a[1], 2, 'rrotate') % 32) + 32) % 32; return [((x << d) | (x >>> ((32 - d) & 31))) >>> 0]; },
    extract: (a) => {
      const x = u(a[0], 1, 'extract'), f = checkint(a[1], 2, 'extract'), w = a[2] === undefined ? 1 : checkint(a[2], 3, 'extract');
      if (f < 0) throw argErr(2, 'extract', 'field cannot be negative');
      if (w <= 0) throw argErr(3, 'extract', 'width must be positive');
      if (f + w > 32) throw rtError('trying to access non-existent bits');
      const mask = w === 32 ? 0xffffffff : ((1 << w) - 1) >>> 0;
      return [((x >>> f) & mask) >>> 0];
    },
    replace: (a) => {
      const x = u(a[0], 1, 'replace'), v = u(a[1], 2, 'replace'), f = checkint(a[2], 3, 'replace'), w = a[3] === undefined ? 1 : checkint(a[3], 4, 'replace');
      if (f < 0) throw argErr(3, 'replace', 'field cannot be negative');
      if (w <= 0) throw argErr(4, 'replace', 'width must be positive');
      if (f + w > 32) throw rtError('trying to access non-existent bits');
      const mask = w === 32 ? 0xffffffff : ((1 << w) - 1) >>> 0;
      return [((x & ~(mask << f)) | ((v & mask) << f)) >>> 0];
    },
    countlz: (a) => [Math.clz32(u(a[0], 1, 'countlz'))],
    countrz: (a) => { const x = u(a[0], 1, 'countrz'); if (x === 0) return [32]; let n = 0; let y = x; while ((y & 1) === 0) { y >>>= 1; n++; } return [n]; },
    byteswap: (a) => { const x = u(a[0], 1, 'byteswap'); return [(((x & 0xff) << 24) | ((x & 0xff00) << 8) | ((x >>> 8) & 0xff00) | (x >>> 24)) >>> 0]; },
  });
  function shift(x, d) {
    if (d <= -32 || d >= 32) return 0;
    if (d >= 0) return (x << d) >>> 0;
    return x >>> (-d);
  }
  bitlib.frozen = true;
  G.set('bit32', bitlib);

  // ----------------------------------------------------------------------------- utf8
  function decodeAt(s, i) { // i 0-based; -> [cp, len] or null
    const c = s.charCodeAt(i);
    if (c < 0x80) return [c, 1];
    let n, cp;
    if (c >= 0xF0 && c < 0xF8) { n = 4; cp = c & 7; }
    else if (c >= 0xE0) { n = 3; cp = c & 15; }
    else if (c >= 0xC0) { n = 2; cp = c & 31; }
    else return null;
    if (c >= 0xF8) return null;
    if (i + n > s.length) return null;
    for (let k = 1; k < n; k++) {
      const cc = s.charCodeAt(i + k);
      if ((cc & 0xC0) !== 0x80) return null;
      cp = (cp << 6) | (cc & 63);
    }
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
    if ((n === 2 && cp < 0x80) || (n === 3 && cp < 0x800) || (n === 4 && cp < 0x10000)) return null;
    return [cp, n];
  }
  const { utf8Bytes } = require('./parser');
  const utf8lib = lib({
    char: (a) => {
      let s = '';
      for (let i = 0; i < a.length; i++) {
        const c = checkint(a[i], i + 1, 'char');
        if (c < 0 || c > 0x10FFFF) throw argErr(i + 1, 'char', 'value out of range');
        s += utf8Bytes(c);
      }
      return [s];
    },
    codepoint: (a) => {
      const s = checkstr(a[0], 1, 'codepoint');
      const i = posrelat(optint(a[1], 2, 'codepoint', 1), s.length);
      const j = posrelat(a[2] === undefined ? i : checkint(a[2], 3, 'codepoint'), s.length);
      if (i < 1) throw argErr(2, 'codepoint', 'out of range');
      if (j > s.length) throw argErr(3, 'codepoint', 'out of range');
      const out = [];
      let p = i - 1;
      while (p < j) {
        const d = decodeAt(s, p);
        if (!d) throw rtError('invalid UTF-8 code');
        out.push(d[0]); p += d[1];
      }
      return out;
    },
    len: (a) => {
      const s = checkstr(a[0], 1, 'len');
      let i = posrelat(optint(a[1], 2, 'len', 1), s.length);
      const j = posrelat(a[2] === undefined ? -1 : checkint(a[2], 3, 'len'), s.length);
      let n = 0;
      let p = i - 1;
      while (p < j) {
        const d = decodeAt(s, p);
        if (!d) return [undefined, p + 1];
        p += d[1]; n++;
      }
      return [n];
    },
    offset: (a) => {
      const s = checkstr(a[0], 1, 'offset');
      const n = checkint(a[1], 2, 'offset');
      const iscont = (p) => (s.charCodeAt(p) & 0xC0) === 0x80;
      let i = posrelat(optint(a[2], 3, 'offset', n >= 0 ? 1 : s.length + 1), s.length) - 1;
      let nn = n;
      if (nn === 0) { while (i > 0 && iscont(i)) i--; return [i + 1]; }
      if (iscont(i)) throw rtError('initial position is a continuation byte');
      if (nn < 0) {
        while (nn < 0 && i > 0) { do { i--; } while (i > 0 && iscont(i)); nn++; }
      } else {
        nn--;
        while (nn > 0 && i < s.length) { do { i++; } while (iscont(i)); nn--; }
      }
      if (nn === 0) return [i + 1];
      return [undefined];
    },
    codes: (a) => {
      const s = checkstr(a[0], 1, 'codes');
      const iter = nf('codes_iter', (b) => {
        let p = checkint(b[1], 2, 'codes');
        // advance past current char
        if (p > 0) { const d = decodeAt(s, p - 1); p = p - 1 + (d ? d[1] : 1); }
        if (p >= s.length) return $E;
        const d = decodeAt(s, p);
        if (!d) throw rtError('invalid UTF-8 code');
        return [p + 1, d[0]];
      });
      return [iter, s, 0];
    },
  });
  utf8lib.set('charpattern', '[\x00-\x7F\xC2-\xF4][\x80-\xBF]*');
  utf8lib.frozen = true;
  G.set('utf8', utf8lib);

  // ----------------------------------------------------------------------------- debug
  const dbglib = lib({
    traceback: (a) => {
      const msg = a[0];
      if (msg !== undefined && typeof msg !== 'string' && typeof msg !== 'number') return [msg];
      return [(msg === undefined ? '' : tostr(msg) + '\n') + 'stack traceback:\n\t[luaujs: no stack]'];
    },
    info: (a) => {
      let f = a[0], what = a[1];
      if (f instanceof Coroutine) { f = a[1]; what = a[2]; }
      if (typeof what !== 'string') throw argErr(2, 'info', 'string expected');
      const out = [];
      if (f instanceof LF || f instanceof NF) {
        for (const ch of what) {
          if (ch === 's') out.push(f instanceof LF ? R.chunkDisplay(f.cn) : '[C]');
          else if (ch === 'l') out.push(f instanceof LF ? f.line : -1);
          else if (ch === 'n') out.push(f.name);
          else if (ch === 'a') { out.push(f instanceof LF ? f.np : 0); out.push(f instanceof LF ? f.va : true); }
          else if (ch === 'f') out.push(f);
        }
        return out;
      }
      for (const ch of what) {
        if (ch === 's') out.push('?'); else if (ch === 'l') out.push(-1); else if (ch === 'n') out.push(undefined);
        else if (ch === 'a') { out.push(0); out.push(true); } else if (ch === 'f') out.push(undefined);
      }
      return out;
    },
  });
  dbglib.frozen = true;
  G.set('debug', dbglib);

  G.frozen = true;
  return G;
}

// pcall / xpcall as generators so a yield inside them reaches the coroutine
function* pcallGen(a) {
  if (a.length === 0) throw argErr(1, 'pcall', 'value expected');
  try {
    const r = yield* $callx(a[0], a.slice(1));
    return [true, ...r];
  } catch (e) {
    const le = fromJsError(e);
    return [false, le.value];
  }
}
function* xpcallGen(a) {
  const h = a[1];
  try {
    const r = yield* $callx(a[0], a.slice(2));
    return [true, ...r];
  } catch (e) {
    const le = fromJsError(e);
    const hr = callSync(h, [le.value]);
    return [false, ...hr];
  }
}
function runGenSync(g) {
  const r = g.next();
  if (!r.done) throw rtError('attempt to yield across metamethod/C-call boundary');
  return r.value;
}

module.exports = { makeBase, flushOut, writeOut, writeErr };
