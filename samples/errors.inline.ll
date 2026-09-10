; sdk 26.0.1 rustc 1.95.0; fingerprints 26.0.1+rustc1.95.0.txt: 2 of 2 helpers named, 0 by shape
; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048604
@g2 = local_unnamed_addr constant i64 1048604
@g3 = local_unnamed_addr constant i64 1048608

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.storage_type(i64) local_unnamed_addr #0

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #1

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.fail_with_error(%Val) local_unnamed_addr #2

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) local_unnamed_addr #3

define "spec.type"="Result<Symbol, Error>" "wasm.type"="i64" %Val @hello(%Val "spec.name"="flag" "spec.type"="Flag" "wasm.type"="i64" %0) local_unnamed_addr #4 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %cmp = icmp ult i64 %arg_payload, 21474836480
  %and = and i64 %arg_payload, 255
  %cmp2.not = icmp eq i64 %and, 4
  %or.cond = and i1 %cmp, %cmp2.not
  br i1 %or.cond, label %fall4, label %c1

c1:                                               ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall4:                                            ; preds = %entry
  %lshr = lshr i64 %arg_payload, 32
  %v_Symbol__persisted__ = tail call %Val @soroban.val.from_payload(i64 3867323444879862030)
  %v_true = tail call %Val @soroban.val.from_payload(i64 1)
  %Persistent = tail call i64 @soroban.storage_type(i64 1)
  %put_contract_data = tail call %Val @ledger.put_contract_data(%Val %v_Symbol__persisted__, %Val %v_true, i64 %Persistent)
  %sel = trunc i64 %lshr to i32
  switch i32 %sel, label %c7 [
    i32 0, label %c6
    i32 1, label %c5
    i32 2, label %c9
    i32 3, label %c8
  ]

c5:                                               ; preds = %c6, %fall4
  %l0.0 = phi i64 [ 4294967299, %fall4 ], [ 196144296974, %c6 ]
  %to_val = tail call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val

c6:                                               ; preds = %fall4
  br label %c5

c7:                                               ; preds = %fall4
  tail call fastcc void @Env_fail_with_error(i64 38654705667)
  tail call void @soroban.trap()
  unreachable

c8:                                               ; preds = %fall4
  tail call fastcc void @panic_fmt()
  unreachable

c9:                                               ; preds = %fall4
  tail call fastcc void @Env_fail_with_error(i64 4294967299)
  tail call void @soroban.trap()
  unreachable
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define internal fastcc void @Env_fail_with_error(i64 "wasm.type"="i64" %0) unnamed_addr #5 {
entry:
  %to_val = tail call %Val @soroban.val.from_payload(i64 %0)
  %fail_with_error = tail call %Val @context.fail_with_error(%Val %to_val)
  ret void
}

; Function Attrs: noreturn
define internal fastcc void @panic_fmt() unnamed_addr #6 {
entry:
  tail call void @soroban.trap()
  unreachable
}

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { noreturn }
attributes #2 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #3 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #4 = { "spec.sig"="fn hello(flag: Flag) -> Result<Symbol, Error>" }
attributes #5 = { memory(inaccessiblemem: readwrite) "sdk.name"="<soroban_sdk::env::Env as soroban_env_common::env::Env>::fail_with_error" }
attributes #6 = { noreturn "sdk.name"="core::panicking::panic_fmt" }

!soroban.spec = !{!0, !1, !2}
!soroban.rodata = !{!3}

!0 = !{!"enum Flag { A = 0, B = 1, C = 2, D = 3, E = 4 }"}
!1 = !{!"error Error { AnError = 1 }"}
!2 = !{!"fn hello(flag: Flag) -> Result<Symbol, Error>"}
!3 = !{!"1048576 53704563563167198dc68a50ebb7537045635631bc0404eaa49e3628"}
