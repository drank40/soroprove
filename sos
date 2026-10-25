; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048680
@mem = external local_unnamed_addr global i8

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
  %g0.i = load i64, ptr @g0, align 8
  %sub.i = add i64 %g0.i, -32
  store i64 %sub.i, ptr @g0, align 8
  %cmp.i = icmp ult i64 %arg_payload, 21474836480
  %and.i = and i64 %arg_payload, 255
  %cmp2.not.i = icmp eq i64 %and.i, 4
  %or.cond.i = and i1 %cmp.i, %cmp2.not.i
  br i1 %or.cond.i, label %fall4.i, label %c2.i

c2.i:                                             ; preds = %entry
  tail call void @soroban.trap()
  unreachable

fall4.i:                                          ; preds = %entry
  %lshr.i = lshr i64 %arg_payload, 32
  %add.i = add i64 %g0.i, -24
  %sub.i.i = add i64 %g0.i, -48
  store i64 %sub.i.i, ptr @g0, align 8
  %1 = trunc i64 %lshr.i to i8
  switch i8 %1, label %c4.i.i [
    i8 0, label %c2.i.i
    i8 1, label %c6.i.i
    i8 2, label %c5.i.i
    i8 3, label %c3.i.i
  ]

c2.i.i:                                           ; preds = %fall4.i
  %2 = getelementptr i8, ptr @mem, i64 %add.i
  %p.i15.i.i = getelementptr i8, ptr %2, i64 8
  store i64 9742, ptr %p.i15.i.i, align 1
  store i64 0, ptr %2, align 1
  br label %f12.exit.i

c3.i.i:                                           ; preds = %fall4.i
  tail call fastcc void @f50()
  unreachable

c4.i.i:                                           ; preds = %fall4.i
  %3 = getelementptr i8, ptr @mem, i64 %add.i
  %p.i17.i.i = getelementptr i8, ptr %3, i64 8
  store i64 10766, ptr %p.i17.i.i, align 1
  store i64 0, ptr %3, align 1
  br label %f12.exit.i

c5.i.i:                                           ; preds = %fall4.i
  tail call fastcc void @f37()
  tail call void @soroban.trap()
  unreachable

c6.i.i:                                           ; preds = %fall4.i
  %p.i18.i.i = getelementptr i8, ptr @mem, i64 %add.i
  store i64 1, ptr %p.i18.i.i, align 1
  %.phi.trans.insert = getelementptr i8, ptr @mem, i64 %g0.i
  %p.i.i.phi.trans.insert = getelementptr i8, ptr %.phi.trans.insert, i64 -16
  %v.i.i.pre = load i64, ptr %p.i.i.phi.trans.insert, align 1
  br label %f12.exit.i

f12.exit.i:                                       ; preds = %c6.i.i, %c4.i.i, %c2.i.i
  %v.i.i.i.i.i = phi i64 [ %v.i.i.pre, %c6.i.i ], [ 10766, %c4.i.i ], [ 9742, %c2.i.i ]
  %v.i29.i = phi i64 [ 1, %c6.i.i ], [ 0, %c4.i.i ], [ 0, %c2.i.i ]
  store i64 %sub.i, ptr @g0, align 8
  store i64 %sub.i.i, ptr @g0, align 8
  %4 = getelementptr i8, ptr @mem, i64 %sub.i
  %p.i12.i.i = getelementptr i8, ptr %4, i64 -8
  store i64 %v.i.i.i.i.i, ptr %p.i12.i.i, align 1
  %p.i.i32.i = getelementptr i8, ptr @mem, i64 %sub.i.i
  store i64 %v.i29.i, ptr %p.i.i32.i, align 1
  %sub.i.i.i = add i64 %g0.i, -64
  store i64 %sub.i.i.i, ptr @g0, align 8
  %5 = trunc i64 %v.i29.i to i32
  %brif.not.i.i.i = icmp eq i32 %5, 0
  br i1 %brif.not.i.i.i, label %fall3.i.i.i, label %f11.exit

fall3.i.i.i:                                      ; preds = %f12.exit.i
  %p.i5.i.i.i.i = getelementptr i8, ptr @mem, i64 %sub.i.i.i
  store i64 0, ptr %p.i5.i.i.i.i, align 1
  %p.i4.i.i.i.i = getelementptr i8, ptr %p.i5.i.i.i.i, i64 8
  store i64 %v.i.i.i.i.i, ptr %p.i4.i.i.i.i, align 1
  br label %f11.exit

f11.exit:                                         ; preds = %f12.exit.i, %fall3.i.i.i
  %l3.0.i.i.i = phi i64 [ 4294967299, %f12.exit.i ], [ %v.i.i.i.i.i, %fall3.i.i.i ]
  store i64 %g0.i, ptr @g0, align 8
  %to_val = tail call %Val @soroban.val.from_payload(i64 %l3.0.i.i.i)
  ret %Val %to_val
}

define %Val @read(%Val %0, %Val %1) local_unnamed_addr {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %g0.i = load i64, ptr @g0, align 8
  %sub.i = add i64 %g0.i, -48
  store i64 %sub.i, ptr @g0, align 8
  %2 = getelementptr i8, ptr @mem, i64 %g0.i
  %p.i59.i = getelementptr i8, ptr %2, i64 -32
  store i64 %arg_payload1, ptr %p.i59.i, align 1
  %p.i58.i = getelementptr i8, ptr %2, i64 -40
  store i64 %arg_payload, ptr %p.i58.i, align 1
  %add.i = add i64 %g0.i, -24
  %and.i.i = and i64 %arg_payload, 255
  %cmp.not.i.not.i = icmp eq i64 %and.i.i, 77
  br i1 %cmp.not.i.not.i, label %fall2.i.i, label %f35.exit.i

fall2.i.i:                                        ; preds = %entry
  %3 = getelementptr i8, ptr @mem, i64 %add.i
  %p.i7.i.i = getelementptr i8, ptr %3, i64 8
  store i64 %arg_payload, ptr %p.i7.i.i, align 1
  br label %f35.exit.i

f35.exit.i:                                       ; preds = %fall2.i.i, %entry
  %l3.0.i.i = phi i64 [ 1, %entry ], [ 0, %fall2.i.i ]
  %p.i6.i.i = getelementptr i8, ptr @mem, i64 %add.i
  store i64 %l3.0.i.i, ptr %p.i6.i.i, align 1
  br i1 %cmp.not.i.not.i, label %fall2.i, label %c1.i

c1.critedge.i:                                    ; preds = %fall2.i
  store i64 1, ptr %p.i6.i.i, align 1
  br label %c1.i

c1.i:                                             ; preds = %c1.critedge.i, %f35.exit.i
  tail call void @soroban.trap()
  unreachable

fall2.i:                                          ; preds = %f35.exit.i
  %and.i62.i = and i64 %arg_payload1, 255
  %cmp.not.i63.not.i = icmp eq i64 %and.i62.i, 77
  br i1 %cmp.not.i63.not.i, label %fall2.i66.i, label %c1.critedge.i

fall2.i66.i:                                      ; preds = %fall2.i
  %p.i54.i = getelementptr i8, ptr %2, i64 -16
  %v.i55.i = load i64, ptr %p.i54.i, align 1
  %p.i7.i67.i = getelementptr i8, ptr %p.i6.i.i, i64 8
  store i64 %arg_payload1, ptr %p.i7.i67.i, align 1
  store i64 0, ptr %p.i6.i.i, align 1
  %sub.i.i = add i64 %g0.i, -80
  store i64 %sub.i.i, ptr @g0, align 8
  %4 = getelementptr i8, ptr @mem, i64 %sub.i
  %p.i20.i.i = getelementptr i8, ptr %4, i64 -16
  store i64 %arg_payload1, ptr %p.i20.i.i, align 1
  %p.i19.i.i = getelementptr i8, ptr %4, i64 -24
  store i64 %v.i55.i, ptr %p.i19.i.i, align 1
  %p.i.i69.i = getelementptr i8, ptr @mem, i64 %sub.i.i
  store i64 0, ptr %p.i.i69.i, align 1
  %sub.i.i.i.i = add i64 %g0.i, -128
  %sub.i74.i = add i64 %g0.i, -144
  %sub.i.i.i = add i64 %g0.i, -160
  store i64 %sub.i.i.i, ptr @g0, align 8
  %5 = getelementptr i8, ptr @mem, i64 %sub.i74.i
  %p.i9.i.i.i = getelementptr i8, ptr %5, i64 -8
  store i64 17180917836, ptr %p.i9.i.i.i, align 1
  %sub.i.i.i75.i = add i64 %g0.i, -176
  store i64 %sub.i.i.i75.i, ptr @g0, align 8
  %sub.i.i.i.i76.i = add i64 %g0.i, -192
  store i64 %sub.i.i.i.i76.i, ptr @g0, align 8
  %6 = getelementptr i8, ptr @mem, i64 %sub.i.i.i
  %7 = getelementptr i8, ptr %6, i64 -24
  %p.i44.i.i.i.i.i.i = getelementptr i8, ptr %6, i64 -23
  %8 = getelementptr i8, ptr @mem, i64 %sub.i.i.i75.i
  br label %c6.i.i.i.i.i

c6.i.i.i.i.i:                                     ; preds = %c1.i.i.i.i.i.i, %fall2.i66.i
  %l4.072.i.i.i.i.i = phi i64 [ 0, %fall2.i66.i ], [ %or29.i.i.i.i.i, %c1.i.i.i.i.i.i ]
  %l2.071.i.i.i.i.i = phi i64 [ 4, %fall2.i66.i ], [ %add21.i.i.i.i.i, %c1.i.i.i.i.i.i ]
  %l1.070.i.i.i.i.i = phi i64 [ 1048652, %fall2.i66.i ], [ %add23.i.i.i.i.i, %c1.i.i.i.i.i.i ]
  %p.i56.i.i.i.i.i = getelementptr i8, ptr @mem, i64 %l1.070.i.i.i.i.i
  %v.i57.i.i.i.i.i = load i8, ptr %p.i56.i.i.i.i.i, align 1
  %zx.i58.i.i.i.i.i = zext i8 %v.i57.i.i.i.i.i to i64
  %cmp.i.i.i.i.i.i = icmp eq i8 %v.i57.i.i.i.i.i, 95
  br i1 %cmp.i.i.i.i.i.i, label %c1.i.i.i.i.i.i, label %fall2.i.i.i.i.i.i

c1.i.i.i.i.i.i:                                   ; preds = %c7.i.i.i.i.i.i, %c4.i.i.i.i.i.i, %c3.i.i.i.i.i.i, %c6.i.i.i.i.i
  %l2.0.i.i.i.i.i.i = phi i8 [ 1, %c6.i.i.i.i.i ], [ %add24.i.i.i.i.i.i, %c4.i.i.i.i.i.i ], [ %add26.i.i.i.i.i.i, %c3.i.i.i.i.i.i ], [ %add22.i.i.i.i.i.i, %c7.i.i.i.i.i.i ]
  store i8 -1, ptr %7, align 1
  store i8 %l2.0.i.i.i.i.i.i, ptr %p.i44.i.i.i.i.i.i, align 1
  %add21.i.i.i.i.i = add nsw i64 %l2.071.i.i.i.i.i, -1
  %add23.i.i.i.i.i = add nuw nsw i64 %l1.070.i.i.i.i.i, 1
  %shl25.i.i.i.i.i = shl i64 %l4.072.i.i.i.i.i, 6
  %zx.i.i.i.i.i.i = zext i8 %l2.0.i.i.i.i.i.i to i64
  %or29.i.i.i.i.i = or i64 %shl25.i.i.i.i.i, %zx.i.i.i.i.i.i
  %brif2.not.i.i.i.i.i = icmp eq i64 %add21.i.i.i.i.i, 0
  br i1 %brif2.not.i.i.i.i.i, label %fall7.loopexit.i.i.i.i.i, label %c6.i.i.i.i.i

fall2.i.i.i.i.i.i:                                ; preds = %c6.i.i.i.i.i
  %add.i.i.i.i.i.i = add nuw nsw i64 %zx.i58.i.i.i.i.i, 208
  %and2.i.i.i.i.i.i = and i64 %add.i.i.i.i.i.i, 254
  %cmp3.i.i.i.i.i.i = icmp ult i64 %and2.i.i.i.i.i.i, 10
  br i1 %cmp3.i.i.i.i.i.i, label %c4.i.i.i.i.i.i, label %fall5.i.i.i.i.i.i

c3.i.i.i.i.i.i:                                   ; preds = %fall5.i.i.i.i.i.i
  %add26.i.i.i.i.i.i = add i8 %v.i57.i.i.i.i.i, -53
  br label %c1.i.i.i.i.i.i

c4.i.i.i.i.i.i:                                   ; preds = %fall2.i.i.i.i.i.i
  %add24.i.i.i.i.i.i = add i8 %v.i57.i.i.i.i.i, -46
  br label %c1.i.i.i.i.i.i

fall5.i.i.i.i.i.i:                                ; preds = %fall2.i.i.i.i.i.i
  %add7.i.i.i.i.i.i = add nuw nsw i64 %zx.i58.i.i.i.i.i, 191
  %and8.i.i.i.i.i.i = and i64 %add7.i.i.i.i.i.i, 254
  %cmp9.i.i.i.i.i.i = icmp ult i64 %and8.i.i.i.i.i.i, 26
  br i1 %cmp9.i.i.i.i.i.i, label %c3.i.i.i.i.i.i, label %fall6.i.i.i.i.i.i

fall6.i.i.i.i.i.i:                                ; preds = %fall5.i.i.i.i.i.i
  %add13.i.i.i.i.i.i = add nuw nsw i64 %zx.i58.i.i.i.i.i, 159
  %and14.i.i.i.i.i.i = and i64 %add13.i.i.i.i.i.i, 254
  %cmp15.i.i.i.i.i.i = icmp ult i64 %and14.i.i.i.i.i.i, 26
  br i1 %cmp15.i.i.i.i.i.i, label %c7.i.i.i.i.i.i, label %fall8.i.i.i.i.i.i

c7.i.i.i.i.i.i:                                   ; preds = %fall6.i.i.i.i.i.i
  %add22.i.i.i.i.i.i = add i8 %v.i57.i.i.i.i.i, -59
  br label %c1.i.i.i.i.i.i

fall8.i.i.i.i.i.i:                                ; preds = %fall6.i.i.i.i.i.i
  store i8 %v.i57.i.i.i.i.i, ptr %p.i44.i.i.i.i.i.i, align 1
  store i8 1, ptr %7, align 1
  %v.i60.i.i.i.i.i = load i64, ptr %7, align 1
  %p.i66.i.i.i.i.i = getelementptr i8, ptr %8, i64 4
  store i64 %v.i60.i.i.i.i.i, ptr %p.i66.i.i.i.i.i, align 1
  store i32 1, ptr %8, align 1
  br label %f46.exit.i.i.i.i

fall7.loopexit.i.i.i.i.i:                         ; preds = %c1.i.i.i.i.i.i
  %9 = shl i64 %or29.i.i.i.i.i, 8
  %10 = or disjoint i64 %9, 14
  %p.i65.i.i.i.i.i = getelementptr i8, ptr @mem, i64 %sub.i.i.i75.i
  store i32 0, ptr %p.i65.i.i.i.i.i, align 1
  %p.i67.i.i.i.i.i = getelementptr i8, ptr %p.i65.i.i.i.i.i, i64 8
  store i64 %10, ptr %p.i67.i.i.i.i.i, align 1
  br label %f46.exit.i.i.i.i

f46.exit.i.i.i.i:                                 ; preds = %fall7.loopexit.i.i.i.i.i, %fall8.i.i.i.i.i.i
  %v.i.i.i.i.i = phi i32 [ 0, %fall7.loopexit.i.i.i.i.i ], [ 1, %fall8.i.i.i.i.i.i ]
  store i64 %sub.i.i.i75.i, ptr @g0, align 8
  %cmp.not.i.i.i.i = icmp eq i32 %v.i.i.i.i.i, 1
  br i1 %cmp.not.i.i.i.i, label %fall3.i.i.i.i, label %c2.i.i.i78.i

c2.i.i.i78.i:                                     ; preds = %f46.exit.i.i.i.i
  %11 = getelementptr i8, ptr @mem, i64 %sub.i.i.i
  %p.i29.i.i.i.i = getelementptr i8, ptr %11, i64 -8
  %v.i30.i.i.i.i = load i64, ptr %p.i29.i.i.i.i, align 1
  br label %f29.exit.i

fall3.i.i.i.i:                                    ; preds = %f46.exit.i.i.i.i
  %v_u32_1048652 = tail call %Val @soroban.val.from_payload(i64 4503926044884996)
  %v_u32_4 = tail call %Val @soroban.val.from_payload(i64 17179869188)
  %Symbol__Pair__ = tail call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048652, %Val %v_u32_4)
  %payload.i.i.i.i80.i = tail call i64 @soroban.val.payload(%Val %Symbol__Pair__)
  %p.i.i.i.i.i.i.i.phi.trans.insert = getelementptr i8, ptr %p.i.i69.i, i64 8
  %v.i.i.i151.i.i.i.i.pre = load i64, ptr %p.i.i.i.i.i.i.i.phi.trans.insert, align 1
  %p.i.i52.i.i.i.i.i.phi.trans.insert = getelementptr i8, ptr %p.i.i69.i, i64 16
  %v.i.i53.i.i.i.i.i.pre = load i64, ptr %p.i.i52.i.i.i.i.i.phi.trans.insert, align 1
  br label %f29.exit.i

f29.exit.i:                                       ; preds = %fall3.i.i.i.i, %c2.i.i.i78.i
  %v.i.i53.i.i.i.i.i = phi i64 [ %arg_payload1, %c2.i.i.i78.i ], [ %v.i.i53.i.i.i.i.i.pre, %fall3.i.i.i.i ]
  %v.i.i.i151.i.i.i.i = phi i64 [ %v.i55.i, %c2.i.i.i78.i ], [ %v.i.i.i151.i.i.i.i.pre, %fall3.i.i.i.i ]
  %l5.0.i.i.i.i = phi i64 [ %v.i30.i.i.i.i, %c2.i.i.i78.i ], [ %payload.i.i.i.i80.i, %fall3.i.i.i.i ]
  store i64 0, ptr %5, align 1
  %p.i31.i.i.i.i = getelementptr i8, ptr %5, i64 8
  store i64 %l5.0.i.i.i.i, ptr %p.i31.i.i.i.i, align 1
  store i64 %sub.i74.i, ptr @g0, align 8
  %12 = getelementptr i8, ptr @mem, i64 %sub.i.i.i.i
  %p.i15.i.i = getelementptr i8, ptr %12, i64 -8
  %13 = getelementptr i8, ptr %2, i64 -96
  %p.i18.i.i = getelementptr i8, ptr %2, i64 -88
  store i64 %l5.0.i.i.i.i, ptr %p.i18.i.i, align 1
  store i64 0, ptr %13, align 1
  store i64 %sub.i.i.i.i, ptr @g0, align 8
  %p.i143.i.i.i.i = getelementptr i8, ptr %p.i.i69.i, i64 -24
  store i64 %l5.0.i.i.i.i, ptr %p.i143.i.i.i.i, align 1
  store i64 %sub.i74.i, ptr @g0, align 8
  store i64 0, ptr %5, align 1
  store i64 %v.i.i.i151.i.i.i.i, ptr %p.i31.i.i.i.i, align 1
  store i64 0, ptr %5, align 1
  store i64 %v.i.i53.i.i.i.i.i, ptr %p.i31.i.i.i.i, align 1
  store i64 %v.i.i.i151.i.i.i.i, ptr %5, align 1
  %shl4.i.i.i.i.i.i.i = shl i64 %sub.i74.i, 32
  %or5.i.i.i.i.i.i.i = or disjoint i64 %shl4.i.i.i.i.i.i.i, 4
  %v_u32_1048636 = tail call %Val @soroban.val.from_payload(i64 4503857325408260)
  %to_val9.i.i.i.i.i.i.i = tail call %Val @soroban.val.from_payload(i64 %or5.i.i.i.i.i.i.i)
  %v_u32_2 = tail call %Val @soroban.val.from_payload(i64 8589934596)
  %Map_BAD_tag_56__BAD_tag_57_ = tail call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048636, %Val %to_val9.i.i.i.i.i.i.i, %Val %v_u32_2)
  %payload.i.i.i153.i.i.i.i = tail call i64 @soroban.val.payload(%Val %Map_BAD_tag_56__BAD_tag_57_)
  store i64 %payload.i.i.i153.i.i.i.i, ptr %p.i18.i.i, align 1
  store i64 0, ptr %13, align 1
  store i64 %sub.i.i.i.i, ptr @g0, align 8
  %p.i142.i.i.i.i = getelementptr i8, ptr %p.i.i69.i, i64 -32
  store i64 %payload.i.i.i153.i.i.i.i, ptr %p.i142.i.i.i.i, align 1
  %p.i141.i.i.i.i = getelementptr i8, ptr %p.i.i69.i, i64 -40
  store i64 %l5.0.i.i.i.i, ptr %p.i141.i.i.i.i, align 1
  store i64 %sub.i74.i, ptr @g0, align 8
  store i64 %payload.i.i.i153.i.i.i.i, ptr %p.i15.i.i, align 1
  store i64 %l5.0.i.i.i.i, ptr %5, align 1
  %vec_new_from_linear_memory.i.i.i165.i.i.i.i = tail call %Val @vec.vec_new_from_linear_memory(%Val %to_val9.i.i.i.i.i.i.i, %Val %v_u32_2)
  %payload.i.i.i166.i.i.i.i = tail call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory.i.i.i165.i.i.i.i)
  store i64 0, ptr %13, align 1
  store i64 %payload.i.i.i166.i.i.i.i, ptr %p.i18.i.i, align 1
  store i64 %sub.i.i.i.i, ptr @g0, align 8
  store i64 %sub.i.i, ptr @g0, align 8
  %to_val.i.i.i.i.i = tail call %Val @soroban.val.from_payload(i64 %payload.i.i.i166.i.i.i.i)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %has_contract_data.i.i.i.i.i = tail call %Val @ledger.has_contract_data(%Val %to_val.i.i.i.i.i, i64 %Persistent)
  %payload.i.i.i.i.i = tail call i64 @soroban.val.payload(%Val %has_contract_data.i.i.i.i.i)
  %cmp.i.i.i.i.i = icmp eq i64 %payload.i.i.i.i.i, 1
  %zext.i.i.i.i.i = zext i1 %cmp.i.i.i.i.i to i64
  %sub.i71.i = add i64 %g0.i, -64
  store i64 %sub.i71.i, ptr @g0, align 8
  %t.i.i.i = zext i1 %cmp.i.i.i.i.i to i8
  %p.i.i72.i = getelementptr i8, ptr %4, i64 -1
  store i8 %t.i.i.i, ptr %p.i.i72.i, align 1
  store i64 %g0.i, ptr @g0, align 8
  %to_val = tail call %Val @soroban.val.from_payload(i64 %zext.i.i.i.i.i)
  ret %Val %to_val
}

; Function Attrs: memory(readwrite, argmem: none)
define %Val @set_flag() local_unnamed_addr #8 {
entry:
  %g0.i = load i64, ptr @g0, align 8
  %sub.i = add i64 %g0.i, -16
  %sub.i.i.i.i = add i64 %g0.i, -32
  store i64 %sub.i.i.i.i, ptr @g0, align 8
  %p.i4.i.i.i.i.i = getelementptr i8, ptr @mem, i64 %sub.i.i.i.i
  store i64 0, ptr %p.i4.i.i.i.i.i, align 1
  %p.i.i.i.i.i.i = getelementptr i8, ptr %p.i4.i.i.i.i.i, i64 8
  store i64 11022, ptr %p.i.i.i.i.i.i, align 1
  store i64 %sub.i, ptr @g0, align 8
  %v_Symbol__f__ = tail call %Val @soroban.val.from_payload(i64 11022)
  %v_true = tail call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data.i.i.i.i.i = tail call %Val @ledger.put_contract_data(%Val %v_Symbol__f__, %Val %v_true, i64 %Persistent)
  store i64 %g0.i, ptr @g0, align 8
  %v_void = tail call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

; Function Attrs: memory(inaccessiblemem: readwrite)
define internal fastcc void @f37() unnamed_addr #9 {
entry:
  %v_Error_type_0__code_1_ = tail call %Val @soroban.val.from_payload(i64 4294967299)
  %fail_with_error.i = tail call %Val @context.fail_with_error(%Val %v_Error_type_0__code_1_)
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
  %g0 = load i64, ptr @g0, align 8
  %sub = add i64 %g0, -32
  store i64 %sub, ptr @g0, align 8
  %0 = getelementptr i8, ptr @mem, i64 %g0
  %p.i24 = getelementptr i8, ptr %0, i64 -16
  store i32 29, ptr %p.i24, align 1
  %ea4 = add i64 %g0, -20
  %p.i23 = getelementptr i8, ptr @mem, i64 %ea4
  store i32 1048577, ptr %p.i23, align 1
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
attributes #1 = { noreturn }
attributes #2 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #3 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.0" "soroban.sig"="(Val, StorageType) -> Bool" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #6 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #7 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #8 = { memory(readwrite, argmem: none) }
attributes #9 = { memory(inaccessiblemem: readwrite) }
