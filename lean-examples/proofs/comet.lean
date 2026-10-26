-- Proofs over the generated `comet.lean` model (appended to it by check.sh): the
-- Comet BLND/USDC pool backing Blend's backstop, mainnet contract
-- CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM (wasm 8abc2891…),
-- exploited 2026-08-25 with self-swaps (`token_in = token_out`).
--
-- The pool prices every trade off its BOOKS, the per-token `Record.balance` in
-- the `AllRecordData` map, not off its real token balances. So the invariant
-- that matters: each swap moves a token's book exactly as it moves the pool's
-- real balance of that token.
open Contract

/-- The book of token `t` moved by exactly what the pool's real balance of `t` did. -/
def booksTrack (st : Step) (t : Addr) : Prop :=
  st.post (AllRecordData.balance t) - st.pre (AllRecordData.balance t)
    = bal t st.post (pool st) - bal t st.pre (pool st)

/-- A swap between two DIFFERENT tokens books its input exactly: the record of
    `token_in` grows by `token_amount_in`, which is what the pool received. -/
theorem swap_books_input (st : Step) (h : swap_exact_amount_in st)
    (hd : swap_exact_amount_in.token_in st ≠ swap_exact_amount_in.token_out st)
    (hu : swap_exact_amount_in.user st ≠ pool st) :
    booksTrack st (swap_exact_amount_in.token_in st) := by
  obtain ⟨u, h⟩ := h
  simp at hd hu
  unfold booksTrack
  rw [h.post]
  simp [hd, Ne.symm hu]
  omega

/-- The same statement WITHOUT `token_in ≠ token_out` is false of the model: the
    first swap of the exploit transaction (41c898a1…, ledger 64112340) is a step
    the model admits, and it breaks the books. Pre-state from the transaction's
    ledger changes: the USDC book and the pool's USDC balance were both
    7782309517250; the attacker swapped 2594103172416 USDC for 1941196544582 USDC. -/
def B : Int := 7782309517250
def amtIn : Int := 2594103172416
def amtOut : Int := 1941196544582
def USDC : Addr := 1
def POOL : Addr := 2
def ATK : Addr := 3

def exploitCall : Call where
  fn := "swap_exact_amount_in"
  caller := ATK
  self := POOL
  arg := fun n => if n = "token_amount_in" then amtIn else 0
  argA := fun n => if n = "token_in" ∨ n = "token_out" then USDC else ATK
  signers := [ATK]
  env := fun _ => 0

def exploitPre : Storage := fun k =>
  if k = AllRecordData.balance USDC then B
  else if k = .has (AllRecordData.get USDC) then 1
  else if k = .bal USDC POOL then B
  else if k = .bal USDC ATK then amtIn
  else 0

/-- the open values: the amount out (transferred and booked), the price-check operands. -/
def exploitU : Unk where
  i := fun _ => amtOut
  g := fun n => if n = 3 then amtIn else 0
  b := fun _ => true
  k := fun _ => .var "?"
  s := fun _ => exploitPre

/-- the call and its pre-state; the step is it with the model's post-state. -/
def st0 : Step := { call := exploitCall, pre := exploitPre, post := exploitPre, writes := [], ret := 0 }

def exploitStep : Step where
  call := exploitCall
  pre := exploitPre
  post := swap_exact_amount_in.s3 st0 exploitU
  writes := [.bal (swap_exact_amount_in.token_in st0) (swap_exact_amount_in.user st0), .bal (swap_exact_amount_in.token_in st0) (pool st0), .bal (swap_exact_amount_in.token_out st0) (pool st0), .bal (swap_exact_amount_in.token_out st0) (swap_exact_amount_in.user st0), (AllRecordData.balance (swap_exact_amount_in.token_in st0)), (AllRecordData.index (swap_exact_amount_in.token_in st0)), (AllRecordData.scalar (swap_exact_amount_in.token_in st0)), (AllRecordData.weight (swap_exact_amount_in.token_in st0)), .has (AllRecordData.get (swap_exact_amount_in.token_in st0)), (swap_exact_amount_in.key_AllRecordData_balance st0), (AllRecordData.index (swap_exact_amount_in.token_out st0)), (AllRecordData.scalar (swap_exact_amount_in.token_out st0)), (AllRecordData.weight (swap_exact_amount_in.token_out st0)), .has (AllRecordData.get (swap_exact_amount_in.token_out st0)), .has AllRecordData]
  ret := amtOut

theorem exploit_admitted : swap_exact_amount_in exploitStep := by
  refine ⟨exploitU, ?_⟩
  constructor <;> simp [exploitStep, st0, exploitCall, exploitPre, exploitU, B, amtIn, amtOut, USDC, POOL, ATK, xferOk, bal, xfer]

/-- On that step the USDC book drops by `amtOut` while the pool's real USDC grows
    by `amtIn - amtOut`: `amtIn` (259,410 USDC) is never booked. -/
theorem exploit_breaks_books : ¬ booksTrack exploitStep USDC := by
  simp [booksTrack, exploitStep, st0, exploitCall, exploitPre, exploitU, B, amtIn, amtOut, USDC, POOL, ATK, bal, xfer]

theorem self_swap_refutes : ¬ ∀ st, swap_exact_amount_in st → booksTrack st (swap_exact_amount_in.token_in st) :=
  fun hall => exploit_breaks_books (by simpa [exploitStep, exploitCall] using hall exploitStep exploit_admitted)
