; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048680

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #1

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) local_unnamed_addr #2

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.fail_with_error(%Val) local_unnamed_addr #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.has_contract_data(%Val, i64) local_unnamed_addr #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) local_unnamed_addr #5

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) local_unnamed_addr #6

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) local_unnamed_addr #7

define %Val @pick(%Val %0) local_unnamed_addr {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %cmp = icmp ult i64 %arg_payload, 21474836480
  %and = and i64 %arg_payload, 255
  %cmp2.not = icmp eq i64 %and, 4
  %or.cond = and i1 %cmp, %cmp2.not
  br i1 %or.cond, label %fall4, label %c2

c2:                                               ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall4:                                            ; preds = %entry
  %lshr = lshr i64 %arg_payload, 32
  %1 = trunc i64 %lshr to i8
  switch i8 %1, label %c4 [
    i8 0, label %f12.exit.sink.split
    i8 1, label %f12.exit
    i8 2, label %c5
    i8 3, label %c3
  ]

c3:                                               ; preds = %fall4
  call fastcc void @f50()
  unreachable

c4:                                               ; preds = %fall4
  br label %f12.exit

c5:                                               ; preds = %fall4
  call fastcc void @f37()
  call void @soroban.trap()
  unreachable

f12.exit.sink.split:                              ; preds = %fall4
  br label %f12.exit

f12.exit:                                         ; preds = %c4, %f12.exit.sink.split, %fall4
  %brif.not = phi i64 [ 4294967299, %fall4 ], [ 10766, %c4 ], [ 9742, %f12.exit.sink.split ]
  %to_val = call %Val @soroban.val.from_payload(i64 %brif.not)
  ret %Val %to_val
}

define %Val @read(%Val %0, %Val %1) local_unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  %frame73 = alloca [16 x i8], align 8
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not.not = icmp eq i64 %and, 77
  %and74 = and i64 %arg_payload1, 255
  %cmp.not.not75 = icmp eq i64 %and74, 77
  %or.cond = select i1 %cmp.not.not, i1 %cmp.not.not75, i1 false
  br i1 %or.cond, label %fall2, label %c1

c1:                                               ; preds = %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame73)
  %fp = ptrtoint ptr %frame73 to i64
  %fp12 = getelementptr inbounds i8, ptr %frame73, i64 8
  store i64 %arg_payload1, ptr %fp12, align 8
  store i64 %arg_payload, ptr %frame73, align 8
  %shl4 = shl i64 %fp, 32
  %or5 = or disjoint i64 %shl4, 4
  %v_u32_1048636 = call %Val @soroban.val.from_payload(i64 4503857325408260)
  %to_val9 = call %Val @soroban.val.from_payload(i64 %or5)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048636, %Val %to_val9, %Val %v_u32_2)
  %payload = call i64 @soroban.val.payload(%Val %Map__a____b__)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame73)
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame)
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 %payload, ptr %slot8, align 8
  store i64 1852552974, ptr %frame, align 8
  %fp77 = ptrtoint ptr %frame to i64
  %shl = shl i64 %fp77, 32
  %or = or disjoint i64 %shl, 4
  %to_val78 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val78, %Val %v_u32_2)
  %payload79 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame)
  %to_val80 = call %Val @soroban.val.from_payload(i64 %payload79)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val80, i64 %Persistent)
  %payload81 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp = icmp eq i64 %payload81, 1
  %zext = zext i1 %cmp to i64
  %to_val = call %Val @soroban.val.from_payload(i64 %zext)
  ret %Val %to_val
}

define %Val @set_flag() local_unnamed_addr {
entry:
  %v_Symbol__f__ = call %Val @soroban.val.from_payload(i64 11022)
  %v_true = call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %v_Symbol__f__, %Val %v_true, i64 %Persistent)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define internal fastcc void @f37() unnamed_addr #8 {
entry:
  %v_Error_type_0__code_1_ = tail call %Val @soroban.val.from_payload(i64 4294967299)
  %fail_with_error = tail call %Val @context.fail_with_error(%Val %v_Error_type_0__code_1_)
  ret void
}

; Function Attrs: noreturn
define internal fastcc void @f50() unnamed_addr #1 {
entry:
  tail call fastcc void @f51()
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f51() unnamed_addr #1 {
entry:
  %frame = alloca [32 x i8], align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  store i32 29, ptr %slot16, align 1
  %slot12 = getelementptr inbounds i8, ptr %frame, i64 12
  store i32 1048577, ptr %slot12, align 1
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
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #9

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #9

declare i64 @soroban.storage_type(i64)

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { noreturn }
attributes #2 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #3 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.0" "soroban.sig"="(Val, StorageType) -> Bool" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #6 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #7 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #8 = { memory(inaccessiblemem: readwrite) }
attributes #9 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }
