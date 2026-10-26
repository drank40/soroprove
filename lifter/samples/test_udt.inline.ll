; sdk 26.0.1 rustc 1.95.0; fingerprints 26.0.1+rustc1.95.0.txt: 5 of 17 helpers named, 1 by shape
; ModuleID = 'diver'
source_filename = "diver"
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048808
@g2 = local_unnamed_addr constant i64 1048808
@g3 = local_unnamed_addr constant i64 1048816

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #1

declare %Val @buf.symbol_index_in_linear_memory(%Val, %Val, %Val) local_unnamed_addr #2

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) local_unnamed_addr #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @int.obj_from_i64(i64) local_unnamed_addr #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @int.obj_to_i64(%Val) local_unnamed_addr #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_get(%Val, %Val) local_unnamed_addr #6

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_has(%Val, %Val) local_unnamed_addr #7

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) local_unnamed_addr #8

declare %Val @map.map_unpack_to_linear_memory(%Val, %Val, %Val, %Val) local_unnamed_addr #9

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_front(%Val) local_unnamed_addr #10

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_get(%Val, %Val) local_unnamed_addr #11

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_len(%Val) local_unnamed_addr #12

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) local_unnamed_addr #13

declare %Val @vec.vec_unpack_to_linear_memory(%Val, %Val, %Val) local_unnamed_addr #14

define "spec.type"="i64" "wasm.type"="i64" %Val @add(%Val "spec.name"="a" "spec.type"="UdtEnum" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="UdtEnum" "wasm.type"="i64" %1) local_unnamed_addr #15 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %frame = alloca [64 x i8], align 8
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %arg_payload1, ptr %slot8, align 8
  store i64 %arg_payload, ptr %frame, align 8
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %2 = ptrtoint ptr %slot16 to i32
  %fp = zext i32 %2 to i64
  %3 = ptrtoint ptr %frame to i32
  %fp3 = zext i32 %3 to i64
  call fastcc void @f13(i64 %fp, i64 %fp3)
  %ld = load i8, ptr %slot16, align 8
  %cmp = icmp eq i8 %ld, 4
  br i1 %cmp, label %c5, label %fall6

c1:                                               ; preds = %c2, %fall32
  %l1.0 = phi i64 [ %payload183, %c2 ], [ %or, %fall32 ]
  %to_val185 = call %Val @soroban.val.from_payload(i64 %l1.0)
  ret %Val %to_val185

c2:                                               ; preds = %fall31
  %obj_from_i64 = call %Val @int.obj_from_i64(i64 %add167)
  %payload183 = call i64 @soroban.val.payload(%Val %obj_from_i64)
  br label %c1

c3.loopexit:                                      ; preds = %h24, %fall26, %c27
  br label %c3

c3.loopexit244:                                   ; preds = %h12, %fall14, %c15
  br label %c3

c3:                                               ; preds = %c3.loopexit244, %c3.loopexit, %c21, %c8, %c9, %c19, %c20
  call fastcc void @panic()
  unreachable

c4:                                               ; preds = %c8, %c9, %c10, %fall7
  %l1.1 = phi i64 [ 0, %fall7 ], [ %zx8, %c10 ], [ %add64, %c9 ], [ %add78, %c8 ]
  switch i8 %ld14, label %c19 [
    i8 3, label %c23
    i8 1, label %c21
    i8 2, label %c22
  ]

c5:                                               ; preds = %fall6, %entry
  call void @soroban.trap()
  unreachable

fall6:                                            ; preds = %entry
  %slot32 = getelementptr inbounds i8, ptr %frame, i32 32
  %ld5 = load i64, ptr %slot32, align 8
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %ld6 = load i64, ptr %slot24, align 8
  %slot17 = getelementptr inbounds i8, ptr %frame, i32 17
  %ld7 = load i8, ptr %slot17, align 1
  %zx8 = zext i8 %ld7 to i64
  %4 = ptrtoint ptr %slot8 to i32
  %fp12 = zext i32 %4 to i64
  call fastcc void @f13(i64 %fp, i64 %fp12)
  %ld14 = load i8, ptr %slot16, align 8
  %cmp17 = icmp eq i8 %ld14, 4
  br i1 %cmp17, label %c5, label %fall7

fall7:                                            ; preds = %fall6
  %ld21 = load i64, ptr %slot32, align 8
  %ld23 = load i64, ptr %slot24, align 8
  %ld25 = load i8, ptr %slot17, align 1
  %zx26 = zext i8 %ld25 to i64
  switch i8 %ld, label %c4 [
    i8 3, label %c11
    i8 1, label %c9
    i8 2, label %c10
  ]

c8:                                               ; preds = %fall14
  %l1.2.lcssa246 = phi i64 [ %l1.2, %fall14 ]
  %add78 = add i64 %l1.2.lcssa246, %ld6
  %5 = icmp slt i64 %l1.2.lcssa246, 0
  %6 = icmp sge i64 %add78, %ld6
  %eqz87223 = xor i1 %5, %6
  br i1 %eqz87223, label %c4, label %c3

c9:                                               ; preds = %fall7
  %add64 = add i64 %ld6, %ld5
  %7 = icmp slt i64 %ld5, 0
  %8 = icmp sge i64 %add64, %ld6
  %eqz222 = xor i1 %7, %8
  br i1 %eqz222, label %c4, label %c3

c10:                                              ; preds = %fall7
  br label %c4

c11:                                              ; preds = %fall7
  %to_val = call %Val @soroban.val.from_payload(i64 %ld5)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  %slot56 = getelementptr inbounds i8, ptr %frame, i32 56
  store i32 0, ptr %slot56, align 8
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 %ld5, ptr %slot48, align 8
  %lshr = lshr i64 %payload, 32
  %slot60 = getelementptr inbounds i8, ptr %frame, i32 60
  %t31 = trunc i64 %lshr to i32
  store i32 %t31, ptr %slot60, align 4
  %9 = ptrtoint ptr %slot48 to i32
  %fp35 = zext i32 %9 to i64
  br label %h12

h12:                                              ; preds = %c15, %c11
  %l1.2 = phi i64 [ 0, %c11 ], [ %add, %c15 ]
  call fastcc void @f25(i64 %fp, i64 %fp35)
  %ld37 = load i64, ptr %slot16, align 8
  %cmp38 = icmp ugt i64 %ld37, 2
  br i1 %cmp38, label %c3.loopexit244, label %fall14

fall14:                                           ; preds = %h12
  %sel42 = trunc i64 %ld37 to i32
  switch i32 %sel42, label %c15 [
    i32 2, label %c8
    i32 1, label %c3.loopexit244
  ]

c15:                                              ; preds = %fall14
  %ld44 = load i64, ptr %slot24, align 8
  %add = add i64 %ld44, %l1.2
  %10 = icmp slt i64 %ld44, 0
  %11 = icmp sge i64 %add, %l1.2
  %cmp54.not224 = xor i1 %10, %11
  br i1 %cmp54.not224, label %h12, label %c3.loopexit244

c19:                                              ; preds = %c20, %c21, %c22, %c4
  %l0.0 = phi i64 [ 0, %c4 ], [ %zx26, %c22 ], [ %add136, %c21 ], [ %add153, %c20 ]
  %add167 = add i64 %l0.0, %l1.1
  %cmp169 = icmp slt i64 %add167, %l1.1
  %12 = icmp slt i64 %l0.0, 0
  %13 = xor i1 %12, %cmp169
  br i1 %13, label %c3, label %fall31

c20:                                              ; preds = %fall26
  %l0.1.lcssa245 = phi i64 [ %l0.1, %fall26 ]
  %add153 = add i64 %l0.1.lcssa245, %ld23
  %cmp155 = icmp slt i64 %add153, %ld23
  %14 = icmp slt i64 %l0.1.lcssa245, 0
  %15 = xor i1 %14, %cmp155
  br i1 %15, label %c3, label %c19

c21:                                              ; preds = %c4
  %add136 = add i64 %ld23, %ld21
  %16 = icmp slt i64 %ld21, 0
  %17 = icmp sge i64 %add136, %ld23
  %eqz145225 = xor i1 %16, %17
  br i1 %eqz145225, label %c19, label %c3

c22:                                              ; preds = %c4
  br label %c19

c23:                                              ; preds = %c4
  %to_val93 = call %Val @soroban.val.from_payload(i64 %ld21)
  %vec_len94 = call %Val @vec.vec_len(%Val %to_val93)
  %payload95 = call i64 @soroban.val.payload(%Val %vec_len94)
  %slot5696 = getelementptr inbounds i8, ptr %frame, i32 56
  store i32 0, ptr %slot5696, align 8
  %slot4898 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 %ld21, ptr %slot4898, align 8
  %lshr100 = lshr i64 %payload95, 32
  %slot60101 = getelementptr inbounds i8, ptr %frame, i32 60
  %t102 = trunc i64 %lshr100 to i32
  store i32 %t102, ptr %slot60101, align 4
  %18 = ptrtoint ptr %slot4898 to i32
  %fp106 = zext i32 %18 to i64
  br label %h24

h24:                                              ; preds = %c27, %c23
  %l0.1 = phi i64 [ 0, %c23 ], [ %add120, %c27 ]
  call fastcc void @f25(i64 %fp, i64 %fp106)
  %ld108 = load i64, ptr %slot16, align 8
  %cmp109 = icmp ugt i64 %ld108, 2
  br i1 %cmp109, label %c3.loopexit, label %fall26

fall26:                                           ; preds = %h24
  %sel113 = trunc i64 %ld108 to i32
  switch i32 %sel113, label %c27 [
    i32 2, label %c20
    i32 1, label %c3.loopexit
  ]

c27:                                              ; preds = %fall26
  %ld115 = load i64, ptr %slot24, align 8
  %add120 = add i64 %ld115, %l0.1
  %19 = icmp slt i64 %ld115, 0
  %20 = icmp sge i64 %add120, %l0.1
  %cmp126.not226 = xor i1 %19, %20
  br i1 %cmp126.not226, label %h24, label %c3.loopexit

fall31:                                           ; preds = %c19
  %21 = add i64 %add167, -36028797018963968
  %cmp178 = icmp ult i64 %21, -72057594037927936
  br i1 %cmp178, label %c2, label %fall32

fall32:                                           ; preds = %fall31
  %shl = shl i64 %add167, 8
  %or = or disjoint i64 %shl, 7
  br label %c1
}

define "spec.type"="Option<UdtRecursive>" "wasm.type"="i64" %Val @recursive(%Val "spec.name"="a" "spec.type"="UdtRecursive" "wasm.type"="i64" %0) local_unnamed_addr #16 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %frame = alloca [32 x i8], align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i32 2, ptr %slot8, align 1
  %1 = ptrtoint ptr %slot8 to i32
  %fp = zext i32 %1 to i64
  call fastcc void @f21(i64 %fp, i64 %arg_payload)
  %ld4 = load i64, ptr %slot8, align 1
  %cmp = icmp eq i64 %ld4, 1
  br i1 %cmp, label %c1, label %fall2

c1:                                               ; preds = %c4, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %ld5 = load i64, ptr %slot24, align 1
  %to_val = call %Val @soroban.val.from_payload(i64 %ld5)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  %cmp6 = icmp ugt i64 %payload, 4294967295
  br i1 %cmp6, label %c4, label %c3

c3:                                               ; preds = %fall2, %fall6
  %l0.0 = phi i64 [ %payload42, %fall6 ], [ 2, %fall2 ]
  %to_val37 = call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val37

c4:                                               ; preds = %fall2
  %vec_front = call %Val @vec.vec_front(%Val %to_val)
  %payload17 = call i64 @soroban.val.payload(%Val %vec_front)
  call fastcc void @f21(i64 %fp, i64 %payload17)
  %ld19 = load i64, ptr %slot8, align 1
  %cmp20 = icmp eq i64 %ld19, 1
  br i1 %cmp20, label %c1, label %fall6

fall6:                                            ; preds = %c4
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %ld23 = load i64, ptr %slot16, align 1
  %ld25 = load i64, ptr %slot24, align 1
  store i64 %ld25, ptr %slot16, align 1
  store i64 %ld23, ptr %slot8, align 1
  %z = shl nuw i64 %fp, 32
  %or = or disjoint i64 %z, 4
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048752, %Val %to_val1, %Val %v_u32_2)
  %payload42 = call i64 @soroban.val.payload(%Val %Map__a____b__)
  br label %c3
}

define "spec.type"="Result<Option<RecursiveEnum>, Error>" "wasm.type"="i64" %Val @recursive_enum(%Val "spec.name"="a" "spec.type"="RecursiveEnum" "wasm.type"="i64" %0, %Val "spec.name"="key" "spec.type"="u32" "wasm.type"="i64" %1) local_unnamed_addr #17 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  store i32 3, ptr %slot24, align 1
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 75
  br i1 %cmp.not, label %fall2, label %c1

c1.sink.split:                                    ; preds = %fall27, %fall19, %fall14, %fall2
  %slot48.sink = phi ptr [ %slot24, %fall2 ], [ %slot48, %fall14 ], [ %slot24, %fall19 ], [ %slot48, %fall27 ]
  store i64 2, ptr %slot48.sink, align 1
  br label %c1

c1:                                               ; preds = %c1.sink.split, %fall2387, %fall2371, %f17.exit, %fall29, %fall2395, %f17.exit269, %f17.exit275, %c21, %fall18, %fall2381, %f17.exit281, %c4, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %arg_payload)
  %vec_len = tail call %Val @vec.vec_len(%Val %to_val)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_len)
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  store i32 0, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %arg_payload, ptr %slot8, align 1
  %lshr = lshr i64 %payload, 32
  %slot20 = getelementptr inbounds i8, ptr %frame, i32 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %2 = ptrtoint ptr %slot24 to i32
  %fp = zext i32 %2 to i64
  %cmp.not.not = icmp eq i32 %t, 0
  br i1 %cmp.not.not, label %c1.sink.split, label %fall2371

fall2371:                                         ; preds = %fall2
  %v_u32_0 = call %Val @soroban.val.from_payload(i64 4)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %v_u32_0)
  %payload372 = call i64 @soroban.val.payload(%Val %vec_get)
  %fp366 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 %payload372, ptr %fp366, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %t19 = trunc i64 %payload372 to i8
  switch i8 %t19, label %c1 [
    i8 74, label %c4
    i8 14, label %c4
  ]

c4:                                               ; preds = %fall2371, %fall2371
  %to_val373 = call %Val @soroban.val.from_payload(i64 %payload372)
  %v_u32_1048792 = call %Val @soroban.val.from_payload(i64 4504527340306436)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val373, %Val %v_u32_1048792, %Val %v_u32_2)
  %payload374 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory)
  %cmp32 = icmp ugt i64 %payload374, 8589934591
  br i1 %cmp32, label %c1, label %fall7

fall7:                                            ; preds = %c4
  %cond.not = icmp ult i64 %payload374, 4294967296
  %ld129 = load i32, ptr %slot16, align 1
  %ld132 = load i32, ptr %slot20, align 1
  %cmp = icmp ult i32 %ld132, %ld129
  br i1 %cond.not, label %c12, label %c13

c8:                                               ; preds = %fall17, %f17.exit275, %fall31, %fall30
  %l0.0 = phi i64 [ %payload408, %fall30 ], [ %payload415, %fall31 ], [ 2, %f17.exit275 ], [ 2, %fall17 ]
  %to_val240 = call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val240

c9:                                               ; preds = %fall24
  br i1 %cmp393, label %c1375, label %f17.exit

c1375:                                            ; preds = %c9
  call fastcc void @panic()
  unreachable

f17.exit:                                         ; preds = %c9
  %brif218.not = icmp eq i32 %ld215, %ld212
  br i1 %brif218.not, label %fall31, label %c1

c10:                                              ; preds = %fall24
  br i1 %cmp393, label %c1376, label %f17.exit269

c1376:                                            ; preds = %c10
  call fastcc void @panic()
  unreachable

f17.exit269:                                      ; preds = %c10
  %sub.narrow = sub i32 %ld215, %ld212
  %cmp157.not = icmp ult i32 %sub.narrow, 2
  br i1 %cmp157.not, label %fall27, label %c1

c12:                                              ; preds = %fall7
  br i1 %cmp, label %c1377, label %f17.exit275

c1377:                                            ; preds = %c12
  call fastcc void @panic()
  unreachable

f17.exit275:                                      ; preds = %c12
  %brif135.not = icmp eq i32 %ld132, %ld129
  %and137 = and i64 %arg_payload1, 255
  %cmp138.not = icmp eq i64 %and137, 4
  %or.cond260 = select i1 %brif135.not, i1 %cmp138.not, i1 false
  br i1 %or.cond260, label %c8, label %c1

c13:                                              ; preds = %fall7
  br i1 %cmp, label %c1378, label %f17.exit281

c1378:                                            ; preds = %c13
  call fastcc void @panic()
  unreachable

f17.exit281:                                      ; preds = %c13
  %sub.narrow379 = sub i32 %ld132, %ld129
  %cmp44.not = icmp ult i32 %sub.narrow379, 2
  br i1 %cmp44.not, label %fall14, label %c1

fall14:                                           ; preds = %f17.exit281
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  %cmp.not380 = icmp ult i32 %ld129, %ld132
  br i1 %cmp.not380, label %fall2381, label %c1.sink.split

fall2381:                                         ; preds = %fall14
  %zx = zext i32 %ld129 to i64
  %v = load i64, ptr %slot8, align 1
  %shl = shl nuw i64 %zx, 32
  %or = or disjoint i64 %shl, 4
  %to_val382 = call %Val @soroban.val.from_payload(i64 %v)
  %to_val10383 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get384 = call %Val @vec.vec_get(%Val %to_val382, %Val %to_val10383)
  %payload385 = call i64 @soroban.val.payload(%Val %vec_get384)
  %fp367 = getelementptr inbounds i8, ptr %frame, i32 56
  store i64 %payload385, ptr %fp367, align 1
  %add = add i32 %ld129, 1
  store i32 %add, ptr %slot16, align 1
  store i64 0, ptr %slot48, align 1
  call fastcc void @f22(i64 %fp, i64 %payload385)
  %ld59 = load i64, ptr %slot24, align 1
  %cmp60 = icmp ne i64 %ld59, 1
  %and64 = and i64 %arg_payload1, 255
  %cmp65.not = icmp eq i64 %and64, 4
  %or.cond = select i1 %cmp60, i1 %cmp65.not, i1 false
  br i1 %or.cond, label %fall17, label %c1

fall17:                                           ; preds = %fall2381
  %slot40 = getelementptr inbounds i8, ptr %frame, i32 40
  %ld68 = load i64, ptr %slot40, align 1
  %and70 = and i64 %arg_payload1, -4294967292
  %to_val71 = call %Val @soroban.val.from_payload(i64 %ld68)
  %to_val72 = call %Val @soroban.val.from_payload(i64 %and70)
  %map_has = call %Val @map.map_has(%Val %to_val71, %Val %to_val72)
  %payload73 = call i64 @soroban.val.payload(%Val %map_has)
  %cmp74.not = icmp eq i64 %payload73, 1
  br i1 %cmp74.not, label %fall18, label %c8

fall18:                                           ; preds = %fall17
  %map_get = call %Val @map.map_get(%Val %to_val71, %Val %to_val72)
  %payload81 = call i64 @soroban.val.payload(%Val %map_get)
  %and82 = and i64 %payload81, 255
  %cmp83.not = icmp eq i64 %and82, 75
  br i1 %cmp83.not, label %fall19, label %c1

fall19:                                           ; preds = %fall18
  %to_val87 = call %Val @soroban.val.from_payload(i64 %payload81)
  %vec_len88 = call %Val @vec.vec_len(%Val %to_val87)
  %payload89 = call i64 @soroban.val.payload(%Val %vec_len88)
  store i32 0, ptr %slot16, align 1
  store i64 %payload81, ptr %slot8, align 1
  %lshr94 = lshr i64 %payload89, 32
  %t96 = trunc i64 %lshr94 to i32
  store i32 %t96, ptr %slot20, align 1
  %cmp.not.not386 = icmp eq i32 %t96, 0
  br i1 %cmp.not.not386, label %c1.sink.split, label %fall2387

fall2387:                                         ; preds = %fall19
  %vec_get388 = call %Val @vec.vec_get(%Val %to_val87, %Val %v_u32_0)
  %payload389 = call i64 @soroban.val.payload(%Val %vec_get388)
  store i64 %payload389, ptr %fp366, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %t108 = trunc i64 %payload389 to i8
  switch i8 %t108, label %c1 [
    i8 74, label %c21
    i8 14, label %c21
  ]

c21:                                              ; preds = %fall2387, %fall2387
  %to_val390 = call %Val @soroban.val.from_payload(i64 %payload389)
  %symbol_index_in_linear_memory391 = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val390, %Val %v_u32_1048792, %Val %v_u32_2)
  %payload392 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory391)
  %cmp123 = icmp ugt i64 %payload392, 8589934591
  br i1 %cmp123, label %c1, label %fall24

fall24:                                           ; preds = %c21
  %cond241.not = icmp ult i64 %payload392, 4294967296
  %ld212 = load i32, ptr %slot16, align 1
  %ld215 = load i32, ptr %slot20, align 1
  %cmp393 = icmp ult i32 %ld215, %ld212
  br i1 %cond241.not, label %c9, label %c10

fall27:                                           ; preds = %f17.exit269
  %cmp.not394 = icmp ult i32 %ld212, %ld215
  br i1 %cmp.not394, label %fall2395, label %c1.sink.split

fall2395:                                         ; preds = %fall27
  %zx396 = zext i32 %ld212 to i64
  %v397 = load i64, ptr %slot8, align 1
  %shl398 = shl nuw i64 %zx396, 32
  %or399 = or disjoint i64 %shl398, 4
  %to_val400 = call %Val @soroban.val.from_payload(i64 %v397)
  %to_val10401 = call %Val @soroban.val.from_payload(i64 %or399)
  %vec_get402 = call %Val @vec.vec_get(%Val %to_val400, %Val %to_val10401)
  %payload403 = call i64 @soroban.val.payload(%Val %vec_get402)
  store i64 %payload403, ptr %fp367, align 1
  %add404 = add i32 %ld212, 1
  store i32 %add404, ptr %slot16, align 1
  store i64 0, ptr %slot48, align 1
  call fastcc void @f22(i64 %fp, i64 %payload403)
  %ld174 = load i64, ptr %slot24, align 1
  %cmp175 = icmp eq i64 %ld174, 1
  br i1 %cmp175, label %c1, label %fall29

fall29:                                           ; preds = %fall2395
  %ld179 = load i64, ptr %slot40, align 1
  %ld181 = load i64, ptr %fp366, align 1
  store i32 3, ptr %slot24, align 1
  call fastcc void @f30(i64 %fp, i64 1048780, i64 9)
  %ld193 = load i32, ptr %slot24, align 1
  %brif195.not = icmp eq i32 %ld193, 0
  br i1 %brif195.not, label %fall30, label %c1

fall30:                                           ; preds = %fall29
  %ld197 = load i64, ptr %fp366, align 1
  store i64 %ld179, ptr %fp366, align 1
  store i64 %ld181, ptr %slot24, align 1
  %z = shl nuw i64 %fp, 32
  %or405 = or disjoint i64 %z, 4
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %or405)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048752, %Val %to_val1, %Val %v_u32_2)
  %payload407 = call i64 @soroban.val.payload(%Val %Map__a____b__)
  store i64 %payload407, ptr %fp366, align 1
  store i64 %ld197, ptr %slot24, align 1
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val1, %Val %v_u32_2)
  %payload408 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  br label %c8

fall31:                                           ; preds = %f17.exit
  store i32 3, ptr %slot24, align 1
  %v_u32_1048768 = call %Val @soroban.val.from_payload(i64 4504424261091332)
  %v_u32_12 = call %Val @soroban.val.from_payload(i64 51539607556)
  %Symbol__NotRecursive__ = call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048768, %Val %v_u32_12)
  %payload410 = call i64 @soroban.val.payload(%Val %Symbol__NotRecursive__)
  store i64 %payload410, ptr %fp366, align 1
  store i64 %payload410, ptr %slot24, align 1
  %z411 = shl nuw i64 %fp, 32
  %or412 = or disjoint i64 %z411, 4
  %to_val413 = call %Val @soroban.val.from_payload(i64 %or412)
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory414 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val413, %Val %v_u32_1)
  %payload415 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory414)
  br label %c8
}

define internal fastcc void @f13(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i32 24
  %2 = trunc i64 %1 to i32
  %p = inttoptr i32 %2 to ptr
  %v = load i64, ptr %p, align 1
  %and = and i64 %v, 255
  %cmp = icmp eq i64 %and, 75
  br i1 %cmp, label %c2, label %c1

c1:                                               ; preds = %c2, %fall2, %c10, %f17.exit292, %f17.exit286, %fall19, %fall20, %fall25, %fall26, %fall27, %f17.exit280, %fall29, %fall30, %fall31, %f17.exit, %fall33, %fall34, %fall39, %fall40, %entry, %c4
  %l5.0.sink = phi i8 [ %l5.0, %c4 ], [ 4, %entry ], [ 4, %fall40 ], [ 4, %fall39 ], [ 4, %fall34 ], [ 4, %fall33 ], [ 4, %f17.exit ], [ 4, %fall31 ], [ 4, %fall30 ], [ 4, %fall29 ], [ 4, %f17.exit280 ], [ 4, %fall27 ], [ 4, %fall26 ], [ 4, %fall25 ], [ 4, %fall20 ], [ 4, %fall19 ], [ 4, %f17.exit286 ], [ 4, %f17.exit292 ], [ 4, %c10 ], [ 4, %fall2 ], [ 4, %c2 ]
  %3 = trunc i64 %0 to i32
  %p303 = inttoptr i32 %3 to ptr
  store i8 %l5.0.sink, ptr %p303, align 1
  ret void

c2:                                               ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v)
  %vec_len = tail call %Val @vec.vec_len(%Val %to_val)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_len)
  %slot16 = getelementptr inbounds i8, ptr %frame, i32 16
  %slot8 = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 %v, ptr %slot8, align 1
  %lshr = lshr i64 %payload, 32
  %slot20 = getelementptr inbounds i8, ptr %frame, i32 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %4 = ptrtoint ptr %slot24 to i32
  %fp = zext i32 %4 to i64
  %5 = ptrtoint ptr %slot8 to i32
  %fp13 = zext i32 %5 to i64
  %cmp.not.not = icmp eq i32 %t, 0
  br i1 %cmp.not.not, label %c1, label %fall2

fall2:                                            ; preds = %c2
  %v_u32_0 = call %Val @soroban.val.from_payload(i64 4)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %v_u32_0)
  %payload304 = call i64 @soroban.val.payload(%Val %vec_get)
  %fp299 = getelementptr inbounds i8, ptr %frame, i32 32
  store i64 %payload304, ptr %fp299, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %t20 = trunc i64 %payload304 to i8
  %z = and i64 %payload304, 255
  switch i8 %t20, label %c1 [
    i8 74, label %c10
    i8 14, label %c10
  ]

c4:                                               ; preds = %fall31, %f17.exit292, %fall41, %fall28
  %l1.0 = phi i64 [ 24, %fall28 ], [ 16, %fall41 ], [ %z, %f17.exit292 ], [ %select152, %fall31 ]
  %l3.0 = phi i64 [ %ld112, %fall28 ], [ %ld214, %fall41 ], [ %lshr32, %f17.exit292 ], [ %ld134, %fall31 ]
  %l4.0 = phi i64 [ %ld97, %fall28 ], [ %ld220, %fall41 ], [ %payload, %f17.exit292 ], [ %payload, %fall31 ]
  %l5.0 = phi i8 [ 1, %fall28 ], [ 3, %fall41 ], [ 0, %f17.exit292 ], [ 2, %fall31 ]
  %l6.0 = phi i64 [ %ld106, %fall28 ], [ 0, %fall41 ], [ 0, %f17.exit292 ], [ 0, %fall31 ]
  %6 = trunc i64 %0 to i32
  %7 = add i32 %6, 24
  %p305 = inttoptr i32 %7 to ptr
  store i64 %l6.0, ptr %p305, align 1
  %8 = add i32 %6, 16
  %p306 = inttoptr i32 %8 to ptr
  store i64 %l3.0, ptr %p306, align 1
  %9 = add i32 %6, 8
  %p307 = inttoptr i32 %9 to ptr
  store i64 %l4.0, ptr %p307, align 1
  %t308 = trunc i64 %l1.0 to i8
  %10 = add i32 %6, 1
  %p309 = inttoptr i32 %10 to ptr
  store i8 %t308, ptr %p309, align 1
  br label %c1

c10:                                              ; preds = %fall2, %fall2
  %to_val310 = call %Val @soroban.val.from_payload(i64 %payload304)
  %v_u32_1048692 = call %Val @soroban.val.from_payload(i64 4504097843576836)
  %v_u32_4 = call %Val @soroban.val.from_payload(i64 17179869188)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val310, %Val %v_u32_1048692, %Val %v_u32_4)
  %payload311 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory)
  %lshr32 = lshr i64 %payload311, 32
  %cmp33 = icmp ugt i64 %payload311, 17179869183
  br i1 %cmp33, label %c1, label %fall13

fall13:                                           ; preds = %c10
  %sel = trunc i64 %lshr32 to i32
  %ld38 = load i32, ptr %slot16, align 1
  %ld41 = load i32, ptr %slot20, align 1
  %cmp312 = icmp ult i32 %ld41, %ld38
  switch i32 %sel, label %c17 [
    i32 3, label %c14
    i32 1, label %c16
    i32 2, label %c15
  ]

c14:                                              ; preds = %fall13
  br i1 %cmp312, label %c1313, label %f17.exit

c1313:                                            ; preds = %c14
  call fastcc void @panic()
  unreachable

f17.exit:                                         ; preds = %c14
  %sub.narrow = sub i32 %ld41, %ld38
  %cmp165.not = icmp ult i32 %sub.narrow, 2
  br i1 %cmp165.not, label %fall33, label %c1

c15:                                              ; preds = %fall13
  br i1 %cmp312, label %c1314, label %f17.exit280

c1314:                                            ; preds = %c15
  call fastcc void @panic()
  unreachable

f17.exit280:                                      ; preds = %c15
  %sub.narrow315 = sub i32 %ld41, %ld38
  %cmp121.not = icmp ult i32 %sub.narrow315, 2
  br i1 %cmp121.not, label %fall29, label %c1

c16:                                              ; preds = %fall13
  br i1 %cmp312, label %c1316, label %f17.exit286

c1316:                                            ; preds = %c16
  call fastcc void @panic()
  unreachable

f17.exit286:                                      ; preds = %c16
  %sub.narrow317 = sub i32 %ld41, %ld38
  %cmp53.not = icmp ult i32 %sub.narrow317, 2
  br i1 %cmp53.not, label %fall19, label %c1

c17:                                              ; preds = %fall13
  br i1 %cmp312, label %c1318, label %f17.exit292

c1318:                                            ; preds = %c17
  call fastcc void @panic()
  unreachable

f17.exit292:                                      ; preds = %c17
  %brif44.not = icmp eq i32 %ld41, %ld38
  br i1 %brif44.not, label %c4, label %c1

fall19:                                           ; preds = %f17.exit286
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld61 = load i64, ptr %slot24, align 1
  %cmp62.not = icmp eq i64 %ld61, 0
  br i1 %cmp62.not, label %fall20, label %c1

fall20:                                           ; preds = %fall19
  %ld66 = load i64, ptr %fp299, align 1
  store i64 2, ptr %slot24, align 1
  store i64 2, ptr %fp299, align 1
  %fp301 = getelementptr inbounds i8, ptr %frame, i32 40
  store i64 2, ptr %fp301, align 1
  %and83 = and i64 %ld66, 255
  %cmp84.not = icmp eq i64 %and83, 76
  br i1 %cmp84.not, label %fall25, label %c1

fall25:                                           ; preds = %fall20
  call fastcc void @f18(i64 %ld66, i64 1048728, i64 3, i64 %fp, i64 3)
  %ld91 = load i64, ptr %slot24, align 1
  %slot48 = getelementptr inbounds i8, ptr %frame, i32 48
  %11 = ptrtoint ptr %slot48 to i32
  %fp92 = zext i32 %11 to i64
  call fastcc void @i64_try_from_val(i64 %fp92, i64 %ld91)
  %ld94 = load i32, ptr %slot48, align 1
  %brif96.not = icmp eq i32 %ld94, 0
  br i1 %brif96.not, label %fall26, label %c1

fall26:                                           ; preds = %fall25
  %slot56 = getelementptr inbounds i8, ptr %frame, i32 56
  %ld97 = load i64, ptr %slot56, align 1
  %ld99 = load i64, ptr %fp299, align 1
  call fastcc void @i64_try_from_val(i64 %fp92, i64 %ld99)
  %ld103 = load i32, ptr %slot48, align 1
  %brif105.not = icmp eq i32 %ld103, 0
  br i1 %brif105.not, label %fall27, label %c1

fall27:                                           ; preds = %fall26
  %ld106 = load i64, ptr %fp301, align 1
  %and107 = and i64 %ld106, 255
  %cmp108.not = icmp eq i64 %and107, 75
  br i1 %cmp108.not, label %fall28, label %c1

fall28:                                           ; preds = %fall27
  %ld112 = load i64, ptr %slot56, align 1
  br label %c4

fall29:                                           ; preds = %f17.exit280
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld129 = load i64, ptr %slot24, align 1
  %cmp130.not = icmp eq i64 %ld129, 0
  br i1 %cmp130.not, label %fall30, label %c1

fall30:                                           ; preds = %fall29
  %ld134 = load i64, ptr %fp299, align 1
  %and135 = and i64 %ld134, 255
  %cmp136.not = icmp eq i64 %and135, 4
  br i1 %cmp136.not, label %fall31, label %c1

fall31:                                           ; preds = %fall30
  %lshr140 = lshr i64 %ld134, 32
  %t141 = trunc i64 %lshr140 to i32
  %cmp142 = icmp eq i32 %t141, 15
  %select = select i1 %cmp142, i64 15, i64 9
  %cmp148 = icmp eq i32 %t141, 10
  %select152 = select i1 %cmp148, i64 10, i64 %select
  %cmp154 = icmp eq i64 %select152, 9
  br i1 %cmp154, label %c1, label %c4

fall33:                                           ; preds = %f17.exit
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld173 = load i64, ptr %slot24, align 1
  %cmp174.not = icmp eq i64 %ld173, 0
  br i1 %cmp174.not, label %fall34, label %c1

fall34:                                           ; preds = %fall33
  %ld178 = load i64, ptr %fp299, align 1
  %and179 = and i64 %ld178, 255
  %cmp180.not = icmp eq i64 %and179, 75
  br i1 %cmp180.not, label %fall39, label %c1

fall39:                                           ; preds = %fall34
  %slot48189 = getelementptr inbounds i8, ptr %frame, i32 48
  store i64 2, ptr %slot48189, align 1
  %fp302 = getelementptr inbounds i8, ptr %frame, i32 56
  store i64 2, ptr %fp302, align 1
  %12 = ptrtoint ptr %slot48189 to i32
  %fp201 = zext i32 %12 to i64
  %shl = shl nuw i64 %fp201, 32
  %or = or disjoint i64 %shl, 4
  %to_val202 = call %Val @soroban.val.from_payload(i64 %ld178)
  %to_val203 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_unpack_to_linear_memory = call %Val @vec.vec_unpack_to_linear_memory(%Val %to_val202, %Val %to_val203, %Val %v_u32_2)
  %ld205 = load i64, ptr %slot48189, align 1
  call fastcc void @i64_try_from_val(i64 %fp, i64 %ld205)
  %ld209 = load i64, ptr %slot24, align 1
  %cmp210 = icmp eq i64 %ld209, 1
  br i1 %cmp210, label %c1, label %fall40

fall40:                                           ; preds = %fall39
  %ld214 = load i64, ptr %fp302, align 1
  %and215 = and i64 %ld214, 255
  %cmp216.not = icmp eq i64 %and215, 75
  br i1 %cmp216.not, label %fall41, label %c1

fall41:                                           ; preds = %fall40
  %ld220 = load i64, ptr %fp299, align 1
  br label %c4
}

define internal fastcc void @f15(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %2 = trunc i64 %1 to i32
  %3 = add i32 %2, 8
  %p = inttoptr i32 %3 to ptr
  %v = load i32, ptr %p, align 1
  %4 = add i32 %2, 12
  %p32 = inttoptr i32 %4 to ptr
  %v33 = load i32, ptr %p32, align 1
  %cmp.not = icmp ult i32 %v, %v33
  br i1 %cmp.not, label %fall2, label %entry.c1_crit_edge

entry.c1_crit_edge:                               ; preds = %entry
  %.pre = trunc i64 %0 to i32
  br label %c1

c1:                                               ; preds = %entry.c1_crit_edge, %fall2
  %.pre-phi = phi i32 [ %.pre, %entry.c1_crit_edge ], [ %5, %fall2 ]
  %l2.0 = phi i64 [ 2, %entry.c1_crit_edge ], [ 0, %fall2 ]
  %p34 = inttoptr i32 %.pre-phi to ptr
  store i64 %l2.0, ptr %p34, align 1
  ret void

fall2:                                            ; preds = %entry
  %zx = zext i32 %v to i64
  %p35 = inttoptr i32 %2 to ptr
  %v36 = load i64, ptr %p35, align 1
  %shl = shl nuw i64 %zx, 32
  %or = or disjoint i64 %shl, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v36)
  %to_val10 = tail call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = tail call %Val @vec.vec_get(%Val %to_val, %Val %to_val10)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_get)
  %5 = trunc i64 %0 to i32
  %6 = add i32 %5, 8
  %p37 = inttoptr i32 %6 to ptr
  store i64 %payload, ptr %p37, align 1
  %add = add i32 %v, 1
  store i32 %add, ptr %p, align 1
  br label %c1
}

define internal fastcc void @f18(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) unnamed_addr {
entry:
  %t = trunc i64 %2 to i32
  %t2 = trunc i64 %4 to i32
  %cmp = icmp eq i32 %t, %t2
  br i1 %cmp, label %c1, label %fall2

c1:                                               ; preds = %entry
  %z = shl i64 %1, 32
  %or = or disjoint i64 %z, 4
  %z8 = shl i64 %3, 32
  %or10 = or disjoint i64 %z8, 4
  %z13 = shl i64 %2, 32
  %or15 = or disjoint i64 %z13, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %0)
  %to_val16 = tail call %Val @soroban.val.from_payload(i64 %or)
  %to_val17 = tail call %Val @soroban.val.from_payload(i64 %or10)
  %to_val18 = tail call %Val @soroban.val.from_payload(i64 %or15)
  %map_unpack_to_linear_memory = tail call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %to_val16, %Val %to_val17, %Val %to_val18)
  ret void

fall2:                                            ; preds = %entry
  tail call void @soroban.trap()
  unreachable
}

; Function Attrs: memory(write, inaccessiblemem: readwrite)
define internal fastcc void @i64_try_from_val(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr #18 {
entry:
  %t = trunc i64 %1 to i8
  switch i8 %t, label %c1 [
    i8 65, label %c2
    i8 7, label %c4
  ]

c1:                                               ; preds = %entry, %c2, %c4
  %l1.0 = phi i64 [ %obj_to_i64, %c2 ], [ %ashr, %c4 ], [ 34359740419, %entry ]
  %l3.0 = phi i64 [ 0, %c2 ], [ 0, %c4 ], [ 1, %entry ]
  %2 = trunc i64 %0 to i32
  %p = inttoptr i32 %2 to ptr
  store i64 %l3.0, ptr %p, align 1
  %3 = add i32 %2, 8
  %p18 = inttoptr i32 %3 to ptr
  store i64 %l1.0, ptr %p18, align 1
  ret void

c2:                                               ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %1)
  %obj_to_i64 = tail call i64 @int.obj_to_i64(%Val %to_val)
  br label %c1

c4:                                               ; preds = %entry
  %ashr = ashr i64 %1, 8
  br label %c1
}

; Function Attrs: noinline noreturn
define internal fastcc void @panic() unnamed_addr #19 {
entry:
  tail call fastcc void @panic_fmt_32()
  unreachable
}

define internal fastcc void @f21(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  store i64 2, ptr %frame, align 8
  %fp = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 2, ptr %fp, align 8
  %and = and i64 %1, 255
  %cmp9.not = icmp eq i64 %and, 76
  br i1 %cmp9.not, label %fall6, label %c5

c5:                                               ; preds = %fall6, %fall10, %c7, %entry
  %l4.0 = phi i64 [ 1, %entry ], [ 1, %c7 ], [ 0, %fall10 ], [ 1, %fall6 ]
  %2 = trunc i64 %0 to i32
  %p = inttoptr i32 %2 to ptr
  store i64 %l4.0, ptr %p, align 1
  ret void

fall6:                                            ; preds = %entry
  %3 = ptrtoint ptr %frame to i32
  %fp13 = zext i32 %3 to i64
  %z8 = shl nuw i64 %fp13, 32
  %or10 = or disjoint i64 %z8, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %1)
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val17 = call %Val @soroban.val.from_payload(i64 %or10)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %v_u32_1048752, %Val %to_val17, %Val %v_u32_2)
  %ld = load i64, ptr %frame, align 8
  %t14 = trunc i64 %ld to i8
  switch i8 %t14, label %c5 [
    i8 74, label %c7
    i8 14, label %c7
  ]

c7:                                               ; preds = %fall6, %fall6
  %ld26 = load i64, ptr %fp, align 8
  %and27 = and i64 %ld26, 255
  %cmp28.not = icmp eq i64 %and27, 75
  br i1 %cmp28.not, label %fall10, label %c5

fall10:                                           ; preds = %c7
  %4 = trunc i64 %0 to i32
  %5 = add i32 %4, 16
  %p49 = inttoptr i32 %5 to ptr
  store i64 %ld26, ptr %p49, align 1
  %6 = add i32 %4, 8
  %p50 = inttoptr i32 %6 to ptr
  store i64 %ld, ptr %p50, align 1
  br label %c5
}

define internal fastcc void @f22(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  store i64 2, ptr %frame, align 8
  %fp = getelementptr inbounds i8, ptr %frame, i32 8
  store i64 2, ptr %fp, align 8
  %and = and i64 %1, 255
  %cmp9.not = icmp eq i64 %and, 76
  br i1 %cmp9.not, label %fall6, label %c5

c5:                                               ; preds = %fall6, %fall10, %c7, %entry
  %l4.0 = phi i64 [ 1, %entry ], [ 1, %c7 ], [ 0, %fall10 ], [ 1, %fall6 ]
  %2 = trunc i64 %0 to i32
  %p = inttoptr i32 %2 to ptr
  store i64 %l4.0, ptr %p, align 1
  ret void

fall6:                                            ; preds = %entry
  %3 = ptrtoint ptr %frame to i32
  %fp13 = zext i32 %3 to i64
  %z8 = shl nuw i64 %fp13, 32
  %or10 = or disjoint i64 %z8, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %1)
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val17 = call %Val @soroban.val.from_payload(i64 %or10)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %v_u32_1048752, %Val %to_val17, %Val %v_u32_2)
  %ld = load i64, ptr %frame, align 8
  %t14 = trunc i64 %ld to i8
  switch i8 %t14, label %c5 [
    i8 74, label %c7
    i8 14, label %c7
  ]

c7:                                               ; preds = %fall6, %fall6
  %ld26 = load i64, ptr %fp, align 8
  %and27 = and i64 %ld26, 255
  %cmp28.not = icmp eq i64 %and27, 76
  br i1 %cmp28.not, label %fall10, label %c5

fall10:                                           ; preds = %c7
  %4 = trunc i64 %0 to i32
  %5 = add i32 %4, 16
  %p49 = inttoptr i32 %5 to ptr
  store i64 %ld26, ptr %p49, align 1
  %6 = add i32 %4, 8
  %p50 = inttoptr i32 %6 to ptr
  store i64 %ld, ptr %p50, align 1
  br label %c5
}

define internal fastcc void @f25(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %2 = trunc i64 %1 to i32
  %3 = add i32 %2, 8
  %p = inttoptr i32 %3 to ptr
  %v = load i32, ptr %p, align 1
  %4 = add i32 %2, 12
  %p35 = inttoptr i32 %4 to ptr
  %v36 = load i32, ptr %p35, align 1
  %cmp.not = icmp ult i32 %v, %v36
  br i1 %cmp.not, label %fall2, label %entry.c1_crit_edge

entry.c1_crit_edge:                               ; preds = %entry
  %.pre = trunc i64 %0 to i32
  br label %c1

c1:                                               ; preds = %entry.c1_crit_edge, %i64_try_from_val.exit
  %.pre-phi = phi i32 [ %.pre, %entry.c1_crit_edge ], [ %5, %i64_try_from_val.exit ]
  %l3.0 = phi i64 [ 2, %entry.c1_crit_edge ], [ %l3.041, %i64_try_from_val.exit ]
  %p37 = inttoptr i32 %.pre-phi to ptr
  store i64 %l3.0, ptr %p37, align 1
  ret void

fall2:                                            ; preds = %entry
  %zx = zext i32 %v to i64
  %p38 = inttoptr i32 %2 to ptr
  %v39 = load i64, ptr %p38, align 1
  %shl = shl nuw i64 %zx, 32
  %or = or disjoint i64 %shl, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v39)
  %to_val9 = tail call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = tail call %Val @vec.vec_get(%Val %to_val, %Val %to_val9)
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  %t = trunc i64 %payload to i8
  switch i8 %t, label %i64_try_from_val.exit [
    i8 65, label %c2
    i8 7, label %c4
  ]

c2:                                               ; preds = %fall2
  %to_val40 = call %Val @soroban.val.from_payload(i64 %payload)
  %obj_to_i64 = call i64 @int.obj_to_i64(%Val %to_val40)
  br label %i64_try_from_val.exit

c4:                                               ; preds = %fall2
  %ashr = ashr i64 %payload, 8
  br label %i64_try_from_val.exit

i64_try_from_val.exit:                            ; preds = %fall2, %c2, %c4
  %l1.0 = phi i64 [ %obj_to_i64, %c2 ], [ %ashr, %c4 ], [ 34359740419, %fall2 ]
  %l3.041 = phi i64 [ 0, %c2 ], [ 0, %c4 ], [ 1, %fall2 ]
  %5 = trunc i64 %0 to i32
  %6 = add i32 %5, 8
  %p42 = inttoptr i32 %6 to ptr
  store i64 %l1.0, ptr %p42, align 1
  %add = add i32 %v, 1
  store i32 %add, ptr %p, align 1
  br label %c1
}

define internal fastcc void @f30(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr {
entry:
  %t = trunc i64 %2 to i32
  %cmp = icmp ugt i32 %t, 9
  br i1 %cmp, label %c2, label %h4.preheader

h4.preheader:                                     ; preds = %entry
  %t9 = trunc i64 %1 to i32
  %p = inttoptr i32 %t9 to ptr
  %v = load i8, ptr %p, align 1
  %zx = zext i8 %v to i64
  %t11 = zext i8 %v to i32
  %cmp12 = icmp eq i8 %v, 95
  br i1 %cmp12, label %c8, label %fall9

c1:                                               ; preds = %c2, %c8.8
  %l3.0 = phi i64 [ %payload, %c2 ], [ %or, %c8.8 ]
  %3 = trunc i64 %0 to i32
  %p101 = inttoptr i32 %3 to ptr
  store i64 0, ptr %p101, align 1
  %4 = add i32 %3, 8
  %p102 = inttoptr i32 %4 to ptr
  store i64 %l3.0, ptr %p102, align 1
  ret void

c2:                                               ; preds = %fall13, %fall13.1, %fall13.2, %fall13.3, %fall13.4, %fall13.5, %fall13.6, %fall13.7, %fall13.8, %entry
  %z72 = shl i64 %1, 32
  %or74 = or disjoint i64 %z72, 4
  %z77 = shl i64 %2, 32
  %or79 = or disjoint i64 %z77, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %or74)
  %to_val80 = tail call %Val @soroban.val.from_payload(i64 %or79)
  %symbol_new_from_linear_memory = tail call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val80)
  %payload = tail call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  br label %c1

c8:                                               ; preds = %c10, %c11, %fall14, %h4.preheader
  %l5.0 = phi i64 [ 1, %h4.preheader ], [ %z54, %c11 ], [ %z58, %c10 ], [ %z50, %fall14 ]
  %add.1 = add i32 %t9, 1
  %p.1 = inttoptr i32 %add.1 to ptr
  %v.1 = load i8, ptr %p.1, align 1
  %zx.1 = zext i8 %v.1 to i64
  %t11.1 = zext i8 %v.1 to i32
  %cmp12.1 = icmp eq i8 %v.1, 95
  br i1 %cmp12.1, label %c8.1, label %fall9.1

fall9.1:                                          ; preds = %c8
  %add17.1 = add nuw nsw i32 %t11.1, 208
  %and.1 = and i32 %add17.1, 254
  %cmp22.1 = icmp ult i32 %and.1, 10
  br i1 %cmp22.1, label %c11.1, label %fall12.1

fall12.1:                                         ; preds = %fall9.1
  %add27.1 = add nuw nsw i32 %t11.1, 191
  %and30.1 = and i32 %add27.1, 254
  %cmp33.1 = icmp ult i32 %and30.1, 26
  br i1 %cmp33.1, label %c10.1, label %fall13.1

fall13.1:                                         ; preds = %fall12.1
  %add38.1 = add nuw nsw i32 %t11.1, 159
  %and41.1 = and i32 %add38.1, 254
  %cmp44.1 = icmp ugt i32 %and41.1, 25
  br i1 %cmp44.1, label %c2, label %fall14.1

fall14.1:                                         ; preds = %fall13.1
  %add49.1 = add nuw nsw i64 %zx.1, 4294967237
  %z50.1 = and i64 %add49.1, 4294967295
  br label %c8.1

c10.1:                                            ; preds = %fall12.1
  %add57.1 = add nuw nsw i64 %zx.1, 4294967243
  %z58.1 = and i64 %add57.1, 4294967295
  br label %c8.1

c11.1:                                            ; preds = %fall9.1
  %add53.1 = add nuw nsw i64 %zx.1, 4294967250
  %z54.1 = and i64 %add53.1, 4294967295
  br label %c8.1

c8.1:                                             ; preds = %c11.1, %c10.1, %fall14.1, %c8
  %l5.0.1 = phi i64 [ 1, %c8 ], [ %z54.1, %c11.1 ], [ %z58.1, %c10.1 ], [ %z50.1, %fall14.1 ]
  %and64 = shl nuw nsw i64 %l5.0, 6
  %shl60.1 = and i64 %and64, 16320
  %and64.1 = and i64 %l5.0.1, 255
  %or65.1 = or i64 %and64.1, %shl60.1
  %add.2 = add i32 %t9, 2
  %p.2 = inttoptr i32 %add.2 to ptr
  %v.2 = load i8, ptr %p.2, align 1
  %zx.2 = zext i8 %v.2 to i64
  %t11.2 = zext i8 %v.2 to i32
  %cmp12.2 = icmp eq i8 %v.2, 95
  br i1 %cmp12.2, label %c8.2, label %fall9.2

fall9.2:                                          ; preds = %c8.1
  %add17.2 = add nuw nsw i32 %t11.2, 208
  %and.2 = and i32 %add17.2, 254
  %cmp22.2 = icmp ult i32 %and.2, 10
  br i1 %cmp22.2, label %c11.2, label %fall12.2

fall12.2:                                         ; preds = %fall9.2
  %add27.2 = add nuw nsw i32 %t11.2, 191
  %and30.2 = and i32 %add27.2, 254
  %cmp33.2 = icmp ult i32 %and30.2, 26
  br i1 %cmp33.2, label %c10.2, label %fall13.2

fall13.2:                                         ; preds = %fall12.2
  %add38.2 = add nuw nsw i32 %t11.2, 159
  %and41.2 = and i32 %add38.2, 254
  %cmp44.2 = icmp ugt i32 %and41.2, 25
  br i1 %cmp44.2, label %c2, label %fall14.2

fall14.2:                                         ; preds = %fall13.2
  %add49.2 = add nuw nsw i64 %zx.2, 4294967237
  %z50.2 = and i64 %add49.2, 4294967295
  br label %c8.2

c10.2:                                            ; preds = %fall12.2
  %add57.2 = add nuw nsw i64 %zx.2, 4294967243
  %z58.2 = and i64 %add57.2, 4294967295
  br label %c8.2

c11.2:                                            ; preds = %fall9.2
  %add53.2 = add nuw nsw i64 %zx.2, 4294967250
  %z54.2 = and i64 %add53.2, 4294967295
  br label %c8.2

c8.2:                                             ; preds = %c11.2, %c10.2, %fall14.2, %c8.1
  %l5.0.2 = phi i64 [ 1, %c8.1 ], [ %z54.2, %c11.2 ], [ %z58.2, %c10.2 ], [ %z50.2, %fall14.2 ]
  %add.3 = add i32 %t9, 3
  %p.3 = inttoptr i32 %add.3 to ptr
  %v.3 = load i8, ptr %p.3, align 1
  %zx.3 = zext i8 %v.3 to i64
  %t11.3 = zext i8 %v.3 to i32
  %cmp12.3 = icmp eq i8 %v.3, 95
  br i1 %cmp12.3, label %c8.3, label %fall9.3

fall9.3:                                          ; preds = %c8.2
  %add17.3 = add nuw nsw i32 %t11.3, 208
  %and.3 = and i32 %add17.3, 254
  %cmp22.3 = icmp ult i32 %and.3, 10
  br i1 %cmp22.3, label %c11.3, label %fall12.3

fall12.3:                                         ; preds = %fall9.3
  %add27.3 = add nuw nsw i32 %t11.3, 191
  %and30.3 = and i32 %add27.3, 254
  %cmp33.3 = icmp ult i32 %and30.3, 26
  br i1 %cmp33.3, label %c10.3, label %fall13.3

fall13.3:                                         ; preds = %fall12.3
  %add38.3 = add nuw nsw i32 %t11.3, 159
  %and41.3 = and i32 %add38.3, 254
  %cmp44.3 = icmp ugt i32 %and41.3, 25
  br i1 %cmp44.3, label %c2, label %fall14.3

fall14.3:                                         ; preds = %fall13.3
  %add49.3 = add nuw nsw i64 %zx.3, 4294967237
  %z50.3 = and i64 %add49.3, 4294967295
  br label %c8.3

c10.3:                                            ; preds = %fall12.3
  %add57.3 = add nuw nsw i64 %zx.3, 4294967243
  %z58.3 = and i64 %add57.3, 4294967295
  br label %c8.3

c11.3:                                            ; preds = %fall9.3
  %add53.3 = add nuw nsw i64 %zx.3, 4294967250
  %z54.3 = and i64 %add53.3, 4294967295
  br label %c8.3

c8.3:                                             ; preds = %c11.3, %c10.3, %fall14.3, %c8.2
  %l5.0.3 = phi i64 [ 1, %c8.2 ], [ %z54.3, %c11.3 ], [ %z58.3, %c10.3 ], [ %z50.3, %fall14.3 ]
  %5 = shl nuw nsw i64 %or65.1, 12
  %and64.2 = shl nuw nsw i64 %l5.0.2, 6
  %6 = and i64 %and64.2, 16320
  %shl60.3 = or i64 %5, %6
  %and64.3 = and i64 %l5.0.3, 255
  %or65.3 = or i64 %and64.3, %shl60.3
  %add.4 = add i32 %t9, 4
  %p.4 = inttoptr i32 %add.4 to ptr
  %v.4 = load i8, ptr %p.4, align 1
  %zx.4 = zext i8 %v.4 to i64
  %t11.4 = zext i8 %v.4 to i32
  %cmp12.4 = icmp eq i8 %v.4, 95
  br i1 %cmp12.4, label %c8.4, label %fall9.4

fall9.4:                                          ; preds = %c8.3
  %add17.4 = add nuw nsw i32 %t11.4, 208
  %and.4 = and i32 %add17.4, 254
  %cmp22.4 = icmp ult i32 %and.4, 10
  br i1 %cmp22.4, label %c11.4, label %fall12.4

fall12.4:                                         ; preds = %fall9.4
  %add27.4 = add nuw nsw i32 %t11.4, 191
  %and30.4 = and i32 %add27.4, 254
  %cmp33.4 = icmp ult i32 %and30.4, 26
  br i1 %cmp33.4, label %c10.4, label %fall13.4

fall13.4:                                         ; preds = %fall12.4
  %add38.4 = add nuw nsw i32 %t11.4, 159
  %and41.4 = and i32 %add38.4, 254
  %cmp44.4 = icmp ugt i32 %and41.4, 25
  br i1 %cmp44.4, label %c2, label %fall14.4

fall14.4:                                         ; preds = %fall13.4
  %add49.4 = add nuw nsw i64 %zx.4, 4294967237
  %z50.4 = and i64 %add49.4, 4294967295
  br label %c8.4

c10.4:                                            ; preds = %fall12.4
  %add57.4 = add nuw nsw i64 %zx.4, 4294967243
  %z58.4 = and i64 %add57.4, 4294967295
  br label %c8.4

c11.4:                                            ; preds = %fall9.4
  %add53.4 = add nuw nsw i64 %zx.4, 4294967250
  %z54.4 = and i64 %add53.4, 4294967295
  br label %c8.4

c8.4:                                             ; preds = %c11.4, %c10.4, %fall14.4, %c8.3
  %l5.0.4 = phi i64 [ 1, %c8.3 ], [ %z54.4, %c11.4 ], [ %z58.4, %c10.4 ], [ %z50.4, %fall14.4 ]
  %add.5 = add i32 %t9, 5
  %p.5 = inttoptr i32 %add.5 to ptr
  %v.5 = load i8, ptr %p.5, align 1
  %zx.5 = zext i8 %v.5 to i64
  %t11.5 = zext i8 %v.5 to i32
  %cmp12.5 = icmp eq i8 %v.5, 95
  br i1 %cmp12.5, label %c8.5, label %fall9.5

fall9.5:                                          ; preds = %c8.4
  %add17.5 = add nuw nsw i32 %t11.5, 208
  %and.5 = and i32 %add17.5, 254
  %cmp22.5 = icmp ult i32 %and.5, 10
  br i1 %cmp22.5, label %c11.5, label %fall12.5

fall12.5:                                         ; preds = %fall9.5
  %add27.5 = add nuw nsw i32 %t11.5, 191
  %and30.5 = and i32 %add27.5, 254
  %cmp33.5 = icmp ult i32 %and30.5, 26
  br i1 %cmp33.5, label %c10.5, label %fall13.5

fall13.5:                                         ; preds = %fall12.5
  %add38.5 = add nuw nsw i32 %t11.5, 159
  %and41.5 = and i32 %add38.5, 254
  %cmp44.5 = icmp ugt i32 %and41.5, 25
  br i1 %cmp44.5, label %c2, label %fall14.5

fall14.5:                                         ; preds = %fall13.5
  %add49.5 = add nuw nsw i64 %zx.5, 4294967237
  %z50.5 = and i64 %add49.5, 4294967295
  br label %c8.5

c10.5:                                            ; preds = %fall12.5
  %add57.5 = add nuw nsw i64 %zx.5, 4294967243
  %z58.5 = and i64 %add57.5, 4294967295
  br label %c8.5

c11.5:                                            ; preds = %fall9.5
  %add53.5 = add nuw nsw i64 %zx.5, 4294967250
  %z54.5 = and i64 %add53.5, 4294967295
  br label %c8.5

c8.5:                                             ; preds = %c11.5, %c10.5, %fall14.5, %c8.4
  %l5.0.5 = phi i64 [ 1, %c8.4 ], [ %z54.5, %c11.5 ], [ %z58.5, %c10.5 ], [ %z50.5, %fall14.5 ]
  %7 = shl nuw nsw i64 %or65.3, 12
  %and64.4 = shl nuw nsw i64 %l5.0.4, 6
  %8 = and i64 %and64.4, 16320
  %shl60.5 = or i64 %7, %8
  %and64.5 = and i64 %l5.0.5, 255
  %or65.5 = or i64 %and64.5, %shl60.5
  %add.6 = add i32 %t9, 6
  %p.6 = inttoptr i32 %add.6 to ptr
  %v.6 = load i8, ptr %p.6, align 1
  %zx.6 = zext i8 %v.6 to i64
  %t11.6 = zext i8 %v.6 to i32
  %cmp12.6 = icmp eq i8 %v.6, 95
  br i1 %cmp12.6, label %c8.6, label %fall9.6

fall9.6:                                          ; preds = %c8.5
  %add17.6 = add nuw nsw i32 %t11.6, 208
  %and.6 = and i32 %add17.6, 254
  %cmp22.6 = icmp ult i32 %and.6, 10
  br i1 %cmp22.6, label %c11.6, label %fall12.6

fall12.6:                                         ; preds = %fall9.6
  %add27.6 = add nuw nsw i32 %t11.6, 191
  %and30.6 = and i32 %add27.6, 254
  %cmp33.6 = icmp ult i32 %and30.6, 26
  br i1 %cmp33.6, label %c10.6, label %fall13.6

fall13.6:                                         ; preds = %fall12.6
  %add38.6 = add nuw nsw i32 %t11.6, 159
  %and41.6 = and i32 %add38.6, 254
  %cmp44.6 = icmp ugt i32 %and41.6, 25
  br i1 %cmp44.6, label %c2, label %fall14.6

fall14.6:                                         ; preds = %fall13.6
  %add49.6 = add nuw nsw i64 %zx.6, 4294967237
  %z50.6 = and i64 %add49.6, 4294967295
  br label %c8.6

c10.6:                                            ; preds = %fall12.6
  %add57.6 = add nuw nsw i64 %zx.6, 4294967243
  %z58.6 = and i64 %add57.6, 4294967295
  br label %c8.6

c11.6:                                            ; preds = %fall9.6
  %add53.6 = add nuw nsw i64 %zx.6, 4294967250
  %z54.6 = and i64 %add53.6, 4294967295
  br label %c8.6

c8.6:                                             ; preds = %c11.6, %c10.6, %fall14.6, %c8.5
  %l5.0.6 = phi i64 [ 1, %c8.5 ], [ %z54.6, %c11.6 ], [ %z58.6, %c10.6 ], [ %z50.6, %fall14.6 ]
  %add.7 = add i32 %t9, 7
  %p.7 = inttoptr i32 %add.7 to ptr
  %v.7 = load i8, ptr %p.7, align 1
  %zx.7 = zext i8 %v.7 to i64
  %t11.7 = zext i8 %v.7 to i32
  %cmp12.7 = icmp eq i8 %v.7, 95
  br i1 %cmp12.7, label %c8.7, label %fall9.7

fall9.7:                                          ; preds = %c8.6
  %add17.7 = add nuw nsw i32 %t11.7, 208
  %and.7 = and i32 %add17.7, 254
  %cmp22.7 = icmp ult i32 %and.7, 10
  br i1 %cmp22.7, label %c11.7, label %fall12.7

fall12.7:                                         ; preds = %fall9.7
  %add27.7 = add nuw nsw i32 %t11.7, 191
  %and30.7 = and i32 %add27.7, 254
  %cmp33.7 = icmp ult i32 %and30.7, 26
  br i1 %cmp33.7, label %c10.7, label %fall13.7

fall13.7:                                         ; preds = %fall12.7
  %add38.7 = add nuw nsw i32 %t11.7, 159
  %and41.7 = and i32 %add38.7, 254
  %cmp44.7 = icmp ugt i32 %and41.7, 25
  br i1 %cmp44.7, label %c2, label %fall14.7

fall14.7:                                         ; preds = %fall13.7
  %add49.7 = add nuw nsw i64 %zx.7, 4294967237
  %z50.7 = and i64 %add49.7, 4294967295
  br label %c8.7

c10.7:                                            ; preds = %fall12.7
  %add57.7 = add nuw nsw i64 %zx.7, 4294967243
  %z58.7 = and i64 %add57.7, 4294967295
  br label %c8.7

c11.7:                                            ; preds = %fall9.7
  %add53.7 = add nuw nsw i64 %zx.7, 4294967250
  %z54.7 = and i64 %add53.7, 4294967295
  br label %c8.7

c8.7:                                             ; preds = %c11.7, %c10.7, %fall14.7, %c8.6
  %l5.0.7 = phi i64 [ 1, %c8.6 ], [ %z54.7, %c11.7 ], [ %z58.7, %c10.7 ], [ %z50.7, %fall14.7 ]
  %9 = shl i64 %or65.5, 12
  %and64.6 = shl nuw nsw i64 %l5.0.6, 6
  %10 = and i64 %and64.6, 16320
  %shl60.7 = or i64 %9, %10
  %and64.7 = and i64 %l5.0.7, 255
  %or65.7 = or i64 %and64.7, %shl60.7
  %add.8 = add i32 %t9, 8
  %p.8 = inttoptr i32 %add.8 to ptr
  %v.8 = load i8, ptr %p.8, align 1
  %zx.8 = zext i8 %v.8 to i64
  %t11.8 = zext i8 %v.8 to i32
  %cmp12.8 = icmp eq i8 %v.8, 95
  br i1 %cmp12.8, label %c8.8, label %fall9.8

fall9.8:                                          ; preds = %c8.7
  %add17.8 = add nuw nsw i32 %t11.8, 208
  %and.8 = and i32 %add17.8, 254
  %cmp22.8 = icmp ult i32 %and.8, 10
  br i1 %cmp22.8, label %c11.8, label %fall12.8

fall12.8:                                         ; preds = %fall9.8
  %add27.8 = add nuw nsw i32 %t11.8, 191
  %and30.8 = and i32 %add27.8, 254
  %cmp33.8 = icmp ult i32 %and30.8, 26
  br i1 %cmp33.8, label %c10.8, label %fall13.8

fall13.8:                                         ; preds = %fall12.8
  %add38.8 = add nuw nsw i32 %t11.8, 159
  %and41.8 = and i32 %add38.8, 254
  %cmp44.8 = icmp ugt i32 %and41.8, 25
  br i1 %cmp44.8, label %c2, label %fall14.8

fall14.8:                                         ; preds = %fall13.8
  %add49.8 = add nuw nsw i64 %zx.8, 4294967237
  %z50.8 = and i64 %add49.8, 4294967295
  br label %c8.8

c10.8:                                            ; preds = %fall12.8
  %add57.8 = add nuw nsw i64 %zx.8, 4294967243
  %z58.8 = and i64 %add57.8, 4294967295
  br label %c8.8

c11.8:                                            ; preds = %fall9.8
  %add53.8 = add nuw nsw i64 %zx.8, 4294967250
  %z54.8 = and i64 %add53.8, 4294967295
  br label %c8.8

c8.8:                                             ; preds = %c11.8, %c10.8, %fall14.8, %c8.7
  %l5.0.8 = phi i64 [ 1, %c8.7 ], [ %z54.8, %c11.8 ], [ %z58.8, %c10.8 ], [ %z50.8, %fall14.8 ]
  %11 = shl i64 %or65.7, 14
  %and64.8 = shl nuw nsw i64 %l5.0.8, 8
  %12 = and i64 %and64.8, 65280
  %shl = or i64 %11, %12
  %or = or disjoint i64 %shl, 14
  br label %c1

fall9:                                            ; preds = %h4.preheader
  %add17 = add nuw nsw i32 %t11, 208
  %and = and i32 %add17, 254
  %cmp22 = icmp ult i32 %and, 10
  br i1 %cmp22, label %c11, label %fall12

c10:                                              ; preds = %fall12
  %add57 = add nuw nsw i64 %zx, 4294967243
  %z58 = and i64 %add57, 4294967295
  br label %c8

c11:                                              ; preds = %fall9
  %add53 = add nuw nsw i64 %zx, 4294967250
  %z54 = and i64 %add53, 4294967295
  br label %c8

fall12:                                           ; preds = %fall9
  %add27 = add nuw nsw i32 %t11, 191
  %and30 = and i32 %add27, 254
  %cmp33 = icmp ult i32 %and30, 26
  br i1 %cmp33, label %c10, label %fall13

fall13:                                           ; preds = %fall12
  %add38 = add nuw nsw i32 %t11, 159
  %and41 = and i32 %add38, 254
  %cmp44 = icmp ugt i32 %and41, 25
  br i1 %cmp44, label %c2, label %fall14

fall14:                                           ; preds = %fall13
  %add49 = add nuw nsw i64 %zx, 4294967237
  %z50 = and i64 %add49, 4294967295
  br label %c8
}

; Function Attrs: noinline noreturn
define internal fastcc void @panic_fmt_32() unnamed_addr #20 {
entry:
  tail call void @soroban.trap()
  unreachable
}

declare i64 @soroban.storage_type(i64)

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { noreturn }
attributes #2 = { "soroban.import"="b.m" "soroban.sig"="(Symbol, U32Val, U32Val) -> U32Val" }
attributes #3 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.1" "soroban.sig"="(i64) -> I64Object" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.2" "soroban.sig"="(I64Object) -> i64" }
attributes #6 = { memory(inaccessiblemem: readwrite) "soroban.import"="m.1" "soroban.sig"="(MapObject, Val) -> Val" }
attributes #7 = { memory(inaccessiblemem: readwrite) "soroban.import"="m.4" "soroban.sig"="(MapObject, Val) -> Bool" }
attributes #8 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #9 = { "soroban.import"="m.a" "soroban.sig"="(MapObject, U32Val, U32Val, U32Val) -> Void" }
attributes #10 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.8" "soroban.sig"="(VecObject) -> Val" }
attributes #11 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.1" "soroban.sig"="(VecObject, U32Val) -> Val" }
attributes #12 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.3" "soroban.sig"="(VecObject) -> U32Val" }
attributes #13 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #14 = { "soroban.import"="v.h" "soroban.sig"="(VecObject, U32Val, U32Val) -> Void" }
attributes #15 = { "spec.sig"="fn add(a: UdtEnum, b: UdtEnum) -> i64" }
attributes #16 = { "spec.sig"="fn recursive(a: UdtRecursive) -> Option<UdtRecursive>" }
attributes #17 = { "spec.sig"="fn recursive_enum(a: RecursiveEnum, key: u32) -> Result<Option<RecursiveEnum>, Error>" }
attributes #18 = { memory(write, inaccessiblemem: readwrite) "sdk.name"="<i64 as soroban_env_common::convert::TryFromVal<E,soroban_env_common::val::Val>>::try_from_val" }
attributes #19 = { noinline noreturn "sdk.name"="core::slice::index::slice_index_fail | core::result::unwrap_failed | core::panicking::panic" }
attributes #20 = { noinline noreturn "sdk.name"="core::panicking::panic_fmt" }

!soroban.spec = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9}
!soroban.keys = !{!10, !11, !12}
!soroban.strings = !{!13}
!soroban.rodata = !{!14}

!0 = !{!"fn add(a: UdtEnum, b: UdtEnum) -> i64"}
!1 = !{!"union UdtEnum { UdtA, UdtB(UdtStruct), UdtC(UdtEnum2), UdtD(UdtTuple) }"}
!2 = !{!"enum UdtEnum2 { A = 10, B = 15 }"}
!3 = !{!"struct UdtTuple { 0: i64, 1: Vec<i64> }"}
!4 = !{!"struct UdtStruct { a: i64, b: i64, c: Vec<i64> }"}
!5 = !{!"fn recursive(a: UdtRecursive) -> Option<UdtRecursive>"}
!6 = !{!"struct UdtRecursive { a: Symbol, b: Vec<UdtRecursive> }"}
!7 = !{!"union RecursiveEnum { NotRecursive, Recursive(RecursiveToEnum) }"}
!8 = !{!"struct RecursiveToEnum { a: Symbol, b: Map<u32, RecursiveEnum> }"}
!9 = !{!"fn recursive_enum(a: RecursiveEnum, key: u32) -> Result<Option<RecursiveEnum>, Error>"}
!10 = !{!"1048692 UdtA UdtB UdtC UdtD"}
!11 = !{!"1048752 a b"}
!12 = !{!"1048792 NotRecursive Recursive"}
!13 = !{!"1048768 NotRecursive"}
!14 = !{!"1048576 537045635631f3b0ab40690d48b4537045635631aff793ba9e4dde9a537045635631eb9f12269a76282a53704563563116276438ffc9b1f8537045635631c81291fed713f59c537045635631ff7b5620ab0ddc64537045635631e16f55dbd4379814556474415564744255647443556474440000620010000400000066001000040000006a001000040000006e0010000400000061626300940010000100000095001000010000009600100001000000940010000100000095001000010000004e6f74526563757273697665526563757273697665000000c00010000c000000cc00100009000000"}
