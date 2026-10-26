/-
The locked statements. A solution must prove theorems with exactly these names and types
(checked by `Check.lean`); it may add any lemmas of its own.

Comet weighted pool, mainnet CAS3FL6TLZKDGGSISDBWGGPXT3NRR4DYTZD7YOD3HMYO6LTJUVGRVEAM
(wasm 8abc2891…). The pool quotes every price from its books, `AllRecordData[t].balance`.
-/
import Spec.Defs

open Contract Spec

namespace Locked

/-- A swap of token 1 for itself: pool `0`, user `2`, `token_amount_in = 1`, nothing paid out
    (`u.i 1 = 0`), and the out-record debit `u.i 2 = 0`. Every slot of `pre` holds 1. -/
def selfSwapU : Unk := ⟨fun _ => 0, fun _ => 1, fun _ => false, fun _ => .var "", fun _ => fun _ => 0⟩

def selfSwapCall : Call :=
  { fn := "swap_exact_amount_in", caller := 5, self := 0, arg := fun _ => 1,
    argA := fun s => if s = "user" then 2 else 1, signers := [2], env := fun _ => 0 }

def selfSwapPre : Storage := fun _ => 1

def selfSwapStep0 : Step :=
  { call := selfSwapCall, pre := selfSwapPre, post := selfSwapPre, writes := [], ret := 0 }

def selfSwap : Step :=
  { call := selfSwapCall, pre := selfSwapPre,
    post := swap_exact_amount_in.s3 selfSwapStep0 selfSwapU,
    writes := (let st := selfSwapStep0
      [.bal (swap_exact_amount_in.token_in st) (swap_exact_amount_in.user st), .bal (swap_exact_amount_in.token_in st) (pool st), .bal (swap_exact_amount_in.token_out st) (pool st), .bal (swap_exact_amount_in.token_out st) (swap_exact_amount_in.user st), (AllRecordData.balance (swap_exact_amount_in.token_in st)), (AllRecordData.index (swap_exact_amount_in.token_in st)), (AllRecordData.scalar (swap_exact_amount_in.token_in st)), (AllRecordData.weight (swap_exact_amount_in.token_in st)), .has (AllRecordData.get (swap_exact_amount_in.token_in st)), (swap_exact_amount_in.key_AllRecordData_balance st), (AllRecordData.index (swap_exact_amount_in.token_out st)), (AllRecordData.scalar (swap_exact_amount_in.token_out st)), (AllRecordData.weight (swap_exact_amount_in.token_out st)), .has (AllRecordData.get (swap_exact_amount_in.token_out st)), .has AllRecordData]),
    ret := 0 }

theorem selfSwap_spec : swap_exact_amount_in.Spec selfSwap selfSwapU := by
  refine ⟨rfl, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, rfl, rfl, rfl⟩ <;>
    simp [selfSwap, selfSwapStep0, selfSwapCall, selfSwapPre, selfSwapU, xferOk, xfer, bal]

/-
`swap_books_track_input` is FALSE for this model. When `token_in = token_out` (no guard in the
model forbids it), the swap first books the input
(`book[t] := pre + amt1`) and then overwrites the same record with the output side
(`book[t] := pre − u.i 2`), so the input is lost from the books, while the pool's real
balance of `t` moved by `amt1 − amt2`. Witness: `selfSwap`, where the book does not move
but the pool's real balance grows by 1.
-/
theorem swap_books_track_input : ∀ st, swap_exact_amount_in st →
    swap_exact_amount_in.user st ≠ pool st →
    st.post (AllRecordData.balance (swap_exact_amount_in.token_in st))
      - st.pre (AllRecordData.balance (swap_exact_amount_in.token_in st))
    = bal (swap_exact_amount_in.token_in st) st.post (pool st)
      - bal (swap_exact_amount_in.token_in st) st.pre (pool st) := sorry

theorem swap_books_track_input_false : ¬ (∀ st, swap_exact_amount_in st →
    swap_exact_amount_in.user st ≠ pool st →
    st.post (AllRecordData.balance (swap_exact_amount_in.token_in st))
      - st.pre (AllRecordData.balance (swap_exact_amount_in.token_in st))
    = bal (swap_exact_amount_in.token_in st) st.post (pool st)
      - bal (swap_exact_amount_in.token_in st) st.pre (pool st)) := by
  intro h
  have := h selfSwap ⟨_, selfSwap_spec⟩ (by simp [selfSwap, selfSwapCall])
  simp [selfSwap, selfSwapStep0, selfSwapCall, selfSwapPre, selfSwapU, xfer, bal] at this

/-- NON-VACUITY: a swap can happen. -/
theorem swap_live : ∃ st, swap_exact_amount_in st := ⟨selfSwap, _, selfSwap_spec⟩

end Locked
