import subprocess, os, sys
muts = [
 ("token", "transfer", 'amount sign flipped', '(getOr0 st.pre (Balance (transfer.«from» st))) - (transfer.amount st)', '(getOr0 st.pre (Balance (transfer.«from» st))) + (transfer.amount st)'),
 ("token", "transfer", 'wrong signer', '(transfer.«from» st) ∈ st.call.signers', '(transfer.to_muxed st) ∈ st.call.signers'),
 ("token", "burn", 'burn forgotten', '- (burn.amount st)', '- 0'),
 ("single_offer", "create", 'swapped price fields', 'Offer.buy_price (create.buy_price st)', 'Offer.buy_price (create.sell_price st)'),
 ("single_offer", "trade", 'seller not paid', '(st.pre Offer.seller) (trade.amt3 st)', '(st.pre Offer.seller) 0'),
 ("timelock", "claim", 'presence guard flipped', '(st.pre (.has Balance)) = 1', '(st.pre (.has Balance)) ≠ 1'),
 ("mint_lock", "set_minter", 'wrong config field', '(set_minter.config.limit st)', '(set_minter.config.epoch_length st)'),
 ("mint_lock", "set_admin", 'admin not updated', 'Admin (set_admin.new_admin st)', 'Admin (st.pre Admin)'),
 ("atomic_swap", "swap", 'parties swapped', '(swap.s1 st) (pool st) (swap.b st)', '(swap.s1 st) (pool st) (swap.a st)'),
 ("liquidity_pool", "withdraw", 'forgets the burn', '(getOr0 st.pre (Shares (withdraw.to st))) - (withdraw.share_amount st)', '(getOr0 st.pre (Shares (withdraw.to st)))'),
 ("liquidity_pool", "deposit", 'wrong token ledger', 'xfer (st.pre TokenA) st.pre', 'xfer (st.pre TokenB) st.pre'),
 ("increment", "increment", 'off by one', '+ 1', '+ 2'),
]
lean = os.path.expanduser("~/.elan/bin/lean")
for c, fn, what, a, b in muts:
    src = open(f"{c}.check.lean").read()
    # the entrypoint's namespace (inputs, amounts, states) and its checker
    start = src.find(f"namespace {fn}\n")
    if start < 0 or src.find(a, start) > src.find(f"end {fn}\n", start):
        start = src.find(f"def {fn}.check (st : Step)")
    end = src.find(f"def {fn}.check (st : Step)")
    end = src.find("\ndef ", end + 1) if end >= 0 else -1
    k = src.find(a, start)
    if start < 0 or k < 0 or k > end:
        print(f"{c:15} {fn+': '+what:40} NOT APPLIED"); continue
    open(f"mut_{c}.lean", "w").write(src[:k] + b + src[k + len(a):])
    out = subprocess.run([lean, f"mut_{c}.lean"], capture_output=True, text=True).stdout
    line = [l for l in out.splitlines() if l.startswith(fn + ":")]
    res = [l for l in out.splitlines() if l.startswith("RESULT")]
    print(f"{c:15} {fn+': '+what:40} {res[0] if res else 'ERR '+out[:150]}  | {line[0] if line else ''}")
