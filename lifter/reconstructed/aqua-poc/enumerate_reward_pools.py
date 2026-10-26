import json, subprocess, hashlib, os, sys

RPC="https://mainnet.sorobanrpc.com"
PASS="Public Global Stellar Network ; September 2015"
ROUTER="CBQDHNBFBZYE4MKPWBSJOPIYLW4SFSXAXUTSXJN76GNKYVYPCKWC6QUK"
AQUA_SAC="CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK"
VULN_WASM="ae0da5a84b15805c5c7931ac567a8d1b34be3f26b483993d9ff80cb2c3de9852"
os.makedirs("/tmp/w",exist_ok=True)

def inv(cid,*args):
    r=subprocess.run(["stellar","contract","invoke","--id",cid,"--source-account","q",
        "--rpc-url",RPC,"--network-passphrase",PASS,"--send=no","--",*args],
        capture_output=True,text=True)
    return r.stdout.strip() if r.returncode==0 else None

def wasm_hash(cid):
    out=f"/tmp/w/{cid}.wasm"
    if not os.path.exists(out):
        r=subprocess.run(["stellar","contract","fetch","--id",cid,"--out-file",out,
            "--rpc-url",RPC,"--network-passphrase",PASS],capture_output=True,text=True)
        if r.returncode!=0: return "ERR:"+r.stderr.strip()[:60]
    return hashlib.sha256(open(out,"rb").read()).hexdigest()

sets=json.load(open("/tmp/reward_sets.json"))
pools={}
for pair_key in sets:
    tokens=json.loads(pair_key)
    out=inv(ROUTER,"get_pools","--tokens",json.dumps(tokens))
    if not out: continue
    for _,addr in json.loads(out).items():
        pools.setdefault(addr,tokens)

rows=[]
for addr,tokens in pools.items():
    wh=wasm_hash(addr)
    bal=inv(AQUA_SAC,"balance","--id",addr)
    bal=int(bal.strip('"')) if bal else 0
    rows.append((addr,wh==VULN_WASM,bal,tokens,wh))

rows.sort(key=lambda r:-r[2])
tot_vuln=tot_all=0
by_hash={}
lines=[]
lines.append(f"{'pool':56} {'vuln':4} {'AQUA_reserve':>16}  wasm[:12]")
for addr,vuln,bal,tokens,wh in rows:
    tot_all+=bal
    if vuln: tot_vuln+=bal
    by_hash[wh]=by_hash.get(wh,0)+bal
    lines.append(f"{addr} {'YES ' if vuln else 'no  '} {bal/1e7:16.2f}  {wh[:12]}")
report="\n".join(lines)
print(report)
print()
print(f"total reward pools: {len(rows)}")
print(f"VULNERABLE (wasm ae0da5a8): {sum(1 for r in rows if r[1])} pools, {tot_vuln/1e7:,.2f} AQUA")
print(f"ALL reward pools:           {len(rows)} pools, {tot_all/1e7:,.2f} AQUA")
print("\nAQUA reserve by wasm hash:")
for wh,b in sorted(by_hash.items(),key=lambda x:-x[1]):
    print(f"  {wh[:16]}  {b/1e7:16,.2f} AQUA  {'<-- VULNERABLE' if wh==VULN_WASM else ''}")
json.dump({"vuln_wasm":VULN_WASM,
    "pools":[{"addr":a,"vuln":v,"aqua_reserve_stroops":b,"tokens":t,"wasm":w} for a,v,b,t,w in rows],
    "vuln_aqua_stroops":tot_vuln,"all_aqua_stroops":tot_all,"by_hash":by_hash},
    open("/tmp/aqua_enum_out.json","w"),indent=2)
open("/tmp/aqua_enum_table.txt","w").write(report)
print("\nwrote /tmp/aqua_enum_out.json + /tmp/aqua_enum_table.txt")
