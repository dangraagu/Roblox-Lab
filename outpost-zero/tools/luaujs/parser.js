'use strict';
// Luau lexer + parser -> AST. Types are parsed and discarded (they never change behaviour).
// Strings are "byte strings": every JS char is one byte 0..255 (sources are read as latin1).

class LuaSyntaxError extends Error {}

const KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in',
  'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);

function utf8Bytes(cp) {
  if (cp < 0x80) return String.fromCharCode(cp);
  if (cp < 0x800) return String.fromCharCode(0xC0 | (cp >> 6), 0x80 | (cp & 63));
  if (cp < 0x10000) return String.fromCharCode(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
  return String.fromCharCode(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
}

const isDigit = (c) => c >= 48 && c <= 57;
const isAlpha = (c) => (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
const isAlnum = (c) => isAlpha(c) || isDigit(c);
const isSpace = (c) => c === 32 || c === 9 || c === 10 || c === 13 || c === 11 || c === 12;

const OPS3 = ['...', '//=', '..='];
const OPS2 = ['==', '~=', '<=', '>=', '..', '::', '->', '+=', '-=', '*=', '/=', '%=', '^=', '//'];
const OPS1 = '+-*/%^#=<>(){}[];:,.?|&@';

function lex(src, chunk) {
  const toks = [];
  const n = src.length;
  let i = 0, line = 1;
  const interp = []; // brace depth per open interpolated string
  const err = (msg, ln) => { throw new LuaSyntaxError(`${chunk}:${ln || line}: ${msg}`); };

  function longBracketLevel(p) { // at '[' ; returns level or -1
    let q = p + 1, lvl = 0;
    while (q < n && src.charCodeAt(q) === 61) { q++; lvl++; }
    return (q < n && src.charCodeAt(q) === 91) ? lvl : -1;
  }
  function readLong(p, lvl) { // p at first '['; returns [string, newPos]
    let q = p + lvl + 2;
    if (src[q] === '\r') { q++; if (src[q] === '\n') q++; line++; }
    else if (src[q] === '\n') { q++; if (src[q] === '\r') q++; line++; }
    const close = ']' + '='.repeat(lvl) + ']';
    const end = src.indexOf(close, q);
    if (end < 0) err('unfinished long string/comment');
    const s = src.slice(q, end);
    for (let k = 0; k < s.length; k++) if (s.charCodeAt(k) === 10) line++;
    return [s, end + close.length];
  }
  function readEscape(q, out) { // q at char after '\\'; returns new q
    const c = src[q];
    switch (c) {
      case 'n': out.push('\n'); return q + 1;
      case 't': out.push('\t'); return q + 1;
      case 'r': out.push('\r'); return q + 1;
      case 'a': out.push('\x07'); return q + 1;
      case 'b': out.push('\b'); return q + 1;
      case 'f': out.push('\f'); return q + 1;
      case 'v': out.push('\v'); return q + 1;
      case '\\': out.push('\\'); return q + 1;
      case '"': out.push('"'); return q + 1;
      case "'": out.push("'"); return q + 1;
      case '`': out.push('`'); return q + 1;
      case '{': out.push('{'); return q + 1;
      case '}': out.push('}'); return q + 1;
      case '\n': out.push('\n'); line++; q++; if (src[q] === '\r') q++; return q;
      case '\r': out.push('\n'); line++; q++; if (src[q] === '\n') q++; return q;
      case 'x': {
        const h = src.slice(q + 1, q + 3);
        if (!/^[0-9a-fA-F]{2}$/.test(h)) err('invalid hexadecimal escape');
        out.push(String.fromCharCode(parseInt(h, 16))); return q + 3;
      }
      case 'z': {
        q++;
        while (q < n && isSpace(src.charCodeAt(q))) { if (src[q] === '\n') line++; q++; }
        return q;
      }
      case 'u': {
        if (src[q + 1] !== '{') err('invalid unicode escape');
        const e = src.indexOf('}', q + 2);
        const h = src.slice(q + 2, e);
        if (!/^[0-9a-fA-F]+$/.test(h)) err('invalid unicode escape');
        out.push(utf8Bytes(parseInt(h, 16))); return e + 1;
      }
      default: {
        if (isDigit(src.charCodeAt(q))) {
          let k = q, v = 0, cnt = 0;
          while (cnt < 3 && k < n && isDigit(src.charCodeAt(k))) { v = v * 10 + (src.charCodeAt(k) - 48); k++; cnt++; }
          if (v > 255) err('escape sequence too large');
          out.push(String.fromCharCode(v)); return k;
        }
        err('invalid escape sequence \\' + c);
      }
    }
  }
  // read interpolated-string body from q (just after ` or }); returns [segment, newPos, endedWithBrace]
  function readInterp(q) {
    const out = [];
    for (;;) {
      if (q >= n) err('unfinished interpolated string');
      const c = src[q];
      if (c === '`') return [out.join(''), q + 1, false];
      if (c === '{') {
        if (src[q + 1] === '{') err('double braces are not permitted within interpolated strings');
        return [out.join(''), q + 1, true];
      }
      if (c === '\\') { q = readEscape(q + 1, out); continue; }
      if (c === '\n') err('unfinished interpolated string');
      out.push(c); q++;
    }
  }

  while (i < n) {
    const c = src.charCodeAt(i);
    if (c === 10) { line++; i++; continue; }
    if (isSpace(c)) { i++; continue; }
    if (c === 45 && src.charCodeAt(i + 1) === 45) { // comment
      if (src[i + 2] === '[') {
        const lvl = longBracketLevel(i + 2);
        if (lvl >= 0) { const r = readLong(i + 2, lvl); i = r[1]; continue; }
      }
      while (i < n && src.charCodeAt(i) !== 10) i++;
      continue;
    }
    const tl = line;
    if (isAlpha(c)) {
      let j = i + 1;
      while (j < n && isAlnum(src.charCodeAt(j))) j++;
      const w = src.slice(i, j);
      toks.push(KEYWORDS.has(w) ? { t: w, line: tl } : { t: 'name', v: w, line: tl });
      i = j; continue;
    }
    if (isDigit(c) || (c === 46 && isDigit(src.charCodeAt(i + 1)))) {
      let j = i;
      let v;
      if (c === 48 && (src[i + 1] === 'x' || src[i + 1] === 'X')) {
        j = i + 2; while (j < n && /[0-9a-fA-F_]/.test(src[j])) j++;
        const h = src.slice(i + 2, j).replace(/_/g, '');
        if (!h) err('malformed number');
        v = h.length <= 13 ? parseInt(h, 16) : Number(BigInt('0x' + h));
      } else if (c === 48 && (src[i + 1] === 'b' || src[i + 1] === 'B')) {
        j = i + 2; while (j < n && /[01_]/.test(src[j])) j++;
        const h = src.slice(i + 2, j).replace(/_/g, '');
        if (!h) err('malformed number');
        v = parseInt(h, 2);
      } else {
        while (j < n) {
          const ch = src[j];
          if (/[0-9_.]/.test(ch)) { j++; continue; }
          if ((ch === 'e' || ch === 'E')) { j++; if (src[j] === '+' || src[j] === '-') j++; continue; }
          break;
        }
        const s = src.slice(i, j).replace(/_/g, '');
        if (!/^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) err('malformed number near ' + src.slice(i, j));
        v = Number(s);
      }
      if (j < n && isAlpha(src.charCodeAt(j))) err('malformed number near ' + src.slice(i, j + 1));
      toks.push({ t: 'number', v, line: tl });
      i = j; continue;
    }
    if (c === 34 || c === 39) { // string
      const q0 = src[i];
      const out = [];
      let q = i + 1;
      for (;;) {
        if (q >= n) err('unfinished string', tl);
        const ch = src[q];
        if (ch === q0) { q++; break; }
        if (ch === '\\') { q = readEscape(q + 1, out); continue; }
        if (ch === '\n' || ch === '\r') err('unfinished string', tl);
        out.push(ch); q++;
      }
      toks.push({ t: 'string', v: out.join(''), line: tl });
      i = q; continue;
    }
    if (c === 96) { // backtick
      const [seg, q, brace] = readInterp(i + 1);
      if (!brace) toks.push({ t: 'string', v: seg, line: tl, interp: true });
      else { toks.push({ t: 'interp_begin', v: seg, line: tl }); interp.push(0); }
      i = q; continue;
    }
    if (c === 91) { // [
      const lvl = longBracketLevel(i);
      if (lvl >= 0) { const r = readLong(i, lvl); toks.push({ t: 'string', v: r[0], line: tl }); i = r[1]; continue; }
    }
    if (c === 123 && interp.length) { interp[interp.length - 1]++; }
    if (c === 125 && interp.length) {
      if (interp[interp.length - 1] === 0) {
        const [seg, q, brace] = readInterp(i + 1);
        if (brace) toks.push({ t: 'interp_mid', v: seg, line: tl });
        else { toks.push({ t: 'interp_end', v: seg, line: tl }); interp.pop(); }
        i = q; continue;
      }
      interp[interp.length - 1]--;
    }
    let op = null;
    const s3 = src.substr(i, 3), s2 = src.substr(i, 2);
    if (OPS3.includes(s3)) op = s3;
    else if (OPS2.includes(s2)) op = s2;
    else if (OPS1.includes(src[i])) op = src[i];
    if (!op) err(`unexpected symbol '${src[i]}'`);
    toks.push({ t: op, line: tl });
    i += op.length;
  }
  toks.push({ t: 'eof', line });
  return toks;
}

// ---------------------------------------------------------------------------------------- parser
const BINPRI = {
  'or': [1, 1], 'and': [2, 2],
  '<': [3, 3], '>': [3, 3], '<=': [3, 3], '>=': [3, 3], '~=': [3, 3], '==': [3, 3],
  '..': [5, 4], '+': [6, 6], '-': [6, 6], '*': [7, 7], '/': [7, 7], '//': [7, 7], '%': [7, 7], '^': [10, 9],
};
const UNARY_PRI = 8;
const COMPOUND = new Set(['+=', '-=', '*=', '/=', '//=', '%=', '^=', '..=']);

function parse(src, chunk) {
  const toks = lex(src, chunk);
  let p = 0;
  let tok = toks[0];
  const next = () => { p++; tok = toks[p]; };
  const peek = (k = 1) => toks[p + k];
  const err = (msg, t) => { throw new LuaSyntaxError(`${chunk}:${(t || tok).line}: ${msg}`); };
  const desc = (t) => t.t === 'name' ? `'${t.v}'` : t.t === 'string' ? 'string' : t.t === 'number' ? `'${t.v}'` : `'${t.t}'`;
  const check = (t) => { if (tok.t !== t) err(`Expected '${t}', got ${desc(tok)}`); };
  const expect = (t, open, openLine) => {
    if (tok.t !== t) {
      if (open) err(`Expected '${t}' (to close '${open}' at line ${openLine}), got ${desc(tok)}`);
      err(`Expected '${t}', got ${desc(tok)}`);
    }
    next();
  };
  const accept = (t) => { if (tok.t === t) { next(); return true; } return false; };
  const name = () => { if (tok.t !== 'name') err(`Expected identifier, got ${desc(tok)}`); const v = tok.v; next(); return v; };

  // ---------------------------------------------------------------- types (parsed, discarded)
  function skipBalanced(open, close) {
    expect(open);
    let depth = 1;
    while (depth > 0) {
      if (tok.t === 'eof') err(`unbalanced '${open}' in type`);
      if (tok.t === open) depth++;
      else if (tok.t === close) depth--;
      next();
    }
  }
  function typeParamsList() { skipBalanced('<', '>'); }
  function simpleType() {
    const t = tok.t;
    if (t === 'nil' || t === 'true' || t === 'false' || t === 'string' || t === 'number') { next(); return; }
    if (t === '...') { next(); type(); return; }
    if (t === 'name') {
      if (tok.v === 'typeof' && peek().t === '(') { next(); skipBalanced('(', ')'); return; }
      next();
      if (tok.t === '.') { next(); name(); }
      if (tok.t === '...') { next(); return; } // generic pack T...
      if (tok.t === '<') typeParamsList();
      return;
    }
    if (t === '{') { skipBalanced('{', '}'); return; }
    if (t === '(') {
      skipBalanced('(', ')');
      if (tok.t === '->') { next(); returnType(); }
      return;
    }
    if (t === '<') { typeParamsList(); skipBalanced('(', ')'); expect('->'); returnType(); return; }
    err(`Expected type, got ${desc(tok)}`);
  }
  function typeWithSuffix() { simpleType(); while (tok.t === '?') next(); }
  function type() {
    if (tok.t === '|' || tok.t === '&') next();
    typeWithSuffix();
    while (tok.t === '|' || tok.t === '&') { next(); typeWithSuffix(); }
  }
  function returnType() { type(); }

  // ---------------------------------------------------------------- expressions
  function funcArgs() {
    const line = tok.line;
    if (tok.t === 'string') { const v = tok.v; next(); return [{ k: 'str', v }]; }
    if (tok.t === '{') return [tableCons()];
    const open = tok.line;
    expect('(');
    if (tok.t === ')') { next(); return []; }
    const args = exprList();
    expect(')', '(', open);
    void line;
    return args;
  }
  function primaryExp() {
    if (tok.t === 'name') { const v = tok.v; const line = tok.line; next(); return { k: 'name', name: v, line }; }
    if (tok.t === '(') {
      const open = tok.line;
      next();
      const e = expr();
      expect(')', '(', open);
      return { k: 'paren', e };
    }
    err(`Expected identifier when parsing expression, got ${desc(tok)}`);
  }
  function suffixedExp() {
    let e = primaryExp();
    for (;;) {
      const t = tok.t;
      if (t === '.') { next(); const line = tok.line; e = { k: 'index', obj: e, key: { k: 'str', v: name() }, line }; }
      else if (t === '[') { const open = tok.line; next(); const key = expr(); expect(']', '[', open); e = { k: 'index', obj: e, key, line: open }; }
      else if (t === ':') { next(); const line = tok.line; const nm = name(); const args = funcArgs(); e = { k: 'method', obj: e, name: nm, args, line }; }
      else if (t === '(' || t === '{' || t === 'string') {
        if (t === 'string' && tok.interp) err('Interpolated strings cannot be used as function call arguments');
        const line = tok.line; const args = funcArgs(); e = { k: 'call', fn: e, args, line };
      }
      else return e;
    }
  }
  function tableCons() {
    const open = tok.line;
    expect('{');
    const items = [];
    while (tok.t !== '}') {
      if (tok.t === '[') {
        const o2 = tok.line; next(); const key = expr(); expect(']', '[', o2); expect('='); items.push({ type: 'kv', key, val: expr() });
      } else if (tok.t === 'name' && peek().t === '=') {
        const key = { k: 'str', v: tok.v }; next(); next(); items.push({ type: 'kv', key, val: expr() });
      } else {
        items.push({ type: 'pos', e: expr() });
      }
      if (tok.t === ',' || tok.t === ';') next(); else break;
    }
    expect('}', '{', open);
    return { k: 'table', items };
  }
  function attributes() { while (tok.t === '@') { next(); if (tok.t === '[') skipBalanced('[', ']'); else name(); } }
  function funcBody(fname, isMethod, line) {
    if (tok.t === '<') typeParamsList();
    const open = tok.line;
    expect('(');
    const params = [];
    let vararg = false;
    if (isMethod) params.push('self');
    if (tok.t !== ')') {
      for (;;) {
        if (tok.t === '...') { next(); vararg = true; if (accept(':')) type(); break; }
        params.push(name());
        if (accept(':')) type();
        if (!accept(',')) break;
      }
    }
    expect(')', '(', open);
    if (accept(':')) returnType();
    const body = block();
    expect('end', 'function', line);
    return { k: 'func', params, vararg, body, name: fname, line };
  }
  function interpString() {
    const parts = [tok.v];
    const line = tok.line;
    next();
    for (;;) {
      parts.push(expr());
      if (tok.t === 'interp_mid') { parts.push(tok.v); next(); continue; }
      if (tok.t === 'interp_end') { parts.push(tok.v); next(); break; }
      err(`Expected '}' after interpolated string expression, got ${desc(tok)}`);
    }
    return { k: 'interp', parts, line };
  }
  function simpleExp() {
    let e;
    const t = tok.t;
    switch (t) {
      case 'number': e = { k: 'num', v: tok.v }; next(); break;
      case 'string': e = { k: 'str', v: tok.v }; next(); break;
      case 'interp_begin': e = interpString(); break;
      case 'nil': e = { k: 'nil' }; next(); break;
      case 'true': e = { k: 'true' }; next(); break;
      case 'false': e = { k: 'false' }; next(); break;
      case '...': e = { k: 'vararg' }; next(); break;
      case '{': e = tableCons(); break;
      case '@': attributes(); check('function'); // fallthrough
      case 'function': { const line = tok.line; next(); e = funcBody('anonymous', false, line); break; }
      case 'if': {
        next();
        const conds = [];
        const c = expr(); expect('then'); const a = expr();
        conds.push([c, a]);
        let els;
        for (;;) {
          if (tok.t === 'elseif') { next(); const c2 = expr(); expect('then'); conds.push([c2, expr()]); continue; }
          expect('else'); els = expr(); break;
        }
        e = { k: 'ifexp', conds, els };
        break;
      }
      default: e = suffixedExp();
    }
    if (tok.t === '::') { next(); type(); e = { k: 'paren', e }; }
    return e;
  }
  function subExpr(limit) {
    let e;
    const t = tok.t;
    if (t === 'not' || t === '-' || t === '#') {
      const line = tok.line;
      next();
      e = { k: 'un', op: t, a: subExpr(UNARY_PRI), line };
    } else e = simpleExp();
    for (;;) {
      const op = tok.t;
      const pri = BINPRI[op];
      if (!pri || pri[0] <= limit) break;
      const line = tok.line;
      next();
      const b = subExpr(pri[1]);
      if (op === 'and') e = { k: 'and', a: e, b };
      else if (op === 'or') e = { k: 'or', a: e, b };
      else e = { k: 'bin', op, a: e, b, line };
    }
    return e;
  }
  function expr() { return subExpr(0); }
  function exprList() { const l = [expr()]; while (accept(',')) l.push(expr()); return l; }

  // ---------------------------------------------------------------- statements
  const blockEnd = () => { const t = tok.t; return t === 'end' || t === 'else' || t === 'elseif' || t === 'until' || t === 'eof'; };
  function block() {
    const stats = [];
    while (!blockEnd()) {
      if (tok.t === 'return') {
        const line = tok.line;
        next();
        const exprs = (blockEnd() || tok.t === ';') ? [] : exprList();
        accept(';');
        stats.push({ k: 'return', exprs, line });
        if (!blockEnd()) err(`Expected <eof>/end after return statement, got ${desc(tok)}`);
        break;
      }
      const s = statement();
      if (s) stats.push(s);
    }
    return stats;
  }
  function binding() { const v = name(); if (accept(':')) type(); return v; }
  function isContinue() {
    if (tok.t !== 'name' || tok.v !== 'continue') return false;
    const nt = peek().t;
    return !(nt === '(' || nt === '.' || nt === '[' || nt === ':' || nt === '=' || nt === ',' || nt === '{' || nt === 'string' || COMPOUND.has(nt));
  }
  function statement() {
    const line = tok.line;
    switch (tok.t) {
      case ';': next(); return null;
      case 'if': {
        next();
        const clauses = [];
        const c = expr(); expect('then'); clauses.push([c, block()]);
        let els = null;
        for (;;) {
          if (tok.t === 'elseif') { next(); const c2 = expr(); expect('then'); clauses.push([c2, block()]); continue; }
          if (tok.t === 'else') { next(); els = block(); }
          expect('end', 'if', line);
          break;
        }
        return { k: 'if', clauses, els, line };
      }
      case 'while': {
        next(); const cond = expr(); expect('do'); const body = block(); expect('end', 'while', line);
        return { k: 'while', cond, body, line };
      }
      case 'do': { next(); const body = block(); expect('end', 'do', line); return { k: 'do', body, line }; }
      case 'repeat': {
        next(); const body = block(); expect('until', 'repeat', line); const cond = expr();
        return { k: 'repeat', body, cond, line };
      }
      case 'for': {
        next();
        const n1 = binding();
        if (tok.t === '=') {
          next();
          const start = expr(); expect(','); const stop = expr();
          const step = accept(',') ? expr() : null;
          expect('do'); const body = block(); expect('end', 'for', line);
          return { k: 'numfor', v: n1, start, stop, step, body, line };
        }
        const names = [n1];
        while (accept(',')) names.push(binding());
        expect('in');
        const exprs = exprList();
        expect('do'); const body = block(); expect('end', 'for', line);
        return { k: 'genfor', names, exprs, body, line };
      }
      case '@': attributes(); // fallthrough to function / local
        if (tok.t === 'local') { next(); check('function'); next(); const nm = name(); return { k: 'localfunc', name: nm, func: funcBody(nm, false, line), line }; }
        check('function');
      // fallthrough
      case 'function': {
        next();
        let target = { k: 'name', name: name(), line };
        let full = target.name;
        let isMethod = false;
        while (tok.t === '.' || tok.t === ':') {
          const sep = tok.t; next();
          const nm = name();
          full += sep + nm;
          target = { k: 'index', obj: target, key: { k: 'str', v: nm }, line };
          if (sep === ':') { isMethod = true; break; }
        }
        const func = funcBody(full, isMethod, line);
        return { k: 'assign', targets: [target], exprs: [func], line };
      }
      case 'local': {
        next();
        if (tok.t === 'function') { next(); const nm = name(); return { k: 'localfunc', name: nm, func: funcBody(nm, false, line), line }; }
        if (tok.t === '@') { attributes(); check('function'); next(); const nm = name(); return { k: 'localfunc', name: nm, func: funcBody(nm, false, line), line }; }
        const names = [binding()];
        while (accept(',')) names.push(binding());
        const exprs = accept('=') ? exprList() : [];
        return { k: 'local', names, exprs, line };
      }
      case 'break': next(); return { k: 'break', line };
      case 'name': {
        if (isContinue()) { next(); return { k: 'continue', line }; }
        if ((tok.v === 'type' && peek().t === 'name') || (tok.v === 'export' && peek().t === 'name' && peek().v === 'type')) {
          if (tok.v === 'export') next();
          next(); // 'type'
          if (tok.t === 'function') { // type function: skip to matching end
            let depth = 0;
            do {
              const t = tok.t;
              if (t === 'function' || t === 'do' || t === 'then' && false) depth++;
              if (t === 'if' || t === 'while' || t === 'for') { /* their 'do'/'then' blocks end with 'end' */ }
              if (t === 'end') depth--;
              next();
            } while (depth > 0 && tok.t !== 'eof');
            return null;
          }
          name();
          if (tok.t === '<') typeParamsList();
          expect('=');
          type();
          return null;
        }
        break;
      }
    }
    // expression statement
    const e = suffixedExp();
    if (tok.t === '=' || tok.t === ',') {
      const targets = [e];
      while (accept(',')) targets.push(suffixedExp());
      expect('=');
      const exprs = exprList();
      for (const t of targets) if (t.k !== 'name' && t.k !== 'index') err('Assigned expression must be a variable or a field', { line });
      return { k: 'assign', targets, exprs, line };
    }
    if (COMPOUND.has(tok.t)) {
      const op = tok.t.slice(0, -1);
      next();
      if (e.k !== 'name' && e.k !== 'index') err('Assigned expression must be a variable or a field', { line });
      return { k: 'compound', op, target: e, e: expr(), line };
    }
    if (e.k !== 'call' && e.k !== 'method') err('Incomplete statement: expected assignment or a function call', { line });
    return { k: 'callstat', call: e, line };
  }

  const body = block();
  if (tok.t !== 'eof') err(`Expected <eof>, got ${desc(tok)}`);
  return { k: 'func', params: [], vararg: true, body, name: 'main chunk', line: 0 };
}

module.exports = { parse, lex, LuaSyntaxError, utf8Bytes };
