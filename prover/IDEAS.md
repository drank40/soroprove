I added StellarLean/Query.lean and redesigned it around your two messages: storage is now named variables and hash maps, and questions are put together from a few simple bricks. It builds cleanly, and I checked with #print axioms that none of the 11 answers relies on sorry.

Your example question

“Is the user’s balance reduced when a transfer happens?” is written as:

theorem transfer_reduces_caller : transfer.exec ⊨ decreases balance[caller]

The proof of that statement is the answer.

The bricks
Kind	Bricks
Storage layout	def owner : Term Addr := var "owner", def balance : Map Int := ⟨"balance"⟩
What to look at	owner, balance[caller], balance[recipient], balance[user], balance.total
How it may change	unchanged, decreases, increases, neverDecreases, changesBy x amount, signedBy owner
Exceptions	isCaller user, isRecipient user, signedBy owner (all usable inside .except)
Glue	∧ₛ, ∨ₛ, ∀ₛ user, …, .except …
Asking	entry.exec ⊨ question for one entry point, token ⊨ question for the whole contract
Questions answered for the token
Caller’s balance on transfer: it goes down by exactly the amount (changesBy balance[caller] (- amount ·)).
Anyone else’s balance on transfer: it never goes down (∀ₛ user, (neverDecreases balance[user]).except (isCaller user)).
Balances a transfer touches: only the caller’s and the recipient’s. The frame rule proves this without looking at what transfer computes.
Supply: a transfer leaves balance.total unchanged, and a mint adds exactly the amount.
Owner: only the owner can mint (signedBy owner), and nothing can replace the owner. That last one is again proved by the frame rule alone, across the whole contract.
Whole contract: the supply changes only when the owner signs, and only the caller can ever lose balance.
Over any sequence of calls: balances never go negative, proved by the invariant rule (Contract.invariant).
Limits worth knowing
Map indexes come from the call. You can write balance[caller] or balance[user], but not an index read from storage, such as balance[owner]. That restriction is what lets every brick know exactly which slots it reads.
balance.total uses a model-only list of holders, because Soroban maps can’t be iterated. The contract never reads that list.
Two value types: storage holds only integers and addresses.
Stand-in for WASM: Spec.Entry plays the role of the converter’s output. A real converter would only need to produce the Contract structure, meaning each entry point’s steps plus the proof that every step writes only the slots it reports.
StellarLean/Query.lean now models storage as named variables and hash maps and answers 11 questions about the token. The build is clean and no answer relies on sorry. Nothing is committed yet.
Commit the project so far?
Not yet

Don't commit yet.

OK, I won’t commit. All the files (the Lake scaffold, TokenSpec.lean, Query.lean) are uncommitted in the working tree, and lake build succeeds.

can you explain the glue symbols in simple terms?

Each question is a yes/no check on a single call: Lean compares storage before and after the call. The glue symbols let you combine these checks into bigger ones.

P ∧ₛ Q (and): both checks must hold for the same call.
unchanged owner ∧ₛ unchanged balance.total means “this call changes neither the owner nor the supply.”

P ∨ₛ Q (or): at least one of the two checks holds. In practice it mostly builds exceptions, like isCaller user ∨ₛ isRecipient user, meaning “this user is the caller or the recipient.”

∀ₛ user, P (for every user): the check must hold for every address you could plug in for user, at once.
∀ₛ user, neverDecreases balance[user] means “no one’s balance goes down.”

P.except G (unless): P must hold, but calls where G is true don’t count. It reads like “…except when G.”
(neverDecreases balance[user]).except (isCaller user) means “your balance never goes down, unless you made the call yourself.”
Under the hood it’s just “G or P”, but .except reads better.

⊨ (holds for): this asks the question. transfer.exec ⊨ Q means “Q is true for every successful transfer call.” token ⊨ Q means “Q is true for every successful call to any entry point of the contract.” A failed call changes nothing, so it’s never checked.

A full example, read left to right:

token ⊨ ∀ₛ user, (neverDecreases balance[user]).except (isCaller user)

“For every call to the token contract, and for every user: that user’s balance doesn’t go down, unless they’re the one calling.”

The ₛ subscript is only there because plain ∧, ∨, and ∀ already mean something in Lean (they work on true/false statements). The ₛ versions work on questions about a call.