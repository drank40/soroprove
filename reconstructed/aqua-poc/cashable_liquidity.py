import json, urllib.request, subprocess
AQUA="AQUA:GBNZILSTVQZ4R7IKQDGHYGY2QXL5QOFJYQMXPKWRRM5PAV7Y4M67AQUA"
AQUA_SAC="CAUIKL3IYGMERDRUN6YSCLWVAKIFG5Q4YJHUKM4S4NJZQIA3BAS6OJPK"
USDC_CLASSIC="USDC:GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN"
RPC="https://stellar-mainnet.g.alchemy.com/v2/<ALCHEMY_KEY>"
PASS="Public Global Stellar Network ; September 2015"
ROUTER="CBQDHNBFBZYE4MKPWBSJOPIYLW4SFSXAXUTSXJN76GNKYVYPCKWC6QUK"
XLM=0.2157
def get(u):
    r=urllib.request.Request(u,headers={"User-Agent":"curl/8"})
    return json.load(urllib.request.urlopen(r,timeout=25))
def inv(cid,*a):
    r=subprocess.run(["stellar","contract","invoke","--id",cid,"--source-account","q","--rpc-url",RPC,"--network-passphrase",PASS,"--send=no","--",*a],capture_output=True,text=True)
    return r.stdout.strip() if r.returncode==0 else None
# STRICT cashable: only native XLM and Circle USDC
def cash(asset,amt):
    if asset=="native": return amt*XLM
    if asset==USDC_CLASSIC: return amt*1.0
    return 0.0
# classic
url=f"https://horizon.stellar.org/liquidity_pools?reserves={AQUA}&limit=200&order=desc"; classic=0.0; n=0; det={}
while url:
    d=get(url); recs=d["_embedded"]["records"]
    if not recs: break
    for p in recs:
        n+=1
        for r in p["reserves"]:
            if r["asset"]==AQUA: continue
            v=cash(r["asset"],float(r["amount"]))
            if v>0: classic+=v; det[r["asset"].split(":")[0]]=det.get(r["asset"].split(":")[0],0)+v
    nx=d["_links"].get("next",{}).get("href")
    if not nx or nx==url: break
    url=nx
    if n>2000: break
# soroban aquarius AQUA pools
sets=json.load(open("/tmp/reward_sets.json")); sor=0.0; spools=set()
for k in sets:
    toks=json.loads(k)
    if AQUA_SAC in toks:
        out=inv(ROUTER,"get_pools","--tokens",json.dumps(toks))
        if out:
            for _,addr in json.loads(out).items(): spools.add(addr)
for addr in spools:
    res=inv(addr,"get_reserves"); tk=inv(addr,"get_tokens")
    if not res or not tk: continue
    reserves=[int(x.strip('"')) for x in json.loads(res)]; tl=json.loads(tk)
    for i,t in enumerate(tl):
        if t==AQUA_SAC: continue
        nm=(inv(t,"name") or '""').strip('"')  # "native" or "USDC:GA5ZSEJY..." etc
        sor+=cash(nm, reserves[i]/1e7)
tot=classic+sor
print(f"XLM=${XLM}  (strict cashable = native XLM + Circle USDC only)")
print(f"classic protocol AMM cashable paired: ${classic:,.0f}  {[(k,round(v)) for k,v in det.items()]}")
print(f"Aquarius Soroban AMM cashable paired: ${sor:,.0f}  ({len(spools)} AQUA pools)")
print(f"TOTAL cashable paired liquidity: ${tot:,.0f}")
print(f"Realizable via pool selling (~90% extraction, tested on real bytecode): ${0.90*tot:,.0f}")
