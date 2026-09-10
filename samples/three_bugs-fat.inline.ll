; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 1 of 17 helpers named, 0 by shape
; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048652

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @ponytail.unknown.i64() local_unnamed_addr #1

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #2

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) local_unnamed_addr #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.fail_with_error(%Val) local_unnamed_addr #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.has_contract_data(%Val, i64) local_unnamed_addr #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) local_unnamed_addr #6

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) local_unnamed_addr #7

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) local_unnamed_addr #8

define "spec.type"="bool" "wasm.type"="i64" %Val @read(%Val "spec.name"="a" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="Address" "wasm.type"="i64" %1) local_unnamed_addr #9 {
entry:
  %frame = alloca [32 x i8], align 1
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  call void @llvm.lifetime.start.p0(i64 32, ptr nonnull %frame)
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 77
  %and2 = and i64 %arg_payload1, 255
  %cmp3.not = icmp eq i64 %and2, 77
  %or.cond = select i1 %cmp.not, i1 %cmp3.not, i1 false
  br i1 %or.cond, label %fall14, label %c1

c1:                                               ; preds = %entry
  call void @soroban.trap()
  unreachable

fall15.2:                                         ; preds = %fall14
  %bottom.2 = call i64 @ponytail.unknown.i64()
  %brif20.not.2 = icmp eq i64 %bottom.2, 0
  br i1 %brif20.not.2, label %fall15.3, label %f23.exit

fall15.3:                                         ; preds = %fall15.2
  %bottom.3 = call i64 @ponytail.unknown.i64()
  %brif20.not.3 = icmp eq i64 %bottom.3, 0
  br i1 %brif20.not.3, label %f14.exit, label %f23.exit

fall14:                                           ; preds = %entry
  %bottom.1 = call i64 @ponytail.unknown.i64()
  %brif20.not.1 = icmp eq i64 %bottom.1, 0
  br i1 %brif20.not.1, label %fall15.2, label %f23.exit

f23.exit:                                         ; preds = %fall15.3, %fall15.2, %fall14
  %v_u32_1048640 = call %Val @soroban.val.from_payload(i64 4503874505277444)
  %v_u32_4 = call %Val @soroban.val.from_payload(i64 17179869188)
  %Symbol__Pair__ = call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048640, %Val %v_u32_4)
  %payload = call i64 @soroban.val.payload(%Val %Symbol__Pair__)
  br label %f14.exit

f14.exit:                                         ; preds = %fall15.3, %f23.exit
  %ld11 = phi i64 [ %payload, %f23.exit ], [ 1852552974, %fall15.3 ]
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  %fp11 = getelementptr inbounds i8, ptr %frame, i64 16
  %fp = ptrtoint ptr %slot8 to i64
  store i64 %arg_payload1, ptr %fp11, align 1
  store i64 %arg_payload, ptr %slot8, align 1
  %shl4 = shl i64 %fp, 32
  %or5 = or disjoint i64 %shl4, 4
  %v_u32_1048624 = call %Val @soroban.val.from_payload(i64 4503805785800708)
  %to_val9 = call %Val @soroban.val.from_payload(i64 %or5)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %pair_key = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048624, %Val %to_val9, %Val %v_u32_2)
  %payload14 = call i64 @soroban.val.payload(%Val %pair_key)
  store i64 %payload14, ptr %fp11, align 1
  store i64 %ld11, ptr %slot8, align 1
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val9, %Val %v_u32_2)
  %payload15 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val16 = call %Val @soroban.val.from_payload(i64 %payload15)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val16, i64 %Persistent)
  %payload17 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp = icmp eq i64 %payload17, 1
  %zext = zext i1 %cmp to i64
  call void @llvm.lifetime.end.p0(i64 32, ptr nonnull %frame)
  %to_val = call %Val @soroban.val.from_payload(i64 %zext)
  ret %Val %to_val
}

define "spec.type"="Result<Symbol, Error>" "wasm.type"="i64" %Val @pick(%Val "spec.name"="f" "spec.type"="Flag" "wasm.type"="i64" %0) local_unnamed_addr #10 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp ne i64 %and, 4
  %cmp2 = icmp ugt i64 %arg_payload, 21474836479
  %or.cond = or i1 %cmp2, %cmp.not
  br i1 %or.cond, label %c6, label %fall8

c1:                                               ; preds = %c2, %c3, %fall8
  %l0.0 = phi i64 [ 9742, %c2 ], [ 4294967299, %fall8 ], [ 10766, %c3 ]
  %to_val = tail call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val

c2:                                               ; preds = %fall8
  br label %c1

c3:                                               ; preds = %fall8
  br label %c1

c4:                                               ; preds = %fall8
  tail call fastcc void @f24()
  unreachable

c5:                                               ; preds = %fall8
  tail call fastcc void @f15()
  tail call void @soroban.trap()
  unreachable

c6:                                               ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall8:                                            ; preds = %entry
  %lshr = lshr i64 %arg_payload, 32
  %sel = trunc i64 %lshr to i32
  switch i32 %sel, label %c2 [
    i32 4, label %c3
    i32 1, label %c1
    i32 2, label %c5
    i32 3, label %c4
  ]
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define "wasm.type"="i64" %Val @set_flag() local_unnamed_addr #11 {
entry:
  %v_Symbol__f__ = tail call %Val @soroban.val.from_payload(i64 11022)
  %v_true = tail call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = tail call %Val @ledger.put_contract_data(%Val %v_Symbol__f__, %Val %v_true, i64 %Persistent)
  %v_void = tail call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define internal fastcc "wasm.type"="i64" void @f15() unnamed_addr #1 {
entry:
  %v_Error_type_0__code_1_ = tail call %Val @soroban.val.from_payload(i64 4294967299)
  %fail_with_error = tail call %Val @context.fail_with_error(%Val %v_Error_type_0__code_1_)
  ret void
}

; Function Attrs: noreturn
define internal fastcc void @f24() unnamed_addr #2 {
entry:
  tail call fastcc void @f25()
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f25() unnamed_addr #2 {
entry:
  %frame = alloca [32 x i8], align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  store i32 29, ptr %slot16, align 1
  %slot12 = getelementptr inbounds i8, ptr %frame, i64 12
  store i32 1048576, ptr %slot12, align 1
  %slot28 = getelementptr inbounds i8, ptr %frame, i64 28
  store i16 1, ptr %slot28, align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i64 24
  store i32 1048604, ptr %slot24, align 1
  %fp = ptrtoint ptr %slot12 to i64
  %slot20 = getelementptr inbounds i8, ptr %frame, i64 20
  %t6 = trunc i64 %fp to i32
  store i32 %t6, ptr %slot20, align 1
  call void @soroban.trap()
  unreachable
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #12

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #12

declare i64 @soroban.storage_type(i64)

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { memory(inaccessiblemem: readwrite) }
attributes #2 = { noreturn }
attributes #3 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.0" "soroban.sig"="(Val, StorageType) -> Bool" }
attributes #6 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #7 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #8 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #9 = { "spec.sig"="fn read(a: Address, b: Address) -> bool" }
attributes #10 = { "spec.sig"="fn pick(f: Flag) -> Result<Symbol, Error>" }
attributes #11 = { memory(inaccessiblemem: readwrite) "spec.sig"="fn set_flag()" }
attributes #12 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!soroban.spec = !{!0, !1, !2, !3, !4, !5, !6}
!soroban.keys = !{!7}
!soroban.strings = !{!8}
!soroban.rodata = !{!9}

!0 = !{!"enum Flag { A = 0, B = 1, C = 2, D = 3, E = 4 }"}
!1 = !{!"error Error { AnError = 1 }"}
!2 = !{!"union DataKey { Pair(PairKey), Single(Address) }"}
!3 = !{!"struct PairKey { a: Address, b: Address }"}
!4 = !{!"fn pick(f: Flag) -> Result<Symbol, Error>"}
!5 = !{!"fn read(a: Address, b: Address) -> bool"}
!6 = !{!"fn set_flag()"}
!7 = !{!"1048624 a b"}
!8 = !{!"1048640 Pair"}
!9 = !{!"1048576 6578706c696369742070616e69637372632f6c69622e7273000000000e0010000a0000003c0000000d000000616200002c001000010000002d00100001000000506169724000100004000000"}
