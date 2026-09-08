; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048652
@mem = external local_unnamed_addr global i8

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

define %Val @read(%Val %0, %Val %1) local_unnamed_addr {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %g0.i = load i64, ptr @g0, align 8
  %sub.i = add i64 %g0.i, -32
  store i64 %sub.i, ptr @g0, align 8
  %and.i = and i64 %arg_payload, 255
  %cmp.not.i = icmp eq i64 %and.i, 77
  %and2.i = and i64 %arg_payload1, 255
  %cmp3.not.i = icmp eq i64 %and2.i, 77
  %or.cond.i = select i1 %cmp.not.i, i1 %cmp3.not.i, i1 false
  br i1 %or.cond.i, label %fall3.i, label %c1.i

c1.i:                                             ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall3.i:                                          ; preds = %entry
  %sub.i.i = add i64 %g0.i, -48
  store i64 %sub.i.i, ptr @g0, align 8
  br label %h8.i.i.i

c2.i.i.i:                                         ; preds = %c10.i.i.i
  %shl47.i.i.i = shl i64 %or33.i.i.i, 8
  %or48.i.i.i = or disjoint i64 %shl47.i.i.i, 14
  %2 = getelementptr i8, ptr @mem, i64 %sub.i.i
  %p.i74.i.i.i = getelementptr i8, ptr %2, i64 8
  store i64 %or48.i.i.i, ptr %p.i74.i.i.i, align 1
  store i32 0, ptr %2, align 1
  br label %f23.exit.i.i

h8.i.i.i:                                         ; preds = %fall3.i, %c10.i.i.i
  %l1.0.i.i.i = phi i64 [ %add35.i.i.i, %c10.i.i.i ], [ 1048640, %fall3.i ]
  %l2.0.i.i.i = phi i64 [ %add37.i.i.i, %c10.i.i.i ], [ 4, %fall3.i ]
  %l3.1.i.i.i = phi i64 [ %or33.i.i.i, %c10.i.i.i ], [ 0, %fall3.i ]
  %p.i.i.i.i = getelementptr i8, ptr @mem, i64 %l1.0.i.i.i
  %v.i.i.i.i = load i8, ptr %p.i.i.i.i, align 1
  %zx.i.i.i.i = zext i8 %v.i.i.i.i to i64
  %cmp4.i.i.i = icmp eq i8 %v.i.i.i.i, 95
  br i1 %cmp4.i.i.i, label %c10.i.i.i, label %fall11.i.i.i

c10.i.i.i:                                        ; preds = %fall17.i.i.i, %c13.i.i.i, %c12.i.i.i, %h8.i.i.i
  %l4.0.i.i.i = phi i64 [ 1, %h8.i.i.i ], [ %add26.i.i.i, %c13.i.i.i ], [ %add28.i.i.i, %c12.i.i.i ], [ %add22.i.i.i, %fall17.i.i.i ]
  %shl30.i.i.i = shl i64 %l3.1.i.i.i, 6
  %and32.i.i.i = and i64 %l4.0.i.i.i, 255
  %or33.i.i.i = or i64 %and32.i.i.i, %shl30.i.i.i
  %add35.i.i.i = add nuw nsw i64 %l1.0.i.i.i, 1
  %add37.i.i.i = add nsw i64 %l2.0.i.i.i, -1
  %eqz.i.i.i = icmp eq i64 %add37.i.i.i, 0
  br i1 %eqz.i.i.i, label %c2.i.i.i, label %h8.i.i.i

fall11.i.i.i:                                     ; preds = %h8.i.i.i
  %add.i.i.i = add nuw nsw i64 %zx.i.i.i.i, 208
  %and.i.i.i = and i64 %add.i.i.i, 254
  %cmp8.i.i.i = icmp ult i64 %and.i.i.i, 10
  br i1 %cmp8.i.i.i, label %c13.i.i.i, label %fall14.i.i.i

c12.i.i.i:                                        ; preds = %fall14.i.i.i
  %add28.i.i.i = add nsw i64 %zx.i.i.i.i, -53
  br label %c10.i.i.i

c13.i.i.i:                                        ; preds = %fall11.i.i.i
  %add26.i.i.i = add nsw i64 %zx.i.i.i.i, -46
  br label %c10.i.i.i

fall14.i.i.i:                                     ; preds = %fall11.i.i.i
  %add12.i.i.i = add nuw nsw i64 %zx.i.i.i.i, 191
  %and13.i.i.i = and i64 %add12.i.i.i, 254
  %cmp14.i.i.i = icmp ult i64 %and13.i.i.i, 26
  br i1 %cmp14.i.i.i, label %c12.i.i.i, label %fall15.i.i.i

fall15.i.i.i:                                     ; preds = %fall14.i.i.i
  %bottom.i.i.i = tail call i64 @ponytail.unknown.i64()
  %brif20.not.i.i.i = icmp eq i64 %bottom.i.i.i, 0
  br i1 %brif20.not.i.i.i, label %fall17.i.i.i, label %c16.i.i.i

c16.i.i.i:                                        ; preds = %fall15.i.i.i
  %shl.i.i.i = shl nuw nsw i64 %zx.i.i.i.i, 8
  %or.i.i.i = or disjoint i64 %shl.i.i.i, 1
  %3 = getelementptr i8, ptr @mem, i64 %sub.i.i
  %p.i75.i.i.i = getelementptr i8, ptr %3, i64 4
  store i64 %or.i.i.i, ptr %p.i75.i.i.i, align 1
  %p.i72.i.i.i = getelementptr i8, ptr @mem, i64 %sub.i.i
  store i32 1, ptr %p.i72.i.i.i, align 1
  br label %f23.exit.i.i

fall17.i.i.i:                                     ; preds = %fall15.i.i.i
  %add22.i.i.i = add nsw i64 %zx.i.i.i.i, -59
  br label %c10.i.i.i

f23.exit.i.i:                                     ; preds = %c16.i.i.i, %c2.i.i.i
  %v.i.i.i = phi i32 [ 1, %c16.i.i.i ], [ 0, %c2.i.i.i ]
  %cmp.not.i.i = icmp eq i32 %v.i.i.i, 1
  br i1 %cmp.not.i.i, label %fall3.i.i, label %c2.i.i

c2.i.i:                                           ; preds = %f23.exit.i.i
  %4 = getelementptr i8, ptr @mem, i64 %sub.i
  %p.i27.i.i = getelementptr i8, ptr %4, i64 -8
  %v.i28.i.i = load i64, ptr %p.i27.i.i, align 1
  br label %f7.exit

fall3.i.i:                                        ; preds = %f23.exit.i.i
  %v_u32_1048640 = tail call %Val @soroban.val.from_payload(i64 4503874505277444)
  %v_u32_4 = tail call %Val @soroban.val.from_payload(i64 17179869188)
  %Symbol__Pair__ = tail call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048640, %Val %v_u32_4)
  %payload.i.i.i = tail call i64 @soroban.val.payload(%Val %Symbol__Pair__)
  br label %f7.exit

f7.exit:                                          ; preds = %c2.i.i, %fall3.i.i
  %l5.0.i.i = phi i64 [ %v.i28.i.i, %c2.i.i ], [ %payload.i.i.i, %fall3.i.i ]
  %add.i = add i64 %g0.i, -24
  %p.i30.i.i = getelementptr i8, ptr @mem, i64 %add.i
  store i64 0, ptr %p.i30.i.i, align 1
  %p.i29.i.i = getelementptr i8, ptr %p.i30.i.i, i64 8
  store i64 %l5.0.i.i, ptr %p.i29.i.i, align 1
  store i64 %sub.i, ptr @g0, align 8
  %5 = getelementptr i8, ptr @mem, i64 %g0.i
  %p.i.i = getelementptr i8, ptr %5, i64 -16
  store i64 %arg_payload1, ptr %p.i.i, align 1
  store i64 %arg_payload, ptr %p.i30.i.i, align 1
  %shl4.i.i.i = shl i64 %add.i, 32
  %or5.i.i.i = or disjoint i64 %shl4.i.i.i, 4
  %v_u32_1048624 = tail call %Val @soroban.val.from_payload(i64 4503805785800708)
  %to_val9.i.i.i = tail call %Val @soroban.val.from_payload(i64 %or5.i.i.i)
  %v_u32_2 = tail call %Val @soroban.val.from_payload(i64 8589934596)
  %Map_BAD_tag_44__BAD_tag_45_ = tail call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048624, %Val %to_val9.i.i.i, %Val %v_u32_2)
  %payload.i.i64.i = tail call i64 @soroban.val.payload(%Val %Map_BAD_tag_44__BAD_tag_45_)
  store i64 %payload.i.i64.i, ptr %p.i.i, align 1
  store i64 %l5.0.i.i, ptr %p.i30.i.i, align 1
  %vec_new_from_linear_memory.i.i.i = tail call %Val @vec.vec_new_from_linear_memory(%Val %to_val9.i.i.i, %Val %v_u32_2)
  %payload.i.i69.i = tail call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory.i.i.i)
  %to_val.i.i70.i = tail call %Val @soroban.val.from_payload(i64 %payload.i.i69.i)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data.i.i.i = tail call %Val @ledger.has_contract_data(%Val %to_val.i.i70.i, i64 %Persistent)
  %payload.i.i71.i = tail call i64 @soroban.val.payload(%Val %has_contract_data.i.i.i)
  %cmp.i.i = icmp eq i64 %payload.i.i71.i, 1
  %zext.i.i = zext i1 %cmp.i.i to i64
  store i64 %g0.i, ptr @g0, align 8
  %to_val = tail call %Val @soroban.val.from_payload(i64 %zext.i.i)
  ret %Val %to_val
}

define %Val @pick(%Val %0) local_unnamed_addr {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %g0 = load i64, ptr @g0, align 8
  %sub = add i64 %g0, -16
  store i64 %sub, ptr @g0, align 8
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp ne i64 %and, 4
  %cmp2 = icmp ugt i64 %arg_payload, 21474836479
  %or.cond = or i1 %cmp2, %cmp.not
  br i1 %or.cond, label %c6, label %fall8

c1:                                               ; preds = %c2, %c3, %fall8
  %l0.0 = phi i64 [ 9742, %c2 ], [ 4294967299, %fall8 ], [ 10766, %c3 ]
  store i64 %g0, ptr @g0, align 8
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

; Function Attrs: memory(readwrite, argmem: none)
define %Val @set_flag() local_unnamed_addr #9 {
entry:
  %g0 = load i64, ptr @g0, align 8
  %sub = add i64 %g0, -16
  store i64 %sub, ptr @g0, align 8
  %v_Symbol__f__ = tail call %Val @soroban.val.from_payload(i64 11022)
  %v_true = tail call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data.i.i = tail call %Val @ledger.put_contract_data(%Val %v_Symbol__f__, %Val %v_true, i64 %Persistent)
  store i64 %g0, ptr @g0, align 8
  %v_void = tail call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define internal fastcc void @f15() unnamed_addr #1 {
entry:
  %v_Error_type_0__code_1_ = tail call %Val @soroban.val.from_payload(i64 4294967299)
  %fail_with_error.i = tail call %Val @context.fail_with_error(%Val %v_Error_type_0__code_1_)
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
  %g0 = load i64, ptr @g0, align 8
  %sub = add i64 %g0, -32
  store i64 %sub, ptr @g0, align 8
  %0 = getelementptr i8, ptr @mem, i64 %g0
  %p.i24 = getelementptr i8, ptr %0, i64 -16
  store i32 29, ptr %p.i24, align 1
  %ea4 = add i64 %g0, -20
  %p.i23 = getelementptr i8, ptr @mem, i64 %ea4
  store i32 1048576, ptr %p.i23, align 1
  %p.i = getelementptr i8, ptr %0, i64 -4
  store i16 1, ptr %p.i, align 1
  %p.i22 = getelementptr i8, ptr %0, i64 -8
  store i32 1048604, ptr %p.i22, align 1
  %t.i = trunc i64 %ea4 to i32
  %p.i21 = getelementptr i8, ptr %0, i64 -12
  store i32 %t.i, ptr %p.i21, align 1
  tail call void @soroban.trap()
  unreachable
}

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
attributes #9 = { memory(readwrite, argmem: none) }
