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
    const roles = new Map();
    const role = (a, r) => roles.set(a, [...(roles.get(a) || []), r]);
    role(c.caller, 'caller');
    for (const [n, a] of c.fixed) role(a, n);
    if (c.to !== c.caller && (C.who.includes('recipient'))) role(c.to, 'recipient');
    const addr = (a) => `<span class="addr">#${a}${roles.has(a) ? ` <small>${esc(roles.get(a).join(', '))}</small>` : ''}</span>`;
    const val = (v) => v === null ? '<span class="unset">unset</span>'
      : v.startsWith('@') ? addr(Number(v.slice(1))) : `<b>${esc(Number(v).toLocaleString('en-US'))}</b>`;
    const iface = (k) => {
      const s = C.storage?.[k];
      if (s) return `<small>${esc(s[1])} · ${esc(s[0])}</small>`;
      const v = C.vars.find(([n]) => n === k);
      return `<small>${v ? (v[1] === 'Int' ? 'number' : 'address') : 'map'}</small>`;
    };
    const words = (k) => (C.vars.find(([n]) => n === k)?.[2] || C.maps.find(([n]) => n === k)?.[1] || '');
    const rows = [];
    for (const [k, b, a] of c.vars)
      rows.push({ key: `<b>${esc(k)}</b>`, k, b, a });
    for (const [m, who, b, a] of c.maps)
      if (b !== null || a !== null) rows.push({ key: `<b>${esc(m)}</b>[${addr(who)}]`, k: m, b, a });
    const table = rows.map((r) => `<tr class="${r.b === r.a ? '' : 'chg'}"><td>${r.key}<br>${iface(r.k)}</td>
      <td>${val(r.b)}</td><td class="arrow">${r.b === r.a ? '=' : '→'}</td><td>${val(r.a)}</td></tr>`).join('');
    const args = c.args.map(([n, v]) => `<span class="arg">${esc(n)} = <b>${esc(Number(v).toLocaleString('en-US'))}</b></span>`).join(', ');
    const tip = rows.map((r) => `${r.k}: ${words(r.k)}`).filter((s) => !s.endsWith(': ')).join('\n');
    return `<div class="cex">
      <div class="cex-title">Counterexample: a call the contract accepts, after which the claim is false</div>
      <div class="cex-call"><span class="fn">${esc(c.fn || '(call)')}</span>(${args})
        <span class="by">${c.signers ? `called by ${addr(c.caller)}, signed by ${c.signers.map((a) => addr(Number(a))).join(', ') || 'nobody'}` : `signed by ${addr(c.caller)}`}</span>${c.ret !== null ? ` <span class="by">returns ${val(c.ret)}</span>` : ''}</div>
      ${c.holders.length ? `<div class="cex-holders">sums (<code>.total</code>) run over the holders list: ${c.holders.map((a) => addr(Number(a))).join(', ')}</div>` : ''}
      <table class="cex-store" title="${esc(tip)}"><thead><tr><th>storage</th><th>before</th><th></th><th>after</th></tr></thead>
        <tbody>${table || '<tr><td colspan="4" class="unset">no storage set</td></tr>'}</tbody></table>
      <div class="cex-claim">Claim: <i>${esc(job.reading || job.stmt)}</i></div>
    </div>`;
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
