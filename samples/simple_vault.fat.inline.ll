; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 1 of 40 helpers named, 0 by shape
; ModuleID = 'diver'
source_filename = "diver"
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048923

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

define "wasm.type"="i64" %Val @deposit(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="amount" "spec.type"="i128" "wasm.type"="i64" %1) local_unnamed_addr #13 {
entry:
  %frame = alloca [48 x i8], align 8
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 77
  br i1 %cmp.not, label %fall4, label %c3

c1:                                               ; preds = %c2, %fall6
  %l1.0 = phi i64 [ %obj_to_i128_lo6461, %c2 ], [ %ashr15, %fall6 ]
  %l4.0 = phi i64 [ %obj_to_i128_hi6460, %c2 ], [ %ashr, %fall6 ]
  call void @llvm.lifetime.start.p0(i64 48, ptr nonnull %frame)
  store i64 %arg_payload, ptr %frame, align 8
  %to_val = tail call %Val @soroban.val.from_payload(i64 %arg_payload)
  %require_auth = tail call %Val @address.require_auth(%Val %to_val)
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %2 = ptrtoint ptr %slot16 to i32
  %fp1 = zext i32 %2 to i64
  call fastcc void @f26(i64 %fp1, i64 1048884)
  %ld = load i64, ptr %slot16, align 8
  %cmp = icmp eq i64 %ld, 1
  br i1 %cmp, label %c4, label %fall5

c231:                                             ; preds = %fall5
  call fastcc void @f50(i64 1048764)
  unreachable

c332:                                             ; preds = %c8
  %slot47 = getelementptr inbounds i8, ptr %frame, i32 47
  %3 = ptrtoint ptr %slot47 to i32
  %fp2 = zext i32 %3 to i64
  call fastcc void @f51(i64 %fp2)
  unreachable

c4:                                               ; preds = %fall16, %fall13, %fall637, %c1
  call void @soroban.trap()
  unreachable

fall5:                                            ; preds = %c1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %ld4 = load i64, ptr %slot24, align 8
  store i64 %ld4, ptr %slot16, align 8
  %z = shl nuw i64 %fp1, 32
  %or = or disjoint i64 %z, 4
  %to_val33 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val33, %Val %v_u32_1)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val34 = call %Val @soroban.val.from_payload(i64 %payload)
  %Instance = call i64 @soroban.storage_type(i64 2)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val34, i64 %Instance)
  %payload35 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp.not36 = icmp eq i64 %payload35, 1
  br i1 %cmp.not36, label %fall637, label %c231

fall637:                                          ; preds = %fall5
  %Instance62 = call i64 @soroban.storage_type(i64 2)
  %get_contract_data = call %Val @ledger.get_contract_data(%Val %to_val34, i64 %Instance62)
  %payload38 = call i64 @soroban.val.payload(%Val %get_contract_data)
  %and39 = and i64 %payload38, 255
  %cmp19.not = icmp eq i64 %and39, 77
  br i1 %cmp19.not, label %fall7, label %c4

fall7:                                            ; preds = %fall637
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %payload38, ptr %slot8, align 8
  %get_current_contract_address = call %Val @context.get_current_contract_address()
  %payload40 = call i64 @soroban.val.payload(%Val %get_current_contract_address)
  %4 = add i64 %l1.0, 36028797018963968
  %cmp29 = icmp ult i64 %4, 72057594037927936
  %ashr41 = ashr i64 %l1.0, 63
  %eqz37 = icmp eq i64 %ashr41, %l4.0
  %or.cond = select i1 %cmp29, i1 %eqz37, i1 false
  br i1 %or.cond, label %c9, label %c10

c8:                                               ; preds = %c10, %c9
  %l7.0 = phi i64 [ %payload47, %c10 ], [ %or45, %c9 ]
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 %l7.0, ptr %slot32, align 8
  store i64 %payload40, ptr %slot24, align 8
  store i64 %arg_payload, ptr %slot16, align 8
  %v_u32_3 = call %Val @soroban.val.from_payload(i64 12884901892)
  %vec_new_from_linear_memory43 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val33, %Val %v_u32_3)
  %payload44 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory43)
  %to_val45 = call %Val @soroban.val.from_payload(i64 %payload38)
  %v_Symbol__transfer__ = call %Val @soroban.val.from_payload(i64 65154533130155790)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %payload44)
  %call = call %Val @call.call(%Val %to_val45, %Val %v_Symbol__transfer__, %Val %to_val4)
  %payload46 = call i64 @soroban.val.payload(%Val %call)
  %and58 = and i64 %payload46, 255
  %cmp59.not = icmp eq i64 %and58, 2
  br i1 %cmp59.not, label %fall13, label %c332

c9:                                               ; preds = %fall7
  %shl = shl i64 %l1.0, 8
  %or45 = or disjoint i64 %shl, 11
  br label %c8

c10:                                              ; preds = %fall7
  %obj_from_i128_pieces = call %Val @int.obj_from_i128_pieces(i64 %l4.0, i64 %l1.0)
  %payload47 = call i64 @soroban.val.payload(%Val %obj_from_i128_pieces)
  br label %c8

fall13:                                           ; preds = %c8
  call fastcc void @f26(i64 %fp1, i64 1048900)
  %ld67 = load i64, ptr %slot16, align 8
  %cmp68 = icmp eq i64 %ld67, 1
  br i1 %cmp68, label %c4, label %fall14

fall14:                                           ; preds = %fall13
  %ld72 = load i64, ptr %slot24, align 8
  store i64 %arg_payload, ptr %slot24, align 8
  store i64 %ld72, ptr %slot16, align 8
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_new_from_linear_memory49 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val33, %Val %v_u32_2)
  %payload50 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory49)
  %to_val51 = call %Val @soroban.val.from_payload(i64 %payload50)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data52 = call %Val @ledger.has_contract_data(%Val %to_val51, i64 %Persistent)
  %payload53 = call i64 @soroban.val.payload(%Val %has_contract_data52)
  %cmp.not54 = icmp eq i64 %payload53, 1
  br i1 %cmp.not54, label %fall16, label %c15

c15:                                              ; preds = %fall19, %c17, %fall14
  %l4.055 = phi i64 [ 0, %fall14 ], [ %obj_to_i128_hi64, %c17 ], [ %ashr105, %fall19 ]
  %l6.0 = phi i64 [ 0, %fall14 ], [ %obj_to_i128_lo64, %c17 ], [ %ashr107, %fall19 ]
  %5 = xor i64 %l4.0, %l4.055
  %xor119 = xor i64 %5, -1
  %add123 = add i64 %l4.055, %l4.0
  %add126 = add i64 %l6.0, %l1.0
  %cmp128 = icmp ult i64 %add126, %l6.0
  %z131 = zext i1 %cmp128 to i64
  %add132 = add i64 %add123, %z131
  %xor133 = xor i64 %add132, %l4.055
  %and134 = and i64 %xor133, %xor119
  %cmp135 = icmp sgt i64 %and134, -1
  br i1 %cmp135, label %f15.exit, label %fall20

fall16:                                           ; preds = %fall14
  %Persistent63 = call i64 @soroban.storage_type(i64 1)
  %get_contract_data56 = call %Val @ledger.get_contract_data(%Val %to_val51, i64 %Persistent63)
  %payload57 = call i64 @soroban.val.payload(%Val %get_contract_data56)
  %t93 = trunc i64 %payload57 to i8
  switch i8 %t93, label %c4 [
    i8 69, label %c17
    i8 11, label %fall19
  ]

c17:                                              ; preds = %fall16
  %to_val58 = call %Val @soroban.val.from_payload(i64 %payload57)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val58)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val58)
  br label %c15

fall19:                                           ; preds = %fall16
  %ashr105 = ashr i64 %payload57, 63
  %ashr107 = ashr i64 %payload57, 8
  br label %c15

fall20:                                           ; preds = %c15
  call fastcc void @f45(i64 1048966, i64 57, i64 1048780)
  unreachable

f15.exit:                                         ; preds = %c15
  call fastcc void @f11(i64 %arg_payload, i64 %add126, i64 %add132)
  call void @llvm.lifetime.end.p0(i64 48, ptr nonnull %frame)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void

c2:                                               ; preds = %fall4
  %to_val59 = tail call %Val @soroban.val.from_payload(i64 %arg_payload1)
  %obj_to_i128_hi6460 = tail call i64 @int.obj_to_i128_hi64(%Val %to_val59)
  %obj_to_i128_lo6461 = tail call i64 @int.obj_to_i128_lo64(%Val %to_val59)
  br label %c1

c3:                                               ; preds = %fall4, %entry
  tail call void @soroban.trap()
  unreachable

fall4:                                            ; preds = %entry
  %t = trunc i64 %arg_payload1 to i8
  switch i8 %t, label %c3 [
    i8 69, label %c2
    i8 11, label %fall6
  ]

fall6:                                            ; preds = %fall4
  %ashr = ashr i64 %arg_payload1, 63
  %ashr15 = ashr i64 %arg_payload1, 8
  br label %c1
}

define "wasm.type"="i64" %Val @withdraw(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="amount" "spec.type"="i128" "wasm.type"="i64" %1) local_unnamed_addr #14 {
entry:
  %frame = alloca [48 x i8], align 8
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 77
  br i1 %cmp.not, label %fall4, label %c3

c1:                                               ; preds = %c2, %fall6
  %l1.0 = phi i64 [ %obj_to_i128_lo6461, %c2 ], [ %ashr15, %fall6 ]
  %l4.0 = phi i64 [ %obj_to_i128_hi6460, %c2 ], [ %ashr, %fall6 ]
  call void @llvm.lifetime.start.p0(i64 48, ptr nonnull %frame)
  store i64 %arg_payload, ptr %frame, align 8
  %to_val = tail call %Val @soroban.val.from_payload(i64 %arg_payload)
  %require_auth = tail call %Val @address.require_auth(%Val %to_val)
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %2 = ptrtoint ptr %slot16 to i32
  %fp1 = zext i32 %2 to i64
  call fastcc void @f26(i64 %fp1, i64 1048900)
  %ld = load i64, ptr %slot16, align 8
  %cmp = icmp eq i64 %ld, 1
  br i1 %cmp, label %c4, label %fall5

c131:                                             ; preds = %c17
  %slot47 = getelementptr inbounds i8, ptr %frame, i32 47
  %3 = ptrtoint ptr %slot47 to i32
  %fp2 = zext i32 %3 to i64
  call fastcc void @f51(i64 %fp2)
  unreachable

c232:                                             ; preds = %fall11
  call fastcc void @f54()
  unreachable

c333:                                             ; preds = %c6
  call fastcc void @f44(i64 1048796, i64 31, i64 1048828)
  unreachable

c4:                                               ; preds = %fall15, %fall12, %fall7, %c1
  call void @soroban.trap()
  unreachable

fall5:                                            ; preds = %c1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %ld4 = load i64, ptr %slot24, align 8
  store i64 %arg_payload, ptr %slot24, align 8
  store i64 %ld4, ptr %slot16, align 8
  %z = shl nuw i64 %fp1, 32
  %or = or disjoint i64 %z, 4
  %to_val34 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val34, %Val %v_u32_2)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val35 = call %Val @soroban.val.from_payload(i64 %payload)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val35, i64 %Persistent)
  %payload36 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp.not37 = icmp eq i64 %payload36, 1
  br i1 %cmp.not37, label %fall7, label %c6

c6:                                               ; preds = %fall10, %c8, %fall5
  %l4.038 = phi i64 [ 0, %fall5 ], [ %obj_to_i128_hi64, %c8 ], [ %ashr41, %fall10 ]
  %l5.0 = phi i64 [ 0, %fall5 ], [ %obj_to_i128_lo64, %c8 ], [ %ashr34, %fall10 ]
  %cmp45 = icmp ult i64 %l5.0, %l1.0
  %cmp49 = icmp slt i64 %l4.038, %l4.0
  %cmp53 = icmp eq i64 %l4.038, %l4.0
  %select.v = select i1 %cmp53, i1 %cmp45, i1 %cmp49
  br i1 %select.v, label %c333, label %fall11

fall7:                                            ; preds = %fall5
  %Persistent62 = call i64 @soroban.storage_type(i64 1)
  %get_contract_data = call %Val @ledger.get_contract_data(%Val %to_val35, i64 %Persistent62)
  %payload39 = call i64 @soroban.val.payload(%Val %get_contract_data)
  %t22 = trunc i64 %payload39 to i8
  switch i8 %t22, label %c4 [
    i8 69, label %c8
    i8 11, label %fall10
  ]

c8:                                               ; preds = %fall7
  %to_val40 = call %Val @soroban.val.from_payload(i64 %payload39)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val40)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val40)
  br label %c6

fall10:                                           ; preds = %fall7
  %ashr41 = ashr i64 %payload39, 63
  %ashr34 = ashr i64 %payload39, 8
  br label %c6

fall11:                                           ; preds = %c6
  %xor = xor i64 %l4.038, %l4.0
  %sub = sub i64 %l4.038, %l4.0
  %z70.neg = sext i1 %cmp45 to i64
  %sub71 = add i64 %sub, %z70.neg
  %xor72 = xor i64 %sub71, %l4.038
  %and73 = and i64 %xor72, %xor
  %cmp74 = icmp slt i64 %and73, 0
  br i1 %cmp74, label %c232, label %fall12

fall12:                                           ; preds = %fall11
  %sub80 = sub i64 %l5.0, %l1.0
  call fastcc void @f11(i64 %arg_payload, i64 %sub80, i64 %sub71)
  call fastcc void @f26(i64 %fp1, i64 1048884)
  %ld89 = load i64, ptr %slot16, align 8
  %cmp90 = icmp eq i64 %ld89, 1
  br i1 %cmp90, label %c4, label %fall13

fall13:                                           ; preds = %fall12
  %ld94 = load i64, ptr %slot24, align 8
  store i64 %ld94, ptr %slot16, align 8
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory43 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val34, %Val %v_u32_1)
  %payload44 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory43)
  %to_val45 = call %Val @soroban.val.from_payload(i64 %payload44)
  %Instance = call i64 @soroban.storage_type(i64 2)
  %has_contract_data46 = call %Val @ledger.has_contract_data(%Val %to_val45, i64 %Instance)
  %payload47 = call i64 @soroban.val.payload(%Val %has_contract_data46)
  %cmp.not48 = icmp eq i64 %payload47, 1
  br i1 %cmp.not48, label %fall15, label %c14

c14:                                              ; preds = %fall13
  call fastcc void @f44(i64 1048923, i64 43, i64 1048860)
  unreachable

fall15:                                           ; preds = %fall13
  %Instance63 = call i64 @soroban.storage_type(i64 2)
  %get_contract_data49 = call %Val @ledger.get_contract_data(%Val %to_val45, i64 %Instance63)
  %payload50 = call i64 @soroban.val.payload(%Val %get_contract_data49)
  %and112 = and i64 %payload50, 255
  %cmp113.not = icmp eq i64 %and112, 77
  br i1 %cmp113.not, label %fall16, label %c4

fall16:                                           ; preds = %fall15
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %payload50, ptr %slot8, align 8
  %get_current_contract_address = call %Val @context.get_current_contract_address()
  %payload51 = call i64 @soroban.val.payload(%Val %get_current_contract_address)
  %4 = add i64 %l1.0, 36028797018963968
  %cmp123 = icmp ult i64 %4, 72057594037927936
  %ashr131 = ashr i64 %l1.0, 63
  %eqz133 = icmp eq i64 %ashr131, %l4.0
  %or.cond = select i1 %cmp123, i1 %eqz133, i1 false
  br i1 %or.cond, label %c18, label %c19

c17:                                              ; preds = %c19, %c18
  %l1.052 = phi i64 [ %payload58, %c19 ], [ %or141, %c18 ]
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 %l1.052, ptr %slot32, align 8
  store i64 %arg_payload, ptr %slot24, align 8
  store i64 %payload51, ptr %slot16, align 8
  %v_u32_3 = call %Val @soroban.val.from_payload(i64 12884901892)
  %vec_new_from_linear_memory54 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val34, %Val %v_u32_3)
  %payload55 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory54)
  %to_val56 = call %Val @soroban.val.from_payload(i64 %payload50)
  %v_Symbol__transfer__ = call %Val @soroban.val.from_payload(i64 65154533130155790)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %payload55)
  %call = call %Val @call.call(%Val %to_val56, %Val %v_Symbol__transfer__, %Val %to_val4)
  %payload57 = call i64 @soroban.val.payload(%Val %call)
  %and154 = and i64 %payload57, 255
  %cmp155.not = icmp eq i64 %and154, 2
  br i1 %cmp155.not, label %f17.exit, label %c131

c18:                                              ; preds = %fall16
  %shl = shl i64 %l1.0, 8
  %or141 = or disjoint i64 %shl, 11
  br label %c17

c19:                                              ; preds = %fall16
  %obj_from_i128_pieces = call %Val @int.obj_from_i128_pieces(i64 %l4.0, i64 %l1.0)
  %payload58 = call i64 @soroban.val.payload(%Val %obj_from_i128_pieces)
  br label %c17

f17.exit:                                         ; preds = %c17
  call void @llvm.lifetime.end.p0(i64 48, ptr nonnull %frame)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void

c2:                                               ; preds = %fall4
  %to_val59 = tail call %Val @soroban.val.from_payload(i64 %arg_payload1)
  %obj_to_i128_hi6460 = tail call i64 @int.obj_to_i128_hi64(%Val %to_val59)
  %obj_to_i128_lo6461 = tail call i64 @int.obj_to_i128_lo64(%Val %to_val59)
  br label %c1

c3:                                               ; preds = %fall4, %entry
  tail call void @soroban.trap()
  unreachable

fall4:                                            ; preds = %entry
  %t = trunc i64 %arg_payload1 to i8
  switch i8 %t, label %c3 [
    i8 69, label %c2
    i8 11, label %fall6
  ]

fall6:                                            ; preds = %fall4
  %ashr = ashr i64 %arg_payload1, 63
  %ashr15 = ashr i64 %arg_payload1, 8
  br label %c1
}

define "wasm.type"="i64" %Val @__constructor(%Val "spec.name"="token" "spec.type"="Address" "wasm.type"="i64" %0) local_unnamed_addr #15 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %frame = alloca [32 x i8], align 1
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 77
  br i1 %cmp.not, label %fall2, label %c1

c1:                                               ; preds = %fall2, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  %1 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %1 to i64
  call fastcc void @f26(i64 %fp, i64 1048884)
  %ld = load i64, ptr %slot8, align 1
  %cmp3 = icmp eq i64 %ld, 1
  br i1 %cmp3, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %ld6 = load i64, ptr %slot16, align 1
  store i64 %ld6, ptr %slot8, align 1
  %z = shl nuw i64 %fp, 32
  %or = or disjoint i64 %z, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %v_u32_1)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val19 = call %Val @soroban.val.from_payload(i64 %payload)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %arg_payload)
  %Instance = call i64 @soroban.storage_type(i64 2)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val19, %Val %to_val3, i64 %Instance)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define "spec.type"="i128" "wasm.type"="i64" %Val @balance(%Val "spec.name"="from" "spec.type"="Address" "wasm.type"="i64" %0) local_unnamed_addr #16 {
entry:
  %frame = alloca [32 x i8], align 1
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 77
  br i1 %cmp.not, label %fall4, label %c3

c1:                                               ; preds = %c2, %c5
  %l0.0 = phi i64 [ %payload37, %c5 ], [ %or17, %c2 ]
  %to_val = call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val

c2:                                               ; preds = %f13.exit
  %shl = shl i64 %l1.0, 8
  %or17 = or disjoint i64 %shl, 11
  br label %c1

c3:                                               ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall4:                                            ; preds = %entry
  call void @llvm.lifetime.start.p0(i64 32, ptr nonnull %frame)
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  %1 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %1 to i64
  call fastcc void @f26(i64 %fp, i64 1048900)
  %ld = load i64, ptr %slot8, align 1
  %cmp = icmp eq i64 %ld, 1
  br i1 %cmp, label %c127, label %fall2

c127:                                             ; preds = %fall432, %fall4
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %fall4
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %ld3 = load i64, ptr %slot16, align 1
  store i64 %arg_payload, ptr %slot16, align 1
  store i64 %ld3, ptr %slot8, align 1
  %z = shl nuw i64 %fp, 32
  %or = or disjoint i64 %z, 4
  %to_val28 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val28, %Val %v_u32_2)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val29 = call %Val @soroban.val.from_payload(i64 %payload)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val29, i64 %Persistent)
  %payload30 = call i64 @soroban.val.payload(%Val %has_contract_data)
  %cmp.not31 = icmp eq i64 %payload30, 1
  br i1 %cmp.not31, label %fall432, label %f13.exit

fall432:                                          ; preds = %fall2
  %Persistent38 = call i64 @soroban.storage_type(i64 1)
  %get_contract_data = call %Val @ledger.get_contract_data(%Val %to_val29, i64 %Persistent38)
  %payload33 = call i64 @soroban.val.payload(%Val %get_contract_data)
  %t20 = trunc i64 %payload33 to i8
  switch i8 %t20, label %c127 [
    i8 69, label %c534
    i8 11, label %fall7
  ]

c534:                                             ; preds = %fall432
  %to_val35 = call %Val @soroban.val.from_payload(i64 %payload33)
  %obj_to_i128_hi64 = call i64 @int.obj_to_i128_hi64(%Val %to_val35)
  %obj_to_i128_lo64 = call i64 @int.obj_to_i128_lo64(%Val %to_val35)
  br label %f13.exit

fall7:                                            ; preds = %fall432
  %ashr36 = ashr i64 %payload33, 63
  %ashr32 = ashr i64 %payload33, 8
  br label %f13.exit

f13.exit:                                         ; preds = %fall2, %c534, %fall7
  %l1.0 = phi i64 [ 0, %fall2 ], [ %obj_to_i128_lo64, %c534 ], [ %ashr32, %fall7 ]
  %l3.0 = phi i64 [ 0, %fall2 ], [ %obj_to_i128_hi64, %c534 ], [ %ashr36, %fall7 ]
  call void @llvm.lifetime.end.p0(i64 32, ptr nonnull %frame)
  %2 = add i64 %l1.0, 36028797018963968
  %cmp3 = icmp ult i64 %2, 72057594037927936
  %ashr = ashr i64 %l1.0, 63
  %eqz = icmp eq i64 %l3.0, %ashr
  %or.cond = select i1 %cmp3, i1 %eqz, i1 false
  br i1 %or.cond, label %c2, label %c5

c5:                                               ; preds = %f13.exit
  %obj_from_i128_pieces = call %Val @int.obj_from_i128_pieces(i64 %l3.0, i64 %l1.0)
  %payload37 = call i64 @soroban.val.payload(%Val %obj_from_i128_pieces)
  br label %c1
}

define internal fastcc void @f11(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2) unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  %3 = ptrtoint ptr %frame to i32
  %fp = zext i32 %3 to i64
  call fastcc void @f26(i64 %fp, i64 1048900)
  %ld = load i32, ptr %frame, align 8
  %brif2.not = icmp eq i32 %ld, 0
  br i1 %brif2.not, label %fall5, label %c1

c1:                                               ; preds = %entry
  call void @soroban.trap()
  unreachable

fall5:                                            ; preds = %entry
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  %ld3 = load i64, ptr %slot8, align 8
  store i64 %0, ptr %slot8, align 8
  store i64 %ld3, ptr %frame, align 8
  %z = shl nuw i64 %fp, 32
  %or = or disjoint i64 %z, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %v_u32_2)
  %4 = add i64 %1, 36028797018963968
  %cmp21 = icmp ult i64 %4, 72057594037927936
  %ashr = ashr i64 %1, 63
  %eqz = icmp eq i64 %ashr, %2
  %or.cond = select i1 %cmp21, i1 %eqz, i1 false
  br i1 %or.cond, label %c8, label %c9

c7:                                               ; preds = %c8, %c9
  %l3.0 = phi i64 [ %payload2, %c9 ], [ %or36, %c8 ]
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %payload)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %l3.0)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val1, %Val %to_val3, i64 %Persistent)
  ret void

c8:                                               ; preds = %fall5
  %shl = shl i64 %1, 8
  %or36 = or disjoint i64 %shl, 11
  br label %c7

c9:                                               ; preds = %fall5
  %obj_from_i128_pieces = call %Val @int.obj_from_i128_pieces(i64 %2, i64 %1)
  %payload2 = call i64 @soroban.val.payload(%Val %obj_from_i128_pieces)
  br label %c7
}

; Function Attrs: noinline noreturn
define internal fastcc void @panic_fmt() unnamed_addr #17 {
entry:
  tail call void @soroban.trap()
  unreachable
}

define internal fastcc void @f26(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %2 = trunc i64 %1 to i32
  %p = inttoptr i32 %2 to ptr
  %v = load i32, ptr %p, align 1
  %zx = zext i32 %v to i64
  %3 = add i32 %2, 4
  %p7 = inttoptr i32 %3 to ptr
  %v8 = load i32, ptr %p7, align 1
  %zx9 = zext i32 %v8 to i64
  %cmp = icmp ugt i32 %v8, 9
  br i1 %cmp, label %f43.exit, label %fall5

c2:                                               ; preds = %c10
  %or60.lcssa = phi i64 [ %or60, %c10 ]
  %shl79 = shl i64 %or60.lcssa, 8
  %or80 = or disjoint i64 %shl79, 14
  br label %c1

fall5:                                            ; preds = %entry
  %brif2.not = icmp eq i32 %v8, 0
  br i1 %brif2.not, label %c1, label %h8.preheader

h8.preheader:                                     ; preds = %fall5
  br label %h8

h8:                                               ; preds = %h8.preheader, %c10
  %l1.0 = phi i64 [ %z64, %c10 ], [ %zx, %h8.preheader ]
  %l2.0 = phi i32 [ %add67, %c10 ], [ %v8, %h8.preheader ]
  %l3.1 = phi i64 [ %or60, %c10 ], [ 0, %h8.preheader ]
  %4 = trunc i64 %l1.0 to i32
  %p10 = inttoptr i32 %4 to ptr
  %v11 = load i8, ptr %p10, align 1
  %zx12 = zext i8 %v11 to i64
  %t4 = zext i8 %v11 to i32
  %cmp5 = icmp eq i8 %v11, 95
  br i1 %cmp5, label %c10, label %fall11

c10:                                              ; preds = %fall17, %c13, %c12, %h8
  %l4.0 = phi i64 [ 1, %h8 ], [ %z49, %c13 ], [ %z53, %c12 ], [ %z41, %fall17 ]
  %shl55 = shl i64 %l3.1, 6
  %and59 = and i64 %l4.0, 255
  %or60 = or i64 %and59, %shl55
  %add63 = add nuw nsw i64 %l1.0, 1
  %z64 = and i64 %add63, 4294967295
  %add67 = add i32 %l2.0, -1
  %eqz = icmp eq i32 %add67, 0
  br i1 %eqz, label %c2, label %h8

fall11:                                           ; preds = %h8
  %add = add nuw nsw i32 %t4, 208
  %and = and i32 %add, 254
  %cmp13 = icmp ult i32 %and, 10
  br i1 %cmp13, label %c13, label %fall14

c12:                                              ; preds = %fall14
  %add52 = add nuw nsw i64 %zx12, 4294967243
  %z53 = and i64 %add52, 4294967295
  br label %c10

c13:                                              ; preds = %fall11
  %add48 = add nuw nsw i64 %zx12, 4294967250
  %z49 = and i64 %add48, 4294967295
  br label %c10

fall14:                                           ; preds = %fall11
  %add18 = add nuw nsw i32 %t4, 191
  %and21 = and i32 %add18, 254
  %cmp24 = icmp ult i32 %and21, 26
  br i1 %cmp24, label %c12, label %fall15

fall15:                                           ; preds = %fall14
  %add29 = add nuw nsw i32 %t4, 159
  %and32 = and i32 %add29, 254
  %cmp35 = icmp ugt i32 %and32, 25
  br i1 %cmp35, label %f43.exit.loopexit, label %fall17

fall17:                                           ; preds = %fall15
  %add40 = add nuw nsw i64 %zx12, 4294967237
  %z41 = and i64 %add40, 4294967295
  br label %c10

f43.exit.loopexit:                                ; preds = %fall15
  br label %f43.exit

f43.exit:                                         ; preds = %f43.exit.loopexit, %entry
  %z = shl nuw i64 %zx, 32
  %or = or disjoint i64 %z, 4
  %z3 = shl nuw i64 %zx9, 32
  %or5 = or disjoint i64 %z3, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val6 = call %Val @soroban.val.from_payload(i64 %or5)
  %symbol_new_from_linear_memory = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val6)
  %payload = call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  br label %c1

c1:                                               ; preds = %c2, %fall5, %f43.exit
  %l5.0 = phi i64 [ %payload, %f43.exit ], [ %or80, %c2 ], [ 14, %fall5 ]
  %5 = trunc i64 %0 to i32
  %p13 = inttoptr i32 %5 to ptr
  store i64 0, ptr %p13, align 1
  %6 = add i32 %5, 8
  %p14 = inttoptr i32 %6 to ptr
  store i64 %l5.0, ptr %p14, align 1
  ret void
}

; Function Attrs: noreturn
define internal fastcc void @f44(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr #1 {
entry:
  %shl = shl i64 %1, 1
  %or = and i64 %shl, 4294967294
  %z3 = or disjoint i64 %or, 1
  tail call fastcc void @f45(i64 %0, i64 %z3, i64 %2)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f45(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr #1 {
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
define internal fastcc void @f50(i64 "wasm.type"="i32" %0) unnamed_addr #1 {
entry:
  tail call fastcc void @f44(i64 1048923, i64 43, i64 %0)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f51(i64 "wasm.type"="i32" %0) unnamed_addr #1 {
entry:
  %frame = alloca [32 x i8], align 4
  %slot4 = getelementptr inbounds i8, ptr %frame, i32 4
  store i32 43, ptr %slot4, align 4
  store i32 1048592, ptr %frame, align 4
  %slot12 = getelementptr inbounds i8, ptr %frame, i32 12
  store i32 1048576, ptr %slot12, align 4
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
  call fastcc void @f45(i64 1048635, i64 %fp12, i64 1048748)
  unreachable
}

; Function Attrs: noreturn
define internal fastcc void @f54() unnamed_addr #1 {
entry:
  tail call fastcc void @f45(i64 1048994, i64 67, i64 1048844)
  unreachable
}

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.start.p0(i64 immarg, ptr nocapture) #18

; Function Attrs: nocallback nofree nosync nounwind willreturn memory(argmem: readwrite)
declare void @llvm.lifetime.end.p0(i64 immarg, ptr nocapture) #18

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
attributes #13 = { "spec.sig"="fn deposit(from: Address, amount: i128)" }
attributes #14 = { "spec.sig"="fn withdraw(from: Address, amount: i128)" }
attributes #15 = { "spec.sig"="fn __constructor(token: Address)" }
attributes #16 = { "spec.sig"="fn balance(from: Address) -> i128" }
attributes #17 = { noinline noreturn "sdk.name"="core::panicking::panic_fmt" }
attributes #18 = { nocallback nofree nosync nounwind willreturn memory(argmem: readwrite) }

!soroban.spec = !{!0, !1, !2, !3, !4}
!soroban.rodata = !{!5}

!0 = !{!"union DataKey { Token, Balance(Address) }"}
!1 = !{!"fn balance(from: Address) -> i128"}
!2 = !{!"fn deposit(from: Address, amount: i128)"}
!3 = !{!"fn withdraw(from: Address, amount: i128)"}
!4 = !{!"fn __constructor(token: Address)"}
!5 = !{!"1048576 0000000000000000010000000100000063616c6c65642060526573756c743a3a756e77726170282960206f6e20616e2060457272602076616c7565c0023a20c0002f686f6d652f72656e6e792f2e636172676f2f72656769737472792f7372632f696e6465782e6372617465732e696f2d313934396366386336623562353537662f736f726f62616e2d73646b2d32352e332e322f7372632f656e762e7273007372632f6c69622e72730000410010005e000000950100000e000000a00010000a000000220000004c000000a00010000a0000002a0000002f000000617373657274696f6e206661696c65643a2062616c203e3d20616d6f756e7400a00010000a0000003300000009000000a00010000a000000340000002f000000a00010000a000000350000004c000000546f6b656e0000002c0110000500000042616c616e6365003c01100007000000436f6e76657273696f6e4572726f7263616c6c656420604f7074696f6e3a3a756e77726170282960206f6e206120604e6f6e65602076616c7565617474656d707420746f206164642077697468206f766572666c6f77617474656d707420746f2073756274726163742077697468206f766572666c6f77"}
