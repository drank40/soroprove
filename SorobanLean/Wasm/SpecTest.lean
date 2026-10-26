/-
Runner for the WebAssembly spec testsuite (converted with `wast2json`), used to
check the decoder + interpreter on the integer / bulk-memory / sign-ext subset.
Modules that need features Soroban disables are expected to be rejected by the
decoder; modules importing memories/tables or registered modules are skipped.
-/
import Lean.Data.Json
import SorobanLean.Wasm.Instantiate
import SorobanLean.Wasm.Decode

namespace Wasm.SpecTest
open Lean

/-- Spectest host: `print*` functions are no-ops; memory growth always allowed
    (wasmi without a ResourceLimiter). -/
def host : HostIface Unit String where
  call _ _ _ st h := .ok ([], st, h)
  memoryGrowing _ _ _ h := .ok (true, h)

structure Loaded where
  m : Module
  cx : Ctx Unit String
  st : Store

structure Stats where
  pass : Nat := 0
  fail : Nat := 0
  skip : Nat := 0
  deriving Repr

def parseVal (j : Json) : Option Value := do
  let t ← (j.getObjValAs? String "type").toOption
  let v ← (j.getObjValAs? String "value").toOption
  match t with
  | "i32" => some (.i32 v.toNat!.toUInt32)
  | "i64" => some (.i64 v.toNat!.toUInt64)
  | _ => none

/-- Map wast trap messages to wasmi trap codes. -/
def trapMatches (msg : String) (c : TrapCode) : Bool :=
  match c with
  | .UnreachableCodeReached => msg.startsWith "unreachable"
  | .MemoryOutOfBounds => msg.startsWith "out of bounds memory access"
  | .TableOutOfBounds => msg.startsWith "undefined element" || msg.startsWith "out of bounds table access"
  | .IndirectCallToNull => msg.startsWith "uninitialized element"
  | .IntegerDivisionByZero => msg.startsWith "integer divide by zero"
  | .IntegerOverflow => msg.startsWith "integer overflow"
  | .BadSignature => msg.startsWith "indirect call type mismatch"
  | .StackOverflow => msg.startsWith "call stack exhausted"
  | _ => false

def trapName : TrapCode → String
  | .UnreachableCodeReached => "UnreachableCodeReached" | .MemoryOutOfBounds => "MemoryOutOfBounds"
  | .TableOutOfBounds => "TableOutOfBounds" | .IndirectCallToNull => "IndirectCallToNull"
  | .IntegerDivisionByZero => "IntegerDivisionByZero" | .IntegerOverflow => "IntegerOverflow"
  | .BadConversionToInteger => "BadConversionToInteger" | .StackOverflow => "StackOverflow"
  | .BadSignature => "BadSignature" | .OutOfFuel => "OutOfFuel" | .GrowthOperationLimited => "GrowthOperationLimited"

def showVal : Value → String
  | .i32 v => s!"i32:{v.toNat}" | .i64 v => s!"i64:{v.toNat}"

def bigFuel : Fuel := { total := 1000000000000, remaining := 1000000000000 }

def run (dir : String) (jsonPath : String) (verbose : Bool := false) (fuelTrace : Bool := false) : IO Stats := do
  let txt ← IO.FS.readFile jsonPath
  let j ← IO.ofExcept (Json.parse txt)
  let cmds ← IO.ofExcept (j.getObjValAs? (Array Json) "commands")
  let mut cur : Option Loaded := none
  let mut stats : Stats := {}
  let note (s : String) : IO Unit := if verbose then IO.println s else pure ()
  for c in cmds do
    let ty := (c.getObjValAs? String "type").toOption.getD ""
    let line := (c.getObjValAs? Nat "line").toOption.getD 0
    match ty with
    | "module" =>
      cur := none
      let some fn := (c.getObjValAs? String "filename").toOption | continue
      let bytes ← IO.FS.readBinFile (dir ++ "/" ++ fn)
      match Decode.decodeModule bytes with
      | .error e => note s!"line {line}: module not decodable (skipping its asserts): {e}"
      | .ok m =>
        if m.imports.any (·.module != "spectest") then note s!"line {line}: imports a registered module, skipping"; continue
        let globals := m.importedGlobals.map fun g => match g.ty with
          | .i32 => Value.i32 666 | .i64 => Value.i64 666
        match Instantiate.instantiate host m globals () with
        | .ok (st, _) => cur := some { m, cx := Instantiate.mkCtx host m, st := { st with fuel := bigFuel } }
        | .err e => note s!"line {line}: instantiate failed: {repr e}"
        | .trap _ => note s!"line {line}: instantiate trapped"
    | "assert_malformed" | "assert_invalid" =>
      let mt := (c.getObjValAs? String "module_type").toOption.getD ""
      let fn := (c.getObjValAs? String "filename").toOption.getD ""
      if mt != "binary" then stats := { stats with skip := stats.skip + 1 }; continue
      let bytes ← IO.FS.readBinFile (dir ++ "/" ++ fn)
      match Decode.decodeModule bytes with
      | .error _ => stats := { stats with pass := stats.pass + 1 }
      | .ok _ =>
        -- decoding succeeded: a validation-only failure (validation is out of scope here)
        if ty == "assert_invalid" then stats := { stats with skip := stats.skip + 1 }
        else stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line}: malformed module decoded"
    | "assert_return" | "assert_trap" | "assert_exhaustion" | "action" =>
      let some l := cur | stats := { stats with skip := stats.skip + 1 }; continue
      let some act := (c.getObjValAs? Json "action").toOption | continue
      if (act.getObjValAs? String "type").toOption != some "invoke" ||
         (act.getObjValAs? String "module").toOption.isSome then
        stats := { stats with skip := stats.skip + 1 }; continue
      let field := (act.getObjValAs? String "field").toOption.getD ""
      let args := ((act.getObjValAs? (Array Json) "args").toOption.getD #[]).toList.map parseVal
      if args.any Option.isNone then stats := { stats with skip := stats.skip + 1 }; continue
      let some fidx := Instantiate.exportedFunc? l.m field | stats := { stats with skip := stats.skip + 1 }; continue
      let r := Exec.invoke l.cx 100000000 fidx (args.filterMap id) l.st ()
      if fuelTrace then
        match r with
        | .ok (res, st', _) => IO.println s!"{line} ok [{",".intercalate (res.map showVal)}] fuel={st'.fuel.consumed}"
        | .trap (.code tc) (st', _) => IO.println s!"{line} trap {trapName tc} fuel={st'.fuel.consumed}"
        | _ => IO.println s!"{line} other"
      match ty, r with
      | "assert_return", .ok (res, st', _) =>
        let exp := ((c.getObjValAs? (Array Json) "expected").toOption.getD #[]).toList.map parseVal
        if exp.any Option.isNone then stats := { stats with skip := stats.skip + 1 }
        else if res == exp.filterMap id then stats := { stats with pass := stats.pass + 1 }
        else stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line} {field}: got {repr res}"
        cur := some { l with st := st' }
      | "action", .ok (_, st', _) => cur := some { l with st := st' }; stats := { stats with pass := stats.pass + 1 }
      | "assert_trap", .trap (.code tc) (st', _) | "assert_exhaustion", .trap (.code tc) (st', _) =>
        cur := some { l with st := st' }
        let msg := (c.getObjValAs? String "text").toOption.getD ""
        if trapMatches msg tc then stats := { stats with pass := stats.pass + 1 }
        else stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line} {field}: trap {repr tc} vs '{msg}'"
      | _, .gasOut => stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line} {field}: gas exhausted"
      | _, .ok (res, _, _) => stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line} {field}: expected trap/exhaustion, got {repr res}"
      | _, .trap _ (st', _) => cur := some { l with st := st' }; stats := { stats with fail := stats.fail + 1 }; note s!"FAIL line {line} {field}: unexpected trap"
    | _ => stats := { stats with skip := stats.skip + 1 }
  return stats

end Wasm.SpecTest
