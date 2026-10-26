// Soroprove — HackMeridian 2026 pitch deck (short cut).
// Chrome and pitch steps follow hackmeridian-2026-pitch-deck-template.pptx;
// copy is lifted from props.md; blocks are drawn the way the playground's
// Scratch 1.4 skin draws them (notch + tab, top-lit gradient, bevel).
// The full-length version lives in main-long.typ.

// --- template palette -------------------------------------------------------
#let ink    = rgb("#0F0F0F")
#let ink2   = rgb("#2A2A2A")
#let grey   = rgb("#5C5C5C")
#let rule   = rgb("#DFDDD6")
#let cream  = rgb("#F7F6F2")
#let yellow = rgb("#FDDA24")

// --- scratch palette (playground style.css) ---------------------------------
#let s-theorem = rgb("#E1A91A")
#let s-storage = rgb("#EE7D16")
#let s-cond    = rgb("#2CA5E2")
#let s-glue    = rgb("#5CB712")
#let s-who     = rgb("#8A55D7")
#let s-entry   = rgb("#D9372B")
#let s-changes = rgb("#4C6CD5")
#let s-grey    = rgb("#A7A9AC")

#let mono  = "JetBrains Mono"
#let sans  = "Instrument Sans"
#let title-font = "Inter Tight"
#let blockfont = "DejaVu Sans" // Verdana's cousin, as Scratch 1.4 used

#let W = 960pt
#let H = 540pt
#let MX = 48pt

#set page(width: W, height: H, margin: 0pt)
#set text(font: (sans, "DejaVu Sans"), size: 16pt, fill: ink2, lang: "en")
#set par(leading: .55em, spacing: .95em, justify: false)
#set list(marker: text(fill: ink, size: .7em, baseline: -.1em)[►], indent: 2pt, body-indent: 10pt, spacing: .75em)
#show link: it => underline(stroke: 1.5pt + yellow, offset: 3pt, it)
#show strong: set text(fill: ink, weight: 700)

// --- scratch 1.4 rendering --------------------------------------------------
#let sgrad(c) = gradient.linear(c.lighten(24%), c, c.darken(7%), angle: 90deg)

// bevel: dark copy nudged down-right, light copy nudged up-left, body on top
#let bevelled(shape-fn, fill) = {
  place(dx: .9pt, dy: 1.4pt, shape-fn(fill.darken(42%)))
  place(dx: -.5pt, dy: -.8pt, shape-fn(fill.lighten(55%)))
  place(shape-fn(sgrad(fill)))
}

// outline of a stack block: notch on top (or hat dome), tab underneath
#let blk-parts(w, h, kind, tab) = {
  let r = 4pt
  let (n0, n1, n2, n3, nd) = (10pt, 14pt, 26pt, 30pt, 4pt)
  let top = if kind == "hat" {
    (curve.move((0pt, 0pt)), curve.cubic((22pt, -17pt), (64pt, -17pt), (86pt, 0pt)), curve.line((w - r, 0pt)))
  } else {
    (curve.move((0pt, r)), curve.quad((0pt, 0pt), (r, 0pt)),
     curve.line((n0, 0pt)), curve.line((n1, nd)), curve.line((n2, nd)), curve.line((n3, 0pt)),
     curve.line((w - r, 0pt)))
  }
  let bottom = if tab {
    (curve.line((n3, h)), curve.line((n2, h + nd)), curve.line((n1, h + nd)), curve.line((n0, h)))
  } else { () }
  top + (curve.quad((w, 0pt), (w, r)), curve.line((w, h - r)), curve.quad((w, h), (w - r, h))) + bottom + (curve.line((r, h)), curve.quad((0pt, h), (0pt, h - r)), curve.close(mode: "straight"))
}

// a stack block; width: auto hugs the content, a length/ratio stretches it
#let sb(fill, body, kind: "cmd", width: auto, tab: true, size: 11pt) = layout(sz => {
  let w0 = if width == auto { auto } else if type(width) == ratio { sz.width * width } else { width }
  let c = block(width: w0, inset: (left: 10pt, right: 12pt, top: 8pt, bottom: 8pt), {
    set text(font: blockfont, weight: "bold", size: size, fill: white)
    set par(leading: .45em)
    body
  })
  let m = measure(c)
  let parts = blk-parts(m.width, m.height, kind, tab)
  block(width: m.width, height: m.height, above: 0pt, below: 0pt, {
    bevelled(f => curve(fill: f, ..parts), fill)
    place(c)
  })
})

// a script: hat clearance + blocks stacked flush so tabs sit in notches
#let script(..blocks) = pad(top: 13pt, stack(dir: ttb, spacing: 0pt, ..blocks.pos()))

// white text field with the 1.4 inset edge
#let slot(body) = box(
  fill: white,
  radius: 3pt,
  stroke: (top: 1pt + black.transparentize(55%), left: .8pt + black.transparentize(65%)),
  inset: (x: 5pt, y: 0pt),
  outset: (y: 3pt),
  text(font: blockfont, weight: "regular", size: .9em, fill: ink, body),
)

// round reporter, usable inline in prose
#let reporter(fill, body, size: .8em) = box(baseline: 18%, fill: fill.darken(40%), radius: 20pt, inset: (bottom: 1.3pt, right: .8pt),
  box(fill: fill.lighten(50%), radius: 20pt, inset: (top: .8pt, left: .5pt),
    box(fill: sgrad(fill), radius: 20pt, inset: (x: 7pt, y: 3pt),
      text(font: mono, size: size, weight: 700, fill: white, body))))

// boolean reporter
#let hexa(fill, body, size: 15pt) = context {
  let t = text(font: blockfont, size: size, weight: "bold", fill: white, body)
  let m = measure(t)
  let h = m.height + 12pt
  let w = m.width + 32pt
  box(baseline: 28%, width: w, height: h, {
    bevelled(f => polygon(fill: f,
      (0pt, h / 2), (h / 2, 0pt), (w - h / 2, 0pt), (w, h / 2), (w - h / 2, h), (h / 2, h)), fill)
    place(center + horizon, t)
  })
}

// inline code in prose → orange "storage value" reporter
#show raw.where(block: false): it => reporter(s-storage, it.text)
// code blocks → the template's white "Think" card
#show raw.where(block: true): set text(size: 11.5pt)
#show raw.where(block: true): it => block(
  width: 100%, fill: white, stroke: 1.5pt + yellow, radius: 10pt, inset: (x: 16pt, y: 12pt),
  text(font: mono, fill: ink, it),
)

#let shot(path, width: 100%, height: auto) = block(
  radius: 8pt, clip: true, stroke: 1pt + rule,
  image(path, width: width, height: height),
)

// the template's yellow-rimmed "Think" box
#let think(body) = block(width: 100%, fill: white, stroke: 1.8pt + yellow, radius: 12pt, inset: (x: 18pt, y: 13pt),
  text(size: 15pt, fill: ink, body))

// Scratch 1.4 editor pane: brushed tab strip over a dotted grey workspace
#let pane(tabs: ([Scripts], [Costumes], [Sounds]), active: 0, body) = block(width: 100%, radius: 8pt, clip: true, stroke: 1pt + rgb("#8E8F92"), {
  let tab(t, on) = box(
    fill: if on { gradient.linear(white, rgb("#E4E5E7"), angle: 90deg) } else { gradient.linear(rgb("#D5D6D8"), rgb("#BEBFC2"), angle: 90deg) },
    stroke: (top: .8pt + rgb("#8E8F92"), x: .8pt + rgb("#8E8F92")), radius: (top: 5pt), inset: (x: 10pt, y: 4pt),
    text(font: blockfont, weight: "bold", size: 9pt, fill: if on { ink } else { rgb("#6D6E71") }, t))
  block(width: 100%, fill: gradient.linear(rgb("#C9CACC"), rgb("#B3B5B8"), angle: 90deg),
    stroke: (bottom: 1pt + rgb("#8E8F92")), inset: (x: 10pt, top: 5pt, bottom: 0pt), below: 0pt,
    stack(dir: ltr, spacing: 3pt, ..tabs.enumerate().map(((i, t)) => tab(t, i == active))))
  block(width: 100%, inset: (x: 20pt, top: 10pt, bottom: 16pt),
    fill: rgb("#E8E8E8"),
    {
      place(top + left, dx: -20pt, dy: -10pt, rect(width: 200%, height: 200%,
        fill: tiling(size: (16pt, 16pt), place(dx: 7pt, dy: 7pt, circle(radius: .7pt, fill: rgb("#C9CACC"))))))
      body
    })
})

#let flag = box(baseline: 15%, width: 10pt, height: 11pt, {
  rect(width: 1.4pt, height: 11pt, fill: rgb("#3B7A16"))
  place(top + left, dx: 1.4pt, polygon(fill: rgb("#4CBF1B"), (0pt, 0pt), (8pt, 1pt), (7pt, 4pt), (9pt, 7pt), (0pt, 6pt)))
})

// glossy 1.4 button with the green flag (playground's "Check in Lean")
#let gobutton(body) = box(
  fill: gradient.linear(rgb("#FDFDFD"), rgb("#DADBDD"), rgb("#C9CACD"), angle: 90deg),
  stroke: 1pt + rgb("#8E8F92"), radius: 6pt, inset: (x: 12pt, y: 7pt),
  text(font: blockfont, weight: "bold", size: 12pt, fill: ink)[#flag #h(4pt) #body])

// --- template chrome --------------------------------------------------------
#let ghost-m(x, y, s, fill) = {
  let w = 259.2pt * s
  let h = 150.3pt * s
  place(top + left, dx: x, dy: y, polygon(fill: fill,
    (0pt, 0pt), (0pt, h * .3853), (w / 2, h), (w, h * .3853), (w, 0pt), (w / 2, h * .5229)))
  let tw = 75.8pt * s
  let th = 93.75pt * s
  let ty = y + 107.5pt * s
  place(top + left, dx: x, dy: ty, polygon(fill: fill, (0pt, 0pt), (0pt, th), (tw, th * .4853)))
  place(top + left, dx: x + w - tw, dy: ty, polygon(fill: fill, (tw, 0pt), (tw, th), (0pt, th * .4853)))
}

#let arrows(x, y, s, fills) = for (i, f) in fills.enumerate() {
  place(top + left, dx: x + i * s * .95, dy: y, polygon(fill: f, (0pt, 0pt), (0pt, s), (s, s / 2)))
}

#let dots = tiling(size: (18pt, 18pt), place(dx: 8pt, dy: 8pt, circle(radius: .8pt, fill: rule)))

#let platform = context {
  let pad(n) = if n < 10 { "0" + str(n) } else { str(n) }
  [PLATFORM #pad(counter(page).get().first()) / #pad(counter(page).final().first())]
}

#let topbar(next) = {
  place(top, rect(width: 100%, height: 38.4pt, fill: ink))
  set text(font: mono, size: 8pt, weight: 600, tracking: .8pt)
  place(top + left, dx: MX, dy: 14pt, text(fill: yellow, platform))
  place(top + center, dy: 14pt, text(fill: white)[HACKMERIDIAN 2026 · LISBON])
  if next != none { place(top + right, dx: -MX, dy: 14pt, text(fill: white, upper[NEXT ▸ #next])) }
}

#let footer-light = {
  place(top + left, dx: MX, dy: 468pt, line(length: W - 2 * MX, stroke: .8pt + rule))
  place(top + left, dx: MX, dy: 486pt,
    text(font: mono, size: 7pt, fill: grey)[© 2026 HackMeridian · Lisbon #h(6pt) · #h(6pt) \#HackMeridian26])
  place(top + right, dx: -MX, dy: 481pt, image("assets/hm-black.png", height: 20pt))
}

#let footer-dark = {
  place(top + left, dx: MX, dy: 453.6pt, line(length: W - 2 * MX, stroke: .8pt + rgb("#3A3A3A")))
  set text(font: mono, size: 8pt, weight: 600)
  place(top + left, dx: MX, dy: 471pt, text(fill: white)[October 2026])
  place(top + center, dy: 471pt, text(fill: yellow)[\#HackMeridian26])
  place(top + right, dx: -MX, dy: 471pt, text(fill: rgb("#A7A7A7"), weight: 400)[© 2026 HackMeridian · Lisbon])
}

// pitch-step kicker, as a yellow hat block
#let step(n) = script(sb(s-theorem, kind: "hat", tab: false, size: 8.5pt,
  text(font: mono, weight: 700, tracking: 1pt)[PITCH STEP 0#n / 04]))

#let slide(step-n: none, title: none, tsize: 60pt, next: none, ghost: false, body) = page(
  background: {
    rect(width: 100%, height: 100%, fill: cream)
    place(top + left, rect(width: 100%, height: 100%, fill: dots))
    if ghost {
      ghost-m(677pt, 211pt, 1, rule.transparentize(25%))
      arrows(828pt, 393pt, 26pt, (yellow, yellow.transparentize(40%), yellow.transparentize(65%)))
    }
  },
  {
    topbar(next)
    footer-light
    place(top + left, dx: MX, dy: 52pt, block(width: W - 2 * MX, height: 406pt, {
      if step-n != none { step(step-n); v(6pt) }
      if title != none {
        block(below: 14pt, text(font: title-font, size: tsize, weight: 800, fill: ink, tracking: -.5pt, upper(title)))
      }
      body
    }))
  },
)

#let sub(body) = block(below: 12pt, text(size: 18pt, weight: 700, fill: ink, body))

// ============================================================================
// 01 · title
// ============================================================================
#page(fill: ink, {
  ghost-m(653pt, 110pt, 1, yellow.transparentize(78%))
  arrows(814.8pt, 368pt, 32pt, (yellow, yellow.darken(35%), yellow.darken(60%)))
  {
    set text(font: mono, size: 8pt, weight: 600, tracking: .8pt)
    place(top + left, dx: MX, dy: 40pt, text(fill: white)[HACKMERIDIAN 2026 · LISBON])
    place(top + right, dx: -MX, dy: 40pt, text(fill: yellow, platform))
  }
  place(top + left, dx: MX, dy: 70pt, box(
    stroke: 1.2pt + yellow, radius: 13pt, inset: (x: 22pt, y: 7pt),
    text(font: mono, size: 7.5pt, weight: 700, fill: yellow, tracking: 1pt)[PITCH DECK · MADE TO MOVE],
  ))
  place(top + left, dx: MX, dy: 112pt, stack(dir: ltr, spacing: 16pt,
    box(baseline: -4pt, circle(radius: 30pt, fill: yellow, align(center + horizon,
      text(font: (sans, "DejaVu Sans"), size: 34pt, weight: 700, fill: ink)[⊨]))),
    text(font: title-font, size: 80pt, weight: 800, fill: yellow, tracking: -2pt)[SOROPROVE],
  ))
  place(top + left, dx: MX, dy: 222pt, block(width: 560pt,
    text(font: sans, size: 22pt, weight: 500, fill: white)[Friendly Lean proofs for Soroban contracts, without any of the sorrow]))
  place(top + left, dx: MX, dy: 290pt, line(length: 300pt, stroke: .8pt + rgb("#3A3A3A")))
  place(top + left, dx: MX, dy: 300pt, {
    let av(p) = box(baseline: 30%, clip: true, radius: 50%, stroke: 1.2pt + yellow, image(p, width: 26pt, height: 26pt))
    set text(font: sans, size: 13pt, fill: white)
    show strong: set text(fill: white, weight: 700)
    [#av("assets/renato.png") #h(3pt) Renato *Marziano* #h(10pt) #text(fill: yellow)[&] #h(10pt) #av("assets/julian.jpg") #h(3pt) Julian *Konchunas*]
  })
  place(top + left, dx: MX, dy: 362pt, image("assets/hm-white.png", height: 38pt))
  place(top + left, dx: 290pt, dy: 357pt, rect(width: .8pt, height: 48pt, fill: rgb("#5C5C5C")))
  place(top + left, dx: 310pt, dy: 368pt, image("assets/guava.png", height: 26pt))
  place(top + left, dx: 436pt, dy: 364pt, image("assets/stellar.png", height: 33pt))
  footer-dark
})

// ============================================================================
// Step 01 · the solution
// ============================================================================
#slide(step-n: 1, title: [The solution], next: [PMF])[
  #grid(columns: (1fr, 370pt), column-gutter: 26pt,
    [
      #sub[Soroprove turns WASM contracts into Lean object representations]
      - abstracting away every contract code path leading to value transfers into a state machine
      - modelling part of the Soroban runtime in Lean
      - a higher level UI, automatically generated from stellar contract builds
      - a lower level Rust macro integration, which allows for custom invariant proofs
      #v(6pt)
      #think[We love #link("https://scratch.mit.edu/")[Scratch]. *Everybody loves Scratch.*]
    ],
    pad(top: 4pt, shot("assets/interface.png")),
  )
]

#slide(step-n: 1, title: [Invariants in blocks], tsize: 44pt, next: [PMF])[
  #sub[Drop a WASM, start laying out desirable invariants and see if they hold.]
  #pane[
    #grid(columns: (auto, 1fr), column-gutter: 18pt, align: horizon,
      shot("assets/sos-crop.png", width: auto, height: 104pt),
      shot("assets/amm.png"),
    )
  ]
  #v(10pt)
  #think[
    #grid(columns: (1fr, auto), column-gutter: 18pt, align: horizon,
      [Suppose that we wanna prove the reserve solvency of an AMM: pretty simple to express in Soroprove, and checked automatically in a very fast manner.],
      link("https://soroprove.marziano.top/#c=lpDiver&w=W3sidHlwZSI6ImxwRGl2ZXIudGhlb3JlbSIsImZpZWxkcyI6eyJOQU1FIjoicmVzZXJ2ZXNfc3RheV9iYWNrZWQiLCJUQVJHRVQiOiJoaXN0b3J5IiwiVEFDVElDIjoidmliZSJ9LCJpbnB1dHMiOnsiUSI6eyJibG9jayI6eyJ0eXBlIjoiYW5kIiwiaW5wdXRzIjp7IlAiOnsiYmxvY2siOnsidHlwZSI6ImNtcC5hbmUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuVG9rZW5BIn19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJscERpdmVyLnZhci5Ub2tlbkIifX19fX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImFuZCIsImlucHV0cyI6eyJQIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUEifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VBIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUIifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VCIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19fX19fX19fX1d")[#gobutton[permalink here]],
    )
  ]
]

// ============================================================================
// Step 02 · PMF
// ============================================================================
#slide(step-n: 2, title: [PMF], next: [Technical workflow], ghost: true)[
  #block(width: 600pt)[
    #sub[Formal verification is hard, yet it's ever more crucial to constraint complex financial codebases, which are now largerly written by AI.]
    - Back in August, the Comet protocol was hacked: `execute_swap_exact_amount_in` accepts swaps from the same token onto the same token, leading to broken accounting.
    - Some proofs can be quite complex and not obvious, and this is usually the boundary where SMT provers stop.
    - Transpiling the entire contract to Lean requires devs to be very skilled in Lean.
    #v(8pt)
    #think[We're interested about *fully securing a protocol*, and not finding particular bugs.]
  ]
]

// ============================================================================
// Step 03 · technical workflow
// ============================================================================
#slide(step-n: 3, title: [Technical workflow], tsize: 48pt, next: [The team])[
  #grid(columns: (1fr, 400pt), column-gutter: 30pt,
    [
      #sub[Soroprove operates directly on the contract's compiled WASM]
      Only a few syscalls that we care about recreating and tracing through:
      #v(6pt)
      #set text(size: 12.5pt)
      #let row(c, ..names) = box(inset: (y: 3pt), names.pos().map(n => reporter(c, n, size: 9.5pt)).join(h(4pt)))
      #row(s-entry, "call", "try_call") #h(4pt) value transfers \
      #row(s-who, "require_auth", "require_auth_for_args") #h(4pt) permission gates \
      #row(s-entry.darken(15%), "update_current_contract_wasm") #h(4pt) upgrades \
      #row(s-storage, "put_contract_data", "get_contract_data") \
      #row(s-storage, "has_contract_data", "del_contract_data") #h(4pt) side effects
    ],
    script(
      sb(s-theorem, kind: "hat", width: 100%)[drop a #slot[WASM]],
      sb(s-glue, width: 100%)[map (lift) WASM to #slot[LLVM IR]],
      sb(s-storage, width: 100%)[backtrace from any kind of #slot[token transfer]],
      sb(s-who, width: 100%)[abstract it into a #slot[state machine]],
      sb(s-changes, width: 100%)[model the #slot[Soroban VM] in Lean],
      sb(s-cond, width: 100%)[prove the #slot[invariant]],
      sb(s-entry, width: 100%, tab: false)[#slot[proved] #slot[counterexampled] #slot[undecided]],
    ),
  )
]

#slide(step-n: 3, title: [Sound but not complete], tsize: 44pt, next: [The team])[
  #grid(columns: (1fr, 300pt), column-gutter: 28pt,
    [
      #sub[We aim for a final model that is #hexa(s-glue, size: 13pt)[sound] but not #hexa(s-entry, size: 13pt)[complete]]
      - everything that we prove on the model will necessarly also hold in the contract
      - disproving something doesn't necessarly mean that we found a bug in our contract
      #v(8pt)
      #think[Essentially, we derive an *over-approximation* of our contract that we can easily reason and prove properties on.]
    ],
    [
      #text(size: 14pt)[We can easily match SEP-41 signatures, for example `transfer`:]
      #v(2pt)
      #show raw.where(block: true): set text(size: 10pt)
      ```rust
      call(token_addr,
           Symbol("transfer"),
           Vec[ from  : AddressObject,
                to    : AddressObject,
                amount: I128Small || I128Object])
      ```
    ],
  )
]

#slide(step-n: 3, title: [Proofs by vibe], tsize: 48pt, next: [The team])[
  #grid(columns: (1fr, 250pt), column-gutter: 30pt,
    [
      #sub[We just lock an LLM in a sandbox and bother it until we either find a proof, or we run out of time]
      #script(
        sb(s-theorem, kind: "hat", width: 100%, size: 11.5pt)[agent edits the #slot[proof body], runs #slot[./check]],
        sb(s-changes, width: 100%, size: 11.5pt)[each version is checked by the #slot[server], not by the agent],
        sb(s-entry, width: 100%, size: 11.5pt)[reject #slot[sorry] #slot[native_decide] #slot[new axioms] #slot[\#eval]],
        sb(s-glue, width: 100%, size: 11.5pt, tab: false)[#slot[proved] #slot[counterexampled] #slot[undecided]],
      )
    ],
    align(right, block(radius: 8pt, clip: true, stroke: 1pt + rule, image("assets/reason.png", height: 330pt))),
  )
]

#slide(step-n: 3, title: [A final example], tsize: 44pt, next: [The team])[
  #grid(columns: (1fr, 300pt), column-gutter: 26pt,
    [
      #sub[Can we find the counterexample that led to the Comet hack by trying to prove book–balance consistency?]
      #shot("assets/comet.png")
      #v(10pt)
      #think[No constraint in the system prevents us from setting `token_in = token_out`, which is exactly what happens in the counterexample.]
    ],
    align(right, block(radius: 8pt, clip: true, stroke: 1pt + rule, image("assets/cex.png", height: 320pt))),
  )
]

// ============================================================================
// Step 04 · the team (scratch sprites + scripts)
// ============================================================================
#let sprite(path, name) = stack(dir: ttb, spacing: 6pt,
  box(fill: white, radius: 8pt, inset: 4pt,
    stroke: 2.5pt + s-cond,
    box(clip: true, radius: 5pt, image(path, width: 92pt, height: 92pt))),
  align(center, box(fill: s-cond, radius: 4pt, inset: (x: 8pt, y: 3pt),
    text(font: blockfont, weight: "bold", size: 9pt, fill: white, name))),
)

#let bubble(body) = box({
  box(fill: white, stroke: 1.6pt + rgb("#A7A9AC"), radius: 14pt, inset: (x: 14pt, y: 10pt),
    text(font: blockfont, weight: "bold", size: 12pt, fill: ink, body))
  place(top + left, dx: 26pt, dy: -10.5pt, polygon(fill: white, stroke: 1.6pt + rgb("#A7A9AC"), (0pt, 12pt), (16pt, 12pt), (2pt, 0pt)))
  place(top + left, dx: 27.5pt, dy: -.5pt, rect(width: 13pt, height: 2.5pt, fill: white))
})


#slide(step-n: 4, title: [The team], tsize: 52pt, next: none)[
  #pane[
    #grid(columns: (auto, auto, 1fr, auto, auto), column-gutter: 14pt, align: top,
      pad(top: 8pt, sprite("assets/renato.png", [Renato])),
      script(
        sb(s-theorem, kind: "hat", size: 12pt)[when #flag clicked],
        sb(s-who, size: 12pt)[say #slot[Renato Marziano]],
        sb(s-changes, size: 12pt)[Security Researcher & Auditor @ #slot[OtterSec]],
        sb(s-glue, size: 12pt, tab: false)[CTF player · reverse engineering],
      ),
      [],
      pad(top: 8pt, sprite("assets/julian.jpg", [Julian])),
      script(
        sb(s-theorem, kind: "hat", size: 12pt)[when #flag clicked],
        sb(s-who, size: 12pt)[say #slot[Julian Konchunas]],
        sb(s-changes, size: 12pt)[Security Auditor @ #slot[OtterSec]],
        sb(s-glue, size: 12pt, tab: false)[hacker],
      ),
    )
    #v(18pt)
    #pad(left: 12pt, bubble[We're experienced auditors and hackers, the right people to make formal verification friendly.])
  ]
]
