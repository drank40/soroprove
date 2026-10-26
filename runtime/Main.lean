import Std.Data.HashMap
import SorobanLean
open Soroban

/-- Compare `difftest val_oracle` output against SorobanLean.Val. -/
def valCheck (path : String) : IO UInt32 := do
  let lines ← IO.FS.lines path
  let mut bad := 0
  for l in lines do
    match l.splitOn " " with
    | [xs, good, tag, bits] =>
      let x := xs.toNat!.toUInt64
      let v : Val := ⟨x⟩
      let mine := String.join (Env.ValTy.all.map fun t => if t.tryMarshal x then "1" else "0")
      let ok := (if v.isGood then "1" else "0") == good && toString v.getTag.toU8 == tag && mine == bits
      if !ok then
        bad := bad + 1
        if bad ≤ 10 then
          IO.println s!"MISMATCH {x}: rust good={good} tag={tag} bits={bits} | lean good={v.isGood} tag={v.getTag.toU8} bits={mine}"
    | _ => pure ()
  IO.println s!"val-check: {lines.size} cases, {bad} mismatches"
  return if bad == 0 then 0 else 1

def decodeDump (path : String) : IO UInt32 := do
  let b ← IO.FS.readBinFile path
  match Wasm.Decode.decodeModule b with
  | .ok m => IO.println "DECODED"; for l in Wasm.Dump.module m do IO.println l
             return 0
  | .error e => IO.println s!"DECODE-ERROR {e}"; return 1

def importsCmd (path : String) : IO UInt32 := do
  let b ← IO.FS.readBinFile path
  let m ← IO.ofExcept (Wasm.Decode.decodeModule b)
  for i in m.imports do
    match Env.HostFn.resolve i.module i.name with
    | some f => IO.println s!"{i.module}.{i.name} {f.name} ({f.arity} args) min={f.minProto} max={f.maxProto}"
    | none => IO.println s!"{i.module}.{i.name} UNRESOLVED"
  return 0

def hexToBytes (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray
  let hv : Char → Nat := fun c => if c.isDigit then c.toNat - '0'.toNat else c.toNat - 'a'.toNat + 10
  let mut out := ByteArray.empty
  for i in [0:cs.size / 2] do
    out := out.push (hv cs[2*i]! * 16 + hv cs[2*i+1]!).toUInt8
  return out

def bytesToHex (b : ByteArray) : String :=
  String.join (b.toList.map fun x => let s := String.ofList (Nat.toDigits 16 x.toNat); if s.length == 1 then "0" ++ s else s)

def errName : Xdr.Err → String
  | .invalid => "invalid" | .lengthExceedsMax => "lengthExceedsMax" | .nonZeroPadding => "nonZeroPadding"
  | .depthLimitExceeded => "depthLimitExceeded" | .lengthLimitExceeded => "lengthLimitExceeded"
  | .io => "io" | .fuel => "fuel"

def xdrCheck (path : String) : IO UInt32 := do
  let lines ← IO.FS.lines path
  let names : Std.HashMap String String := Xdr.allTypeNames.foldl (fun m n => m.insert n.toLower n) {}
  let mut bad := 0
  let mut skipped := 0
  for l in lines do
    match l.splitOn " " with
    | rname :: hex :: res =>
      let res := " ".intercalate res
      let rname := if rname == "SError" then "Error" else rname
      match names[rname.toLower]? with
      | none => skipped := skipped + 1
      | some n =>
        match Xdr.roundTripByName n (hexToBytes hex) with
        | none => skipped := skipped + 1
        | some r =>
          let mine := match r with | .ok b => s!"ok {bytesToHex b}" | .error e => s!"err {errName e}"
          if mine != res then
            bad := bad + 1
            if bad ≤ 15 then IO.println s!"MISMATCH {n} {hex.take 80}: rust={res.take 80} lean={mine.take 80}"
    | _ => pure ()
  IO.println s!"xdr-check: {lines.size} cases, {bad} mismatches, {skipped} skipped"
  return if bad == 0 then 0 else 1

/-- `Error`'s `Debug` form in the host (`Error(Type, Code)`, contract errors as `Error(Contract, #n)`). -/
def errDebug (e : Val) : String :=
  let tys := #["Contract", "WasmVm", "Context", "Storage", "Object", "Crypto", "Events", "Budget", "Value", "Auth"]
  let codes := #["ArithDomain", "IndexBounds", "InvalidInput", "MissingValue", "ExistingValue", "ExceededLimit",
                 "InvalidAction", "InternalError", "UnexpectedType", "UnexpectedSize"]
  let t := e.getMinor.toNat; let c := e.getMajor.toNat
  if t == 0 then s!"Error(Contract, #{c})"
  else s!"Error({tys.getD t s!"?{t}"}, {codes.getD c s!"?{c}"})"

def parseOptNat (s : String) : Option Nat :=
  if s.startsWith "Some(" then ((s.drop 5).dropRight 1).toString.toNat? else none

def costName (t : Xdr.ContractCostType) : String :=
  ((reprStr t).splitOn ".").getLast!

def parseE2EInput (lines : Array String) (tag : String) : IO E2EInput := do
  let mut hf := ByteArray.empty; let mut res := ByteArray.empty; let mut src := ByteArray.empty
  let mut ents := #[]
  let mut auths := #[]
  let mut li : LedgerInfo := default
  for l in lines do
    match l.splitOn " " with
    | t :: "input" :: "host_fn" :: h :: _ => if t == tag then hf := hexToBytes h
    | t :: "input" :: "resources" :: h :: _ => if t == tag then res := hexToBytes h
    | t :: "input" :: "source" :: h :: _ => if t == tag then src := hexToBytes h
    | t :: "input" :: "auth" :: h :: _ => if t == tag then auths := auths.push (hexToBytes h)
    | t :: "input" :: "entry" :: h :: ttl :: rs :: _ =>
      if t == tag then
        let e := if h == "-" then none else some (hexToBytes h)
        let tm := match parseOptNat (ttl.drop 4).toString, parseOptNat (rs.drop 10).toString with
          | some a, some b => some { liveUntilLedger := a, entrySizeForRent := b : TtlMeta }
          | _, _ => none
        ents := ents.push (e, tm)
    | t :: "input" :: "ledger" :: kvs =>
      if t == tag then
        let kv : String → Option String := fun k => (kvs.find? (·.startsWith (k ++ "="))).map (fun x => (x.drop (k.length + 1)).toString)
        let n : String → Nat := fun k => ((kv k).bind String.toNat?).getD 0
        li := { protocolVersion := n "proto", sequenceNumber := n "seq", timestamp := n "ts",
                networkId := hexToBytes ((kv "nid").getD ""), baseReserve := n "reserve",
                minTempEntryTtl := n "min_temp", minPersistentEntryTtl := n "min_pers", maxEntryTtl := n "max_ttl" }
    | _ => pure ()
  pure { hostFn := hf, resources := res, sourceAccount := src, ledgerInfo := li, authEntries := auths,
         ledgerEntries := ents, basePrngSeed := ByteArray.mk (Array.replicate 32 0) }

def loadE2EInput (path tag : String) : IO E2EInput := do
  parseE2EInput (← IO.FS.lines path) tag

def loadBudget (settings : String) : IO Budget := do
  let b64 ← IO.FS.readFile settings
  let some bytes := base64Decode b64 | throw (IO.userError "bad base64")
  let set ← match Xdr.decodeToEnd Xdr.rd_ConfigUpgradeSet bytes with
    | .ok s => pure s | .error e => throw (IO.userError s!"settings decode: {errName e}")
  let some net := NetConfig.ofUpgradeSet set | throw (IO.userError "settings incomplete")
  let some b := net.budget | throw (IO.userError "bad cost params")
  pure b

abbrev SCValLike := Xdr.SCVal

def e2eTrace (settings path tag : String) : IO UInt32 := do
  let b ← loadBudget settings
  let inp ← loadE2EInput path tag
  let st0 : HostState := { budget := { b with tracing := true }, storage := default, cells := #[] }
  let (r, st) := runHost (invokeHostFunction 1000 inp) st0
  for (t, it, i) in st.budget.log do
    IO.println s!"CHARGE {costName t} {it} {match i with | some x => s!"Some({x})" | none => "None"}"
  match r with
  | .ok res =>
    match res.result with
    | .ok b => IO.println s!"{tag} output result ok {bytesToHex b}"
    | .error e => IO.println s!"{tag} output result err {errDebug e}"
    for c in res.ledgerChanges do
      let nv := match c.encodedNewValue with | some v => bytesToHex v | none => "-"
      let ttl := match c.ttlChange with | some t => s!"Some(({t.oldLiveUntilLedger}, {t.newLiveUntilLedger}))" | none => "None"
      IO.println s!"{tag} output change ro={c.readOnly} key={bytesToHex c.encodedKey} old_size={c.oldEntrySizeBytesForRent} new={nv} new_size={c.newEntrySizeBytesForRent} ttl={ttl}"
    for e in res.encodedContractEvents do IO.println s!"{tag} output event {bytesToHex e}"
  | .error e => IO.println s!"{tag} HOST-ERROR payload={e.payload} type={e.getMinor} code={e.getMajor}"
  IO.println s!"{tag} output budget cpu={st.budget.cpu.netCount} mem={st.budget.mem.peakCount}"
  for h : i in [0:st.budget.trackers.size] do
    let t := st.budget.trackers[i]
    if t.iterations > 0 then
      let ct := (Xdr.ContractCostType.ofI32? (Int32.ofNat i)).get!
      IO.println s!"{tag} tracker {costName ct} it={t.iterations} in={match t.inputs with | some x => s!"Some({x})" | none => "None"} cpu={t.cpu} mem={t.mem}"
  return 0

/-- Replay every invocation in an oracle file on the Lean host (all inputs carried by
    the file, so tags are independent) and print the outputs in the oracle's format.
    Tags whose host function the Lean host doesn't implement (upload/create) are skipped. -/
def e2eBatch (settings path : String) : IO UInt32 := do
  let b ← loadBudget settings
  let lines ← IO.FS.lines path
  let tags := lines.filterMap fun l => match l.splitOn " " with
    | t :: "input" :: "host_fn" :: _ => if t.startsWith "upload" || t.startsWith "create" then none else some t
    | _ => none
  -- Group the lines by tag once (re-reading the file per tag is quadratic).
  let mut byTag : Std.HashMap String (Array String) := {}
  for l in lines do
    let t := (l.splitOn " ").head!
    byTag := byTag.insert t ((byTag.getD t #[]).push l)
  let t0 ← IO.monoMsNow
  for tag in tags do
    let inp ← parseE2EInput (byTag.getD tag #[]) tag
    let st0 : HostState := { budget := b, storage := default, cells := #[] }
    let (r, st) := runHost (invokeHostFunction 1000 inp) st0
    match r with
    | .ok res =>
      match res.result with
      | .ok v => IO.println s!"{tag} output result ok {bytesToHex v}"
      | .error e => IO.println s!"{tag} output result err {errDebug e}"
      for c in res.ledgerChanges do
        let nv := match c.encodedNewValue with | some v => bytesToHex v | none => "-"
        let ttl := match c.ttlChange with | some t => s!"Some(({t.oldLiveUntilLedger}, {t.newLiveUntilLedger}))" | none => "None"
        IO.println s!"{tag} output change ro={c.readOnly} key={bytesToHex c.encodedKey} old_size={c.oldEntrySizeBytesForRent} new={nv} new_size={c.newEntrySizeBytesForRent} ttl={ttl}"
      for e in res.encodedContractEvents do IO.println s!"{tag} output event {bytesToHex e}"
    | .error e => IO.println s!"{tag} HOST-ERROR payload={e.payload} type={e.getMinor} code={e.getMajor}"
    IO.println s!"{tag} output budget cpu={st.budget.cpu.netCount} mem={st.budget.mem.peakCount}"
  let t1 ← IO.monoMsNow
  IO.eprintln s!"e2e-batch: {tags.size} invocations in {t1 - t0} ms"
  return 0

def main (args : List String) : IO UInt32 := do
  match args with
  | ["imports", p] => importsCmd p
  | ["xdr-check", p] => xdrCheck p
  | ["decode-dump", p] => decodeDump p
  | ["spectest", dir, json] =>
      let st ← Wasm.SpecTest.run dir json false
      IO.println s!"{json}: pass {st.pass} fail {st.fail} skip {st.skip}"; return (if st.fail == 0 then 0 else 1)
  | ["spectest-fuel", dir, json] =>
      let _ ← Wasm.SpecTest.run dir json false true; return 0
  | ["spectest-v", dir, json] =>
      let st ← Wasm.SpecTest.run dir json true
      IO.println s!"{json}: pass {st.pass} fail {st.fail} skip {st.skip}"; return (if st.fail == 0 then 0 else 1)
  | ["val-check", p] => valCheck p
  | ["e2e-trace", settings, p, tag] => e2eTrace settings p tag
  | ["e2e-batch", settings, p] => e2eBatch settings p
  | _ => IO.println s!"soroban-lean: {Env.hostFnCount} host fns"; return 0
