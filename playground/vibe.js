/* Proof by vibe, in the editor: start a job for a theorem whose proof is "vibe",
   follow its events (server-sent), and show the live proof, Lean's verdict on each
   version, the time left, and the counterexample when there is one. */
(function (root) {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const jobs = [];          // newest first
  let app = null;           // { ws, contractKey(), C(), showTab, store }

  const token = () => app.store.get('pg.vibeToken', '');
  const STATUS = {
    running: ['…', 'Searching'], proved: ['✓', 'Proved'], refuted: ['✗', 'Counterexample found'],
    undecided: ['?', 'Undecided'], failed: ['!', 'Could not start'],
  };

  async function start(t) {
    const budget = Math.max(10, Math.min(1800, Number(document.querySelector('#budget').value) || 120));
    const body = { contract: app.contractKey(), theorem: { name: t.name, target: t.target, stmt: t.plainStmt, pred: t.plainPred },
                   reading: t.reading, budget };
    for (const old of jobs.filter((j) => j.blockId === t.block.id && j.status === 'running')) stop(old);
    const job = { blockId: t.block.id, name: t.name, reading: t.reading, stmt: t.kind === 'diver' ? t.plainStmt : `${t.target} ⊨ ${t.plainStmt}`,
                  contract: app.contractKey(), C: app.C(), budget, start: Date.now(), status: 'running',
                  proof: '', check: null, checking: false, checks: 0, log: [], cex: null, versions: 0 };
    jobs.unshift(job);
    render();
    let res, out;
    for (let attempt = 0; attempt < 2; attempt++) {
      res = await fetch('/vibe', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Vibe-Token': token() },
                                   body: JSON.stringify(body) });
      out = await res.json().catch(() => ({}));
      if (res.status !== 403) break;
      const tk = prompt('This server runs vibe proofs only with its token (VIBE_TOKEN). Token:');
      if (!tk) break;
      app.store.set('pg.vibeToken', tk);
    }
    if (!res.ok) { job.status = 'failed'; job.log.push({ text: out.error || res.statusText }); render(); return; }
    job.id = out.id;
    const es = new EventSource(`/vibe/${out.id}/events?token=${encodeURIComponent(token())}`);
    job.es = es;
    es.onmessage = (m) => { apply(job, JSON.parse(m.data)); render(); };
    es.onerror = () => { if (job.status !== 'running') es.close(); };
  }

  function stop(job) {
    if (job.id) fetch(`/vibe/${job.id}/stop`, { method: 'POST', headers: { 'X-Vibe-Token': token() } });
  }

  function apply(job, ev) {
    switch (ev.type) {
      case 'proof': job.proof = ev.text; job.versions++; break;
      case 'checking': job.checking = true; break;
      case 'check': job.checking = false; job.check = ev; job.checks++; if (ev.cex) job.cex = ev.cex; break;
      case 'log': job.log.push(ev); break;
      case 'done':
        job.status = ev.status; job.elapsed = ev.elapsed; job.checking = false;
        if (ev.proof != null) job.proof = ev.proof;
        if (ev.result?.cex) job.cex = ev.result.cex;
        job.es?.close();
        mark(job);
        break;
    }
  }

  /** The theorem block shows the outcome, like a Lean check does. */
  function mark(job) {
    const b = app.ws.getBlockById(job.blockId);
    if (!b) return;
    const [icon, label] = STATUS[job.status];
    const text = job.status === 'proved' ? null
      : `${icon} vibe: ${label}${job.status === 'refuted' ? ' (see the Vibe tab)' : job.status === 'undecided' ? ` after ${job.elapsed}s` : ''}`;
    b.setWarningText(text);
  }

  /* ----------------------------------------------------------------- Views */

  function timeLeft(job) {
    const used = job.status === 'running' ? (Date.now() - job.start) / 1000 : job.elapsed ?? 0;
    return { used, frac: Math.min(1, used / job.budget) };
  }

  function proofView(job) {
    const errs = new Map();
    for (const m of job.check?.messages || [])
      if (m.line > 0) errs.set(m.line, [...(errs.get(m.line) || []), m.text]);
    const lines = (job.proof || '').replace(/\n$/, '').split('\n');
    const rows = lines.map((l, i) => {
      const e = errs.get(i + 1);
      return `<span class="ln${e ? ' err' : ''}"${e ? ` title="${esc(e.join('\n\n'))}"` : ''}><i>${i + 1}</i>${esc(l) || ' '}</span>`;
    }).join('');
    return `<pre class="vproof">${rows || '<span class="cm">(the agent has not written a proof yet)</span>'}</pre>`;
  }

  function checkView(job) {
    if (job.checking) return `<div class="vcheck busy">Lean is checking version ${job.versions}…</div>`;
    const c = job.check;
    if (!c) return `<div class="vcheck">Waiting for the first version.</div>`;
    const general = c.messages.filter((m) => m.line === 0 && m.severity === 'error');
    const errs = c.messages.filter((m) => m.severity === 'error');
    const head = {
      proved: '✓ Lean accepts the proof of the exact statement (standard axioms only)',
      refuted: '✗ Lean accepts the refutation: the statement is false',
      incomplete: '◇ Compiles, but there is no complete proof or refutation yet',
      error: `! ${errs.length} error${errs.length === 1 ? '' : 's'} in version ${job.versions}`,
    }[c.verdict];
    return `<div class="vcheck v-${c.verdict}">${esc(head)} <small>(${c.elapsed}s)</small>${
      general.length ? `<pre>${esc(general.map((m) => m.text).join('\n\n'))}</pre>` : ''}${
      errs.length && !general.length ? `<small class="hint">hover the red lines for Lean's messages</small>` : ''}</div>`;
  }

  /** A counterexample as the contract sees it: the call, and storage before and after,
      labelled with the storage interface recovered from the wasm. */
  function cexView(job) {
    const c = job.cex, C = job.C;
    if (!c) return '';
    // a stellar-diver model: only the called entry point's own arguments.
    const own = C.diver?.entryArgs?.[c.fn];
    const fixed = own ? c.fixed.filter(([n]) => n === 'pool' || own.addrs.includes(n)) : c.fixed;
    const shown = own ? c.args.filter(([n]) => own.amounts.includes(n)) : c.args;
    const roles = new Map();
    const role = (a, r) => roles.set(a, [...(roles.get(a) || []), r]);
    role(c.caller, 'caller');
    for (const [n, a] of fixed) role(a, n);
    if (c.to !== c.caller && (C.who.includes('recipient'))) role(c.to, 'recipient');
    const rows = [];
    for (const [k, b, a] of c.vars)
      rows.push({ k, b, a });
    // a ledger read through a token argument: one row per (token, holder), however many
    // arguments name that token.
    const argTok = (m) => { const x = C.diver?.argLedgers?.[m]; return x === undefined ? null : c.fixed.find(([n]) => n === x)?.[1]; };
    const seen = new Map();
    for (const [m, who, b, a] of c.maps) {
      if (b === null && a === null) continue;
      const tok = argTok(m);
      if (tok !== null && tok !== undefined) {
        const id = `${tok}/${who}`;
        if (seen.has(id)) { seen.get(id).names.push(m); continue; }
        const r = { names: [m], who, k: m, b, a };
        seen.set(id, r); rows.push(r);
        continue;
      }
      rows.push({ k: m, who, b, a });
    }
    // a stellar-diver model names dozens of keys: keep the rows that change, and the exact
    // (key, address) pairs the claim reads: `KEY (argA "x")`, `KEY (pool st)`, `bal (argA "t") s w`.
    let hidden = 0;
    if (C.kind === 'diver') {
      const stmt = job.stmt || '';
      const at = (w) => w === 'pool st' ? fixed.find(([n]) => n === 'pool')?.[1]
        : fixed.find(([n]) => n === w.match(/argA "(\w+)"/)?.[1])?.[1];
      const pairs = new Set();
      for (const m of stmt.matchAll(/\(([A-Za-z_][\w.]*) \((st\.call\.argA "\w+"|pool st)\)\)/g)) pairs.add(`${m[1]}/${at(m[2])}`);
      for (const m of stmt.matchAll(/bal \(st\.call\.argA "(\w+)"\) \S+ \((st\.call\.argA "\w+"|pool st)\)/g)) {
        for (const [b, x] of Object.entries(C.diver.argLedgers || {})) if (x === m[1]) pairs.add(`${b}/${at(m[2])}`);
      }
      const vars = new Set([...stmt.matchAll(/\(st\.(?:pre|post) ([A-Za-z_]\w*)\)/g)].map((m) => m[1]));
      const reads = (r) => r.who === undefined ? vars.has(r.k) : (r.names || [r.k]).some((m) => pairs.has(`${m}/${r.who}`));
      const keep = rows.filter((r) => r.b !== r.a || reads(r));
      hidden = rows.length - keep.length;
      rows.splice(0, rows.length, ...keep);
    }
    // Scratch-style: a stack of blocks, one per fact of the call.
    const pill = (t, cls = '') => `<span class="sp ${cls}">${t}</span>`;
    const num = (v) => v === null ? pill('unset', 'num unset') : v.startsWith('@') ? who(Number(v.slice(1))) : pill(esc(Number(v).toLocaleString('en-US')), 'num');
    const who = (a) => pill(`#${a}${roles.has(a) ? ` ${esc(roles.get(a).join(', '))}` : ''}`, 'addr');
    const label = (r) => r.who === undefined ? pill(esc(r.k), 'key')
      : `${pill(esc((r.names || [r.k]).join(' = ')), 'key')} of ${who(r.who)}`;
    const blocks = [];
    blocks.push(`<div class="sb hat">when ${pill(esc(c.fn || 'a call'), 'fn')} is called</div>`);
    if (shown.length) blocks.push(`<div class="sb args">with ${shown.map(([n, v]) => `${esc(n)} ${num(v)}`).join(' ')}</div>`);
    const signers = c.signers ? [...new Set(c.signers.map(Number))] : [c.caller];
    blocks.push(`<div class="sb who">called by ${who(c.caller)} · signed by ${signers.map(who).join(' ') || 'nobody'}</div>`);
    for (const [a, rs] of [...roles.entries()].filter(([, rs]) => rs.length > 1))
      blocks.push(`<div class="sb op">${rs.map((r) => pill(esc(r), 'addr')).join(' = ')} <small>both #${a}</small></div>`);
    if (c.holders.length) blocks.push(`<div class="sb who">sums run over ${c.holders.map((a) => who(Number(a))).join(' ')}</div>`);
    for (const r of rows)
      blocks.push(r.b === r.a
        ? `<div class="sb store same">${label(r)} stays ${num(r.b)}</div>`
        : `<div class="sb store">change ${label(r)} from ${num(r.b)} to ${num(r.a)}</div>`);
    if (!rows.length) blocks.push(`<div class="sb store same">no storage set</div>`);
    if (hidden) blocks.push(`<div class="sb note">${hidden} other entries unchanged</div>`);
    blocks.push(`<div class="sb cap" title="${esc(job.reading || job.stmt)}">the claim is false</div>`);
    return `<div class="cex"><div class="stack">${blocks.join('')}</div></div>`;
  }

  function card(job) {
    const [icon, label] = STATUS[job.status];
    const { used, frac } = timeLeft(job);
    const logs = job.log.slice(-60).map((l) => `<div class="${l.tool ? 'tool' : ''}"><i>${l.t ?? ''}s</i> ${esc(l.text)}</div>`).join('');
    return `<article class="vjob st-${job.status}" data-job="${esc(job.id || '')}" data-t="${esc(job.blockId)}">
      <header><b>${icon} ${esc(job.name)}</b><span class="pill">${label}</span>
        ${job.status === 'running' ? `<button class="stop">Stop</button>` : ''}</header>
      <div class="budget" title="time used of the budget"><div style="width:${(frac * 100).toFixed(1)}%"></div>
        <span>${used.toFixed(0)}s / ${job.budget}s · ${job.versions} version${job.versions === 1 ? '' : 's'} checked</span></div>
      <code class="vstmt">${esc(job.stmt)}</code>
      ${checkView(job)}
      ${job.cex ? cexView(job) : ''}
      ${proofView(job)}
      <details class="vlog"${job.logOpen ? ' open' : ''}><summary>agent (${job.log.length})</summary><div>${logs}</div></details>
    </article>`;
  }

  function render() {
    const el = document.querySelector('#vibe');
    if (!jobs.length) return;
    const scroll = el.parentElement.scrollTop;
    el.innerHTML = jobs.map(card).join('');
    el.parentElement.scrollTop = scroll;
    el.querySelectorAll('.vlog').forEach((d, i) => d.addEventListener('toggle', () => { jobs[i].logOpen = d.open; }));
    el.querySelectorAll('.stop').forEach((b) => b.addEventListener('click', (e) => {
      e.stopPropagation();
      const job = jobs.find((j) => j.id === b.closest('.vjob').dataset.job);
      if (job) stop(job);
    }));
  }

  // The clock moves even when no event arrives.
  setInterval(() => {
    if (!jobs.some((j) => j.status === 'running')) return;
    document.querySelectorAll('.vjob').forEach((el, i) => {
      const job = jobs[i];
      if (job?.status !== 'running') return;
      const { used, frac } = timeLeft(job);
      el.querySelector('.budget div').style.width = `${(frac * 100).toFixed(1)}%`;
      el.querySelector('.budget span').textContent =
        `${used.toFixed(0)}s / ${job.budget}s · ${job.versions} version${job.versions === 1 ? '' : 's'} checked`;
    });
  }, 500);

  root.Vibe = { init(a) { app = a; }, start, render };
})(window);
