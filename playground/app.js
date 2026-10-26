/* The editor: Blockly with Scratch's look, the vocabulary of `vocab.js`, and
   the printing/parsing of `lean.js`. */
(() => {
  const V = window.VOCAB, L = window.LeanBlocks;
  const $ = (s) => document.querySelector(s);
  const store = {
    get(k, d) { try { const v = localStorage.getItem(k); return v === null ? d : JSON.parse(v); } catch { return d; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* storage unavailable */ } },
  };

  let contract = store.get('pg.contract', 'amm');
  if (!V.contracts[contract]) contract = 'amm';
  let mode = store.get('pg.mode', 'lean');
  const SPECS = Object.fromEntries(Object.entries(V.contracts).map(([k, C]) => [k, L.buildSpecs(k, C)]));
  const specs = () => SPECS[contract];
  const C = () => V.contracts[contract];

  /* ------------------------------------------------------------ Look & feel */

  const HEX = new Set(['Q', 'I']), SQUARE = new Set(['W', 'A', 'D', 'E']);
  class Constants extends Blockly.zelos.ConstantProvider {
    // Scratch 1.4 proportions: tight corners, a small notch, compact rows.
    constructor() {
      super();
      this.CORNER_RADIUS = 3;
      this.NOTCH_WIDTH = 5 * this.GRID_UNIT;
      this.NOTCH_HEIGHT = this.GRID_UNIT;
      this.STATEMENT_BOTTOM_SPACER = -this.NOTCH_HEIGHT;
      this.MIN_BLOCK_HEIGHT = 9 * this.GRID_UNIT;
      this.TOP_ROW_MIN_HEIGHT = this.BOTTOM_ROW_MIN_HEIGHT = this.CORNER_RADIUS;
      this.SELECTED_GLOW_COLOUR = '#FFFFFF';
      this.SELECTED_GLOW_SIZE = 1.5;
    }
    // Empty slots take the shape of the blocks that fit them.
    shapeFor(conn) {
      if (conn.type === Blockly.ConnectionType.INPUT_VALUE) {
        const check = conn.getCheck() || [];
        if (check.some((c) => HEX.has(c))) return this.HEXAGONAL;
        if (check.every((c) => SQUARE.has(c)) && check.length) return this.SQUARED;
        return this.ROUNDED;
      }
      return super.shapeFor(conn);
    }
  }
  class Renderer extends Blockly.zelos.Renderer {
    makeConstants_() { return new Constants(); }
  }
  Blockly.blockRendering.register('scratchy', Renderer);

  class Category extends Blockly.ToolboxCategory {
    addColourBorder_(colour) { this.rowDiv_.style.setProperty('--cat', colour); }
  }
  Blockly.registry.register(Blockly.registry.Type.TOOLBOX_ITEM, Blockly.ToolboxCategory.registrationName, Category, true);

  const theme = Blockly.Theme.defineTheme('scratchy', {
    base: Blockly.Themes.Classic,
    fontStyle: { family: '"Lucida Grande", Verdana, Geneva, sans-serif', weight: 'bold', size: 10 },
    componentStyles: {
      workspaceBackgroundColour: '#E8E8E8', toolboxBackgroundColour: '#C9CACC', toolboxForegroundColour: '#333',
      flyoutBackgroundColour: '#D9DADC', flyoutForegroundColour: '#333', flyoutOpacity: 1,
      scrollbarColour: '#9A9B9E', scrollbarOpacity: 0.8, insertionMarkerColour: '#000', insertionMarkerOpacity: 0.3,
    },
  });

  /* ---------------------------------------------------------------- Blocks */

  const SHAPE = { Q: 1, I: 1, TI: 2, TA: 2, W: 3, A: 3, D: 3, E: 3 };

  function blockJson(s) {
    const args = s.args.map((a) => {
      if (a.k === 'in') return { type: 'input_value', name: a.name, check: a.check };
      if (a.k === 'text') return { type: 'field_input', name: a.name, text: a.value, spellcheck: false };
      if (a.k === 'row') return { type: 'input_end_row', name: a.name };
      if (a.k === 'num') return { type: 'field_number', name: a.name, value: a.value, precision: 1 };
      return { type: 'field_dropdown', name: a.name, options: a.options };
    });
    const j = { type: s.type, message0: mode === 'words' ? s.words : s.lean, args0: args, inputsInline: true,
      colour: L.CAT[s.cat].colour, tooltip: s.tip };
    if (s.out) { j.output = s.out; j.outputShape = SHAPE[s.out]; }
    return j;
  }

  for (const S of Object.values(SPECS))
    for (const s of Object.values(S))
      Blockly.Blocks[s.type] = {
        init() {
          this.jsonInit(blockJson(s));
          if (s.g === 'theorem') {
            this.hat = 'cap';
            this.getField('NAME').setValidator((v) => v.replace(/\s/g, '_'));
          }
        },
      };

  /* --------------------------------------------------------------- Toolbox */

  function preset(s) {
    const b = { kind: 'block', type: s.type };
    const C0 = C();
    // Fill slots with a typical first choice, the way Scratch's palette does.
    if (s.g === 'index' && C0.who.length) b.inputs = { W: { block: { type: `who.${C0.who[0]}` } } };
    if (s.type === 'calls' && C0.entries.length) b.inputs = { E: { block: { type: `${contract}.entry.${C0.entries[0]}` } } };
    if (s.type === 'isCaller' || s.type === 'isRecipient' || s.type.includes('.pred.'))
      b.inputs = { A: { block: { type: 'user' } } };
    return b;
  }

  function toolbox() {
    const S = specs();
    const cats = Object.entries(L.CAT).map(([k, c]) => ({
      kind: 'category', name: c.name, colour: c.colour,
      contents: Object.values(S).filter((s) => s.cat === k).map(preset),
    })).filter((c) => c.contents.length);
    const examples = [];
    for (const ex of C().examples) {
      try { examples.push({ kind: 'block', ...L.parseTheorem(S, contract, C(), ex) }); }
      catch (e) { console.warn('example', ex, e); }
    }
    cats.push({ kind: 'category', name: 'Examples', colour: '#D65CA8', contents: examples });
    return { kind: 'categoryToolbox', contents: cats };
  }

  /* ------------------------------------------------------------- Workspace */

  const ws = Blockly.inject('blockly', {
    renderer: 'scratchy', theme, toolbox: toolbox(), trashcan: true, sounds: false,
    grid: { spacing: 20, length: 1, colour: '#D2D2D2', snap: false },
    zoom: { controls: true, wheel: true, startScale: 0.85, maxScale: 2, minScale: 0.3, scaleSpeed: 1.15 },
    move: { scrollbars: true, drag: true, wheel: false },
  });

  const key = () => `pg.ws.${contract}.v1`;
  function save() { store.set(key(), Blockly.serialization.workspaces.save(ws)); }

  function starter() {
    const S = specs(), C0 = C();
    if (!C0.examples.length)
      return { blocks: { languageVersion: 0, blocks: [{ type: `${contract}.theorem`, x: 40, y: 40, fields: { NAME: 'my_question' } }] } };
    const b = L.parseTheorem(S, contract, C0, C0.examples[0]);
    return { blocks: { languageVersion: 0, blocks: [{ ...b, x: 40, y: 40 }] } };
  }

  let loading = false;
  function load(state) {
    loading = true;
    ws.clear();
    try { Blockly.serialization.workspaces.load(state || starter(), ws); }
    catch (e) { console.warn('could not restore workspace', e); Blockly.serialization.workspaces.load(starter(), ws); }
    loading = false;
    refresh();
    // Show the top-left corner of the blocks.
    if (ws.getTopBlocks(false).length) {
      const box = ws.getBlocksBoundingBox(), s = ws.scale;
      ws.scroll(24 - box.left * s, 24 - box.top * s);
    }
  }

  /* ------------------------------------------------------------ Code panel */

  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

  /** Marked Lean text → HTML with one span per block. */
  function markup(text) {
    let html = '';
    for (const part of text.split(/([^]*||)/)) {
      if (!part) continue;
      if (part[0] === L.OPEN) html += `<span class="b" data-b="${esc(part.slice(1, -1))}">`;
      else if (part === L.CLOSE) html += '</span>';
      else if (part === L.HOLE) html += '<span class="hole" title="empty slot">?</span>';
      else html += esc(part).replace(/(∧ₛ|∨ₛ|∀ₛ|⊨|\.given|\.except)|\b(theorem|by)\b|("[a-z_]+")/g,
        (m, op, kw) => `<i class="${op ? 'op' : kw ? 'kw' : 'str'}">${m}</i>`);
    }
    return html;
  }

  let current = [];   // theorems on the workspace, top to bottom
  function theorems() {
    const state = Blockly.serialization.workspaces.save(ws);
    const tops = (state.blocks?.blocks || []).filter((b) => specs()[b.type]?.g === 'theorem');
    tops.sort((a, b) => (a.y ?? 0) - (b.y ?? 0));
    return tops.map((b) => ({ block: b, ...L.genTheorem(specs(), b), reading: L.words(specs(), b, C().targets) }));
  }

  function refresh() {
    current = theorems();
    const C0 = C();
    const names = new Map();
    for (const t of current) names.set(t.name, (names.get(t.name) || 0) + 1);
    for (const t of current) if (names.get(t.name) > 1) t.problems.push(`another theorem is also called ${t.name}`);

    const head = [...C0.header, ''].map(esc).join('\n');
    const body = current.map((t) => {
      const warn = t.problems.length ? `<span class="cm">-- ⚠ ${esc([...new Set(t.problems)].join('; '))}</span>\n` : '';
      return `<div class="thm" data-t="${esc(t.block.id)}">${warn}<span class="cm">/-- ${esc(t.reading)} -/</span>\n${markup(t.text)}</div>`;
    }).join('\n');
    $('#code').innerHTML = `<span class="cm">${head}</span>\n${body || '<span class="cm">-- Drag a "theorem" block from the Theorem category.</span>'}\n\n<span class="cm">${esc(C0.footer.join('\n'))}</span>`;

    $('#reading').innerHTML = current.length
      ? current.map((t) => `<li data-t="${esc(t.block.id)}"><b>${esc(t.name)}</b><span>${esc(t.reading)}</span>${
          t.problems.length ? `<em>Incomplete: ${esc([...new Set(t.problems)].join('; '))}</em>` : ''}</li>`).join('')
      : '<li class="empty">No theorems yet.</li>';

    for (const b of ws.getAllBlocks(false)) {
      if (specs()[b.type]?.g === 'bound') {
        const name = b.getFieldValue('NAME');
        let p = b.getParent(), ok = false;
        for (; p; p = p.getParent()) if (p.type === 'forall' && p.getFieldValue('VAR') === name) { ok = true; break; }
        b.setWarningText(ok || !b.getRootBlock() || specs()[b.getRootBlock().type]?.g !== 'theorem' ? null
          : `"${name}" is not bound: put this inside a "FOR EACH ${name}" block.`);
      }
    }
    markSelected();
  }

  function markSelected() {
    const sel = Blockly.getSelected();
    document.querySelectorAll('#code .b.sel').forEach((e) => e.classList.remove('sel'));
    if (sel) document.querySelectorAll(`#code .b[data-b="${CSS.escape(sel.id)}"]`).forEach((e) => e.classList.add('sel'));
  }

  ws.addChangeListener((e) => {
    if (e.type === Blockly.Events.SELECTED) return markSelected();
    if (loading || e.isUiEvent) return;
    refresh();
    save();
  });

  // Hover code → glow the block; click code → select it.
  $('#code').addEventListener('mouseover', (e) => {
    const sp = e.target.closest('.b');
    ws.highlightBlock(sp ? sp.dataset.b : null);
  });
  $('#code').addEventListener('mouseleave', () => ws.highlightBlock(null));
  $('#code').addEventListener('click', (e) => {
    const sp = e.target.closest('.b') || e.target.closest('.thm');
    const id = sp && (sp.dataset.b || sp.dataset.t);
    const b = id && ws.getBlockById(id);
    if (b) { b.select(); ws.centerOnBlock(b.id); }
  });
  for (const sel of ['#reading', '#results', '#vibe'])
    $(sel).addEventListener('click', (e) => {
      const li = e.target.closest('[data-t]');
      const b = li && ws.getBlockById(li.dataset.t);
      if (b) { b.select(); ws.centerOnBlock(b.id); }
    });

  /* ------------------------------------------------------------- Controls */

  const sel = $('#contract');
  for (const [k, c] of Object.entries(V.contracts)) sel.add(new Option(c.title, k));
  sel.value = contract;
  sel.addEventListener('change', () => {
    save();
    contract = sel.value;
    store.set('pg.contract', contract);
    ws.updateToolbox(toolbox());
    $('#source').textContent = C().source;
    clearResults();
    load(store.get(key(), null));
  });
  $('#source').textContent = C().source;

  function setMode(m) {
    mode = m;
    store.set('pg.mode', m);
    document.querySelectorAll('#mode button').forEach((b) => b.classList.toggle('on', b.dataset.mode === m));
    const state = Blockly.serialization.workspaces.save(ws);
    ws.updateToolbox(toolbox());
    load(state);
  }
  document.querySelectorAll('#mode button').forEach((b) => b.addEventListener('click', () => setMode(b.dataset.mode)));
  document.querySelectorAll('#mode button').forEach((b) => b.classList.toggle('on', b.dataset.mode === mode));

  document.querySelectorAll('.tabs button').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));
  function showTab(t) {
    document.querySelectorAll('.tabs button').forEach((b) => b.classList.toggle('on', b.dataset.tab === t));
    document.querySelectorAll('.pane').forEach((p) => p.hidden = p.id !== `pane-${t}`);
  }

  const plainFile = () => [...C().header, '', ...current.map((t) => `/-- ${t.reading} -/\n${L.plain(t.text)}\n`), C().footer.join('\n'), ''].join('\n');
  $('#copy').addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(plainFile()); flash('#copy', 'Copied'); }
    catch { flash('#copy', 'Copy failed'); }
  });
  $('#download').addEventListener('click', () => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([plainFile()], { type: 'text/plain' }));
    a.download = 'Playground.lean';
    a.click();
    URL.revokeObjectURL(a.href);
  });
  function flash(s, text) {
    const b = $(s), old = b.textContent;
    b.textContent = text;
    setTimeout(() => (b.textContent = old), 1200);
  }

  $('#new').addEventListener('click', () => {
    const b = ws.newBlock(`${contract}.theorem`);
    b.setFieldValue(`my_question_${current.length + 1}`, 'NAME');
    b.initSvg(); b.render();
    placeBelow(b);
    b.select();
  });

  /** Move a new top block below all the others and scroll to it. */
  function placeBelow(b) {
    const others = ws.getTopBlocks(false).filter((o) => o !== b);
    const y = others.length ? Math.max(...others.map((o) => o.getBoundingRectangle().bottom)) + 40 : 40;
    const x = others.length ? Math.min(...others.map((o) => o.getBoundingRectangle().left)) : 40;
    const at = b.getRelativeToSurfaceXY();
    b.moveBy(x - at.x, y - at.y);
    ws.scrollBoundsIntoView(b.getBoundingRectangle());
  }
  $('#tidy').addEventListener('click', () => ws.cleanUp());

  // Import Lean
  const dlg = $('#import');
  $('#open-import').addEventListener('click', () => { $('#import-error').textContent = ''; dlg.showModal(); $('#import-text').focus(); });
  $('#import-cancel').addEventListener('click', () => dlg.close());
  $('#import-ok').addEventListener('click', () => {
    const src = $('#import-text').value;
    // One theorem per `theorem` keyword, or one per non-empty line when there is none.
    const chunks = /\btheorem\b/.test(src) ? src.split(/(?=\btheorem\b)/).filter((s) => s.trim())
      : src.split('\n').filter((s) => s.trim());
    const made = [], errs = [];
    for (const ch of chunks) {
      try { made.push(L.parseTheorem(specs(), contract, C(), ch)); }
      catch (e) { errs.push(`${ch.trim().slice(0, 60)}…: ${e.message}`); }
    }
    if (errs.length) { $('#import-error').textContent = errs.join('\n'); return; }
    for (const b of made) placeBelow(Blockly.serialization.blocks.append(b, ws));
    dlg.close();
  });

  /* ---------------------------------------------------------------- Checks */

  let leanAvailable = false;
  fetch('/health').then((r) => r.json()).then((h) => {
    leanAvailable = !!h.lean;
    if (!h.vibe?.available) $('#budget-box').title = 'claude was not found by the server: vibe proofs are unavailable';
    $('#check').disabled = !leanAvailable;
    if (!leanAvailable) $('#check').title = 'lake was not found by the server';
  }).catch(() => {
    $('#check').disabled = true;
    $('#check').title = 'Start playground/server.py to check theorems with Lean';
  });

  function clearResults() {
    $('#results').innerHTML = '<li class="empty">Press “Check in Lean” to run the proofs.</li>';
    for (const b of ws.getAllBlocks(false)) if (specs()[b.type]?.g === 'theorem') b.setWarningText(null);
  }

  const STATUS = { proved: ['✓', 'Proved'], typed: ['◇', 'Well-typed, not proved (sorry)'],
                   unproved: ['✗', 'Not proved'], error: ['!', 'Lean error'], incomplete: ['…', 'Incomplete'] };

  $('#check').addEventListener('click', async () => {
    const complete = current.filter((t) => !t.problems.length);
    // Theorems proved "by vibe" go to the agent; the Vibe tab follows them live.
    const vibes = complete.filter((t) => t.tactic === 'vibe');
    const ready = complete.filter((t) => t.tactic !== 'vibe');
    for (const t of vibes) Vibe.start({ ...t, plainStmt: L.plain(t.stmt), plainPred: t.pred && L.plain(t.pred) });
    const rows = current.filter((t) => t.problems.length).map((t) => ({ t, r: { status: 'incomplete', messages: [...new Set(t.problems)] } }));
    if (vibes.length && !ready.length && !rows.length) { showTab('vibe'); return; }
    showTab('results');
    if (!ready.length) { render(rows); return; }
    const btn = $('#check');
    btn.disabled = true; btn.classList.add('busy'); btn.textContent = 'Checking…';
    $('#results').innerHTML = `<li class="empty">Lean is checking ${ready.length} theorem${ready.length > 1 ? 's' : ''}…</li>`;
    try {
      const res = await fetch('/check', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contract, theorems: ready.map((t) => ({ name: t.name, target: t.target, tactic: t.tactic, stmt: L.plain(t.stmt) })) }),
      });
      const out = await res.json();
      if (!res.ok) throw new Error(out.error || res.statusText);
      ready.forEach((t, i) => rows.push({ t, r: out.results[i] }));
      render(rows, out);
    } catch (e) {
      $('#results').innerHTML = `<li class="st-error"><b>! Check failed</b><pre>${esc(String(e.message || e))}</pre></li>`;
    } finally {
      btn.disabled = !leanAvailable; btn.classList.remove('busy'); btn.textContent = 'Check in Lean';
    }
  });

  function render(rows, out) {
    rows.sort((a, b) => current.indexOf(a.t) - current.indexOf(b.t));
    let html = rows.map(({ t, r }) => {
      const [icon, label] = STATUS[r.status];
      return `<li class="st-${r.status}" data-t="${esc(t.block.id)}"><b>${icon} ${esc(t.name)}</b><small>${label}</small>${
        r.messages.length ? `<pre>${esc(r.messages.join('\n\n'))}</pre>` : ''}</li>`;
    }).join('');
    if (out?.general?.length) html += `<li class="st-error"><b>! Errors outside the theorems</b><pre>${esc(out.general.join('\n\n'))}</pre></li>`;
    if (out) html += `<li class="empty">Checked in ${out.elapsed}s.</li>`;
    $('#results').innerHTML = html;
    for (const { t, r } of rows) {
      const b = ws.getBlockById(t.block.id);
      if (b) b.setWarningText(r.status === 'proved' || r.status === 'typed' ? null : `${STATUS[r.status][1]}\n\n${r.messages.join('\n\n')}`.slice(0, 1200));
    }
  }

  /* ------------------------------------------------------------ Permalinks
     `#c=<contract>&t=<theorems>`: the theorems as their Lean text (base64url),
     which `parseTheorem` turns back into blocks. */

  const b64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const unb64 = (s) => new TextDecoder().decode(Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0)));

  function permalink() {
    const tops = (Blockly.serialization.workspaces.save(ws).blocks?.blocks || []).map(({ x, y, ...b }) => b);
    return `${location.origin}${location.pathname}#${new URLSearchParams({ c: contract, w: b64(JSON.stringify(tops)) })}`;
  }

  /** Open the theorems of a permalink; the workspace they replace is kept as a backup. */
  function openPermalink() {
    const h = new URLSearchParams(location.hash.slice(1));
    if (!h.get('c') || !(h.get('t') || h.get('w')) || !V.contracts[h.get('c')]) return false;
    let lines = [], tops = null;
    try {
      if (h.get('w')) tops = JSON.parse(unb64(h.get('w')));
      else lines = unb64(h.get('t')).split('\n').filter((l) => l.trim());
    } catch { return false; }
    if (contract !== h.get('c')) {
      contract = h.get('c'); sel.value = contract; store.set('pg.contract', contract);
      ws.updateToolbox(toolbox()); $('#source').textContent = C().source;
    }
    const prev = store.get(key(), null);
    if (prev) store.set(`${key()}.backup`, prev);
    const blocks = tops ? tops.map((b, i) => ({ ...b, x: 40, y: 40 + 200 * i })) : [];
    lines.forEach((l, i) => {
      try { blocks.push({ ...L.parseTheorem(specs(), contract, C(), l), x: 40, y: 40 + 170 * i }); }
      catch (e) { console.warn('permalink', l, e); }
    });
    load({ blocks: { languageVersion: 0, blocks } });
    return true;
  }

  $('#share').addEventListener('click', async () => {
    const url = permalink();
    history.replaceState(null, '', url);
    try { await navigator.clipboard.writeText(url); flash('#share', 'Link copied'); }
    catch { flash('#share', 'Link in the address bar'); }
  });
  window.addEventListener('hashchange', () => { if (openPermalink()) clearResults(); });

  Vibe.init({ ws, contractKey: () => contract, C, showTab, store });
  clearResults();
  if (!openPermalink()) load(store.get(key(), null));
  showTab('code');
  window.addEventListener('resize', () => Blockly.svgResize(ws));
  window.pg = { ws, refresh };   // for debugging
})();
