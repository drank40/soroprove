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
    i8 0, label %f12.exit.i.sink.split
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

f12.exit.i.sink.split:                            ; preds = %fall4
  br label %f12.exit

f12.exit:                                         ; preds = %c4, %f12.exit.i.sink.split, %fall4
  %brif.not = phi i64 [ 4294967299, %fall4 ], [ 10766, %c4 ], [ 9742, %f12.exit.i.sink.split ]
  %to_val = call %Val @soroban.val.from_payload(i64 %brif.not)
  ret %Val %to_val
}

define %Val @read(%Val %0, %Val %1) local_unnamed_addr {
entry:
  %frame.i.i.i36.i.sroa.2 = alloca [12 x i8], align 4
  %frame = alloca [16 x i8], align 8
  %frame32 = alloca [16 x i8], align 8
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not.i.not = icmp eq i64 %and, 77
  %and33 = and i64 %arg_payload1, 255
  %cmp.not.i29.not = icmp eq i64 %and33, 77
  %or.cond = select i1 %cmp.not.i.not, i1 %cmp.not.i29.not, i1 false
  br i1 %or.cond, label %fall2, label %c1

c1:                                               ; preds = %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  call void @llvm.lifetime.start.p0(i64 12, ptr nonnull %frame.i.i.i36.i.sroa.2)
  br label %c6

c6:                                               ; preds = %c8, %fall2
  %frame.i.i.i.i35.i.sroa.2.0 = phi i64 [ undef, %fall2 ], [ %frame.i.i.i.i35.i.sroa.2.1, %c8 ]
  %l4.053 = phi i64 [ 0, %fall2 ], [ %or24, %c8 ]
  %l1.052 = phi i64 [ 1048652, %fall2 ], [ %add19, %c8 ]
  %l2.051 = phi i64 [ 4, %fall2 ], [ %add37, %c8 ]
  %p = inttoptr i64 %l1.052 to ptr
  %v = load i8, ptr %p, align 1
  %zx = zext i8 %v to i64
  %cmp = icmp eq i8 %v, 95
  br i1 %cmp, label %c134, label %fall235

c134:                                             ; preds = %c7, %c4, %c3, %c6
  %l2.0 = phi i8 [ 1, %c6 ], [ %add24, %c4 ], [ %add26, %c3 ], [ %add22, %c7 ]
  %frame.i.i.i.i35.i.sroa.2.9.insert.ext = zext i8 %l2.0 to i64
  %frame.i.i.i.i35.i.sroa.2.9.insert.shift = shl nuw nsw i64 %frame.i.i.i.i35.i.sroa.2.9.insert.ext, 8
  %frame.i.i.i.i35.i.sroa.2.8.insert.insert26 = and i64 %frame.i.i.i.i35.i.sroa.2.0, -65536
  %frame.i.i.i.i35.i.sroa.2.9.insert.mask = or disjoint i64 %frame.i.i.i.i35.i.sroa.2.8.insert.insert26, %frame.i.i.i.i35.i.sroa.2.9.insert.shift
  %frame.i.i.i.i35.i.sroa.2.9.insert.insert = or disjoint i64 %frame.i.i.i.i35.i.sroa.2.9.insert.mask, 255
  br label %f47.exit

fall235:                                          ; preds = %c6
  %add = add nuw nsw i64 %zx, 208
  %and2 = and i64 %add, 254
  %cmp3 = icmp ult i64 %and2, 10
  br i1 %cmp3, label %c4, label %fall5

c3:                                               ; preds = %fall5
  %add26 = add i8 %v, -53
  br label %c134

c4:                                               ; preds = %fall235
  %add24 = add i8 %v, -46
  br label %c134

fall5:                                            ; preds = %fall235
  %add7 = add nuw nsw i64 %zx, 191
  %and8 = and i64 %add7, 254
  %cmp9 = icmp ult i64 %and8, 26
  br i1 %cmp9, label %c3, label %fall6

fall6:                                            ; preds = %fall5
  %add13 = add nuw nsw i64 %zx, 159
  %and14 = and i64 %add13, 254
  %cmp15 = icmp ult i64 %and14, 26
  br i1 %cmp15, label %c7, label %fall8

c7:                                               ; preds = %fall6
  %add22 = add i8 %v, -59
  br label %c134

fall8:                                            ; preds = %fall6
  %frame.i.i.i.i35.i.sroa.2.9.insert.shift29 = shl nuw nsw i64 %zx, 8
  %frame.i.i.i.i35.i.sroa.2.9.insert.mask30 = and i64 %frame.i.i.i.i35.i.sroa.2.0, -65536
  %frame.i.i.i.i35.i.sroa.2.9.insert.insert31 = or disjoint i64 %frame.i.i.i.i35.i.sroa.2.9.insert.mask30, %frame.i.i.i.i35.i.sroa.2.9.insert.shift29
  %frame.i.i.i.i35.i.sroa.2.8.insert.insert = or disjoint i64 %frame.i.i.i.i35.i.sroa.2.9.insert.insert31, 1
  br label %f47.exit

f47.exit:                                         ; preds = %fall8, %c134
  %frame.i.i.i.i35.i.sroa.2.1 = phi i64 [ %frame.i.i.i.i35.i.sroa.2.9.insert.insert, %c134 ], [ %frame.i.i.i.i35.i.sroa.2.8.insert.insert, %fall8 ]
  %ld22 = phi i8 [ %l2.0, %c134 ], [ %v, %fall8 ]
  %cmp936 = phi i1 [ true, %c134 ], [ false, %fall8 ]
  br i1 %cmp936, label %c8, label %fall9

fall7.loopexit:                                   ; preds = %c8
  %2 = shl i64 %or24, 8
  %3 = or disjoint i64 %2, 14
  %frame.i.i.i36.i.sroa.2.4.sroa_idx23 = getelementptr inbounds i8, ptr %frame.i.i.i36.i.sroa.2, i64 4
  store i64 %3, ptr %frame.i.i.i36.i.sroa.2.4.sroa_idx23, align 4
  br label %f46.exit

c8:                                               ; preds = %f47.exit
  %add37 = add nsw i64 %l2.051, -1
  %add19 = add nuw nsw i64 %l1.052, 1
  %shl21 = shl i64 %l4.053, 6
  %zx23 = zext i8 %ld22 to i64
  %or24 = or i64 %shl21, %zx23
  %brif2.not = icmp eq i64 %add37, 0
  br i1 %brif2.not, label %fall7.loopexit, label %c6

fall9:                                            ; preds = %f47.exit
  store i64 %frame.i.i.i.i35.i.sroa.2.1, ptr %frame.i.i.i36.i.sroa.2, align 4
  br label %f46.exit

f46.exit:                                         ; preds = %fall9, %fall7.loopexit
  br i1 %cmp936, label %c2, label %fall3

c2:                                               ; preds = %f46.exit
  %frame.i.i.i36.i.sroa.2.4.sroa_idx = getelementptr inbounds i8, ptr %frame.i.i.i36.i.sroa.2, i64 4
  %frame.i.i.i36.i.sroa.2.4.frame.i.i.i36.i.sroa.2.8.ld7 = load i64, ptr %frame.i.i.i36.i.sroa.2.4.sroa_idx, align 4
  br label %f26.exit

fall3:                                            ; preds = %f46.exit
  %v_u32_1048652 = call %Val @soroban.val.from_payload(i64 4503926044884996)
  %v_u32_4 = call %Val @soroban.val.from_payload(i64 17179869188)
  %Symbol__Pair__ = call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048652, %Val %v_u32_4)
  %payload = call i64 @soroban.val.payload(%Val %Symbol__Pair__)
  br label %f26.exit

f26.exit:                                         ; preds = %fall3, %c2
  %ld3 = phi i64 [ %frame.i.i.i36.i.sroa.2.4.frame.i.i.i36.i.sroa.2.8.ld7, %c2 ], [ %payload, %fall3 ]
  call void @llvm.lifetime.end.p0(i64 12, ptr nonnull %frame.i.i.i36.i.sroa.2)
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame32)
  %fp = ptrtoint ptr %frame32 to i64
  %fp12 = getelementptr inbounds i8, ptr %frame32, i64 8
  store i64 %arg_payload1, ptr %fp12, align 8
  store i64 %arg_payload, ptr %frame32, align 8
  %shl4 = shl i64 %fp, 32
  %or5 = or disjoint i64 %shl4, 4
  %v_u32_1048636 = call %Val @soroban.val.from_payload(i64 4503857325408260)
  %to_val9 = call %Val @soroban.val.from_payload(i64 %or5)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %Map_BAD_tag_56__BAD_tag_57_ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048636, %Val %to_val9, %Val %v_u32_2)
  %payload40 = call i64 @soroban.val.payload(%Val %Map_BAD_tag_56__BAD_tag_57_)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame32)
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame)
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 %payload40, ptr %slot8, align 8
  store i64 %ld3, ptr %frame, align 8
  %fp41 = ptrtoint ptr %frame to i64
  %shl = shl i64 %fp41, 32
  %or = or disjoint i64 %shl, 4
  %to_val42 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val42, %Val %v_u32_2)
  %payload43 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame)
  %to_val44 = call %Val @soroban.val.from_payload(i64 %payload43)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val44, i64 %Persistent)
  %payload45 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp46 = icmp eq i64 %payload45, 1
  %zext = zext i1 %cmp46 to i64
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
