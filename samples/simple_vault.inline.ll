; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 5 of 78 helpers named, 4 by shape
; ModuleID = 'diver'
source_filename = "diver"
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048856

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #1

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @address.require_auth(%Val) local_unnamed_addr #2

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) local_unnamed_addr #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @call.call(%Val, %Val, %Val) local_unnamed_addr #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.get_current_contract_address() local_unnamed_addr #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @int.obj_from_i128_pieces(i64, i64) local_unnamed_addr #6

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @int.obj_to_i128_hi64(%Val) local_unnamed_addr #7

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @int.obj_to_i128_lo64(%Val) local_unnamed_addr #8

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.get_contract_data(%Val, i64) local_unnamed_addr #9

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.has_contract_data(%Val, i64) local_unnamed_addr #10

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) local_unnamed_addr #11

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) local_unnamed_addr #12

define "wasm.type"="i64" %Val @__constructor(%Val "spec.name"="token" "spec.type"="Address" "wasm.type"="i64" %0) local_unnamed_addr #13 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %and = and i64 %arg_payload, 255
  %cmp.not.not = icmp eq i64 %and, 77
  br i1 %cmp.not.not, label %f27.exit, label %fall2.critedge

fall2.critedge:                                   ; preds = %entry
  tail call void @soroban.trap()
  unreachable

f27.exit:                                         ; preds = %entry
  %lc = call fastcc i64 @f12(i64 1048584)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %lc)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %arg_payload)
  %Instance = call i64 @soroban.storage_type(i64 2)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val1, %Val %to_val3, i64 %Instance)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define "spec.type"="i128" "wasm.type"="i64" %Val @balance(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0) local_unnamed_addr #14 {
entry:
  %frame = alloca [16 x i8], align 8
  %frame1 = alloca [64 x i8], align 8
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %and = and i64 %arg_payload, 255
  %cmp.not.not = icmp eq i64 %and, 77
  br i1 %cmp.not.not, label %f20.exit, label %fall2.critedge

fall2.critedge:                                   ; preds = %entry
  tail call void @soroban.trap()
  unreachable

f20.exit:                                         ; preds = %entry
  call void @llvm.lifetime.start.p0(i64 64, ptr nonnull %frame1)
  store i64 1, ptr %frame1, align 8
  %slot8 = getelementptr inbounds i8, ptr %frame1, i32 8
  store i64 %arg_payload, ptr %slot8, align 8
  %slot16 = getelementptr inbounds i8, ptr %frame1, i32 16
  %1 = ptrtoint ptr %slot16 to i32
  %fp1 = zext i32 %1 to i64
  %2 = ptrtoint ptr %frame1 to i32
  %fp4 = zext i32 %2 to i64
  call fastcc void @f11(i64 %fp1, i64 %fp4)
  %slot32 = getelementptr inbounds i8, ptr %frame1, i32 32
  %ld = load i64, ptr %slot32, align 8
  %slot40 = getelementptr inbounds i8, ptr %frame1, i32 40
  %ld6 = load i64, ptr %slot40, align 8
  %ld8 = load i32, ptr %slot16, align 8
  %and2 = and i32 %ld8, 1
  %sel.not = icmp eq i32 %and2, 0
  %select = select i1 %sel.not, i64 0, i64 %ld6
  %select15 = select i1 %sel.not, i64 0, i64 %ld
  call void @llvm.lifetime.end.p0(i64 64, ptr nonnull %frame1)
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame)
  %slot83 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %select, ptr %slot83, align 8
  store i64 %select15, ptr %frame, align 8
  %3 = ptrtoint ptr %frame to i32
  %fp = zext i32 %3 to i64
  %lc = call fastcc i64 @f62(i64 %fp)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define "wasm.type"="i64" %Val @deposit(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="amount" "spec.type"="i128" "wasm.type"="i64" %1) local_unnamed_addr #15 {
entry:
  %frame = alloca [112 x i8], align 1
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not.not = icmp eq i64 %and, 77
  br i1 %cmp.not.not, label %fall2, label %c1

fall2:                                            ; preds = %entry
  %t = trunc i64 %arg_payload1 to i8
  switch i8 %t, label %c1 [
    i8 69, label %c4
    i8 11, label %fall6
  ]

c1:                                               ; preds = %fall2, %entry
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %fall2
  %to_val7 = call %Val @soroban.val.from_payload(i64 %arg_payload1)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val7)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val7)
  br label %f34.exit

fall6:                                            ; preds = %fall2
  %ashr = ashr i64 %arg_payload1, 63
  %ashr4 = ashr i64 %arg_payload1, 8
  br label %f34.exit

f34.exit:                                         ; preds = %fall6, %c4
  %ld19 = phi i64 [ %ashr, %fall6 ], [ %obj_to_i128_hi64, %c4 ]
  %ashr4.sink = phi i64 [ %ashr4, %fall6 ], [ %obj_to_i128_lo64, %c4 ]
  call void @llvm.lifetime.start.p0(i64 112, ptr nonnull %frame)
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %ld19, ptr %slot24, align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 %ashr4.sink, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %arg_payload, ptr %slot8, align 1
  %to_val8 = call %Val @soroban.val.from_payload(i64 %arg_payload)
  %require_auth = call %Val @address.require_auth(%Val %to_val8)
  %slot64 = getelementptr inbounds i8, ptr %frame, i32 64
  %2 = ptrtoint ptr %slot64 to i32
  %fp5 = zext i32 %2 to i64
  call fastcc void @f15(i64 %fp5)
  %ld = load i32, ptr %slot64, align 1
  %eqz = icmp eq i32 %ld, 0
  br i1 %eqz, label %c2, label %fall3

c2:                                               ; preds = %f34.exit
  call fastcc void @f88(i64 1048712)
  unreachable

fall3:                                            ; preds = %f34.exit
  %3 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %3 to i64
  %slot72 = getelementptr inbounds i8, ptr %frame, i32 72
  %ld9 = load i64, ptr %slot72, align 1
  %slot40 = getelementptr inbounds i8, ptr %frame, i32 40
  store i64 %ld9, ptr %slot40, align 1
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 %ld9, ptr %slot48, align 1
  %get_current_contract_address = call %Val @context.get_current_contract_address()
  %payload = call i64 @soroban.val.payload(%Val %get_current_contract_address)
  store i64 %payload, ptr %slot64, align 1
  %4 = ptrtoint ptr %slot48 to i32
  %fp19 = zext i32 %4 to i64
  %5 = ptrtoint ptr %slot16 to i32
  %fp25 = zext i32 %5 to i64
  call fastcc void @f18(i64 %fp19, i64 %fp, i64 %fp5, i64 %fp25)
  store i64 1, ptr %slot48, align 1
  %slot56 = getelementptr inbounds i8, ptr %frame, i32 56
  store i64 %arg_payload, ptr %slot56, align 1
  call fastcc void @f11(i64 %fp5, i64 %fp19)
  %ld37 = load i32, ptr %slot64, align 1
  %slot80 = getelementptr inbounds i8, ptr %frame, i32 80
  %ld39 = load i64, ptr %slot80, align 1
  %slot88 = getelementptr inbounds i8, ptr %frame, i32 88
  %ld40 = load i64, ptr %slot88, align 1
  %and9 = and i32 %ld37, 1
  %sel.not = icmp eq i32 %and9, 0
  %select = select i1 %sel.not, i64 0, i64 %ld40
  %6 = xor i64 %ld19, %select
  %xor48 = xor i64 %6, -1
  %add = add i64 %select, %ld19
  %select56 = select i1 %sel.not, i64 0, i64 %ld39
  %add58 = add i64 %select56, %ashr4.sink
  %cmp = icmp ult i64 %add58, %select56
  %z62 = zext i1 %cmp to i64
  %add63 = add i64 %add, %z62
  %xor64 = xor i64 %add63, %select
  %and65 = and i64 %xor64, %xor48
  %cmp66 = icmp sgt i64 %and65, -1
  br i1 %cmp66, label %f23.exit, label %fall4

fall4:                                            ; preds = %fall3
  call fastcc void @f91()
  unreachable

f23.exit:                                         ; preds = %fall3
  store i64 %add58, ptr %slot64, align 1
  store i64 %add63, ptr %slot72, align 1
  %lc = call fastcc i64 @f12(i64 %fp19)
  %lc5 = call fastcc i64 @f62(i64 %fp5)
  %to_val10 = call %Val @soroban.val.from_payload(i64 %lc)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %lc5)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val10, %Val %to_val3, i64 %Persistent)
  call void @llvm.lifetime.end.p0(i64 112, ptr nonnull %frame)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define "wasm.type"="i64" %Val @withdraw(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="amount" "spec.type"="i128" "wasm.type"="i64" %1) local_unnamed_addr #16 {
entry:
  %frame = alloca [112 x i8], align 1
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not.not = icmp eq i64 %and, 77
  br i1 %cmp.not.not, label %fall2, label %c1

fall2:                                            ; preds = %entry
  %t = trunc i64 %arg_payload1 to i8
  switch i8 %t, label %c1 [
    i8 69, label %c4
    i8 11, label %fall6
  ]

c1:                                               ; preds = %fall2, %entry
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %fall2
  %to_val7 = call %Val @soroban.val.from_payload(i64 %arg_payload1)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val7)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val7)
  br label %f34.exit

fall6:                                            ; preds = %fall2
  %ashr = ashr i64 %arg_payload1, 63
  %ashr4 = ashr i64 %arg_payload1, 8
  br label %f34.exit

f34.exit:                                         ; preds = %fall6, %c4
  %ld19 = phi i64 [ %ashr, %fall6 ], [ %obj_to_i128_hi64, %c4 ]
  %ashr4.sink = phi i64 [ %ashr4, %fall6 ], [ %obj_to_i128_lo64, %c4 ]
  call void @llvm.lifetime.start.p0(i64 112, ptr nonnull %frame)
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %ld19, ptr %slot24, align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 %ashr4.sink, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %arg_payload, ptr %slot8, align 1
  %to_val8 = call %Val @soroban.val.from_payload(i64 %arg_payload)
  %require_auth = call %Val @address.require_auth(%Val %to_val8)
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 1, ptr %slot32, align 1
  %slot40 = getelementptr inbounds i8, ptr %frame, i32 40
  store i64 %arg_payload, ptr %slot40, align 1
  %slot64 = getelementptr inbounds i8, ptr %frame, i32 64
  %2 = ptrtoint ptr %slot64 to i32
  %fp6 = zext i32 %2 to i64
  %3 = ptrtoint ptr %slot32 to i32
  %fp10 = zext i32 %3 to i64
  call fastcc void @f11(i64 %fp6, i64 %fp10)
  %slot80 = getelementptr inbounds i8, ptr %frame, i32 80
  %ld = load i64, ptr %slot80, align 1
  %ld12 = load i32, ptr %slot64, align 1
  %and9 = and i32 %ld12, 1
  %sel.not = icmp eq i32 %and9, 0
  %select = select i1 %sel.not, i64 0, i64 %ld
  %cmp = icmp ult i64 %select, %ashr4.sink
  %slot88 = getelementptr inbounds i8, ptr %frame, i32 88
  %ld15 = load i64, ptr %slot88, align 1
  %select19 = select i1 %sel.not, i64 0, i64 %ld15
  %cmp21 = icmp slt i64 %select19, %ld19
  %cmp25 = icmp eq i64 %select19, %ld19
  %select29.v = select i1 %cmp25, i1 %cmp, i1 %cmp21
  br i1 %select29.v, label %c2, label %fall3

c110:                                             ; preds = %fall5
  call fastcc void @f88(i64 1048808)
  unreachable

c2:                                               ; preds = %f34.exit
  call fastcc void @f82(i64 1048744, i64 31, i64 1048776)
  unreachable

fall3:                                            ; preds = %f34.exit
  %xor = xor i64 %select19, %ld19
  %sub = sub i64 %select19, %ld19
  %z44.neg = sext i1 %cmp to i64
  %sub45 = add i64 %sub, %z44.neg
  %xor46 = xor i64 %sub45, %select19
  %and47 = and i64 %xor46, %xor
  %cmp48 = icmp slt i64 %and47, 0
  br i1 %cmp48, label %c411, label %fall5

c411:                                             ; preds = %fall3
  call fastcc void @f92()
  unreachable

fall5:                                            ; preds = %fall3
  %sub53 = sub i64 %select, %ashr4.sink
  store i64 %sub53, ptr %slot64, align 1
  %slot72 = getelementptr inbounds i8, ptr %frame, i32 72
  store i64 %sub45, ptr %slot72, align 1
  %lc = call fastcc i64 @f12(i64 %fp10)
  %lc5 = call fastcc i64 @f62(i64 %fp6)
  %to_val12 = call %Val @soroban.val.from_payload(i64 %lc)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %lc5)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val12, %Val %to_val3, i64 %Persistent)
  call fastcc void @f15(i64 %fp6)
  %ld69 = load i32, ptr %slot64, align 1
  %eqz72 = icmp eq i32 %ld69, 0
  br i1 %eqz72, label %c110, label %f25.exit

f25.exit:                                         ; preds = %fall5
  %4 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %4 to i64
  %ld76 = load i64, ptr %slot72, align 1
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 %ld76, ptr %slot48, align 1
  %slot56 = getelementptr inbounds i8, ptr %frame, i32 56
  store i64 %ld76, ptr %slot56, align 1
  %get_current_contract_address = call %Val @context.get_current_contract_address()
  %payload = call i64 @soroban.val.payload(%Val %get_current_contract_address)
  store i64 %payload, ptr %slot64, align 1
  %5 = ptrtoint ptr %slot56 to i32
  %fp86 = zext i32 %5 to i64
  %6 = ptrtoint ptr %slot16 to i32
  %fp92 = zext i32 %6 to i64
  call fastcc void @f18(i64 %fp86, i64 %fp6, i64 %fp, i64 %fp92)
  call void @llvm.lifetime.end.p0(i64 112, ptr nonnull %frame)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define internal fastcc void @f11(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %lc = tail call fastcc i64 @f12(i64 %1)
  %to_val = tail call %Val @soroban.val.from_payload(i64 %lc)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = tail call %Val @ledger.has_contract_data(%Val %to_val, i64 %Persistent)
  %payload = tail call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp.not = icmp eq i64 %payload, 1
  br i1 %cmp.not, label %c3, label %fall4

c2:                                               ; preds = %f34.exit, %fall4
  %.sink = phi i32 [ %5, %f34.exit ], [ %6, %fall4 ]
  %ld14.sink = phi i64 [ %obj_to_i128_lo64.sink, %f34.exit ], [ 0, %fall4 ]
  %p = inttoptr i32 %.sink to ptr
  store i64 %ld14.sink, ptr %p, align 1
  ret void

c3:                                               ; preds = %entry
  %Persistent13 = call i64 @soroban.storage_type(i64 1)
  %get_contract_data = tail call %Val @ledger.get_contract_data(%Val %to_val, i64 %Persistent13)
  %payload6 = tail call i64 @soroban.val.payload(%Val %get_contract_data)
  %t = trunc i64 %payload6 to i8
  switch i8 %t, label %c27 [
    i8 69, label %c4
    i8 11, label %fall6
  ]

c27:                                              ; preds = %c3
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %c3
  %to_val8 = call %Val @soroban.val.from_payload(i64 %payload6)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val8)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val8)
  br label %f34.exit

fall6:                                            ; preds = %c3
  %ashr = ashr i64 %payload6, 63
  %ashr4 = ashr i64 %payload6, 8
  br label %f34.exit

f34.exit:                                         ; preds = %c4, %fall6
  %ld15 = phi i64 [ %obj_to_i128_hi64, %c4 ], [ %ashr, %fall6 ]
  %obj_to_i128_lo64.sink = phi i64 [ %obj_to_i128_lo64, %c4 ], [ %ashr4, %fall6 ]
  %2 = trunc i64 %0 to i32
  %3 = add i32 %2, 8
  %p9 = inttoptr i32 %3 to ptr
  store i64 0, ptr %p9, align 1
  %p10 = inttoptr i32 %2 to ptr
  store i64 1, ptr %p10, align 1
  %4 = add i32 %2, 24
  %p11 = inttoptr i32 %4 to ptr
  store i64 %ld15, ptr %p11, align 1
  %5 = add i32 %2, 16
  br label %c2

fall4:                                            ; preds = %entry
  %6 = trunc i64 %0 to i32
  %7 = add i32 %6, 8
  %p12 = inttoptr i32 %7 to ptr
  store i64 0, ptr %p12, align 1
  br label %c2
}

define internal fastcc "wasm.type"="i64" i64 @f12(i64 "wasm.type"="i32" %0) unnamed_addr {
entry:
  %frame6 = alloca [16 x i8], align 8
  %frame7 = alloca [16 x i8], align 8
  %frame = alloca [48 x i8], align 1
  %1 = trunc i64 %0 to i32
  %p = inttoptr i32 %1 to ptr
  %v = load i64, ptr %p, align 1
  %cmp.not = icmp eq i64 %v, 1
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  %2 = ptrtoint ptr %slot32 to i32
  %fp = zext i32 %2 to i64
  br i1 %cmp.not, label %fall5, label %c4

c2:                                               ; preds = %c4, %fall5
  call void @soroban.trap()
  unreachable

c3:                                               ; preds = %fall8, %fall6
  %ld45 = phi i64 [ %payload18, %fall8 ], [ %payload, %fall6 ]
  ret i64 %ld45

c4:                                               ; preds = %entry
  call fastcc void @Symbol_try_from_val(i64 %fp, i64 1048832)
  %ld28 = load i64, ptr %slot32, align 1
  %cmp29 = icmp eq i64 %ld28, 1
  br i1 %cmp29, label %c2, label %fall8

fall5:                                            ; preds = %entry
  call fastcc void @Symbol_try_from_val(i64 %fp, i64 1048848)
  %ld3 = load i32, ptr %slot32, align 1
  %brif4.not = icmp eq i32 %ld3, 0
  br i1 %brif4.not, label %fall6, label %c2

fall6:                                            ; preds = %fall5
  %slot40 = getelementptr inbounds i8, ptr %frame, i32 40
  %ld5 = load i64, ptr %slot40, align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %ld5, ptr %slot24, align 1
  store i64 0, ptr %slot32, align 1
  %3 = add i32 %1, 8
  %p8 = inttoptr i32 %3 to ptr
  %v9 = load i64, ptr %p8, align 1
  store i64 %v9, ptr %slot40, align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 %v9, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %ld5, ptr %slot8, align 1
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame7)
  %slot810 = getelementptr inbounds i8, ptr %frame7, i32 8
  store i64 %v9, ptr %slot810, align 8
  store i64 %ld5, ptr %frame7, align 8
  %4 = ptrtoint ptr %frame7 to i32
  %fp11 = zext i32 %4 to i64
  %z = shl nuw i64 %fp11, 32
  %or = or disjoint i64 %z, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %v_u32_2)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame7)
  br label %c3

fall8:                                            ; preds = %c4
  %slot4032 = getelementptr inbounds i8, ptr %frame, i32 40
  %ld33 = load i64, ptr %slot4032, align 1
  %slot834 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %ld33, ptr %slot834, align 1
  %slot2438 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %ld33, ptr %slot2438, align 1
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame6)
  %fp3 = getelementptr inbounds i8, ptr %frame6, i32 8
  store i64 %ld33, ptr %fp3, align 8
  %5 = ptrtoint ptr %frame6 to i32
  %fp12 = zext i32 %5 to i64
  store i64 %ld33, ptr %frame6, align 8
  %z13 = shl nuw i64 %fp12, 32
  %or14 = or disjoint i64 %z13, 4
  %to_val15 = call %Val @soroban.val.from_payload(i64 %or14)
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory17 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val15, %Val %v_u32_1)
  %payload18 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory17)
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame6)
  br label %c3
}

define internal fastcc void @f15(i64 "wasm.type"="i32" %0) unnamed_addr {
entry:
  %lc = tail call fastcc i64 @f12(i64 1048584)
  %to_val = tail call %Val @soroban.val.from_payload(i64 %lc)
  %Instance = call i64 @soroban.storage_type(i64 2)
  %has_contract_data = tail call %Val @ledger.has_contract_data(%Val %to_val, i64 %Instance)
  %payload = tail call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp.not = icmp eq i64 %payload, 1
  br i1 %cmp.not, label %c3, label %fall4

c1.critedge:                                      ; preds = %c3
  tail call void @soroban.trap()
  unreachable

c2:                                               ; preds = %fall2, %fall4
  %.sink = phi i32 [ %2, %fall2 ], [ %3, %fall4 ]
  %ld13.sink = phi i64 [ %payload1, %fall2 ], [ 0, %fall4 ]
  %p = inttoptr i32 %.sink to ptr
  store i64 %ld13.sink, ptr %p, align 1
  ret void

c3:                                               ; preds = %entry
  %Instance3 = call i64 @soroban.storage_type(i64 2)
  %get_contract_data = tail call %Val @ledger.get_contract_data(%Val %to_val, i64 %Instance3)
  %payload1 = tail call i64 @soroban.val.payload(%Val %get_contract_data)
  %and = and i64 %payload1, 255
  %cmp.not.not = icmp eq i64 %and, 77
  br i1 %cmp.not.not, label %fall2, label %c1.critedge

fall2:                                            ; preds = %c3
  %1 = trunc i64 %0 to i32
  %p2 = inttoptr i32 %1 to ptr
  store i64 1, ptr %p2, align 1
  %2 = add i32 %1, 8
  br label %c2

fall4:                                            ; preds = %entry
  %3 = trunc i64 %0 to i32
  br label %c2
}

define internal fastcc void @f18(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3) unnamed_addr {
entry:
  %frame131 = alloca [16 x i8], align 1
  %frame = alloca [96 x i8], align 1
  %4 = trunc i64 %1 to i32
  %p = inttoptr i32 %4 to ptr
  %v = load i64, ptr %p, align 1
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 0, ptr %slot32, align 1
  %5 = trunc i64 %2 to i32
  %p132 = inttoptr i32 %5 to ptr
  %v133 = load i64, ptr %p132, align 1
  %fp = getelementptr inbounds i8, ptr %frame, i32 40
  store i64 %v133, ptr %fp, align 1
  %6 = ptrtoint ptr %slot32 to i32
  %lc9 = call fastcc i64 @f62(i64 %3)
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %lc9, ptr %slot24, align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 %v133, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %v, ptr %slot8, align 1
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 2, ptr %slot48, align 1
  %fp124 = getelementptr inbounds i8, ptr %frame, i32 56
  store i64 2, ptr %fp124, align 1
  %fp125 = getelementptr inbounds i8, ptr %frame, i32 64
  store i64 2, ptr %fp125, align 1
  %slot72 = getelementptr inbounds i8, ptr %frame, i32 72
  %7 = ptrtoint ptr %slot72 to i32
  %8 = ptrtoint ptr %slot48 to i32
  %9 = ptrtoint ptr %slot8 to i32
  %fp126 = getelementptr inbounds i8, ptr %frame, i32 88
  store i32 0, ptr %fp126, align 1
  %fp127 = getelementptr inbounds i8, ptr %frame, i32 84
  store i32 %6, ptr %fp127, align 1
  %fp128 = getelementptr inbounds i8, ptr %frame, i32 80
  store i32 %9, ptr %fp128, align 1
  %fp129 = getelementptr inbounds i8, ptr %frame, i32 76
  store i32 %7, ptr %fp129, align 1
  store i32 %8, ptr %slot72, align 1
  %fp130 = getelementptr inbounds i8, ptr %frame, i32 92
  store i32 3, ptr %fp130, align 1
  br label %fall8.prol

fall8.prol:                                       ; preds = %entry, %fall8.prol
  %l2.0.in121.prol = phi i32 [ %add76.prol, %fall8.prol ], [ %9, %entry ]
  %l3.0.in120.prol = phi i32 [ %add80.prol, %fall8.prol ], [ %8, %entry ]
  %prol.iter = phi i32 [ %prol.iter.next, %fall8.prol ], [ 0, %entry ]
  %p.prol = inttoptr i32 %l2.0.in121.prol to ptr
  %v.prol = load i64, ptr %p.prol, align 1
  %p.prol134 = inttoptr i32 %l3.0.in120.prol to ptr
  store i64 %v.prol, ptr %p.prol134, align 1
  %add76.prol = add nuw i32 %l2.0.in121.prol, 8
  %add80.prol = add nuw i32 %l3.0.in120.prol, 8
  %prol.iter.next = add nuw nsw i32 %prol.iter, 1
  %prol.iter.cmp.not = icmp eq i32 %prol.iter.next, 3
  br i1 %prol.iter.cmp.not, label %c5, label %fall8.prol, !llvm.loop !6

c5:                                               ; preds = %fall8.prol
  %fp26 = zext i32 %8 to i64
  %z = shl nuw i64 %fp26, 32
  %or = or disjoint i64 %z, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_3 = call %Val @soroban.val.from_payload(i64 12884901892)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %v_u32_3)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  call void @llvm.lifetime.start.p0(i64 16, ptr nonnull %frame131)
  %10 = trunc i64 %0 to i32
  %p135 = inttoptr i32 %10 to ptr
  %v136 = load i64, ptr %p135, align 1
  %to_val137 = call %Val @soroban.val.from_payload(i64 %v136)
  %v_Symbol__transfer__ = call %Val @soroban.val.from_payload(i64 65154533130155790)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %payload)
  %call = call %Val @call.call(%Val %to_val137, %Val %v_Symbol__transfer__, %Val %to_val4)
  %payload138 = call i64 @soroban.val.payload(%Val %call)
  %and = and i64 %payload138, 255
  %cmp = icmp eq i64 %and, 2
  br i1 %cmp, label %f35.exit, label %fall2

fall2:                                            ; preds = %c5
  %slot15 = getelementptr inbounds i8, ptr %frame131, i32 15
  %11 = ptrtoint ptr %slot15 to i32
  %fp139 = zext i32 %11 to i64
  call fastcc void @f89(i64 %fp139)
  unreachable

f35.exit:                                         ; preds = %c5
  call void @llvm.lifetime.end.p0(i64 16, ptr nonnull %frame131)
  ret void
}

; Function Attrs: noinline noreturn
define internal fastcc void @panic_fmt() unnamed_addr #17 {
entry:
  tail call void @soroban.trap()
  unreachable
}

define internal fastcc void @Symbol_try_from_val(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr #18 {
entry:
  %frame.sroa.2 = alloca [12 x i8], align 4
  %2 = trunc i64 %1 to i32
  %p = inttoptr i32 %2 to ptr
  %v = load i64, ptr %p, align 1
  call void @llvm.lifetime.start.p0(i64 12, ptr nonnull %frame.sroa.2)
  %zx = and i64 %v, 4294967295
  %3 = lshr i64 %v, 32
  %4 = trunc i64 %3 to i32
  %cmp = icmp ugt i32 %4, 9
  br i1 %cmp, label %c2, label %h4.preheader

h4.preheader:                                     ; preds = %entry
  %brif2.not55 = icmp eq i32 %4, 0
  br i1 %brif2.not55, label %fall7, label %c6.preheader

c6.preheader:                                     ; preds = %h4.preheader
  br label %c6

c2:                                               ; preds = %entry
  %frame.sroa.2.4.sroa_idx13 = getelementptr inbounds i8, ptr %frame.sroa.2, i32 4
  store i32 %4, ptr %frame.sroa.2.4.sroa_idx13, align 4
  br label %fall3

c6:                                               ; preds = %c6.preheader, %c8
  %frame.sroa.2.0 = phi i64 [ %frame.sroa.2.1, %c8 ], [ undef, %c6.preheader ]
  %l4.058 = phi i64 [ %or28, %c8 ], [ 0, %c6.preheader ]
  %l1.057 = phi i64 [ %z23, %c8 ], [ %zx, %c6.preheader ]
  %l2.056 = phi i64 [ %z, %c8 ], [ %3, %c6.preheader ]
  %5 = trunc i64 %l1.057 to i32
  %p23 = inttoptr i32 %5 to ptr
  %v24 = load i8, ptr %p23, align 1
  %t = zext i8 %v24 to i32
  %cmp25 = icmp eq i8 %v24, 95
  br i1 %cmp25, label %c1, label %fall2

c1:                                               ; preds = %c7, %c4, %c3, %c6
  %l2.0 = phi i8 [ 1, %c6 ], [ %add43, %c4 ], [ %add47, %c3 ], [ %add39, %c7 ]
  %frame.sroa.2.9.insert.ext = zext i8 %l2.0 to i64
  %frame.sroa.2.9.insert.shift = shl nuw nsw i64 %frame.sroa.2.9.insert.ext, 8
  %frame.sroa.2.8.insert.insert16 = and i64 %frame.sroa.2.0, -65536
  %frame.sroa.2.9.insert.mask = or disjoint i64 %frame.sroa.2.8.insert.insert16, %frame.sroa.2.9.insert.shift
  %frame.sroa.2.9.insert.insert = or disjoint i64 %frame.sroa.2.9.insert.mask, 255
  br label %f77.exit

fall2:                                            ; preds = %c6
  %add = add nuw nsw i32 %t, 208
  %and6 = and i32 %add, 254
  %cmp9 = icmp ult i32 %and6, 10
  br i1 %cmp9, label %c4, label %fall5

c3:                                               ; preds = %fall5
  %add47 = add i8 %v24, -53
  br label %c1

c4:                                               ; preds = %fall2
  %add43 = add i8 %v24, -46
  br label %c1

fall5:                                            ; preds = %fall2
  %add14 = add nuw nsw i32 %t, 191
  %and17 = and i32 %add14, 254
  %cmp20 = icmp ult i32 %and17, 26
  br i1 %cmp20, label %c3, label %fall6

fall6:                                            ; preds = %fall5
  %add25 = add nuw nsw i32 %t, 159
  %and28 = and i32 %add25, 254
  %cmp31 = icmp ult i32 %and28, 26
  br i1 %cmp31, label %c7, label %fall8

c7:                                               ; preds = %fall6
  %add39 = add i8 %v24, -59
  br label %c1

fall8:                                            ; preds = %fall6
  %frame.sroa.2.9.insert.ext18 = zext i8 %v24 to i64
  %frame.sroa.2.9.insert.shift19 = shl nuw nsw i64 %frame.sroa.2.9.insert.ext18, 8
  %frame.sroa.2.9.insert.mask20 = and i64 %frame.sroa.2.0, -65536
  %frame.sroa.2.9.insert.insert21 = or disjoint i64 %frame.sroa.2.9.insert.mask20, %frame.sroa.2.9.insert.shift19
  %frame.sroa.2.8.insert.insert = or disjoint i64 %frame.sroa.2.9.insert.insert21, 1
  br label %f77.exit

f77.exit:                                         ; preds = %fall8, %c1
  %frame.sroa.2.1 = phi i64 [ %frame.sroa.2.9.insert.insert, %c1 ], [ %frame.sroa.2.8.insert.insert, %fall8 ]
  %ld26 = phi i8 [ %l2.0, %c1 ], [ %v24, %fall8 ]
  %cmp10 = phi i1 [ true, %c1 ], [ false, %fall8 ]
  br i1 %cmp10, label %c8, label %fall9

fall7.loopexit:                                   ; preds = %c8
  %or28.lcssa = phi i64 [ %or28, %c8 ]
  %6 = shl i64 %or28.lcssa, 8
  %7 = or disjoint i64 %6, 14
  br label %fall7

fall7:                                            ; preds = %fall7.loopexit, %h4.preheader
  %l4.0.lcssa = phi i64 [ 14, %h4.preheader ], [ %7, %fall7.loopexit ]
  %frame.sroa.2.4.sroa_idx12 = getelementptr inbounds i8, ptr %frame.sroa.2, i32 4
  store i64 %l4.0.lcssa, ptr %frame.sroa.2.4.sroa_idx12, align 4
  %frame.sroa.2.4.sroa_idx = getelementptr inbounds i8, ptr %frame.sroa.2, i32 4
  %frame.sroa.2.4.frame.sroa.2.8.ld7 = load i64, ptr %frame.sroa.2.4.sroa_idx, align 4
  br label %f41.exit

c8:                                               ; preds = %f77.exit
  %add26 = add nuw nsw i64 %l2.056, 4294967295
  %z = and i64 %add26, 4294967295
  %add22 = add nuw nsw i64 %l1.057, 1
  %z23 = and i64 %add22, 4294967295
  %shl25 = shl i64 %l4.058, 6
  %zx27 = zext i8 %ld26 to i64
  %or28 = or i64 %shl25, %zx27
  %brif2.not = icmp eq i64 %z, 0
  br i1 %brif2.not, label %fall7.loopexit, label %c6

fall9:                                            ; preds = %f77.exit
  %frame.sroa.2.1.lcssa = phi i64 [ %frame.sroa.2.1, %f77.exit ]
  store i64 %frame.sroa.2.1.lcssa, ptr %frame.sroa.2, align 4
  br label %fall3

fall3:                                            ; preds = %fall9, %c2
  %z27 = shl nuw i64 %zx, 32
  %or = or disjoint i64 %z27, 4
  %z3 = and i64 %v, -4294967296
  %or5 = or disjoint i64 %z3, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val6 = call %Val @soroban.val.from_payload(i64 %or5)
  %symbol_new_from_linear_memory = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val6)
  %payload = call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  br label %f41.exit

f41.exit:                                         ; preds = %fall7, %fall3
  %ld3 = phi i64 [ %frame.sroa.2.4.frame.sroa.2.8.ld7, %fall7 ], [ %payload, %fall3 ]
  call void @llvm.lifetime.end.p0(i64 12, ptr nonnull %frame.sroa.2)
  %8 = trunc i64 %0 to i32
  %9 = add i32 %8, 8
  %p28 = inttoptr i32 %9 to ptr
  store i64 %ld3, ptr %p28, align 1
  %p29 = inttoptr i32 %8 to ptr
  store i64 0, ptr %p29, align 1
  ret void
}

define internal fastcc "wasm.type"="i64" i64 @f62(i64 "wasm.type"="i32" %0) unnamed_addr {
entry:
  %1 = trunc i64 %0 to i32
  %p = inttoptr i32 %1 to ptr
  %v = load i64, ptr %p, align 1
  %2 = add i32 %1, 8
  %p4 = inttoptr i32 %2 to ptr
  %v5 = load i64, ptr %p4, align 1
  %3 = add i64 %v, 36028797018963968
  %cmp = icmp ult i64 %3, 72057594037927936
  %ashr = ashr i64 %v, 63
  %cmp6.not = icmp eq i64 %ashr, %v5
  %or.cond.not.not = select i1 %cmp, i1 %cmp6.not, i1 false
  br i1 %or.cond.not.not, label %fall3, label %c2

c2:                                               ; preds = %entry
  %obj_from_i128_pieces = call %Val @int.obj_from_i128_pieces(i64 %v5, i64 %v)
  %payload = call i64 @soroban.val.payload(%Val %obj_from_i128_pieces)
  br label %f51.exit

fall3:                                            ; preds = %entry
  %shl = shl i64 %v, 8
  %or11 = or disjoint i64 %shl, 11
  br label %f51.exit

f51.exit:                                         ; preds = %fall3, %c2
  %ld2 = phi i64 [ %payload, %c2 ], [ %or11, %fall3 ]
  ret i64 %ld2
}

; Function Attrs: noreturn
define internal fastcc void @f82(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr #1 {
entry:
  %shl = shl i64 %1, 1
  %or = and i64 %shl, 4294967294
  %z3 = or disjoint i64 %or, 1
  tail call fastcc void @f83(i64 %0, i64 %z3, i64 %2)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f83(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr #1 {
entry:
  %frame = alloca [32 x i8], align 1
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %t = trunc i64 %1 to i32
  store i32 %t, ptr %slot16, align 1
  %slot12 = getelementptr inbounds i8, ptr %frame, i32 12
  %t2 = trunc i64 %0 to i32
  store i32 %t2, ptr %slot12, align 1
  %slot28 = getelementptr inbounds i8, ptr %frame, i32 28
  store i16 1, ptr %slot28, align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %t4 = trunc i64 %2 to i32
  store i32 %t4, ptr %slot24, align 1
  %3 = ptrtoint ptr %slot12 to i32
  %slot20 = getelementptr inbounds i8, ptr %frame, i32 20
  store i32 %3, ptr %slot20, align 1
  call fastcc void @panic_fmt()
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f88(i64 "wasm.type"="i32" %0) unnamed_addr #1 {
entry:
  tail call fastcc void @f82(i64 1048946, i64 43, i64 %0)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f89(i64 "wasm.type"="i32" %0) unnamed_addr #1 {
entry:
  %frame = alloca [32 x i8], align 4
  %slot4 = getelementptr inbounds i8, ptr %frame, i32 4
  store i32 43, ptr %slot4, align 4
  store i32 1048888, ptr %frame, align 4
  %slot12 = getelementptr inbounds i8, ptr %frame, i32 12
  store i32 1048872, ptr %slot12, align 4
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  %t6 = trunc i64 %0 to i32
  store i32 %t6, ptr %slot8, align 4
  %1 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %1 to i64
  %or = or disjoint i64 %fp, 8589934592
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i64 %or, ptr %slot24, align 4
  %2 = ptrtoint ptr %frame to i32
  %fp8 = zext i32 %2 to i64
  %or9 = or disjoint i64 %fp8, 12884901888
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i64 %or9, ptr %slot16, align 4
  %3 = ptrtoint ptr %slot16 to i32
  %fp12 = zext i32 %3 to i64
  call fastcc void @f83(i64 1048600, i64 %fp12, i64 1048856)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f91() unnamed_addr #1 {
entry:
  tail call fastcc void @f83(i64 1048989, i64 57, i64 1048728)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f92() unnamed_addr #1 {
entry:
  tail call fastcc void @f83(i64 1049017, i64 67, i64 1048792)
  unreachable
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare i32 @llvm.usub.sat.i32(i32, i32) #19

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #20

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #20

declare i64 @soroban.storage_type(i64)

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { noreturn }
attributes #2 = { memory(inaccessiblemem: readwrite) "soroban.import"="a.0" "soroban.sig"="(AddressObject) -> Void" }
attributes #3 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="d._" "soroban.sig"="(AddressObject, Symbol, VecObject) -> Val" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.7" "soroban.sig"="() -> AddressObject" }
attributes #6 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.6" "soroban.sig"="(i64, u64) -> I128Object" }
attributes #7 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.8" "soroban.sig"="(I128Object) -> i64" }
attributes #8 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.7" "soroban.sig"="(I128Object) -> u64" }
attributes #9 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.1" "soroban.sig"="(Val, StorageType) -> Val" }
attributes #10 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.0" "soroban.sig"="(Val, StorageType) -> Bool" }
attributes #11 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #12 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #13 = { "spec.sig"="fn __constructor(token: Address)" }
attributes #14 = { "spec.sig"="fn balance(from: Address) -> i128" }
attributes #15 = { "spec.sig"="fn deposit(from: Address, amount: i128)" }
attributes #16 = { "spec.sig"="fn withdraw(from: Address, amount: i128)" }
attributes #17 = { noinline noreturn "sdk.name"="core::panicking::panic_fmt" }
attributes #18 = { "sdk.name"="<soroban_sdk::symbol::Symbol as soroban_env_common::convert::TryFromVal<soroban_sdk::env::Env, &str>>::try_from_val" }
attributes #19 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #20 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!soroban.spec = !{!0, !1, !2, !3, !4}
!soroban.rodata = !{!5}

!0 = !{!"union DataKey { Token, Balance(Address) }"}
!1 = !{!"fn balance(from: Address) -> i128"}
!2 = !{!"fn deposit(from: Address, amount: i128)"}
!3 = !{!"fn withdraw(from: Address, amount: i128)"}
!4 = !{!"fn __constructor(token: Address)"}
!5 = !{!"1048576 0eb7bae2b379e70000000000000000000000000000000000c0023a20c0002f686f6d652f72656e6e792f2e636172676f2f72656769737472792f7372632f696e6465782e6372617465732e696f2d313934396366386336623562353537662f736f726f62616e2d73646b2d32352e332e322f7372632f656e762e7273007372632f6c69622e7273007d0010000a000000220000004c0000007d0010000a0000002a0000002f000000617373657274696f6e206661696c65643a2062616c203e3d20616d6f756e74007d0010000a00000033000000090000007d0010000a000000340000002f0000007d0010000a000000350000004c000000546f6b656e000000f80010000500000042616c616e63650008011000070000001e0010005e000000950100000e0000000000000000000000010000000100000063616c6c65642060526573756c743a3a756e77726170282960206f6e20616e2060457272602076616c7565436f6e76657273696f6e4572726f7263616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565617474656d707420746f206164642077697468206f766572666c6f77617474656d707420746f2073756274726163742077697468206f766572666c6f77"}
!6 = distinct !{!6, !7}
!7 = !{!"llvm.loop.unroll.disable"}
