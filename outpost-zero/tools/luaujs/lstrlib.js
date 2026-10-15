'use strict';
// Lua 5.1 pattern matching (port of lstrlib.c) and C-exact string.format, over byte strings.
const R = require('./runtime');
const { rtError, typeName, tostr, fmtNum, callSync, $idx } = R;

const CAP_UNFINISHED = -1, CAP_POSITION = -2;
const MAXCCALLS = 200;

const isalpha = (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
const isdigit = (c) => c >= 48 && c <= 57;
const islower = (c) => c >= 97 && c <= 122;
const isupper = (c) => c >= 65 && c <= 90;
const isspace = (c) => c === 32 || (c >= 9 && c <= 13);
const iscntrl = (c) => c < 32 || c === 127;
const ispunct = (c) => (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
const isxdigit = (c) => isdigit(c) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70);
const isalnum = (c) => isalpha(c) || isdigit(c);
const isgraph = (c) => c > 32 && c < 127;

function argErr(n, fname, msg) { return rtError(`invalid argument #${n} to '${fname}' (${msg})`); }

class MatchState {
  constructor(src, pat) { this.src = src; this.pat = pat; this.level = 0; this.capture = []; this.depth = 0; }
}

function classEnd(ms, p) {
  const pat = ms.pat;
  const c = pat.charCodeAt(p++);
  if (c === 37) {
    if (p >= pat.length) throw rtError("malformed pattern (ends with '%')");
    return p + 1;
  }
  if (c === 91) {
    if (pat.charCodeAt(p) === 94) p++;
    do {
      if (p >= pat.length) throw rtError("malformed pattern (missing ']')");
      const cc = pat.charCodeAt(p++);
      if (cc === 37 && p < pat.length) p++;
    } while (pat.charCodeAt(p) !== 93);
    return p + 1;
  }
  return p;
}
function matchClass(c, cl) {
  let res;
  switch (cl | 0x20) {
    case 97: res = isalpha(c); break; // a
    case 99: res = iscntrl(c); break; // c
    case 100: res = isdigit(c); break; // d
    case 103: res = isgraph(c); break; // g
    case 108: res = islower(c); break; // l
    case 112: res = ispunct(c); break; // p
    case 115: res = isspace(c); break; // s
    case 117: res = isupper(c); break; // u
    case 119: res = isalnum(c); break; // w
    case 120: res = isxdigit(c); break; // x
    case 122: res = c === 0; break; // z
    default: return cl === c;
  }
  if (isupper(cl)) res = !res;
  return res;
}
function matchBracketClass(ms, c, p, ec) {
  const pat = ms.pat;
  let sig = true;
  if (pat.charCodeAt(p + 1) === 94) { sig = false; p++; }
  while (++p < ec) {
    const pc = pat.charCodeAt(p);
    if (pc === 37) { p++; if (matchClass(c, pat.charCodeAt(p))) return sig; }
    else if (pat.charCodeAt(p + 1) === 45 && p + 2 < ec) {
      p += 2;
      if (pat.charCodeAt(p - 2) <= c && c <= pat.charCodeAt(p)) return sig;
    } else if (pc === c) return sig;
  }
  return !sig;
}
function singleMatch(ms, c, p, ep) {
  const pc = ms.pat.charCodeAt(p);
  switch (pc) {
    case 46: return true; // .
    case 37: return matchClass(c, ms.pat.charCodeAt(p + 1));
    case 91: return matchBracketClass(ms, c, p, ep - 1);
    default: return pc === c;
  }
}
function matchBalance(ms, s, p) {
  const pat = ms.pat, src = ms.src;
  if (p + 1 >= pat.length) throw rtError("missing arguments to '%b'");
  if (s >= src.length || src.charCodeAt(s) !== pat.charCodeAt(p)) return -1;
  const b = pat.charCodeAt(p), e = pat.charCodeAt(p + 1);
  let cont = 1;
  for (let i = s + 1; i < src.length; i++) {
    const c = src.charCodeAt(i);
    if (c === e) { if (--cont === 0) return i + 1; }
    else if (c === b) cont++;
  }
  return -1;
}
function maxExpand(ms, s, p, ep) {
  let i = 0;
  const src = ms.src;
  while (s + i < src.length && singleMatch(ms, src.charCodeAt(s + i), p, ep)) i++;
  while (i >= 0) {
    const res = doMatch(ms, s + i, ep + 1);
    if (res !== -1) return res;
    i--;
  }
  return -1;
}
function minExpand(ms, s, p, ep) {
  const src = ms.src;
  for (;;) {
    const res = doMatch(ms, s, ep + 1);
    if (res !== -1) return res;
    if (s < src.length && singleMatch(ms, src.charCodeAt(s), p, ep)) s++;
    else return -1;
  }
}
function startCapture(ms, s, p, what) {
  if (ms.level >= 32) throw rtError('too many captures');
  ms.capture[ms.level] = { init: s, len: what };
  ms.level++;
  const res = doMatch(ms, s, p);
  if (res === -1) ms.level--;
  return res;
}
function captureToClose(ms) {
  for (let level = ms.level - 1; level >= 0; level--) if (ms.capture[level].len === CAP_UNFINISHED) return level;
  throw rtError('invalid pattern capture');
}
function endCapture(ms, s, p) {
  const l = captureToClose(ms);
  ms.capture[l].len = s - ms.capture[l].init;
  const res = doMatch(ms, s, p);
  if (res === -1) ms.capture[l].len = CAP_UNFINISHED;
  return res;
}
function checkCapture(ms, l) {
  l -= 49; // '1'
  if (l < 0 || l >= ms.level || ms.capture[l].len === CAP_UNFINISHED) throw rtError(`invalid capture index %${l + 1}`);
  return l;
}
function matchCapture(ms, s, l) {
  l = checkCapture(ms, l);
  const len = ms.capture[l].len, init = ms.capture[l].init;
  if (ms.src.length - s >= len && ms.src.substr(init, len) === ms.src.substr(s, len)) return s + len;
  return -1;
}
function doMatch(ms, s, p) {
  if (ms.depth++ > MAXCCALLS) throw rtError('pattern too complex');
  try {
    const pat = ms.pat, src = ms.src, plen = pat.length;
    for (;;) {
      if (p === plen) return s;
      const pc = pat.charCodeAt(p);
      let dflt = true;
      switch (pc) {
        case 40: // (
          if (pat.charCodeAt(p + 1) === 41) return startCapture(ms, s, p + 2, CAP_POSITION);
          return startCapture(ms, s, p + 1, CAP_UNFINISHED);
        case 41: // )
          return endCapture(ms, s, p + 1);
        case 37: { // %
          const nc = pat.charCodeAt(p + 1);
          if (nc === 98) { // b
            s = matchBalance(ms, s, p + 2);
            if (s !== -1) { p += 4; continue; }
            return -1;
          }
          if (nc === 102) { // f
            p += 2;
            if (pat.charCodeAt(p) !== 91) throw rtError("missing '[' after '%f' in pattern");
            const ep = classEnd(ms, p);
            const prev = (s === 0) ? 0 : src.charCodeAt(s - 1);
            const cur = (s < src.length) ? src.charCodeAt(s) : 0;
            if (!matchBracketClass(ms, prev, p, ep - 1) && matchBracketClass(ms, cur, p, ep - 1)) { p = ep; continue; }
            return -1;
          }
          if (isdigit(nc)) {
            s = matchCapture(ms, s, nc);
            if (s !== -1) { p += 2; continue; }
            return -1;
          }
          break;
        }
        case 36: // $
          if (p + 1 === plen) return (s === src.length) ? s : -1;
          break;
      }
      if (dflt) {
        const ep = classEnd(ms, p);
        const m = s < src.length && singleMatch(ms, src.charCodeAt(s), p, ep);
        const epc = ep < plen ? pat.charCodeAt(ep) : -1;
        switch (epc) {
          case 63: { // ?
            if (m) { const res = doMatch(ms, s + 1, ep + 1); if (res !== -1) return res; }
            p = ep + 1; continue;
          }
          case 42: return maxExpand(ms, s, p, ep); // *
          case 43: return m ? maxExpand(ms, s + 1, p, ep) : -1; // +
          case 45: return minExpand(ms, s, p, ep); // -
          default:
            if (!m) return -1;
            s++; p = ep; continue;
        }
      }
    }
  } finally { ms.depth--; }
}
function getCapture(ms, i, s, e) {
  if (i >= ms.level) {
    if (i === 0) return ms.src.slice(s, e);
    throw rtError('invalid capture index');
  }
  const c = ms.capture[i];
  if (c.len === CAP_UNFINISHED) throw rtError('unfinished capture');
  if (c.len === CAP_POSITION) return c.init + 1;
  return ms.src.substr(c.init, c.len);
}
function captures(ms, s, e, wholeIfNone) {
  const n = (ms.level === 0 && wholeIfNone) ? 1 : ms.level;
  const out = new Array(n);
  for (let i = 0; i < n; i++) out[i] = getCapture(ms, i, s, e);
  return out;
}

function checkstr(v, n, fname) {
  if (typeof v === 'string') return v;
  if (typeof v === 'number') return fmtNum(v);
  throw argErr(n, fname, `string expected, got ${v === undefined ? 'no value' : typeName(v)}`);
}
function checknum(v, n, fname) {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') { const x = R.str2number(v); if (x !== undefined) return x; }
  throw argErr(n, fname, `number expected, got ${v === undefined ? 'no value' : typeName(v)}`);
}
function checkint(v, n, fname) { return Math.trunc(checknum(v, n, fname)); }
function optint(v, n, fname, d) { return v === undefined ? d : checkint(v, n, fname); }
function posrelat(pos, len) { if (pos >= 0) return pos; if (-pos > len) return 0; return len + pos + 1; }

const SPECIALS = /[\^$*+?.()[\]%-]/;
function strFindAux(args, find) {
  const fname = find ? 'find' : 'match';
  const s = checkstr(args[0], 1, fname), p = checkstr(args[1], 2, fname);
  let init = posrelat(optint(args[2], 3, fname, 1), s.length);
  if (init < 1) init = 1;
  if (init > s.length + 1) return [undefined];
  init -= 1;
  if (find && ((args[3] !== undefined && args[3] !== false) || !SPECIALS.test(p))) {
    const idx = s.indexOf(p, init);
    if (idx >= 0) return [idx + 1, idx + p.length];
    return [undefined];
  }
  const ms = new MatchState(s, p);
  const anchor = p.charCodeAt(0) === 94;
  const pi = anchor ? 1 : 0;
  let s1 = init;
  do {
    ms.level = 0; ms.depth = 0;
    const e = doMatch(ms, s1, pi);
    if (e !== -1) {
      if (find) return [s1 + 1, e, ...captures(ms, -1, 0, false)];
      return captures(ms, s1, e, true);
    }
  } while (s1++ < s.length && !anchor);
  return [undefined];
}
function gmatch(args) {
  const s = checkstr(args[0], 1, 'gmatch'), p = checkstr(args[1], 2, 'gmatch');
  const ms = new MatchState(s, p);
  let pos = 0;
  return [new R.NF(() => {
    for (let src = pos; src <= s.length; src++) {
      ms.level = 0; ms.depth = 0;
      const e = doMatch(ms, src, 0);
      if (e !== -1) {
        let ns = e;
        if (e === src) ns++;
        pos = ns;
        return captures(ms, src, e, true);
      }
    }
    pos = s.length + 1;
    return [];
  }, 'gmatch_iter')];
}
function addValue(ms, out, s, e, repl, tr) {
  const src = ms.src;
  if (tr === 'string' || tr === 'number') {
    const r = tr === 'number' ? fmtNum(repl) : repl;
    for (let i = 0; i < r.length; i++) {
      const c = r.charCodeAt(i);
      if (c !== 37) { out.push(r[i]); continue; }
      i++;
      const d = r.charCodeAt(i);
      if (isdigit(d)) {
        if (d === 48) out.push(src.slice(s, e));
        else {
          const cap = getCapture(ms, d - 49, s, e);
          out.push(typeof cap === 'number' ? fmtNum(cap) : cap);
        }
      } else if (d === 37) out.push('%');
      else throw rtError("invalid use of '%' in replacement string");
    }
    return;
  }
  let val;
  if (tr === 'table') val = $idx(repl, getCapture(ms, 0, s, e));
  else val = callSync(repl, captures(ms, s, e, true))[0];
  if (val === undefined || val === false) out.push(src.slice(s, e));
  else if (typeof val === 'string') out.push(val);
  else if (typeof val === 'number') out.push(fmtNum(val));
  else throw rtError(`invalid replacement value (a ${typeName(val)})`);
}
function gsub(args) {
  const src = checkstr(args[0], 1, 'gsub'), p = checkstr(args[1], 2, 'gsub');
  const repl = args[2];
  const tr = typeName(repl);
  if (!(tr === 'number' || tr === 'string' || tr === 'function' || tr === 'table'))
    throw argErr(3, 'gsub', 'string/function/table expected');
  const maxN = args[3] === undefined ? src.length + 1 : checkint(args[3], 4, 'gsub');
  const anchor = p.charCodeAt(0) === 94;
  const pi = anchor ? 1 : 0;
  let n = 0, s = 0;
  const out = [];
  const ms = new MatchState(src, p);
  while (n < maxN) {
    ms.level = 0; ms.depth = 0;
    const e = doMatch(ms, s, pi);
    if (e !== -1) { n++; addValue(ms, out, s, e, repl, tr); }
    if (e !== -1 && e > s) s = e;
    else if (s < src.length) out.push(src[s++]);
    else break;
    if (anchor) break;
  }
  out.push(src.slice(s));
  return [out.join(''), n];
}

// ------------------------------------------------------------------------------------- format
const dv = new DataView(new ArrayBuffer(8));
function decompose(x) {
  dv.setFloat64(0, x);
  const hi = dv.getUint32(0), lo = dv.getUint32(4);
  const exp = (hi >>> 20) & 0x7ff;
  const mant = (BigInt(hi & 0xfffff) << 32n) | BigInt(lo);
  if (exp === 0) return [mant, -1074];
  return [mant | (1n << 52n), exp - 1075];
}
const POW10 = [];
function pow10(n) { if (POW10[n] === undefined) POW10[n] = 10n ** BigInt(n); return POW10[n]; }
function roundScaled(x, s) { // round_half_even(x * 10^s), x >= 0 finite
  const [M, E] = decompose(x);
  let num = M, den = 1n;
  if (E >= 0) num <<= BigInt(E); else den <<= BigInt(-E);
  if (s >= 0) num *= pow10(s); else den *= pow10(-s);
  const q = num / den, r = num - q * den;
  const r2 = r * 2n;
  if (r2 > den || (r2 === den && (q & 1n) === 1n)) return q + 1n;
  return q;
}
function fmtF(x, prec, alt) {
  const n = roundScaled(x, prec);
  let s = n.toString();
  if (prec > 0) {
    if (s.length <= prec) s = '0'.repeat(prec - s.length + 1) + s;
    s = s.slice(0, s.length - prec) + '.' + s.slice(s.length - prec);
  } else if (alt) s += '.';
  return s;
}
function expParts(x, prec) { // -> [digits string of length prec+1, exponent]
  if (x === 0) return ['0'.repeat(prec + 1), 0];
  let X = Math.floor(Math.log10(x));
  for (let tries = 0; tries < 4; tries++) {
    const n = roundScaled(x, prec - X);
    const s = n.toString();
    if (s.length > prec + 1) { X++; continue; }
    if (s.length < prec + 1) { X--; continue; }
    return [s, X];
  }
  const n = roundScaled(x, prec - X);
  return [n.toString().slice(0, prec + 1), X];
}
function fmtE(x, prec, alt, upper) {
  const [d, X] = expParts(x, prec);
  let s = d[0];
  if (prec > 0) s += '.' + d.slice(1);
  else if (alt) s += '.';
  const ax = Math.abs(X);
  s += (upper ? 'E' : 'e') + (X < 0 ? '-' : '+') + (ax < 10 ? '0' + ax : String(ax));
  return s;
}
function fmtG(x, prec, alt, upper) {
  let P = prec === null ? 6 : prec;
  if (P === 0) P = 1;
  let X = 0;
  if (x !== 0) X = expParts(x, P - 1)[1];
  let s;
  if (P > X && X >= -4) s = fmtF(x, P - 1 - X, alt);
  else s = fmtE(x, P - 1, alt, upper);
  if (!alt) {
    let mant = s, exp = '';
    const ei = s.search(/[eE]/);
    if (ei >= 0) { mant = s.slice(0, ei); exp = s.slice(ei); }
    if (mant.includes('.')) { mant = mant.replace(/0+$/, ''); if (mant.endsWith('.')) mant = mant.slice(0, -1); }
    s = mant + exp;
  }
  return s;
}
function padNum(prefix, body, flags, width, allowZero) {
  const len = prefix.length + body.length;
  if (width <= len) return prefix + body;
  if (flags.includes('-')) return prefix + body + ' '.repeat(width - len);
  if (flags.includes('0') && allowZero) return prefix + '0'.repeat(width - len) + body;
  return ' '.repeat(width - len) + prefix + body;
}
function padStr(s, flags, width) {
  if (width <= s.length) return s;
  if (flags.includes('-')) return s + ' '.repeat(width - s.length);
  return ' '.repeat(width - s.length) + s;
}
function quoteStr(s) {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 34 || c === 92 || c === 10) out += '\\' + s[i];
    else if (c === 13) out += '\\r';
    else if (c === 0) out += '\\000';
    else out += s[i];
  }
  return out + '"';
}
function strFormat(args) {
  const fmt = checkstr(args[0], 1, 'format');
  let argi = 1;
  const out = [];
  const L = fmt.length;
  for (let i = 0; i < L; i++) {
    const c = fmt.charCodeAt(i);
    if (c !== 37) {
      let j = fmt.indexOf('%', i);
      if (j < 0) j = L;
      out.push(fmt.slice(i, j));
      i = j - 1;
      continue;
    }
    i++;
    if (i >= L) throw rtError("invalid option '%' to 'format'");
    if (fmt[i] === '%') { out.push('%'); continue; }
    let j = i;
    while (j < L && '-+ #0'.includes(fmt[j])) j++;
    const flags = fmt.slice(i, j);
    if (flags.length > 5) throw rtError('invalid format (repeated flags)');
    let ws = '';
    while (j < L && isdigit(fmt.charCodeAt(j))) ws += fmt[j++];
    let prec = null;
    if (fmt[j] === '.') {
      j++;
      let ps = '';
      while (j < L && isdigit(fmt.charCodeAt(j))) ps += fmt[j++];
      prec = ps === '' ? 0 : parseInt(ps, 10);
      if (ps.length > 2) throw rtError('invalid format (width or precision too long)');
    }
    if (ws.length > 2) throw rtError('invalid format (width or precision too long)');
    const width = ws === '' ? 0 : parseInt(ws, 10);
    const conv = fmt[j];
    i = j;
    const an = argi + 1;
    if (conv === undefined) throw rtError("invalid option '%' to 'format'");
    const arg = args[argi++];
    switch (conv) {
      case 'd': case 'i': {
        const n = Math.trunc(checknum(arg, an, 'format'));
        let digits = Number.isFinite(n) ? BigInt(Math.abs(n)).toString() : String(Math.abs(n));
        if (prec !== null) { if (prec === 0 && digits === '0') digits = ''; digits = digits.padStart(prec, '0'); }
        const prefix = n < 0 || Object.is(n, -0) && false ? '-' : flags.includes('+') ? '+' : flags.includes(' ') ? ' ' : '';
        out.push(padNum(prefix, digits, flags, width, prec === null));
        break;
      }
      case 'u': case 'x': case 'X': case 'o': {
        const n = Math.trunc(checknum(arg, an, 'format'));
        const u = Number.isFinite(n) ? BigInt.asUintN(64, BigInt(n)) : 0n;
        let digits = u.toString(conv === 'o' ? 8 : conv === 'u' ? 10 : 16);
        if (conv === 'X') digits = digits.toUpperCase();
        if (prec !== null) { if (prec === 0 && digits === '0') digits = ''; digits = digits.padStart(prec, '0'); }
        let prefix = '';
        if (flags.includes('#')) {
          if ((conv === 'x' || conv === 'X') && u !== 0n) prefix = conv === 'x' ? '0x' : '0X';
          if (conv === 'o' && digits[0] !== '0') digits = '0' + digits;
        }
        out.push(padNum(prefix, digits, flags, width, prec === null));
        break;
      }
      case 'c': {
        const n = checkint(arg, an, 'format');
        out.push(padStr(String.fromCharCode(n & 255), flags, width));
        break;
      }
      case 'e': case 'E': case 'f': case 'F': case 'g': case 'G': {
        const x = checknum(arg, an, 'format');
        const neg = x < 0 || (x === 0 && 1 / x < 0);
        const ax = Math.abs(x);
        const prefix = neg ? '-' : flags.includes('+') ? '+' : flags.includes(' ') ? ' ' : '';
        const alt = flags.includes('#');
        const upper = conv === 'E' || conv === 'F' || conv === 'G';
        let body;
        if (!Number.isFinite(x)) {
          body = x !== x ? 'nan' : 'inf';
          if (upper) body = body.toUpperCase();
          out.push(padNum(x !== x ? (flags.includes('+') ? '+' : '') : prefix, body, flags, width, false));
          break;
        }
        if (conv === 'f' || conv === 'F') body = fmtF(ax, prec === null ? 6 : prec, alt);
        else if (conv === 'e' || conv === 'E') body = fmtE(ax, prec === null ? 6 : prec, alt, upper);
        else body = fmtG(ax, prec, alt, upper);
        out.push(padNum(prefix, body, flags, width, true));
        break;
      }
      case 'a': case 'A': {
        const x = checknum(arg, an, 'format');
        out.push(padStr(hexFloat(x, conv === 'A'), flags, width));
        break;
      }
      case 'q': out.push(quoteStr(checkstr(arg, an, 'format'))); break;
      case 's': {
        if (arg === undefined && argi - 1 >= args.length) throw argErr(an, 'format', 'string expected, got no value');
        let s = tostr(arg);
        if (prec !== null) s = s.slice(0, prec);
        out.push(padStr(s, flags, width));
        break;
      }
      case '*': {
        if (argi - 1 >= args.length) throw argErr(an, 'format', 'value expected');
        out.push(tostr(arg));
        break;
      }
      default:
        throw rtError(`invalid option '%${conv}' to 'format'`);
    }
  }
  return [out.join('')];
}
function hexFloat(x, upper) {
  if (!Number.isFinite(x)) return x !== x ? 'nan' : (x < 0 ? '-inf' : 'inf');
  if (x === 0) return (1 / x < 0 ? '-' : '') + '0x0p+0';
  const neg = x < 0; const ax = Math.abs(x);
  const [M, E] = decompose(ax);
  let m = M, e = E;
  while ((m >> 52n) === 0n) { m <<= 1n; e--; }
  const frac = (m & ((1n << 52n) - 1n)).toString(16).padStart(13, '0').replace(/0+$/, '');
  let s = (neg ? '-' : '') + '0x1' + (frac ? '.' + frac : '') + 'p' + (e + 52 >= 0 ? '+' : '') + (e + 52);
  if (upper) s = s.toUpperCase();
  return s;
}

module.exports = { strFindAux, gmatch, gsub, strFormat, checkstr, checknum, checkint, optint, posrelat, argErr, quoteStr };
