# Soroprove

Friendly Lean proofs for Soroban contracts, without any of the sorrow

## Goal

Formal verification is hard, yet it's ever more crucial to constraint complex financial codebases, which are now largerly written by AI.

Soroprove turns WASM contracts into Lean object representations, while also offering sane macros for developers to prove common properties about their contracts.

This is achieved by abstracting away every contract code path leading to value transfers into a state machine, and by modelling part of the Soroban runtime in Lean.

This is all offered both with a higher level UI, automatically generated from stellar contract builds, as well as through a lower level Rust macro integration, which allows for custom invariant proofs.

[image of the interface]


## Technical implementation

Soroprove operates directly on the contract's compiled WASM: a big part of the codebase is dedicated to lifting and abstracting this code into something that is wieldy for a prover to handle in a reasonable amount of CPU time.

The rest of the backend consists as a light, but accurate abstraction of the Soroban VM into Lean. The technical brief here is split up in covering these two components, starting from the latter.

### Runtime modelling

In general, given our scope, which is preventing losses of funds, there are only a few syscalls that we care about recreating and tracing through:

1. `call` or `try_call` : this is obviously needed to trace value transfers, as we consider value transfers operations on SEP-41 contracts, which we're gonna trace abstractly. We ignore other kinds of cross contract calls and assume a Top value to avoid balooning complexity.


- `require_auth` / `require_auth_for_args` , as we need this to understand permission gates, which can be a source of very critical bugs
- `verify_sig_ed25519, recover_key_ecdsa_secp256k1, verify_sig_ecdsa_secp256r1, verify_sig_ml_dsa_*` : similar auth, derived from external signatures these time
- `authorize_as_curr_contract` : any nested auth given to a foreign contract essentially gives it full control of funds
- `update_current_contract_wasm`, `update_current_contract_executable_ref` : any contract upgrade should be a highly priviledged function that results in a total loss of funds if mishandled
- any storage operation: `put_contract_data` , `get_contract_data` , `has_contract_data` , `del_contract_data` , which we need in order to track side effects

And some peripheral ones:

- `get_current_contract_address`: the best way to abstract address is into the contract itself, priviledged users (which are checked against a value set) and unpriviledged users
- `fail_with_error` : one the ways the FSM should terminate
- `obj_cmp`


### Code abstraction

After we model the runtime, we need to understand what we can realistically keep and abstract out of the contract's logic. all formal verification requires some level of abstraction if we wanna avoid running into a never ending execution loop.

[image from the abstract analysis paper with the multiplications becoming + and -]

We start off with some WASM. WASM is not fun to work with, so to make our lives ~easier~ more painful we wrote code to map (lift) WASM to LLVM IR, which has a lot of semantic analysis tooling to work with. 

We will glance over the details as they're not too revelant to the final problem and could be abstracted into a separate library

It's more interesting to focus on the sematic operations that we run on the LLVM IR

#### Abstractions

At one point we considered transpiling the entire contract to Lean, but then we realized that's currently a bit too computationally complex, and it also requires devs to be very skilled in Lean to make use of that properly

This means that we will aim for a final model that is **sound** but not **complete** : everything that we prove on the model will necessarly also hold in the contract, but disproving something doesn't necessarly mean that we found a bug in our contract. This is a necessary tradeoff that we need to make, and in this case we're interested about fully securing a protocol, and not finding particular bugs.

So we decided to abstract away the kind of information that can prevent loss of fund and bricking bugs by backtracing from any kind of token transfer

We can easily trace this, even in the WASM, because both symbols, and, less intuitively, `Value` types are preserved, since the lower byte of every value is its enum tag

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

Thus we can easily match SEP-41 signatures, for example `transfer` :

```rust
call(token_addr,
     Symbol("transfer"),               
     Vec[ from  : AddressObject,
          to    : AddressObject,
          amount: I128Small || I128Object])
          
```

Other kinds of calls are ignored, and thanks to the no reentrancy assurance provided by the Soroban runtime, we can at the very least be sure that the storage state of the analyzed contract won't have changed after the external call, while treating its `Value` result as unknown (`Top`)


In the end, we can extract something like this for each value moving operation:

### tokens and roles

Key operations like moving funds and assigning roles require further abstractions for performance and ease of proofs down the line

#### token

Token balance transitions are accounted in ad hoc mapping

===

Insert mapping

===


## Lean prover

Since Lean is an prove assistant and not an automatic theorem prover 
## User experience

We love [Scratch](https://scratch.mit.edu/). Everybody loves Scratch.

In an attempt to mask formal verification with a friendly interface, we made it so that invariants can be expressed in blocks, in alternative to the manual writing of the invariant in Lean, which is still possible in the side tab.

The intended user experience there is just to drop a WASM, have the metadata be extracted (there is a lot of it), the model generated in the backend, in order for the user to be instantly able to start laying out desirable invariants and see if they hold.

One could imagine a developer trying to verify that the AMM invariant on his contract is always decreasing. It would look as simple as this example:

[AMM example]

This kind of proof can be handled well by the `answer` strategy that we implemented, where we utilized a bit of LEAN 4 metaprogramming trickery, to remove the need to select the tactic, which narrows the spectrum of provable properties, but allows for a friendlier interface in most cases.

Suppose that we wanna prove the reserve solvency of an AMM. This is pretty simple to express in Soroprove, and can be checked automatically in a very fast manner.

You can play around with the proof using the [permalink here](https://soroprove.marziano.top/#c=lpDiver&w=W3sidHlwZSI6ImxwRGl2ZXIudGhlb3JlbSIsImZpZWxkcyI6eyJOQU1FIjoicmVzZXJ2ZXNfc3RheV9iYWNrZWQiLCJUQVJHRVQiOiJoaXN0b3J5IiwiVEFDVElDIjoidmliZSJ9LCJpbnB1dHMiOnsiUSI6eyJibG9jayI6eyJ0eXBlIjoiYW5kIiwiaW5wdXRzIjp7IlAiOnsiYmxvY2siOnsidHlwZSI6ImNtcC5hbmUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuVG9rZW5BIn19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJscERpdmVyLnZhci5Ub2tlbkIifX19fX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImFuZCIsImlucHV0cyI6eyJQIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUEifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VBIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19LCJSIjp7ImJsb2NrIjp7InR5cGUiOiJjbXAubGUiLCJpbnB1dHMiOnsiTCI6eyJibG9jayI6eyJ0eXBlIjoibHBEaXZlci52YXIuUmVzZXJ2ZUIifX0sIlIiOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIubWFwLkJhbGFuY2VCIiwiaW5wdXRzIjp7IlciOnsiYmxvY2siOnsidHlwZSI6ImxwRGl2ZXIuYWRkci5wb29sIn19fX19fX19fX19fX19fX1d)

[image of the simple property](./amm.png)


## More complex proofs

Not every proof is as trivial as the one from before. Some can be quite complex and not obvious, and this is usually the boundary where SMT provers stop.

Since Lean is a proof assistant, we can push further, given a solid model that we know is deterministically derived from the WASM, and an invariant to prove. 

The question is, how do we prove complex properties, especially cross transaction inductive properties? 

Of course, we just lock an LLM in a sandbox and bother it until we either find a proof, or we run out of time

## Lean sandboxes and proofs by vibe

Lean sandboxes are a surprisigly well studied problem : both [Mistral](https://github.com/mistralai/LeanstralSafeVerify) and [Lean themselves](https://github.com/leanprover/comparator) ship checkers that compare a submitted proof against a reference statement (the invariant): what we want to be sure of here is that the reference statement is not changed and that no obvious or malicious strategy is used, like using `sorry` or other soundness holes.

What we do in our smaller sandbox is :

- The agent, powered by Claude Opus 5.5, edits a single file, the proof body, and can run a single command, `./check`, with very limited access to other tools
- Each saved version is checked by the server, not by the agent: the body goes after the contract model,
  followed by the server's own copy of the invariant, which the agent's theorem must prove exactly, using
  only Lean's three standard axioms. `sorry`, `native_decide`, new axioms, `#eval`, macros, notation and
  instances are rejected.
- We have a time budget, so an invariant can end up as **proved**, **counterexampled**, or **undecided**.

The exciting part here is that, as long as we know that our model has a determinstic provenance from the WASM, and the invariant to be proven is unchanged and not cheesed away, then we don't really care about how we prove something and we can trust the system with a great degree of abstraction.


[let him reason...](./reason.png)


## A final example

Back in August, the Comet protocol was hacked: the bug was pretty simple: `execute_swap_exact_amount_in` accepts swaps from the same token onto the same token, leading to broken accounting.

Let's see if we can find the counterexample that led to the hack by trying to prove book–balance consistency.

Book–balance consistency asks that the pool's accounting moves with its money: on every swap, the book of the token the pool receives, AllRecordData[token_in].balance, changes by exactly as much as the pool's real balance of that token. The pool computes every price from these books, never from its real holdings, so this is the property its pricing silently relies on.

We state it as a change over one call (books after minus before, equal to balance after minus before), not as "books equal balances". Anyone can send tokens to the pool without calling it, so its real balance can sit above its books without anything being wrong. What must never happen is a swap that moves the two by different amounts. Comparing changes is also what makes the statement about a single call, so a refutation points at one transaction.

[screenshot of the property](./comet.png)

Of course, this model is not **complete** , so any counterexample should be checked against the original program to be confirmed, but we can know for sure that if there is a hole in terms of token handling, we will also find it in our abstract Lean model.

Ultimately, we find a counterexample, which we can analyze to discover that no constraint in the system prevents us from setting `token_in = token_out` , which is exactly what happens in the counterexample








