/*
  Blocks for StellarLean questions, independent of the editor.

  * `buildSpecs(contract)` lists every block a contract offers: its shape, the
    types of its slots, its label (as Lean or in words) and how it prints.
  * `genLean` / `genWords` print a block tree (Blockly's JSON serialization).
  * `parseTheorem` reads a Lean question back into a block tree.

  Types (Blockly connection checks):
    Q question   I invariant   TI number term   TA address term
    W whose (taken from the call)   A address   D call argument   E entry point
*/
(function (root) {
  const CAT = {
    theorem:   { name: 'Theorem',      colour: '#E1A91A' },
    glue:      { name: 'Glue',         colour: '#5CB712' },
    change:    { name: 'Changes',      colour: '#4A6CD4' },
    cond:      { name: 'Conditions',   colour: '#2CA5E2' },
    storage:   { name: 'Storage',      colour: '#EE7D16' },
    who:       { name: 'Who',          colour: '#8A55D7' },
    arg:       { name: 'Arguments',    colour: '#BB42C3' },
    entry:     { name: 'Entry points', colour: '#CC5B22' },
    invariant: { name: 'Invariants',   colour: '#0E9A6C' },
  };

  const ATOM = 1024, APP = 1000;
  const TERM = ['TI', 'TA'];
  const inp = (name, check) => ({ k: 'in', name, check });

  /** Every block of contract `C` (an entry of `VOCAB.contracts`), keyed by type. */
  function buildSpecs(key, C) {
    const specs = {};
    const add = (s) => { specs[s.type] = s; return s; };
    const has = (f) => C.features.includes(f);

    add({ type: `${key}.theorem`, cat: 'theorem', out: null,
      lean: 'theorem %1 : %2 ⊨ %3 %4 %5 := by %6',
      words: 'claim %1 : after every successful call to %2 %3 %4 %5 proved by %6',
      args: [{ k: 'text', name: 'NAME', value: 'my_question' },
             { k: 'drop', name: 'TARGET', options: C.targets.map(([t, w]) => [t, t]) },
             { k: 'row', name: 'ROW1' },
             inp('Q', ['Q']),
             { k: 'row', name: 'ROW2' },
             { k: 'drop', name: 'TACTIC', options: C.tactics.map((t) => [t, t]) }],
      g: 'theorem', kind: C.kind, diver: C.diver, tip: 'A question about the contract. Its proof is the answer.' });

    // Glue
    add({ type: 'and', cat: 'glue', out: 'Q', lean: '%1 AND %2', words: '%1 AND %2',
      args: [inp('P', ['Q']), inp('R', ['Q'])], g: 'infix', op: '∧ₛ', prec: 35,
      say: '{P} and {R}', tip: 'Both checks hold for the same call.' });
    add({ type: 'or', cat: 'glue', out: 'Q', lean: '%1 OR %2', words: '%1 OR %2',
      args: [inp('P', ['Q']), inp('R', ['Q'])], g: 'infix', op: '∨ₛ', prec: 30,
      say: '{P} or {R}', tip: 'At least one of the two checks holds.' });
    add({ type: 'given', cat: 'glue', out: 'Q', lean: '%1 .given %2', words: '%1 whenever %2',
      args: [inp('P', ['Q']), inp('G', ['Q'])], g: 'method', m: 'given',
      say: 'whenever {G}, {P}', tip: 'P, on calls where G holds. Nothing is claimed about the others.' });
    add({ type: 'except', cat: 'glue', out: 'Q', lean: '%1 .except %2', words: '%1 unless %2',
      args: [inp('P', ['Q']), inp('G', ['Q'])], g: 'method', m: 'except',
      say: '{P}, unless {G}', tip: 'P must hold, except on calls where G holds.' });
    add({ type: 'forall', cat: 'glue', out: 'Q', lean: 'FOR EACH %1 , %2', words: 'FOR EACH %1 , %2',
      args: [{ k: 'text', name: 'VAR', value: 'user' }, inp('P', ['Q'])], g: 'forall',
      say: 'for every address {VAR}: {P}',
      tip: 'The check holds for every address plugged in for the variable. Use the variable with the "user" block in Who.' });

    // Changes
    const change = (type, lean, check, say, tip, more) => add({ type, cat: 'change', out: 'Q',
      lean: more ? `${lean} %1 %2` : `${lean} %1`, words: say.replace('{T}', '%1').replace('{D}', '%2'),
      args: more ? [inp('T', check), inp('D', ['D'])] : [inp('T', check)],
      g: 'app', head: lean, say, tip });
    change('unchanged', 'unchanged', TERM, '{T} stays the same', 'The value is the same after the call as before.');
    change('decreases', 'decreases', ['TI'], '{T} goes down', 'The value is strictly lower after the call.');
    change('increases', 'increases', ['TI'], '{T} goes up', 'The value is strictly higher after the call.');
    change('neverDecreases', 'neverDecreases', ['TI'], '{T} never goes down', 'The value is at least as high after the call.');
    change('changesBy', 'changesBy', ['TI'], '{T} changes by exactly {D}', 'after = before + d', true);
    change('dropsAtMost', 'dropsAtMost', ['TI'], '{T} drops by at most {D}', 'before − d ≤ after (e.g. "pays at most in_max")', true);
    change('gainsAtLeast', 'gainsAtLeast', ['TI'], '{T} gains at least {D}', 'before + d ≤ after (e.g. "receives at least min_a")', true);
    change('returns', 'returns', TERM, 'the call returns {T}', 'The call returns the value after the call.');
    change('signedBy', 'signedBy', ['TA'], '{T} signed the call', 'The address stored there signed the call (require_auth).');

    // Conditions
    if (has('calls'))
      add({ type: 'calls', cat: 'cond', out: 'Q', lean: 'calls %1', words: 'the call is %1',
        args: [inp('E', ['E'])], g: 'app', head: 'calls', say: 'the call is {E}', tip: 'The call invokes this entry point.' });
    add({ type: 'isCaller', cat: 'cond', out: 'Q', lean: 'isCaller %1', words: '%1 is the caller',
      args: [inp('A', ['A'])], g: 'app', head: 'isCaller', say: '{A} is the caller', tip: 'This address signed the call.' });
    if (C.who.includes('recipient'))
      add({ type: 'isRecipient', cat: 'cond', out: 'Q', lean: 'isRecipient %1', words: '%1 is the recipient',
        args: [inp('A', ['A'])], g: 'app', head: 'isRecipient', say: '{A} is the recipient', tip: 'This address receives the transfer.' });
    for (const [name, words] of C.addrPreds)
      add({ type: `${key}.pred.${name}`, cat: 'cond', out: 'Q', lean: `${name} %1`, words: `%1 ${words}`,
        args: [inp('A', ['A'])], g: 'app', head: name, say: `{A} ${words}`, tip: `${name}: this address ${words}.` });
    for (const [name, words] of C.conds)
      add({ type: `${key}.cond.${name}`, cat: 'cond', out: 'Q', lean: name, words, args: [],
        g: 'atom', text: name, say: words, tip: `${name}: ${words}.` });
    if (has('beforeAfter')) {
      add({ type: 'before', cat: 'invariant', out: 'Q', lean: 'before %1', words: 'before the call, %1',
        args: [inp('I', ['I'])], g: 'app', head: 'before', say: 'before the call, {I}', tip: 'The invariant holds before the call.' });
      add({ type: 'after', cat: 'invariant', out: 'Q', lean: 'after %1', words: 'after the call, %1',
        args: [inp('I', ['I'])], g: 'app', head: 'after', say: 'after the call, {I}', tip: 'The invariant holds after the call.' });
    }
    if (has('preserves'))
      add({ type: 'preserves', cat: 'invariant', out: 'Q', lean: 'preserves %1', words: 'the call keeps %1',
        args: [inp('I', ['I'])], g: 'app', head: 'preserves', say: 'if {I} before the call, then also after',
        tip: 'If the invariant holds before the call, it holds after.' });
    for (const [name, words] of C.invariants)
      add({ type: `${key}.inv.${name}`, cat: 'invariant', out: 'I', lean: name, words, args: [],
        g: 'atom', text: name, say: words, tip: `${name}: ${words}.` });

    // Storage
    for (const [name, ty, words] of C.vars)
      add({ type: `${key}.var.${name}`, cat: 'storage', out: ty === 'Int' ? 'TI' : 'TA', lean: name, words,
        args: [], g: 'atom', text: name, say: words, tip: `Storage variable ${name} (${ty === 'Int' ? 'number' : 'address'}).` });
    for (const [name, words] of C.maps) {
      add({ type: `${key}.map.${name}`, cat: 'storage', out: 'TI', lean: `${name} [ %1 ]`, words: `${words} %1`,
        args: [inp('W', ['W', 'A'])], g: 'index', map: name, say: `${words} {W}`,
        tip: `One entry of the storage map ${name}. Put a Who block in the slot.` });
      if (!C.kind) add({ type: `${key}.total.${name}`, cat: 'storage', out: 'TI', lean: `${name}.total`, words: `the sum of all ${name}`,
        args: [], g: 'atom', text: `${name}.total`, say: `the sum of all ${name}`,
        tip: `Sum of ${name} over the (ghost) list of holders.` });
    }
    const arith = (type, op, prec, say) => add({ type, cat: 'storage', out: 'TI', lean: `%1 ${op} %2`, words: `%1 ${say} %2`,
      args: [inp('L', C.kind ? ['TI', 'D'] : ['TI']), inp('R', C.kind ? ['TI', 'D'] : ['TI'])], g: 'infix', op, prec, assoc: 'l',
      say: `{L} ${say} {R}`, tip: `Arithmetic on number terms.` });
    arith('add', '+', 65, 'plus');
    arith('sub', '-', 65, 'minus');
    arith('mul', '*', 70, 'times');

    // Who
    const WHO = { caller: ['the caller', 'Whoever signed the call.'], recipient: ['the recipient', 'The `to` argument of the call.'] };
    for (const w of C.who)
      add({ type: `who.${w}`, cat: 'who', out: 'W', lean: w, words: WHO[w][0], args: [], g: 'atom', text: w,
        say: WHO[w][0], tip: WHO[w][1] });
    for (const [name, words] of C.addrs)
      add({ type: `${key}.addr.${name}`, cat: 'who', out: 'A', lean: name, words, args: [], g: 'atom', text: name,
        say: words, tip: `The fixed address ${name}.` });
    add({ type: 'user', cat: 'who', out: 'A', lean: '%1', words: 'address %1',
      args: [{ k: 'text', name: 'NAME', value: 'user' }], g: 'bound', say: '{NAME}',
      tip: 'The address bound by an enclosing "FOR EACH" block (the names must match).' });

    // Arguments
    for (const [name, rust] of C.amounts)
      add({ type: `${key}.amt.${name}`, cat: 'arg', out: 'D', lean: name, words: rust, args: [], g: 'atom', text: name,
        say: rust, tip: `Call argument ${rust}.` });
    add({ type: 'neg', cat: 'arg', out: 'D', lean: '(- %1 ·)', words: 'minus %1', args: [inp('D', ['D'])], g: 'neg',
      say: 'minus {D}', tip: 'The argument, negated.' });
    add({ type: 'const', cat: 'arg', out: 'D', lean: 'fun _ => %1', words: 'the number %1',
      args: [{ k: 'num', name: 'N', value: 1 }], g: 'const', say: '{N}', tip: 'A fixed number, whatever the call.' });

    // Models emitted by stellar-diver: compare any two values, in the state before or
    // after the call, and use the values the model derives for each entry point.
    if (C.kind === 'diver') {
      const NUM = ['TI', 'D'];
      for (const [type, op, say] of [['cmp.eq', '=', 'equals'], ['cmp.ne', '≠', 'differs from'], ['cmp.le', '≤', 'is at most'],
                                     ['cmp.lt', '<', 'is less than'], ['cmp.aeq', '=', 'is the same address as'], ['cmp.ane', '≠', 'is not the address']]) {
        const addr = type.startsWith('cmp.a');
        add({ type, cat: 'cond', out: 'Q', lean: `%1 ${op} %2`, words: `%1 ${say} %2`,
          args: [inp('L', addr ? ['TA', 'A', 'W'] : NUM), inp('R', addr ? ['TA', 'A', 'W'] : NUM)], g: 'cmp', op, prec: 50,
          say: `{L} ${say} {R}`, tip: `Compare two ${addr ? 'addresses' : 'numbers'}.` });
      }
      add({ type: 'not', cat: 'glue', out: 'Q', lean: 'NOT %1', words: 'NOT %1', args: [inp('P', ['Q'])], g: 'not',
        say: 'not [{P}]', tip: 'The check does not hold.' });
      add({ type: 'dbefore', cat: 'cond', out: 'Q', lean: 'before %1', words: 'before the call, %1', args: [inp('P', ['Q'])],
        g: 'state', state: 'pre', say: 'before the call, {P}', tip: 'Storage in the check is read before the call.' });
      add({ type: 'dafter', cat: 'cond', out: 'Q', lean: 'after %1', words: 'after the call, %1', args: [inp('P', ['Q'])],
        g: 'state', state: 'post', say: 'after the call, {P}', tip: 'Storage in the check is read after the call.' });
      add({ type: 'num', cat: 'arg', out: 'TI', lean: '%1', words: '%1', args: [{ k: 'num', name: 'N', value: 0 }],
        g: 'num', say: '{N}', tip: 'A number.' });
      for (const d of C.diver.derived)
        add({ type: `${key}.derived.${d}`, cat: 'storage', out: 'TI', lean: d, words: `the ${d.replace('.', ' ')} of the call`, args: [],
          g: 'derived', text: d, say: d, tip: `A value the model derives for the call (${d} in the model).` });
    }

    // Entry points
    for (const e of C.entries)
      add({ type: `${key}.entry.${e}`, cat: 'entry', out: 'E', lean: `"${e}"`, words: e, args: [], g: 'atom',
        text: `"${e}"`, say: e, tip: `The ${e} entry point.` });
    return specs;
  }

  /* ---------------------------------------------------------------- Printing
     Printed code carries markers around each block (`id … `)
     so the editor can link code to blocks; `plain` removes them. */

  const OPEN = '', MID = '', CLOSE = '', HOLE = '';
  const plain = (s) => s.replace(/[^]*/g, '').replace(//g, '').replace(//g, '?');
  const wrap = (b, s) => OPEN + (b.id || '') + MID + s + CLOSE;

  /** Lean for block `b`: `{code, prec}`. `ctx.problems` collects what is missing. */
  function lean(specs, b, ctx, scope = []) {
    if (!b) { ctx.problems.push('an empty slot'); return { code: HOLE, prec: ATOM }; }
    const s = specs[b.type];
    if (!s) { ctx.problems.push(`unknown block ${b.type}`); return { code: HOLE, prec: ATOM }; }
    const sub = (name, min, sc = scope) => {
      const r = lean(specs, b.inputs?.[name]?.block, ctx, sc);
      return r.prec >= min ? r.code : `(${r.code})`;
    };
    const f = (name) => b.fields?.[name] ?? s.args.find((a) => a.name === name)?.value;
    const ins = s.args.filter((a) => a.k === 'in').map((a) => a.name);
    let code, prec;
    switch (s.g) {
      case 'atom': code = s.text; prec = ATOM; break;
      case 'app': code = [s.head, ...ins.map((n) => sub(n, ATOM))].join(' '); prec = APP; break;
      case 'index': code = `${s.map}[${sub('W', 0)}]`; prec = ATOM; break;
      case 'infix': {
        const [l, r] = ins, left = s.assoc === 'l';
        code = `${sub(l, left ? s.prec : s.prec + 1)} ${s.op} ${sub(r, left ? s.prec + 1 : s.prec)}`;
        prec = s.prec; break;
      }
      case 'method': code = `${sub('P', ATOM)}.${s.m} ${sub('G', ATOM)}`; prec = APP; break;
      case 'forall': {
        const v = f('VAR');
        code = `∀ₛ ${v}, ${sub('P', 0, [...scope, v])}`; prec = 0; break;
      }
      case 'bound': {
        const v = f('NAME');
        if (!scope.includes(v)) ctx.problems.push(`"${v}" is not bound by an enclosing FOR EACH block`);
        code = v; prec = ATOM; break;
      }
      case 'neg': code = `(- ${sub('D', ATOM)} ·)`; prec = ATOM; break;
      case 'const': code = `(fun _ => ${Math.trunc(Number(f('N')) || 0)})`; prec = ATOM; break;
      default: code = HOLE; prec = ATOM;
    }
    return { code: wrap(b, code), prec };
  }

  /** Lean over a stellar-diver model for block `b`. `env.st` is the storage being read
      (`st.pre`, `st.post`, or a history state), `env.hist` when the theorem is about
      histories (where `pool` is the contract `me` and there is no call). */
  function dlean(specs, b, ctx, env, D) {
    if (!b) { ctx.problems.push('an empty slot'); return HOLE; }
    const s = specs[b.type];
    if (!s) { ctx.problems.push(`unknown block ${b.type}`); return HOLE; }
    const sub = (name, e = env) => dlean(specs, b.inputs?.[name]?.block, ctx, e, D);
    const f = (name) => b.fields?.[name] ?? s.args.find((a) => a.name === name)?.value;
    const store = () => {
      if (env.st) return env.st;
      ctx.problems.push('storage is read outside "before"/"after": put the check inside one');
      return 'st.post';
    };
    const call = (what) => { if (env.hist) ctx.problems.push(`${what} needs a call: use "each call", not "every history"`); return 'st.call'; };
    const at = (st) => (n) => dlean(specs, b.inputs?.[n]?.block, ctx, { ...env, st }, D);
    let code;
    const t = b.type.split('.');
    switch (s.g) {
      case 'atom':
        if (s.cat === 'storage') code = `(${store()} ${s.text})`;
        else if (s.cat === 'who') code = b.type === 'who.caller' ? `${call('the caller')}.caller`
          : s.text === 'pool' ? (env.hist ? 'me' : '(pool st)') : `(${call('an argument')}.argA "${s.text}")`;
        else if (s.cat === 'arg') code = `(${call('an argument')}.arg "${s.text}")`;
        else if (s.cat === 'entry') code = s.text.slice(1, -1);
        else code = s.text;
        break;
      case 'index': {
        const st = store(), w = sub('W'), tok = D.ledgers[s.map];
        code = tok ? `(bal (${st} ${tok}) ${st} ${w})` : `(getOr0 ${st} (${s.map} ${w}))`;
        break;
      }
      case 'derived': code = `(${s.text} ${call('a derived value')})`.replace('st.call)', 'st)'); break;
      case 'num': code = String(Math.trunc(Number(f('N')) || 0)); break;
      case 'infix':
        code = s.cat === 'glue' ? `(${sub(s.args[0].name)} ${s.op === '∧ₛ' ? '∧' : '∨'} ${sub(s.args[1].name)})`
          : `(${sub('L')} ${s.op} ${sub('R')})`;
        break;
      case 'cmp': code = `${sub('L')} ${s.op} ${sub('R')}`; break;
      case 'not': code = `¬ (${sub('P')})`; break;
      case 'state': code = `(${dlean(specs, b.inputs?.P?.block, ctx, { ...env, st: env.hist ? env.st : `st.${s.state}` }, D)})`; break;
      case 'method': code = b.type === 'given' ? `(${sub('G')} → ${sub('P')})` : `(${sub('G')} ∨ ${sub('P')})`; break;
      case 'forall': {
        const v = f('VAR');
        code = `(∀ ${v} : Addr, ${dlean(specs, b.inputs?.P?.block, ctx, { ...env, scope: [...(env.scope || []), v] }, D)})`;
        break;
      }
      case 'bound': {
        const v = f('NAME');
        if (!(env.scope || []).includes(v)) ctx.problems.push(`"${v}" is not bound by an enclosing FOR EACH block`);
        code = v; break;
      }
      case 'neg': code = `(-${sub('D')})`; break;
      case 'const': code = `${Math.trunc(Number(f('N')) || 0)}`; break;
      case 'app': {
        if (env.hist && s.cat === 'change') ctx.problems.push(`"${s.head}" compares before and after a call: use "each call"`);
        const pre = at('st.pre'), post = at('st.post');
        switch (s.head) {
          case 'unchanged': code = `${post('T')} = ${pre('T')}`; break;
          case 'increases': code = `${pre('T')} < ${post('T')}`; break;
          case 'decreases': code = `${post('T')} < ${pre('T')}`; break;
          case 'neverDecreases': code = `${pre('T')} ≤ ${post('T')}`; break;
          case 'changesBy': code = `${post('T')} = ${pre('T')} + ${sub('D')}`; break;
          case 'dropsAtMost': code = `${pre('T')} - ${sub('D')} ≤ ${post('T')}`; break;
          case 'gainsAtLeast': code = `${pre('T')} + ${sub('D')} ≤ ${post('T')}`; break;
          case 'returns': code = `st.ret = ${post('T')}`; break;
          case 'signedBy': code = `${pre('T')} ∈ ${call('signedBy')}.signers`; break;
          case 'calls': code = `${sub('E')} ${env.hist ? (ctx.problems.push('"calls" needs a call'), 'st') : 'st'}`; break;
          case 'isCaller': code = `${sub('A')} = ${call('the caller')}.caller`; break;
          default: ctx.problems.push(`"${s.head}" is not available for this model`); code = HOLE;
        }
        code = `(${code})`;
        break;
      }
      default: ctx.problems.push(`"${b.type}" is not available for this model`); code = HOLE;
    }
    return wrap(b, code);
  }

  /** A theorem block as Lean: `{name, target, tactic, stmt, text, problems}`. */
  function genTheorem(specs, b) {
    const ts = specs[b.type];
    if (ts?.kind === 'diver') {
      const ctx = { problems: [] };
      const name = b.fields?.NAME ?? 'my_question', target = b.fields?.TARGET, tactic = b.fields?.TACTIC;
      if (!/^[A-Za-z_][A-Za-z0-9_']*$/.test(name)) ctx.problems.push('the name is not a Lean identifier');
      let stmt, pred = null;
      if (target === 'history') {
        const s0 = dlean(specs, b.inputs?.Q?.block, ctx, { hist: true, st: 's' }, ts.diver);
        const s1 = dlean(specs, b.inputs?.Q?.block, { problems: [] }, { hist: true, st: 't' }, ts.diver);
        stmt = `∀ (me : Addr) (s t : Storage), Run me s t →\n      ${s0} →\n      ${s1}`;
      } else {
        const q = dlean(specs, b.inputs?.Q?.block, ctx, {}, ts.diver);
        stmt = `∀ st, (∃ e ∈ entries, e st) →\n      ${q}`;
        pred = `fun st => ${q}`;
      }
      const text = `theorem ${name} :\n    ${stmt} := by\n  ${tactic}`;
      return { name, target, tactic, stmt, pred, text, problems: ctx.problems, kind: 'diver' };
    }
    const ctx = { problems: [] };
    const q = lean(specs, b.inputs?.Q?.block, ctx);
    const name = b.fields?.NAME ?? 'my_question', target = b.fields?.TARGET, tactic = b.fields?.TACTIC;
    if (!/^[A-Za-z_][A-Za-z0-9_']*$/.test(name)) ctx.problems.push('the name is not a Lean identifier');
    const stmt = q.code;
    const text = `theorem ${name} :\n    ${target} ⊨ ${stmt} := by\n  ${tactic}`;
    return { name, target, tactic, stmt, text, problems: ctx.problems };
  }

  /** Plain words for block `b`. */
  function words(specs, b, targets, depth = 0) {
    if (!b) return '…';
    const s = specs[b.type];
    if (!s) return '…';
    if (s.g === 'theorem' && s.kind === 'diver') {
      const q = words(specs, b.inputs?.Q?.block, targets, 0);
      return b.fields?.TARGET === 'history'
        ? `Across any history of the contract (its calls and anything else on the ledger), if ${q} at the start, then also at the end.`
        : `After every successful call: ${q}.`;
    }
    if (s.g === 'theorem') {
      const t = (targets.find(([x]) => x === b.fields?.TARGET) || [, b.fields?.TARGET])[1];
      return `After every successful call to ${t}: ${words(specs, b.inputs?.Q?.block, targets, 0)}.`;
    }
    const nested = s.g === 'infix' && s.cat === 'glue' && depth > 0;
    const out = s.say.replace(/\{(\w+)\}/g, (_, n) => {
      const a = s.args.find((x) => x.name === n);
      if (a && a.k !== 'in') return b.fields?.[n] ?? a.value;
      return words(specs, b.inputs?.[n]?.block, targets, depth + (s.cat === 'glue' ? 1 : 0));
    });
    return nested ? `[${out}]` : out;
  }

  /* ----------------------------------------------------------------- Parsing */

  function tokenize(src) {
    const re = /\s+|"[^"]*"|\d+|∀ₛ|∧ₛ|∨ₛ|=>|\.[A-Za-z_]+|[A-Za-z_][A-Za-z0-9_']*|[()\[\],·+\-*]/gy;
    const out = [];
    let m;
    while (re.lastIndex < src.length) {
      const at = re.lastIndex;
      if (!(m = re.exec(src))) throw new Error(`cannot read "${src.slice(at, at + 12)}"`);
      if (!/^\s/.test(m[0])) out.push(m[0]);
    }
    return out;
  }

  /** Read `stmt` (the part after `⊨`) into a block tree, for contract `key`. */
  function parseQuestion(specs, key, stmt) {
    const toks = tokenize(stmt);
    let i = 0;
    const peek = () => toks[i], next = () => toks[i++];
    const expect = (t) => { if (next() !== t) throw new Error(`expected "${t}" near token ${i}`); };
    const byHead = {}, byText = {};
    for (const s of Object.values(specs)) {
      if (s.g === 'app') byHead[s.head] = s;
      if (s.g === 'atom') byText[s.text] = s;
    }
    const node = (s, inputs = {}, fields) => {
      const b = { type: s.type };
      if (fields) b.fields = fields;
      const ins = Object.fromEntries(Object.entries(inputs).map(([k, v]) => [k, { block: v }]));
      if (Object.keys(ins).length) b.inputs = ins;
      return b;
    };
    const infix = { '∧ₛ': ['and', 35, 'r'], '∨ₛ': ['or', 30, 'r'], '+': ['add', 65, 'l'],
                    '-': ['sub', 65, 'l'], '*': ['mul', 70, 'l'] };
    const scope = [];

    function expr(min) {
      let left = app();
      while (infix[peek()] && infix[peek()][1] >= min) {
        const [type, p, assoc] = infix[next()];
        const s = specs[type];
        const right = expr(assoc === 'r' ? p : p + 1);
        const [l, r] = s.args.map((a) => a.name);
        left = node(s, { [l]: left, [r]: right });
      }
      return left;
    }
    function app() {
      const t = peek();
      if (t === '∀ₛ') {
        next();
        const v = next();
        expect(',');
        scope.push(v);
        const body = expr(0);
        scope.pop();
        return node(specs.forall, { P: body }, { VAR: v });
      }
      if (byHead[t]) {
        next();
        const s = byHead[t];
        const ins = {};
        for (const a of s.args.filter((a) => a.k === 'in')) ins[a.name] = atom();
        return postfix(node(s, ins));
      }
      return postfix(atom());
    }
    function postfix(b) {
      while (peek() === '.given' || peek() === '.except') {
        const m = next().slice(1);
        b = node(specs[m], { P: b, G: atom() });
      }
      return b;
    }
    function atom() {
      const t = next();
      if (t === undefined) throw new Error('the question ends too early');
      if (t === '(') {
        if (peek() === '-') {
          next();
          const d = atom();
          expect('·'); expect(')');
          return node(specs.neg, { D: d });
        }
        if (peek() === 'fun') {
          next(); expect('_'); expect('=>');
          const n = next();
          expect(')');
          return node(specs.const, {}, { N: Number(n) });
        }
        const e = expr(0);
        expect(')');
        return e;
      }
      const map = specs[`${key}.map.${t}`];
      if (map && peek() === '[') {
        next();
        const w = expr(0);
        expect(']');
        return node(map, { W: w });
      }
      if (map && peek() === '.total') { next(); return node(specs[`${key}.total.${t}`]); }
      if (byText[t]) return node(byText[t]);
      // A variable; the editor flags it when no ∀ₛ binds it.
      if (scope.includes(t) || /^[a-z][A-Za-z0-9_]*$/.test(t)) return node(specs.user, {}, { NAME: t });
      throw new Error(`"${t}" is not a block of this contract`);
    }
    const q = expr(0);
    if (i < toks.length) throw new Error(`unexpected "${toks[i]}"`);
    return q;
  }

  /** Read `name : target ⊨ question` (with or without `theorem`, `:= by …`). */
  function parseTheorem(specs, key, C, src) {
    let s = src.replace(/--.*$/gm, '').replace(/\/-[\s\S]*?-\//g, '').trim();
    s = s.replace(/^theorem\s+/, '');
    let tactic = C.tactics[0];
    const by = s.match(/:=\s*by\s+(\w+)\s*$/);
    if (by) { if (C.tactics.includes(by[1])) tactic = by[1]; s = s.slice(0, by.index).trim(); }
    let name = 'my_question';
    const nm = s.match(/^([A-Za-z_][A-Za-z0-9_']*)\s*:(?!=)\s*/);
    if (nm) { name = nm[1]; s = s.slice(nm[0].length); }
    let target = C.targets[0][0];
    const turn = s.indexOf('⊨');
    if (turn >= 0) {
      target = s.slice(0, turn).trim();
      if (!C.targets.some(([t]) => t === target)) throw new Error(`"${target}" is not an entry point or contract here`);
      s = s.slice(turn + 1);
    }
    const q = parseQuestion(specs, key, s);
    return { type: `${key}.theorem`, fields: { NAME: name, TARGET: target, TACTIC: tactic }, inputs: { Q: { block: q } } };
  }

  root.LeanBlocks = { CAT, buildSpecs, genTheorem, words, parseTheorem, plain, OPEN, MID, CLOSE, HOLE };
  if (typeof module !== 'undefined') module.exports = root.LeanBlocks;
})(typeof window !== 'undefined' ? window : globalThis);
