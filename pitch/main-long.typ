// Soroprove — HackMeridian 2026 pitch deck.
// Chrome follows hackmeridian-2026-pitch-deck-template.pptx (dark/cream,
// #FDDA24, Inter Tight / Instrument Sans / JetBrains Mono, ghost "M").
// Text is props.md verbatim; Scratch block styling comes from the
// stellar-lean-playground UI.

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

#let W = 960pt
#let H = 540pt
#let MX = 48pt

#set page(width: W, height: H, margin: 0pt)
#set text(font: (sans, "DejaVu Sans"), size: 16pt, fill: ink2, lang: "en")
#set par(leading: .55em, spacing: .95em, justify: false)
#set list(marker: text(fill: ink, size: .7em, baseline: -.1em)[►], indent: 2pt, body-indent: 10pt, spacing: .8em)
#show link: it => underline(stroke: 1.5pt + yellow, offset: 3pt, it)
#show strong: set text(fill: ink, weight: 700)

// inline code → scratch "storage value" reporter pill
#show raw.where(block: false): it => box(
  fill: s-storage,
  inset: (x: 6pt, y: 0pt),
  outset: (y: 3.5pt),
  radius: 8pt,
  stroke: .8pt + s-storage.darken(18%),
  text(font: mono, size: .82em, fill: white, weight: 600, it),
)
// code blocks → the template's white "Think" card
#show raw.where(block: true): set text(size: 10.5pt)
#show raw.where(block: true): it => block(
  width: 100%,
  fill: white,
  stroke: 1.5pt + yellow,
  radius: 10pt,
  inset: (x: 16pt, y: 12pt),
  text(font: mono, fill: ink, it),
)

// --- scratch pieces ---------------------------------------------------------
// hat block (section kicker), replaces the template's "PITCH STEP" pill
#let hat(body, fill: s-theorem) = box(inset: (top: 10pt), {
  place(top + left, dx: 0pt, dy: -10pt, ellipse(width: 74pt, height: 24pt, fill: fill))
  box(
    fill: fill,
    radius: (top-right: 5pt, bottom: 5pt),
    inset: (x: 11pt, y: 6pt),
    text(font: mono, size: 8.5pt, weight: 700, fill: white, tracking: 1pt, upper(body)),
  )
})

// command block with its top tab
#let cmd(fill, body, width: 100%) = block(width: width, above: 12pt, below: 0pt, {
  place(top + left, dx: 16pt, dy: -4pt, rect(width: 18pt, height: 5pt, fill: fill, radius: (top: 2pt)))
  block(
    width: if width == auto { auto } else { 100% },
    fill: fill,
    radius: 5pt,
    stroke: 1pt + fill.darken(15%),
    inset: (x: 11pt, y: 8pt),
    body,
  )
})

// white input slot inside a block
#let slot(body) = box(
  fill: white,
  radius: 9pt,
  inset: (x: 7pt, y: 0pt),
  outset: (y: 3pt),
  text(font: mono, size: 10.5pt, weight: 600, fill: ink, body),
)

// syscall block: coloured strip with slots, text beside it
#let syscall(fill, names, body) = cmd(fill, {
  set text(fill: white, size: 13.5pt)
  grid(columns: (auto, 1fr), column-gutter: 12pt, align: horizon,
    box(names),
    text(weight: 500, body),
  )
})

// boolean (hexagon) reporter
#let hexa(fill, body) = context {
  let t = text(font: sans, size: 15pt, weight: 700, fill: white, body)
  let m = measure(t)
  let h = m.height + 10pt
  let w = m.width + 30pt
  box(baseline: 26%, {
    polygon(fill: fill, stroke: 1pt + fill.darken(15%),
      (0pt, h / 2), (h / 2, 0pt), (w - h / 2, 0pt), (w, h / 2), (w - h / 2, h), (h / 2, h))
    place(center + horizon, t)
  })
}

// empty scratch slot for content the md leaves as a placeholder
#let placeholder(body, height: 120pt) = block(
  width: 100%,
  height: height,
  radius: 14pt,
  fill: white.transparentize(30%),
  stroke: (paint: s-grey, thickness: 1.5pt, dash: "dashed"),
  align(center + horizon, text(font: mono, size: 11pt, fill: grey, ligatures: false, features: (calt: 0), body)),
)

#let shot(path, width: 100%) = block(
  width: width,
  radius: 8pt,
  clip: true,
  stroke: 1pt + rule,
  image(path, width: 100%),
)

// --- template chrome --------------------------------------------------------
#let ghost-m(x, y, s, fill) = {
  // the template's "M" mark, in its original EMU-derived proportions
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

#let counter-label = context {
  let n = counter(page).get().first()
  let t = counter(page).final().first()
  [PLATFORM #str(n).clusters().len() #h(0pt)]
}
#let platform = context {
  let pad(n) = if n < 10 { "0" + str(n) } else { str(n) }
  [PLATFORM #pad(counter(page).get().first()) / #pad(counter(page).final().first())]
}

#let topbar(next) = {
  place(top, rect(width: 100%, height: 38.4pt, fill: ink))
  set text(font: mono, size: 8pt, weight: 600, tracking: .8pt)
  place(top + left, dx: MX, dy: 14pt, text(fill: yellow, platform))
  place(top + center, dy: 14pt, text(fill: white)[HACKMERIDIAN 2026 · LISBON])
  if next != none {
    place(top + right, dx: -MX, dy: 14pt, text(fill: white, upper[NEXT ▸ #next]))
  }
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

// light content slide
#let slide(kicker: none, title: none, tsize: 46pt, next: none, ghost: false, body) = page(
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
    place(top + left, dx: MX, dy: 62pt, block(width: W - 2 * MX, height: 396pt, {
      if kicker != none { hat(kicker); v(4pt) }
      if title != none {
        block(below: 16pt, text(font: title-font, size: tsize, weight: 800, fill: ink, tracking: -.5pt, upper(title)))
      }
      body
    }))
  },
)

// dark section slide, the title slide's language
#let section(kicker: none, title: none, tsize: 56pt, next: none, body) = page(
  fill: ink,
  {
    ghost-m(653pt, 110pt, 1, yellow.transparentize(78%))
    arrows(782pt, 357.6pt, 38.4pt, (yellow, yellow.darken(35%), yellow.darken(60%)))
    set text(font: mono, size: 8pt, weight: 600, tracking: .8pt)
    place(top + left, dx: MX, dy: 40pt, text(fill: white)[HACKMERIDIAN 2026 · LISBON])
    place(top + right, dx: -MX, dy: 40pt, text(fill: yellow, platform))
    if next != none {
      place(top + right, dx: -MX, dy: 54pt, text(fill: rgb("#A7A7A7"), upper[NEXT ▸ #next]))
    }
    footer-dark
    place(top + left, dx: MX, dy: 84pt, block(width: 570pt, {
      set text(font: sans, size: 15pt, weight: 400, tracking: 0pt, fill: rgb("#DFDDD6"))
      show strong: set text(fill: white)
      if kicker != none { hat(kicker); v(8pt) }
      if title != none {
        block(below: 18pt, text(font: title-font, size: tsize, weight: 800, fill: yellow, tracking: -1pt, upper(title)))
      }
      body
    }))
  },
)

#let lead(body) = block(below: 14pt, text(size: 18pt, weight: 700, fill: ink, body))

// ============================================================================
// 01 · title
// ============================================================================
#page(fill: ink, {
  ghost-m(653pt, 110pt, 1, yellow.transparentize(78%))
  arrows(652.8pt + 162pt, 368pt, 32pt, (yellow, yellow.darken(35%), yellow.darken(60%)))
  {
    set text(font: mono, size: 8pt, weight: 600, tracking: .8pt)
    place(top + left, dx: MX, dy: 40pt, text(fill: white)[HACKMERIDIAN 2026 · LISBON])
    place(top + right, dx: -MX, dy: 40pt, text(fill: yellow, platform))
  }
  // kicker pill, outlined like the template
  place(top + left, dx: MX, dy: 70pt, box(
    stroke: 1.2pt + yellow, radius: 13pt, inset: (x: 22pt, y: 7pt),
    text(font: mono, size: 7.5pt, weight: 700, fill: yellow, tracking: 1pt)[PITCH DECK · MADE TO MOVE],
  ))
  // project mark + name
  place(top + left, dx: MX, dy: 112pt, stack(dir: ltr, spacing: 16pt,
    box(baseline: -4pt, circle(radius: 30pt, fill: yellow, align(center + horizon,
      text(font: (sans, "DejaVu Sans"), size: 34pt, weight: 700, fill: ink)[⊨]))),
    text(font: title-font, size: 80pt, weight: 800, fill: yellow, tracking: -2pt)[SOROPROVE],
  ))
  place(top + left, dx: MX, dy: 222pt, block(width: 560pt,
    text(font: sans, size: 22pt, weight: 500, fill: white)[Friendly Lean proofs for Soroban contracts, without any of the sorrow]))
  // author row (as in the June deck): hairline, names, affiliation
  place(top + left, dx: MX, dy: 290pt, line(length: 300pt, stroke: .8pt + rgb("#3A3A3A")))
  place(top + left, dx: MX, dy: 302pt, {
    set text(font: sans, size: 13pt, fill: white)
    show strong: set text(fill: white, weight: 700)
    [Renato *Marziano* #h(8pt) #text(fill: yellow)[&] #h(8pt) *Julian*]
    linebreak()
    text(size: 10.5pt, fill: rgb("#A7A7A7"))[OtterSec]
  })
  // sponsor strip
  place(top + left, dx: MX, dy: 362pt, image("assets/hm-white.png", height: 38pt))
  place(top + left, dx: 290pt, dy: 357pt, rect(width: .8pt, height: 48pt, fill: rgb("#5C5C5C")))
  place(top + left, dx: 310pt, dy: 368pt, image("assets/guava.png", height: 26pt))
  place(top + left, dx: 436pt, dy: 364pt, image("assets/stellar.png", height: 33pt))
  footer-dark
})

// ============================================================================
// Goal
// ============================================================================
#slide(kicker: [Goal], title: [Goal], next: [Technical implementation], ghost: true)[
  #block(width: 610pt)[
    #lead[Formal verification is hard, yet it's ever more crucial to constraint complex financial codebases, which are now largerly written by AI.]

    - Soroprove turns WASM contracts into Lean object representations, while also offering sane macros for developers to prove common properties about their contracts.
    - This is achieved by abstracting away every contract code path leading to value transfers into a state machine, and by modelling part of the Soroban runtime in Lean.
  ]
]

#slide(kicker: [Goal], next: [Technical implementation])[
  #grid(columns: (250pt, 1fr), column-gutter: 22pt,
    pad(top: 10pt, text(size: 17pt, weight: 600, fill: ink)[This is all offered both with a higher level UI, automatically generated from stellar contract builds, as well as through a lower level Rust macro integration, which allows for custom invariant proofs.]),
    shot("assets/interface.png"),
  )
]

// ============================================================================
// Technical implementation
// ============================================================================
#section(kicker: [Technical implementation], title: [Technical\ implementation], tsize: 54pt, next: [Runtime modelling])[
  Soroprove operates directly on the contract's compiled WASM: a big part of the codebase is dedicated to lifting and abstracting this code into something that is wieldy for a prover to handle in a reasonable amount of CPU time.

  The rest of the backend consists as a light, but accurate abstraction of the Soroban VM into Lean. The technical brief here is split up in covering these two components, starting from the latter.
]

#slide(kicker: [Technical implementation], title: [Runtime modelling], tsize: 38pt, next: [Code abstraction])[
  #text(size: 14pt)[In general, given our scope, which is preventing losses of funds, there are only a few syscalls that we care about recreating and tracing through:]
  #v(6pt)
  #syscall(s-entry, [#slot[call] or #slot[try\_call] :])[this is obviously needed to trace value transfers, as we consider value transfers operations on SEP-41 contracts, which we're gonna trace abstractly. We ignore other kinds of cross contract calls and assume a Top value to avoid balooning complexity.]
  #syscall(s-who, [#slot[require\_auth] / #slot[require\_auth\_for\_args] ,])[as we need this to understand permission gates, which can be a source of very critical bugs]
  #syscall(s-who.lighten(12%), [#slot[verify\_sig\_ed25519, recover\_key\_ecdsa\_secp256k1, verify\_sig\_ecdsa\_secp256r1, verify\_sig\_ml\_dsa\_\*] :])[similar auth, derived from external signatures these time]
]

#slide(kicker: [Technical implementation], title: [Runtime modelling], tsize: 38pt, next: [Code abstraction])[
  #syscall(s-who.darken(10%), [#slot[authorize\_as\_curr\_contract] :])[any nested auth given to a foreign contract essentially gives it full control of funds]
  #syscall(s-entry.darken(12%), [#slot[update\_current\_contract\_wasm], #slot[update\_current\_contract\_executable\_ref] :])[any contract upgrade should be a highly priviledged function that results in a total loss of funds if mishandled]
  #cmd(s-storage, {
    set text(fill: white, size: 13.5pt, weight: 500)
    [any storage operation: #slot[put\_contract\_data] , #slot[get\_contract\_data] , #slot[has\_contract\_data] , #slot[del\_contract\_data] , which we need in order to track side effects]
  })
  #v(14pt)
  #text(size: 14pt, weight: 700, fill: ink)[And some peripheral ones:]
  #syscall(s-grey, [#slot[get\_current\_contract\_address]:])[the best way to abstract address is into the contract itself, priviledged users (which are checked against a value set) and unpriviledged users]
  #syscall(s-grey, [#slot[fail\_with\_error] :])[one the ways the FSM should terminate]
  #cmd(s-grey, width: auto, slot[obj\_cmp])
]

// ============================================================================
// Code abstraction
// ============================================================================
#slide(kicker: [Technical implementation], title: [Code abstraction], tsize: 38pt, next: [Abstractions])[
  #lead[After we model the runtime, we need to understand what we can realistically keep and abstract out of the contract's logic. all formal verification requires some level of abstraction if we wanna avoid running into a never ending execution loop.]
  #placeholder(height: 200pt)[\[image from the abstract analysis paper with the multiplications becoming + and -\]]
]

#slide(kicker: [Technical implementation], title: [Code abstraction], tsize: 38pt, next: [Abstractions], ghost: true)[
  #block(width: 580pt)[
    #cmd(s-glue, width: auto, text(fill: white, weight: 700, size: 13pt)[#slot[WASM] #h(6pt) → #h(6pt) #slot[LLVM IR]])
    #v(14pt)
    We start off with some WASM. WASM is not fun to work with, so to make our lives #strike(stroke: 1.5pt + s-entry)[easier] more painful we wrote code to map (lift) WASM to LLVM IR, which has a lot of semantic analysis tooling to work with.

    #text(fill: grey)[We will glance over the details as they're not too revelant to the final problem and could be abstracted into a separate library]

    #lead[It's more interesting to focus on the sematic operations that we run on the LLVM IR]
  ]
]

#slide(kicker: [Code abstraction], title: [Abstractions], tsize: 38pt, next: [tokens and roles])[
  At one point we considered transpiling the entire contract to Lean, but then we realized that's currently a bit too computationally complex, and it also requires devs to be very skilled in Lean to make use of that properly

  #v(4pt)
  #block(width: 100%, fill: white, stroke: 1.5pt + yellow, radius: 10pt, inset: (x: 18pt, y: 14pt))[
    #text(size: 17pt, weight: 600, fill: ink)[This means that we will aim for a final model that is #hexa(s-glue)[sound] but not #hexa(s-entry)[complete] :]
    #v(2pt)
    everything that we prove on the model will necessarly also hold in the contract, but disproving something doesn't necessarly mean that we found a bug in our contract. This is a necessary tradeoff that we need to make, and in this case we're interested about fully securing a protocol, and not finding particular bugs.
  ]
  #v(4pt)
  #lead[Essentially, we derive an over-approximation of our contract that we can easily reason and prove properties on.]
]

#slide(kicker: [Code abstraction], title: [Abstractions], tsize: 38pt, next: [tokens and roles])[
  So we decided to abstract away the kind of information that can prevent loss of fund and bricking bugs by backtracing from any kind of token transfer

  We can easily trace this, even in the WASM, because both symbols, and, less intuitively, `Value` types are preserved, since the lower byte of every value is its enum tag

  #show raw.where(block: true): set text(size: 12.5pt)
  ```
              MSB                                                         LSB
               63      55      47      39      31      23      15       7       0
              ┌───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐
   Val(u64) = │ byte7 │ byte6 │ byte5 │ byte4 │ byte3 │ byte2 │ byte1 │ byte0 │
              └───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘
              └───────────────── body / payload ──────────────────────┘└──┬──┘
                          56 bits: value , handle , packed symbol         │

                                                                     byte 0 = TAG
                                                                     tag = val & 0xFF
  ```
]

#slide(kicker: [Code abstraction], title: [Abstractions], tsize: 38pt, next: [tokens and roles])[
  #grid(columns: (1fr, 1fr), column-gutter: 26pt,
    [
      Thus we can easily match SEP-41 signatures, for example `transfer` :
      #v(4pt)
      #show raw.where(block: true): set text(size: 12.5pt)
      ```rust
      call(token_addr,
           Symbol("transfer"),
           Vec[ from  : AddressObject,
                to    : AddressObject,
                amount: I128Small || I128Object])
      ```
    ],
    [
      Other kinds of calls are ignored, and thanks to the no reentrancy assurance provided by the Soroban runtime, we can at the very least be sure that the storage state of the analyzed contract won't have changed after the external call, while treating its `Value` result as unknown (`Top`)

      #v(10pt)
      #lead[In the end, we can extract something like this for each value moving operation:]
    ],
  )
]

#slide(kicker: [Code abstraction], title: [tokens and roles], tsize: 38pt, next: [Lean prover])[
  #lead[Key operations like moving funds and assigning roles require further abstractions for performance and ease of proofs down the line]
  #hat(fill: s-storage)[token]
  #v(2pt)
  Token balance transitions are accounted in ad hoc mapping
  #v(4pt)
  #placeholder(height: 150pt)[\=\=\=#linebreak()Insert mapping#linebreak()\=\=\=]
]

// ============================================================================
// Lean prover
// ============================================================================
#section(kicker: [Lean prover], title: [Lean prover], next: [User experience])[
  #text(size: 20pt)[Since Lean is an prove assistant and not an automatic theorem prover]
]

// ============================================================================
// User experience
// ============================================================================
#slide(kicker: [User experience], title: [User experience], next: [More complex proofs], ghost: true)[
  #block(width: 580pt)[
    #text(size: 26pt, weight: 700, fill: ink)[We love #link("https://scratch.mit.edu/")[Scratch]. Everybody loves Scratch.]
    #v(10pt)
    In an attempt to mask formal verification with a friendly interface, we made it so that invariants can be expressed in blocks, in alternative to the manual writing of the invariant in Lean, which is still possible in the side tab.

    The intended user experience there is just to drop a WASM, have the metadata be extracted (there is a lot of it), the model generated in the backend, in order for the user to be instantly able to start laying out desirable invariants and see if they hold.
  ]
]

#slide(kicker: [User experience], next: [More complex proofs])[
  #grid(columns: (1fr, 380pt), column-gutter: 26pt, align: horizon,
    [
      #lead[One could imagine a developer trying to verify that the AMM invariant on his contract is always decreasing. It would look as simple as this example:]
      This kind of proof can be handled well by the `answer` strategy that we implemented, where we utilized a bit of LEAN 4 metaprogramming trickery, to remove the need to select the tactic, which narrows the spectrum of provable properties, but allows for a friendlier interface in most cases.
    ],
    shot("assets/sos.png"),
  )
]

#slide(kicker: [User experience], next: [More complex proofs])[
  #v(14pt)
  #lead[Suppose that we wanna prove the reserve solvency of an AMM. This is pretty simple to express in Soroprove, and can be checked automatically in a very fast manner.]
  #v(14pt)
  #shot("assets/amm.png")
  #v(18pt)
  You can play around with the proof using the #link("https://soroprove.marziano.top/#c=lpDiver&w=W3sidHlwZSI6ImxwRGl2ZXIudGhlb3JlbSIsImZpZWxkcyI6eyJOQU1FIjoicmVzZXJ2ZXNfc3RheV9iYWNrZWQiLCJUQVJHRVQiOiJoaXN0b3J5IiwiVEFDVElDIjoidmliZSJ9LCJpbnB1dHMiOnsiUSI6eyJibG9jayI6eyJ0eXBlIjoiYW5kIiwiaW5wdXRzIjp7IlAiOnsiYmxvY2siOnsidHlwZSI6ImNtcC5hbmUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuVG9rZW5BIn19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJscERpdmVyLnZhci5Ub2tlbkIifX19fX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImFuZCIsImlucHV0cyI6eyJQIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUEifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VBIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUIifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VCIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19fX19fX19fX1d")[permalink here]
]

// ============================================================================
// More complex proofs
// ============================================================================
#section(kicker: [More complex proofs], title: [More complex proofs], tsize: 40pt, next: [Lean sandboxes and proofs by vibe])[
  Not every proof is as trivial as the one from before. Some can be quite complex and not obvious, and this is usually the boundary where SMT provers stop.

  Since Lean is a proof assistant, we can push further, given a solid model that we know is deterministically derived from the WASM, and an invariant to prove.

  *The question is, how do we prove complex properties, especially cross transaction inductive properties?*

  #text(size: 19pt, weight: 700, fill: yellow)[Of course, we just lock an LLM in a sandbox and bother it until we either find a proof, or we run out of time]
]

// ============================================================================
// Lean sandboxes and proofs by vibe
// ============================================================================
#slide(kicker: [More complex proofs], title: [Lean sandboxes and proofs by vibe], tsize: 34pt, next: [A final example])[
  Lean sandboxes are a surprisigly well studied problem : both #link("https://github.com/mistralai/LeanstralSafeVerify")[Mistral] and #link("https://github.com/leanprover/comparator")[Lean themselves] ship checkers that compare a submitted proof against a reference statement (the invariant): what we want to be sure of here is that the reference statement is not changed and that no obvious or malicious strategy is used, like using `sorry` or other soundness holes.

  #text(weight: 700, fill: ink)[What we do in our smaller sandbox is :]
  #{
    set text(fill: white, size: 12.5pt, weight: 500)
    show strong: set text(fill: white, weight: 800)
    cmd(s-who)[The agent, powered by Claude Opus 5.5, edits a single file, the proof body, and can run a single command, #slot[./check], with very limited access to other tools]
    cmd(s-changes)[Each saved version is checked by the server, not by the agent: the body goes after the contract model, followed by the server's own copy of the invariant, which the agent's theorem must prove exactly, using only Lean's three standard axioms. #slot[sorry], #slot[native\_decide], new axioms, #slot[\#eval], macros, notation and instances are rejected.]
    cmd(s-theorem)[We have a time budget, so an invariant can end up as *proved*, *counterexampled*, or *undecided*.]
  }
]

#slide(kicker: [Lean sandboxes and proofs by vibe], next: [A final example])[
  #grid(columns: (1fr, 280pt), column-gutter: 30pt, align: horizon,
    text(size: 19pt, weight: 600, fill: ink)[The exciting part here is that, as long as we know that our model has a determinstic provenance from the WASM, and the invariant to be proven is unchanged and not cheesed away, then we don't really care about how we prove something and we can trust the system with a great degree of abstraction.],
    stack(spacing: 6pt,
      align(right, block(radius: 8pt, clip: true, stroke: 1pt + rule, image("assets/reason.png", height: 340pt))),
      align(right, text(font: mono, size: 9pt, fill: grey)[let him reason...]),
    ),
  )
]

// ============================================================================
// A final example
// ============================================================================
#section(kicker: [A final example], title: [A final example], tsize: 54pt, next: [Book–balance consistency])[
  Back in August, the Comet protocol was hacked: the bug was pretty simple: `execute_swap_exact_amount_in` accepts swaps from the same token onto the same token, leading to broken accounting.

  #text(size: 19pt, weight: 700, fill: white)[Let's see if we can find the counterexample that led to the hack by trying to prove book–balance consistency.]
]

#slide(kicker: [A final example], title: [Book–balance consistency], tsize: 36pt, next: [counterexample], ghost: false)[
  #lead[Book–balance consistency asks that the pool's accounting moves with its money: on every swap, the book of the token the pool receives, AllRecordData\[token\_in\].balance, changes by exactly as much as the pool's real balance of that token.]
  The pool computes every price from these books, never from its real holdings, so this is the property its pricing silently relies on.

  We state it as a change over one call (books after minus before, equal to balance after minus before), not as "books equal balances". Anyone can send tokens to the pool without calling it, so its real balance can sit above its books without anything being wrong. What must never happen is a swap that moves the two by different amounts. Comparing changes is also what makes the statement about a single call, so a refutation points at one transaction.
]

#slide(kicker: [A final example], next: [counterexample])[
  #v(6pt)
  #shot("assets/comet.png")
  #v(14pt)
  #grid(columns: (1fr, 330pt), column-gutter: 26pt, align: horizon,
    block(fill: white, stroke: 1.5pt + yellow, radius: 10pt, inset: (x: 18pt, y: 14pt))[
      Of course, this model is not #hexa(s-entry)[complete] , so any counterexample should be checked against the original program to be confirmed, but we can know for sure that if there is a hole in terms of token handling, we will also find it in our abstract Lean model.
    ],
    shot("assets/lean.png"),
  )
]

#slide(kicker: [A final example], next: none)[
  #grid(columns: (1fr, 380pt), column-gutter: 30pt, align: horizon,
    text(size: 20pt, weight: 600, fill: ink)[Ultimately, we find a counterexample, which we can analyze to discover that no constraint in the system prevents us from setting `token_in = token_out` , which is exactly what happens in the counterexample],
    align(right, block(radius: 8pt, clip: true, stroke: 1pt + rule, image("assets/cex.png", height: 370pt))),
  )
]
