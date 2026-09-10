; sdk 26.0.1 rustc 1.95.0; fingerprints 26.0.1+rustc1.95.0.txt: 5 of 17 helpers named, 1 by shape
; ModuleID = 'ponytail'
source_filename = "ponytail"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

%Val = type { i64 }

@g0 = local_unnamed_addr global i64 1048576
@g1 = local_unnamed_addr constant i64 1048808
@g2 = local_unnamed_addr constant i64 1048808
@g3 = local_unnamed_addr constant i64 1048816

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) local_unnamed_addr #0

; Function Attrs: mustprogress nofree nosync nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) local_unnamed_addr #0

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @ponytail.unknown.i64() local_unnamed_addr #1

; Function Attrs: noreturn
declare void @soroban.trap() local_unnamed_addr #2

declare %Val @buf.symbol_index_in_linear_memory(%Val, %Val, %Val) local_unnamed_addr #3

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) local_unnamed_addr #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @int.obj_from_i64(i64) local_unnamed_addr #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @int.obj_to_i64(%Val) local_unnamed_addr #6

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_get(%Val, %Val) local_unnamed_addr #7

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_has(%Val, %Val) local_unnamed_addr #8

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) local_unnamed_addr #9

declare %Val @map.map_unpack_to_linear_memory(%Val, %Val, %Val, %Val) local_unnamed_addr #10

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_front(%Val) local_unnamed_addr #11

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_get(%Val, %Val) local_unnamed_addr #12

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_len(%Val) local_unnamed_addr #13

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) local_unnamed_addr #14

declare %Val @vec.vec_unpack_to_linear_memory(%Val, %Val, %Val) local_unnamed_addr #15

define "spec.type"="i64" "wasm.type"="i64" %Val @add(%Val "spec.name"="a" "spec.type"="UdtEnum" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="UdtEnum" "wasm.type"="i64" %1) local_unnamed_addr #16 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %frame = alloca [64 x i8], align 8
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 %arg_payload1, ptr %slot8, align 8
  store i64 %arg_payload, ptr %frame, align 8
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  %fp = ptrtoint ptr %slot16 to i64
  %fp3 = ptrtoint ptr %frame to i64
  call fastcc void @f13(i64 %fp, i64 %fp3)
  %ld = load i8, ptr %slot16, align 8
  %cmp = icmp eq i8 %ld, 4
  br i1 %cmp, label %c5, label %fall6

c1:                                               ; preds = %c2, %fall32
  %l1.0 = phi i64 [ %payload160, %c2 ], [ %or, %fall32 ]
  %to_val162 = call %Val @soroban.val.from_payload(i64 %l1.0)
  ret %Val %to_val162

c2:                                               ; preds = %fall31
  %obj_from_i64 = call %Val @int.obj_from_i64(i64 %add147)
  %payload160 = call i64 @soroban.val.payload(%Val %obj_from_i64)
  br label %c1

c3.loopexit:                                      ; preds = %h24, %fall26, %c27
  br label %c3

c3.loopexit218:                                   ; preds = %h12, %fall14, %c15
  br label %c3

c3:                                               ; preds = %c3.loopexit218, %c3.loopexit, %c21, %c8, %c9, %c19, %c20
  call fastcc void @panic()
  unreachable

c4:                                               ; preds = %c8, %c9, %c10, %fall7
  %l1.1 = phi i64 [ 0, %fall7 ], [ %zx8, %c10 ], [ %add60, %c9 ], [ %add71, %c8 ]
  switch i8 %ld14, label %c19 [
    i8 3, label %c23
    i8 1, label %c21
    i8 2, label %c22
  ]

c5:                                               ; preds = %fall6, %entry
  call void @soroban.trap()
  unreachable

fall6:                                            ; preds = %entry
  %slot32 = getelementptr inbounds i8, ptr %frame, i64 32
  %ld5 = load i64, ptr %slot32, align 8
  %slot24 = getelementptr inbounds i8, ptr %frame, i64 24
  %ld6 = load i64, ptr %slot24, align 8
  %slot17 = getelementptr inbounds i8, ptr %frame, i64 17
  %ld7 = load i8, ptr %slot17, align 1
  %zx8 = zext i8 %ld7 to i64
  %fp12 = ptrtoint ptr %slot8 to i64
  call fastcc void @f13(i64 %fp, i64 %fp12)
  %ld14 = load i8, ptr %slot16, align 8
  %cmp16 = icmp eq i8 %ld14, 4
  br i1 %cmp16, label %c5, label %fall7

fall7:                                            ; preds = %fall6
  %ld20 = load i64, ptr %slot32, align 8
  %ld22 = load i64, ptr %slot24, align 8
  %ld24 = load i8, ptr %slot17, align 1
  %zx25 = zext i8 %ld24 to i64
  switch i8 %ld, label %c4 [
    i8 3, label %c11
    i8 1, label %c9
    i8 2, label %c10
  ]

c8:                                               ; preds = %fall14
  %l1.2.lcssa220 = phi i64 [ %l1.2, %fall14 ]
  %add71 = add i64 %l1.2.lcssa220, %ld6
  %2 = icmp slt i64 %l1.2.lcssa220, 0
  %3 = icmp sge i64 %add71, %ld6
  %eqz76 = xor i1 %2, %3
  br i1 %eqz76, label %c4, label %c3

c9:                                               ; preds = %fall7
  %add60 = add i64 %ld6, %ld5
  %4 = icmp slt i64 %ld5, 0
  %5 = icmp sge i64 %add60, %ld6
  %eqz = xor i1 %4, %5
  br i1 %eqz, label %c4, label %c3

c10:                                              ; preds = %fall7
  br label %c4

c11:                                              ; preds = %fall7
  %to_val = call %Val @soroban.val.from_payload(i64 %ld5)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  %slot56 = getelementptr inbounds i8, ptr %frame, i64 56
  store i32 0, ptr %slot56, align 8
  %slot48 = getelementptr inbounds i8, ptr %frame, i64 48
  store i64 %ld5, ptr %slot48, align 8
  %lshr = lshr i64 %payload, 32
  %slot60 = getelementptr inbounds i8, ptr %frame, i64 60
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot60, align 4
  %fp33 = ptrtoint ptr %slot48 to i64
  br label %h12

h12:                                              ; preds = %c15, %c11
  %l1.2 = phi i64 [ 0, %c11 ], [ %add, %c15 ]
  call fastcc void @f25(i64 %fp, i64 %fp33)
  %ld35 = load i64, ptr %slot16, align 8
  %cmp36 = icmp ugt i64 %ld35, 2
  br i1 %cmp36, label %c3.loopexit218, label %fall14

fall14:                                           ; preds = %h12
  %sel40 = trunc i64 %ld35 to i32
  switch i32 %sel40, label %c15 [
    i32 2, label %c8
    i32 1, label %c3.loopexit218
  ]

c15:                                              ; preds = %fall14
  %ld42 = load i64, ptr %slot24, align 8
  %add = add i64 %ld42, %l1.2
  %6 = icmp slt i64 %ld42, 0
  %7 = icmp sge i64 %add, %l1.2
  %cmp50.not199 = xor i1 %6, %7
  br i1 %cmp50.not199, label %h12, label %c3.loopexit218

c19:                                              ; preds = %c20, %c21, %c22, %c4
  %l0.0 = phi i64 [ 0, %c4 ], [ %zx25, %c22 ], [ %add123, %c21 ], [ %add136, %c20 ]
  %add147 = add i64 %l0.0, %l1.1
  %cmp149 = icmp slt i64 %add147, %l1.1
  %8 = icmp slt i64 %l0.0, 0
  %9 = xor i1 %8, %cmp149
  br i1 %9, label %c3, label %fall31

c20:                                              ; preds = %fall26
  %l0.1.lcssa219 = phi i64 [ %l0.1, %fall26 ]
  %add136 = add i64 %l0.1.lcssa219, %ld22
  %cmp138 = icmp slt i64 %add136, %ld22
  %10 = icmp slt i64 %l0.1.lcssa219, 0
  %11 = xor i1 %10, %cmp138
  br i1 %11, label %c3, label %c19

c21:                                              ; preds = %c4
  %add123 = add i64 %ld22, %ld20
  %12 = icmp slt i64 %ld20, 0
  %13 = icmp sge i64 %add123, %ld22
  %eqz128 = xor i1 %12, %13
  br i1 %eqz128, label %c19, label %c3

c22:                                              ; preds = %c4
  br label %c19

c23:                                              ; preds = %c4
  %to_val82 = call %Val @soroban.val.from_payload(i64 %ld20)
  %vec_len83 = call %Val @vec.vec_len(%Val %to_val82)
  %payload84 = call i64 @soroban.val.payload(%Val %vec_len83)
  %slot5685 = getelementptr inbounds i8, ptr %frame, i64 56
  store i32 0, ptr %slot5685, align 8
  %slot4887 = getelementptr inbounds i8, ptr %frame, i64 48
  store i64 %ld20, ptr %slot4887, align 8
  %lshr89 = lshr i64 %payload84, 32
  %slot6090 = getelementptr inbounds i8, ptr %frame, i64 60
  %t91 = trunc i64 %lshr89 to i32
  store i32 %t91, ptr %slot6090, align 4
  %fp95 = ptrtoint ptr %slot4887 to i64
  br label %h24

h24:                                              ; preds = %c27, %c23
  %l0.1 = phi i64 [ 0, %c23 ], [ %add109, %c27 ]
  call fastcc void @f25(i64 %fp, i64 %fp95)
  %ld97 = load i64, ptr %slot16, align 8
  %cmp98 = icmp ugt i64 %ld97, 2
  br i1 %cmp98, label %c3.loopexit, label %fall26

fall26:                                           ; preds = %h24
  %sel102 = trunc i64 %ld97 to i32
  switch i32 %sel102, label %c27 [
    i32 2, label %c20
    i32 1, label %c3.loopexit
  ]

c27:                                              ; preds = %fall26
  %ld104 = load i64, ptr %slot24, align 8
  %add109 = add i64 %ld104, %l0.1
  %14 = icmp slt i64 %ld104, 0
  %15 = icmp sge i64 %add109, %l0.1
  %cmp113.not200 = xor i1 %14, %15
  br i1 %cmp113.not200, label %h24, label %c3.loopexit

fall31:                                           ; preds = %c19
  %16 = add i64 %add147, -36028797018963968
  %cmp155 = icmp ult i64 %16, -72057594037927936
  br i1 %cmp155, label %c2, label %fall32

fall32:                                           ; preds = %fall31
  %shl = shl i64 %add147, 8
  %or = or disjoint i64 %shl, 7
  br label %c1
}

define "spec.type"="Option<UdtRecursive>" "wasm.type"="i64" %Val @recursive(%Val "spec.name"="a" "spec.type"="UdtRecursive" "wasm.type"="i64" %0) local_unnamed_addr #17 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %frame = alloca [32 x i8], align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i32 2, ptr %slot8, align 1
  %fp = ptrtoint ptr %slot8 to i64
  call fastcc void @f21(i64 %fp, i64 %arg_payload)
  %ld4 = load i64, ptr %slot8, align 1
  %cmp = icmp eq i64 %ld4, 1
  br i1 %cmp, label %c1, label %fall2

c1:                                               ; preds = %c4, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %slot24 = getelementptr inbounds i8, ptr %frame, i64 24
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
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  %ld23 = load i64, ptr %slot16, align 1
  %ld25 = load i64, ptr %slot24, align 1
  store i64 %ld25, ptr %slot16, align 1
  store i64 %ld23, ptr %slot8, align 1
  %shl = shl i64 %fp, 32
  %or = or disjoint i64 %shl, 4
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048752, %Val %to_val1, %Val %v_u32_2)
  %payload42 = call i64 @soroban.val.payload(%Val %Map__a____b__)
  br label %c3
}

define "spec.type"="Result<Option<RecursiveEnum>, Error>" "wasm.type"="i64" %Val @recursive_enum(%Val "spec.name"="a" "spec.type"="RecursiveEnum" "wasm.type"="i64" %0, %Val "spec.name"="key" "spec.type"="u32" "wasm.type"="i64" %1) local_unnamed_addr #18 {
entry:
  %arg_payload = tail call i64 @soroban.val.payload(%Val %0)
  %arg_payload1 = tail call i64 @soroban.val.payload(%Val %1)
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i64 24
  store i32 3, ptr %slot24, align 1
  %and = and i64 %arg_payload, 255
  %cmp.not = icmp eq i64 %and, 75
  br i1 %cmp.not, label %fall2, label %c1

c1.sink.split:                                    ; preds = %fall27, %fall19, %fall14, %fall2
  %slot48.sink = phi ptr [ %slot24, %fall2 ], [ %slot48, %fall14 ], [ %slot24, %fall19 ], [ %slot48, %fall27 ]
  store i64 2, ptr %slot48.sink, align 1
  br label %c1

c1:                                               ; preds = %c1.sink.split, %fall2381, %fall2363, %f17.exit, %fall29, %fall2390, %f17.exit259, %f17.exit264, %c21, %fall18, %fall2374, %f17.exit269, %c4, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %arg_payload)
  %vec_len = tail call %Val @vec.vec_len(%Val %to_val)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_len)
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  store i32 0, ptr %slot16, align 1
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 %arg_payload, ptr %slot8, align 1
  %lshr = lshr i64 %payload, 32
  %slot20 = getelementptr inbounds i8, ptr %frame, i64 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %fp = ptrtoint ptr %slot24 to i64
  %bottom = call i64 @ponytail.unknown.i64()
  %brif.not = icmp eq i64 %bottom, 0
  br i1 %brif.not, label %fall2363, label %c1.sink.split

fall2363:                                         ; preds = %fall2
  %v_u32_0 = call %Val @soroban.val.from_payload(i64 4)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %v_u32_0)
  %payload364 = call i64 @soroban.val.payload(%Val %vec_get)
  %fp358 = getelementptr inbounds i8, ptr %frame, i64 32
  store i64 %payload364, ptr %fp358, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %trunc = trunc i64 %payload364 to i8
  switch i8 %trunc, label %c1 [
    i8 74, label %c4
    i8 14, label %c4
  ]

c4:                                               ; preds = %fall2363, %fall2363
  %to_val365 = call %Val @soroban.val.from_payload(i64 %payload364)
  %v_u32_1048792 = call %Val @soroban.val.from_payload(i64 4504527340306436)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val365, %Val %v_u32_1048792, %Val %v_u32_2)
  %payload366 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory)
  %cmp29 = icmp ugt i64 %payload366, 8589934591
  br i1 %cmp29, label %c1, label %fall7

fall7:                                            ; preds = %c4
  %cond.not = icmp ult i64 %payload366, 4294967296
  %ld121 = load i32, ptr %slot16, align 1
  %ld124 = load i32, ptr %slot20, align 1
  %cmp = icmp ult i32 %ld124, %ld121
  br i1 %cond.not, label %c12, label %c13

c8:                                               ; preds = %fall17, %f17.exit264, %fall31, %fall30
  %l0.0 = phi i64 [ %payload403, %fall30 ], [ %payload410, %fall31 ], [ 2, %f17.exit264 ], [ 2, %fall17 ]
  %to_val231 = call %Val @soroban.val.from_payload(i64 %l0.0)
  ret %Val %to_val231

c9:                                               ; preds = %fall24
  br i1 %cmp387, label %c1367, label %f17.exit

c1367:                                            ; preds = %c9
  call fastcc void @panic()
  unreachable

f17.exit:                                         ; preds = %c9
  %brif209.not = icmp eq i32 %ld206, %ld203
  br i1 %brif209.not, label %fall31, label %c1

c10:                                              ; preds = %fall24
  br i1 %cmp387, label %c1368, label %f17.exit259

c1368:                                            ; preds = %c10
  call fastcc void @panic()
  unreachable

f17.exit259:                                      ; preds = %c10
  %zx143 = zext i32 %ld203 to i64
  %zx146 = zext i32 %ld206 to i64
  %sub = sub nsw i64 %zx146, %zx143
  %cmp148 = icmp ugt i64 %sub, 1
  br i1 %cmp148, label %c1, label %fall27

c12:                                              ; preds = %fall7
  br i1 %cmp, label %c1369, label %f17.exit264

c1369:                                            ; preds = %c12
  call fastcc void @panic()
  unreachable

f17.exit264:                                      ; preds = %c12
  %brif127.not = icmp eq i32 %ld124, %ld121
  %and129 = and i64 %arg_payload1, 255
  %cmp130.not = icmp eq i64 %and129, 4
  %or.cond251 = select i1 %brif127.not, i1 %cmp130.not, i1 false
  br i1 %or.cond251, label %c8, label %c1

c13:                                              ; preds = %fall7
  br i1 %cmp, label %c1370, label %f17.exit269

c1370:                                            ; preds = %c13
  call fastcc void @panic()
  unreachable

f17.exit269:                                      ; preds = %c13
  %zx35 = zext i32 %ld121 to i64
  %zx38 = zext i32 %ld124 to i64
  %sub371 = sub nsw i64 %zx38, %zx35
  %cmp40 = icmp ugt i64 %sub371, 1
  br i1 %cmp40, label %c1, label %fall14

fall14:                                           ; preds = %f17.exit269
  %slot48 = getelementptr inbounds i8, ptr %frame, i64 48
  %bottom372 = call i64 @ponytail.unknown.i64()
  %brif.not373 = icmp eq i64 %bottom372, 0
  br i1 %brif.not373, label %fall2374, label %c1.sink.split

fall2374:                                         ; preds = %fall14
  %v = load i64, ptr %slot8, align 1
  %shl = shl nuw i64 %zx35, 32
  %or = or disjoint i64 %shl, 4
  %to_val375 = call %Val @soroban.val.from_payload(i64 %v)
  %to_val8376 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get377 = call %Val @vec.vec_get(%Val %to_val375, %Val %to_val8376)
  %payload378 = call i64 @soroban.val.payload(%Val %vec_get377)
  %fp359 = getelementptr inbounds i8, ptr %frame, i64 56
  store i64 %payload378, ptr %fp359, align 1
  %add = add i32 %ld121, 1
  store i32 %add, ptr %slot16, align 1
  store i64 0, ptr %slot48, align 1
  call fastcc void @f22(i64 %fp, i64 %payload378)
  %ld55 = load i64, ptr %slot24, align 1
  %cmp56 = icmp ne i64 %ld55, 1
  %and60 = and i64 %arg_payload1, 255
  %cmp61.not = icmp eq i64 %and60, 4
  %or.cond = select i1 %cmp56, i1 %cmp61.not, i1 false
  br i1 %or.cond, label %fall17, label %c1

fall17:                                           ; preds = %fall2374
  %slot40 = getelementptr inbounds i8, ptr %frame, i64 40
  %ld64 = load i64, ptr %slot40, align 1
  %and66 = and i64 %arg_payload1, -4294967292
  %to_val67 = call %Val @soroban.val.from_payload(i64 %ld64)
  %to_val68 = call %Val @soroban.val.from_payload(i64 %and66)
  %map_has = call %Val @map.map_has(%Val %to_val67, %Val %to_val68)
  %payload69 = call i64 @soroban.val.payload(%Val %map_has)
  %cmp70.not = icmp eq i64 %payload69, 1
  br i1 %cmp70.not, label %fall18, label %c8

fall18:                                           ; preds = %fall17
  %map_get = call %Val @map.map_get(%Val %to_val67, %Val %to_val68)
  %payload77 = call i64 @soroban.val.payload(%Val %map_get)
  %and78 = and i64 %payload77, 255
  %cmp79.not = icmp eq i64 %and78, 75
  br i1 %cmp79.not, label %fall19, label %c1

fall19:                                           ; preds = %fall18
  %to_val83 = call %Val @soroban.val.from_payload(i64 %payload77)
  %vec_len84 = call %Val @vec.vec_len(%Val %to_val83)
  %payload85 = call i64 @soroban.val.payload(%Val %vec_len84)
  store i32 0, ptr %slot16, align 1
  store i64 %payload77, ptr %slot8, align 1
  %lshr90 = lshr i64 %payload85, 32
  %t92 = trunc i64 %lshr90 to i32
  store i32 %t92, ptr %slot20, align 1
  %bottom379 = call i64 @ponytail.unknown.i64()
  %brif.not380 = icmp eq i64 %bottom379, 0
  br i1 %brif.not380, label %fall2381, label %c1.sink.split

fall2381:                                         ; preds = %fall19
  %vec_get382 = call %Val @vec.vec_get(%Val %to_val83, %Val %v_u32_0)
  %payload383 = call i64 @soroban.val.payload(%Val %vec_get382)
  store i64 %payload383, ptr %fp358, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %trunc353 = trunc i64 %payload383 to i8
  switch i8 %trunc353, label %c1 [
    i8 74, label %c21
    i8 14, label %c21
  ]

c21:                                              ; preds = %fall2381, %fall2381
  %to_val384 = call %Val @soroban.val.from_payload(i64 %payload383)
  %symbol_index_in_linear_memory385 = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val384, %Val %v_u32_1048792, %Val %v_u32_2)
  %payload386 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory385)
  %cmp115 = icmp ugt i64 %payload386, 8589934591
  br i1 %cmp115, label %c1, label %fall24

fall24:                                           ; preds = %c21
  %cond232.not = icmp ult i64 %payload386, 4294967296
  %ld203 = load i32, ptr %slot16, align 1
  %ld206 = load i32, ptr %slot20, align 1
  %cmp387 = icmp ult i32 %ld206, %ld203
  br i1 %cond232.not, label %c9, label %c10

fall27:                                           ; preds = %f17.exit259
  %bottom388 = call i64 @ponytail.unknown.i64()
  %brif.not389 = icmp eq i64 %bottom388, 0
  br i1 %brif.not389, label %fall2390, label %c1.sink.split

fall2390:                                         ; preds = %fall27
  %v391 = load i64, ptr %slot8, align 1
  %shl392 = shl nuw i64 %zx143, 32
  %or393 = or disjoint i64 %shl392, 4
  %to_val394 = call %Val @soroban.val.from_payload(i64 %v391)
  %to_val8395 = call %Val @soroban.val.from_payload(i64 %or393)
  %vec_get396 = call %Val @vec.vec_get(%Val %to_val394, %Val %to_val8395)
  %payload397 = call i64 @soroban.val.payload(%Val %vec_get396)
  store i64 %payload397, ptr %fp359, align 1
  %add398 = add i32 %ld203, 1
  store i32 %add398, ptr %slot16, align 1
  store i64 0, ptr %slot48, align 1
  call fastcc void @f22(i64 %fp, i64 %payload397)
  %ld165 = load i64, ptr %slot24, align 1
  %cmp166 = icmp eq i64 %ld165, 1
  br i1 %cmp166, label %c1, label %fall29

fall29:                                           ; preds = %fall2390
  %ld170 = load i64, ptr %slot40, align 1
  %ld172 = load i64, ptr %fp358, align 1
  store i32 3, ptr %slot24, align 1
  call fastcc void @f30(i64 %fp, i64 1048780, i64 9)
  %ld184 = load i32, ptr %slot24, align 1
  %brif186.not = icmp eq i32 %ld184, 0
  br i1 %brif186.not, label %fall30, label %c1

fall30:                                           ; preds = %fall29
  %ld188 = load i64, ptr %fp358, align 1
  store i64 %ld170, ptr %fp358, align 1
  store i64 %ld172, ptr %slot24, align 1
  %shl399 = shl i64 %fp, 32
  %or400 = or disjoint i64 %shl399, 4
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %or400)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048752, %Val %to_val1, %Val %v_u32_2)
  %payload402 = call i64 @soroban.val.payload(%Val %Map__a____b__)
  store i64 %payload402, ptr %fp358, align 1
  store i64 %ld188, ptr %slot24, align 1
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val1, %Val %v_u32_2)
  %payload403 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  br label %c8

fall31:                                           ; preds = %f17.exit
  store i32 3, ptr %slot24, align 1
  %v_u32_1048768 = call %Val @soroban.val.from_payload(i64 4504424261091332)
  %v_u32_12 = call %Val @soroban.val.from_payload(i64 51539607556)
  %Symbol__NotRecursive__ = call %Val @buf.symbol_new_from_linear_memory(%Val %v_u32_1048768, %Val %v_u32_12)
  %payload405 = call i64 @soroban.val.payload(%Val %Symbol__NotRecursive__)
  store i64 %payload405, ptr %fp358, align 1
  store i64 %payload405, ptr %slot24, align 1
  %shl406 = shl i64 %fp, 32
  %or407 = or disjoint i64 %shl406, 4
  %to_val408 = call %Val @soroban.val.from_payload(i64 %or407)
  %v_u32_1 = call %Val @soroban.val.from_payload(i64 4294967300)
  %vec_new_from_linear_memory409 = call %Val @vec.vec_new_from_linear_memory(%Val %to_val408, %Val %v_u32_1)
  %payload410 = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory409)
  br label %c8
}

define internal fastcc void @f13(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr inbounds i8, ptr %frame, i64 24
  %p = inttoptr i64 %1 to ptr
  %v = load i64, ptr %p, align 1
  %and = and i64 %v, 255
  %cmp = icmp eq i64 %and, 75
  br i1 %cmp, label %c2, label %c1

c1:                                               ; preds = %c2, %fall2, %c10, %f17.exit263, %f17.exit258, %fall19, %fall20, %fall25, %fall26, %fall27, %f17.exit253, %fall29, %fall30, %fall31, %f17.exit, %fall33, %fall34, %fall39, %fall40, %entry, %c4
  %l5.0.sink = phi i8 [ %l5.0, %c4 ], [ 4, %entry ], [ 4, %fall40 ], [ 4, %fall39 ], [ 4, %fall34 ], [ 4, %fall33 ], [ 4, %f17.exit ], [ 4, %fall31 ], [ 4, %fall30 ], [ 4, %fall29 ], [ 4, %f17.exit253 ], [ 4, %fall27 ], [ 4, %fall26 ], [ 4, %fall25 ], [ 4, %fall20 ], [ 4, %fall19 ], [ 4, %f17.exit258 ], [ 4, %f17.exit263 ], [ 4, %c10 ], [ 4, %fall2 ], [ 4, %c2 ]
  %p271 = inttoptr i64 %0 to ptr
  store i8 %l5.0.sink, ptr %p271, align 1
  ret void

c2:                                               ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v)
  %vec_len = tail call %Val @vec.vec_len(%Val %to_val)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_len)
  %slot16 = getelementptr inbounds i8, ptr %frame, i64 16
  %slot8 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 %v, ptr %slot8, align 1
  %lshr = lshr i64 %payload, 32
  %slot20 = getelementptr inbounds i8, ptr %frame, i64 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %fp = ptrtoint ptr %slot24 to i64
  %fp13 = ptrtoint ptr %slot8 to i64
  %bottom272 = call i64 @ponytail.unknown.i64()
  %brif.not = icmp eq i64 %bottom272, 0
  br i1 %brif.not, label %fall2, label %c1

fall2:                                            ; preds = %c2
  %v_u32_0 = call %Val @soroban.val.from_payload(i64 4)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %v_u32_0)
  %payload273 = call i64 @soroban.val.payload(%Val %vec_get)
  %fp267 = getelementptr inbounds i8, ptr %frame, i64 32
  store i64 %payload273, ptr %fp267, align 1
  store i32 1, ptr %slot16, align 1
  store i64 0, ptr %slot24, align 1
  %and20 = and i64 %payload273, 255
  %trunc = trunc i64 %payload273 to i8
  switch i8 %trunc, label %c1 [
    i8 74, label %c10
    i8 14, label %c10
  ]

c4:                                               ; preds = %fall31, %f17.exit263, %fall41, %fall28
  %l1.0 = phi i64 [ 24, %fall28 ], [ 16, %fall41 ], [ %and20, %f17.exit263 ], [ %bottom, %fall31 ]
  %l3.0 = phi i64 [ %ld102, %fall28 ], [ %ld188, %fall41 ], [ %lshr29, %f17.exit263 ], [ %ld123, %fall31 ]
  %l4.0 = phi i64 [ %ld87, %fall28 ], [ %ld194, %fall41 ], [ %payload, %f17.exit263 ], [ %payload, %fall31 ]
  %l5.0 = phi i8 [ 1, %fall28 ], [ 3, %fall41 ], [ 0, %f17.exit263 ], [ 2, %fall31 ]
  %l6.0 = phi i64 [ %ld96, %fall28 ], [ 0, %fall41 ], [ 0, %f17.exit263 ], [ 0, %fall31 ]
  %ea = add i64 %0, 24
  %p274 = inttoptr i64 %ea to ptr
  store i64 %l6.0, ptr %p274, align 1
  %ea201 = add i64 %0, 16
  %p275 = inttoptr i64 %ea201 to ptr
  store i64 %l3.0, ptr %p275, align 1
  %ea204 = add i64 %0, 8
  %p276 = inttoptr i64 %ea204 to ptr
  store i64 %l4.0, ptr %p276, align 1
  %ea207 = add i64 %0, 1
  %t277 = trunc i64 %l1.0 to i8
  %p278 = inttoptr i64 %ea207 to ptr
  store i8 %t277, ptr %p278, align 1
  br label %c1

c10:                                              ; preds = %fall2, %fall2
  %to_val279 = call %Val @soroban.val.from_payload(i64 %payload273)
  %v_u32_1048692 = call %Val @soroban.val.from_payload(i64 4504097843576836)
  %v_u32_4 = call %Val @soroban.val.from_payload(i64 17179869188)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val279, %Val %v_u32_1048692, %Val %v_u32_4)
  %payload280 = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory)
  %lshr29 = lshr i64 %payload280, 32
  %cmp30 = icmp ugt i64 %payload280, 17179869183
  br i1 %cmp30, label %c1, label %fall13

fall13:                                           ; preds = %c10
  %sel = trunc i64 %lshr29 to i32
  %ld35 = load i32, ptr %slot16, align 1
  %ld38 = load i32, ptr %slot20, align 1
  %cmp281 = icmp ult i32 %ld38, %ld35
  switch i32 %sel, label %c17 [
    i32 3, label %c14
    i32 1, label %c16
    i32 2, label %c15
  ]

c14:                                              ; preds = %fall13
  br i1 %cmp281, label %c1282, label %f17.exit

c1282:                                            ; preds = %c14
  call fastcc void @panic()
  unreachable

f17.exit:                                         ; preds = %c14
  %zx140 = zext i32 %ld35 to i64
  %zx143 = zext i32 %ld38 to i64
  %sub = sub nsw i64 %zx143, %zx140
  %cmp145 = icmp ugt i64 %sub, 1
  br i1 %cmp145, label %c1, label %fall33

c15:                                              ; preds = %fall13
  br i1 %cmp281, label %c1283, label %f17.exit253

c1283:                                            ; preds = %c15
  call fastcc void @panic()
  unreachable

f17.exit253:                                      ; preds = %c15
  %zx105 = zext i32 %ld35 to i64
  %zx108 = zext i32 %ld38 to i64
  %sub284 = sub nsw i64 %zx108, %zx105
  %cmp110 = icmp ugt i64 %sub284, 1
  br i1 %cmp110, label %c1, label %fall29

c16:                                              ; preds = %fall13
  br i1 %cmp281, label %c1285, label %f17.exit258

c1285:                                            ; preds = %c16
  call fastcc void @panic()
  unreachable

f17.exit258:                                      ; preds = %c16
  %zx44 = zext i32 %ld35 to i64
  %zx47 = zext i32 %ld38 to i64
  %sub286 = sub nsw i64 %zx47, %zx44
  %cmp49 = icmp ugt i64 %sub286, 1
  br i1 %cmp49, label %c1, label %fall19

c17:                                              ; preds = %fall13
  br i1 %cmp281, label %c1287, label %f17.exit263

c1287:                                            ; preds = %c17
  call fastcc void @panic()
  unreachable

f17.exit263:                                      ; preds = %c17
  %brif41.not = icmp eq i32 %ld38, %ld35
  br i1 %brif41.not, label %c4, label %c1

fall19:                                           ; preds = %f17.exit258
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld57 = load i64, ptr %slot24, align 1
  %cmp58.not = icmp eq i64 %ld57, 0
  br i1 %cmp58.not, label %fall20, label %c1

fall20:                                           ; preds = %fall19
  %ld62 = load i64, ptr %fp267, align 1
  store i64 2, ptr %slot24, align 1
  store i64 2, ptr %fp267, align 1
  %fp269 = getelementptr inbounds i8, ptr %frame, i64 40
  store i64 2, ptr %fp269, align 1
  %and73 = and i64 %ld62, 255
  %cmp74.not = icmp eq i64 %and73, 76
  br i1 %cmp74.not, label %fall25, label %c1

fall25:                                           ; preds = %fall20
  call fastcc void @f18(i64 %ld62, i64 1048728, i64 3, i64 %fp, i64 3)
  %ld81 = load i64, ptr %slot24, align 1
  %slot48 = getelementptr inbounds i8, ptr %frame, i64 48
  %fp82 = ptrtoint ptr %slot48 to i64
  call fastcc void @i64_try_from_val(i64 %fp82, i64 %ld81)
  %ld84 = load i32, ptr %slot48, align 1
  %brif86.not = icmp eq i32 %ld84, 0
  br i1 %brif86.not, label %fall26, label %c1

fall26:                                           ; preds = %fall25
  %slot56 = getelementptr inbounds i8, ptr %frame, i64 56
  %ld87 = load i64, ptr %slot56, align 1
  %ld89 = load i64, ptr %fp267, align 1
  call fastcc void @i64_try_from_val(i64 %fp82, i64 %ld89)
  %ld93 = load i32, ptr %slot48, align 1
  %brif95.not = icmp eq i32 %ld93, 0
  br i1 %brif95.not, label %fall27, label %c1

fall27:                                           ; preds = %fall26
  %ld96 = load i64, ptr %fp269, align 1
  %and97 = and i64 %ld96, 255
  %cmp98.not = icmp eq i64 %and97, 75
  br i1 %cmp98.not, label %fall28, label %c1

fall28:                                           ; preds = %fall27
  %ld102 = load i64, ptr %slot56, align 1
  br label %c4

fall29:                                           ; preds = %f17.exit253
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld118 = load i64, ptr %slot24, align 1
  %cmp119.not = icmp eq i64 %ld118, 0
  br i1 %cmp119.not, label %fall30, label %c1

fall30:                                           ; preds = %fall29
  %ld123 = load i64, ptr %fp267, align 1
  %and124 = and i64 %ld123, 255
  %cmp125.not = icmp eq i64 %and124, 4
  br i1 %cmp125.not, label %fall31, label %c1

fall31:                                           ; preds = %fall30
  %bottom = call i64 @ponytail.unknown.i64()
  %cmp135 = icmp eq i64 %bottom, 9
  br i1 %cmp135, label %c1, label %c4

fall33:                                           ; preds = %f17.exit
  call fastcc void @f15(i64 %fp, i64 %fp13)
  %ld153 = load i64, ptr %slot24, align 1
  %cmp154.not = icmp eq i64 %ld153, 0
  br i1 %cmp154.not, label %fall34, label %c1

fall34:                                           ; preds = %fall33
  %ld158 = load i64, ptr %fp267, align 1
  %and159 = and i64 %ld158, 255
  %cmp160.not = icmp eq i64 %and159, 75
  br i1 %cmp160.not, label %fall39, label %c1

fall39:                                           ; preds = %fall34
  %slot48168 = getelementptr inbounds i8, ptr %frame, i64 48
  store i64 2, ptr %slot48168, align 1
  %fp270 = getelementptr inbounds i8, ptr %frame, i64 56
  store i64 2, ptr %fp270, align 1
  %fp175 = ptrtoint ptr %slot48168 to i64
  %shl = shl i64 %fp175, 32
  %or = or disjoint i64 %shl, 4
  %to_val176 = call %Val @soroban.val.from_payload(i64 %ld158)
  %to_val177 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_unpack_to_linear_memory = call %Val @vec.vec_unpack_to_linear_memory(%Val %to_val176, %Val %to_val177, %Val %v_u32_2)
  %ld179 = load i64, ptr %slot48168, align 1
  call fastcc void @i64_try_from_val(i64 %fp, i64 %ld179)
  %ld183 = load i64, ptr %slot24, align 1
  %cmp184 = icmp eq i64 %ld183, 1
  br i1 %cmp184, label %c1, label %fall40

fall40:                                           ; preds = %fall39
  %ld188 = load i64, ptr %fp270, align 1
  %and189 = and i64 %ld188, 255
  %cmp190.not = icmp eq i64 %and189, 75
  br i1 %cmp190.not, label %fall41, label %c1

fall41:                                           ; preds = %fall40
  %ld194 = load i64, ptr %fp267, align 1
  br label %c4
}

define internal fastcc void @f15(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %ea = add i64 %1, 8
  %p = inttoptr i64 %ea to ptr
  %v = load i32, ptr %p, align 1
  %bottom = tail call i64 @ponytail.unknown.i64()
  %brif.not = icmp eq i64 %bottom, 0
  br i1 %brif.not, label %fall2, label %c1

c1:                                               ; preds = %fall2, %entry
  %l2.0 = phi i64 [ 2, %entry ], [ 0, %fall2 ]
  %p28 = inttoptr i64 %0 to ptr
  store i64 %l2.0, ptr %p28, align 1
  ret void

fall2:                                            ; preds = %entry
  %zx = zext i32 %v to i64
  %p29 = inttoptr i64 %1 to ptr
  %v30 = load i64, ptr %p29, align 1
  %shl = shl nuw i64 %zx, 32
  %or = or disjoint i64 %shl, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v30)
  %to_val8 = tail call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = tail call %Val @vec.vec_get(%Val %to_val, %Val %to_val8)
  %payload = tail call i64 @soroban.val.payload(%Val %vec_get)
  %ea9 = add i64 %0, 8
  %p31 = inttoptr i64 %ea9 to ptr
  store i64 %payload, ptr %p31, align 1
  %add = add i32 %v, 1
  store i32 %add, ptr %p, align 1
  br label %c1
}

define internal fastcc void @f18(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) unnamed_addr {
entry:
  %cmp = icmp eq i64 %2, %4
  br i1 %cmp, label %c1, label %fall2

c1:                                               ; preds = %entry
  %shl = shl nuw nsw i64 %1, 32
  %or = or disjoint i64 %shl, 4
  %shl5 = shl i64 %3, 32
  %or6 = or disjoint i64 %shl5, 4
  %shl8 = shl nuw nsw i64 %2, 32
  %or9 = or disjoint i64 %shl8, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %0)
  %to_val10 = tail call %Val @soroban.val.from_payload(i64 %or)
  %to_val11 = tail call %Val @soroban.val.from_payload(i64 %or6)
  %to_val12 = tail call %Val @soroban.val.from_payload(i64 %or9)
  %map_unpack_to_linear_memory = tail call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %to_val10, %Val %to_val11, %Val %to_val12)
  ret void

fall2:                                            ; preds = %entry
  tail call void @soroban.trap()
  unreachable
}

; Function Attrs: memory(write, inaccessiblemem: readwrite)
define internal fastcc void @i64_try_from_val(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr #19 {
entry:
  %trunc = trunc i64 %1 to i8
  switch i8 %trunc, label %c1 [
    i8 65, label %c2
    i8 7, label %c4
  ]

c1:                                               ; preds = %entry, %c2, %c4
  %l1.0 = phi i64 [ %obj_to_i64, %c2 ], [ %ashr, %c4 ], [ 34359740419, %entry ]
  %l3.0 = phi i64 [ 0, %c2 ], [ 0, %c4 ], [ 1, %entry ]
  %p = inttoptr i64 %0 to ptr
  store i64 %l3.0, ptr %p, align 1
  %ea = add i64 %0, 8
  %p16 = inttoptr i64 %ea to ptr
  store i64 %l1.0, ptr %p16, align 1
  ret void

c2:                                               ; preds = %entry
  %to_val = tail call %Val @soroban.val.from_payload(i64 %1)
  %obj_to_i64 = tail call i64 @int.obj_to_i64(%Val %to_val)
  br label %c1

c4:                                               ; preds = %entry
  %ashr = ashr i64 %1, 8
  br label %c1
}

; Function Attrs: noreturn
define internal fastcc void @panic() unnamed_addr #20 {
entry:
  tail call fastcc void @panic_fmt_32()
  unreachable
}

define internal fastcc void @f21(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  store i64 2, ptr %frame, align 8
  %fp41 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 2, ptr %fp41, align 8
  %and = and i64 %1, 255
  %cmp5.not = icmp eq i64 %and, 76
  br i1 %cmp5.not, label %fall6, label %c5

c5:                                               ; preds = %fall6, %fall10, %c7, %entry
  %l4.0 = phi i64 [ 1, %entry ], [ 1, %c7 ], [ 0, %fall10 ], [ 1, %fall6 ]
  %p = inttoptr i64 %0 to ptr
  store i64 %l4.0, ptr %p, align 1
  ret void

fall6:                                            ; preds = %entry
  %fp9 = ptrtoint ptr %frame to i64
  %shl5 = shl i64 %fp9, 32
  %or6 = or disjoint i64 %shl5, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %1)
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val11 = call %Val @soroban.val.from_payload(i64 %or6)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %v_u32_1048752, %Val %to_val11, %Val %v_u32_2)
  %ld = load i64, ptr %frame, align 8
  %trunc = trunc i64 %ld to i8
  switch i8 %trunc, label %c5 [
    i8 74, label %c7
    i8 14, label %c7
  ]

c7:                                               ; preds = %fall6, %fall6
  %ld18 = load i64, ptr %fp41, align 8
  %and19 = and i64 %ld18, 255
  %cmp20.not = icmp eq i64 %and19, 75
  br i1 %cmp20.not, label %fall10, label %c5

fall10:                                           ; preds = %c7
  %ea = add i64 %0, 16
  %p42 = inttoptr i64 %ea to ptr
  store i64 %ld18, ptr %p42, align 1
  %ea27 = add i64 %0, 8
  %p43 = inttoptr i64 %ea27 to ptr
  store i64 %ld, ptr %p43, align 1
  br label %c5
}

define internal fastcc void @f22(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) unnamed_addr {
entry:
  %frame = alloca [16 x i8], align 8
  store i64 2, ptr %frame, align 8
  %fp41 = getelementptr inbounds i8, ptr %frame, i64 8
  store i64 2, ptr %fp41, align 8
  %and = and i64 %1, 255
  %cmp5.not = icmp eq i64 %and, 76
  br i1 %cmp5.not, label %fall6, label %c5

c5:                                               ; preds = %fall6, %fall10, %c7, %entry
  %l4.0 = phi i64 [ 1, %entry ], [ 1, %c7 ], [ 0, %fall10 ], [ 1, %fall6 ]
  %p = inttoptr i64 %0 to ptr
  store i64 %l4.0, ptr %p, align 1
  ret void

fall6:                                            ; preds = %entry
  %fp9 = ptrtoint ptr %frame to i64
  %shl5 = shl i64 %fp9, 32
  %or6 = or disjoint i64 %shl5, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %1)
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val11 = call %Val @soroban.val.from_payload(i64 %or6)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %v_u32_1048752, %Val %to_val11, %Val %v_u32_2)
  %ld = load i64, ptr %frame, align 8
  %trunc = trunc i64 %ld to i8
  switch i8 %trunc, label %c5 [
    i8 74, label %c7
    i8 14, label %c7
  ]

c7:                                               ; preds = %fall6, %fall6
  %ld18 = load i64, ptr %fp41, align 8
  %and19 = and i64 %ld18, 255
  %cmp20.not = icmp eq i64 %and19, 76
  br i1 %cmp20.not, label %fall10, label %c5

fall10:                                           ; preds = %c7
  %ea = add i64 %0, 16
  %p42 = inttoptr i64 %ea to ptr
  store i64 %ld18, ptr %p42, align 1
  %ea27 = add i64 %0, 8
  %p43 = inttoptr i64 %ea27 to ptr
  store i64 %ld, ptr %p43, align 1
  br label %c5
}

define internal fastcc void @f25(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) unnamed_addr {
entry:
  %ea = add i64 %1, 8
  %p = inttoptr i64 %ea to ptr
  %v = load i32, ptr %p, align 1
  %bottom = tail call i64 @ponytail.unknown.i64()
  %brif.not = icmp eq i64 %bottom, 0
  br i1 %brif.not, label %fall2, label %c1

c1:                                               ; preds = %i64_try_from_val.exit, %entry
  %l3.0 = phi i64 [ 2, %entry ], [ %l3.035, %i64_try_from_val.exit ]
  %p31 = inttoptr i64 %0 to ptr
  store i64 %l3.0, ptr %p31, align 1
  ret void

fall2:                                            ; preds = %entry
  %zx = zext i32 %v to i64
  %p32 = inttoptr i64 %1 to ptr
  %v33 = load i64, ptr %p32, align 1
  %shl = shl nuw i64 %zx, 32
  %or = or disjoint i64 %shl, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %v33)
  %to_val7 = tail call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = tail call %Val @vec.vec_get(%Val %to_val, %Val %to_val7)
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  %trunc = trunc i64 %payload to i8
  switch i8 %trunc, label %i64_try_from_val.exit [
    i8 65, label %c2
    i8 7, label %c4
  ]

c2:                                               ; preds = %fall2
  %to_val34 = call %Val @soroban.val.from_payload(i64 %payload)
  %obj_to_i64 = call i64 @int.obj_to_i64(%Val %to_val34)
  br label %i64_try_from_val.exit

c4:                                               ; preds = %fall2
  %ashr = ashr i64 %payload, 8
  br label %i64_try_from_val.exit

i64_try_from_val.exit:                            ; preds = %fall2, %c2, %c4
  %l1.0 = phi i64 [ %obj_to_i64, %c2 ], [ %ashr, %c4 ], [ 34359740419, %fall2 ]
  %l3.035 = phi i64 [ 0, %c2 ], [ 0, %c4 ], [ 1, %fall2 ]
  %ea11 = add i64 %0, 8
  %p36 = inttoptr i64 %ea11 to ptr
  store i64 %l1.0, ptr %p36, align 1
  %add = add i32 %v, 1
  store i32 %add, ptr %p, align 1
  br label %c1
}

define internal fastcc void @f30(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) unnamed_addr {
entry:
  %cmp = icmp ugt i64 %2, 9
  br i1 %cmp, label %c2, label %c6.preheader

c6.preheader:                                     ; preds = %entry
  %p = inttoptr i64 %1 to ptr
  %v = load i8, ptr %p, align 1
  %zx = zext i8 %v to i64
  %cmp8 = icmp eq i8 %v, 95
  br i1 %cmp8, label %c8, label %fall9

c1:                                               ; preds = %c2, %c8.8
  %l3.0 = phi i64 [ %payload, %c2 ], [ %or, %c8.8 ]
  %p66 = inttoptr i64 %0 to ptr
  store i64 0, ptr %p66, align 1
  %ea = add i64 %0, 8
  %p67 = inttoptr i64 %ea to ptr
  store i64 %l3.0, ptr %p67, align 1
  ret void

c2:                                               ; preds = %fall13, %fall13.1, %fall13.2, %fall13.3, %fall13.4, %fall13.5, %fall13.6, %fall13.7, %fall13.8, %entry
  %shl40 = shl nuw nsw i64 %1, 32
  %or41 = or disjoint i64 %shl40, 4
  %shl43 = shl nuw nsw i64 %2, 32
  %or44 = or disjoint i64 %shl43, 4
  %to_val = tail call %Val @soroban.val.from_payload(i64 %or41)
  %to_val45 = tail call %Val @soroban.val.from_payload(i64 %or44)
  %symbol_new_from_linear_memory = tail call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val45)
  %payload = tail call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  br label %c1

c8:                                               ; preds = %c10, %c11, %fall14, %c6.preheader
  %l5.0 = phi i64 [ 1, %c6.preheader ], [ %add29, %c11 ], [ %add31, %c10 ], [ %add27, %fall14 ]
  %add.1 = add i64 %1, 1
  %p.1 = inttoptr i64 %add.1 to ptr
  %v.1 = load i8, ptr %p.1, align 1
  %zx.1 = zext i8 %v.1 to i64
  %cmp8.1 = icmp eq i8 %v.1, 95
  br i1 %cmp8.1, label %c8.1, label %fall9.1

fall9.1:                                          ; preds = %c8
  %add12.1 = add nuw nsw i64 %zx.1, 208
  %and.1 = and i64 %add12.1, 254
  %cmp13.1 = icmp ult i64 %and.1, 10
  br i1 %cmp13.1, label %c11.1, label %fall12.1

fall12.1:                                         ; preds = %fall9.1
  %add17.1 = add nuw nsw i64 %zx.1, 191
  %and18.1 = and i64 %add17.1, 254
  %cmp19.1 = icmp ult i64 %and18.1, 26
  br i1 %cmp19.1, label %c10.1, label %fall13.1

fall13.1:                                         ; preds = %fall12.1
  %bottom.1 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.1 = icmp eq i64 %bottom.1, 0
  br i1 %brif25.not.1, label %fall14.1, label %c2

fall14.1:                                         ; preds = %fall13.1
  %add27.1 = add nsw i64 %zx.1, -59
  br label %c8.1

c10.1:                                            ; preds = %fall12.1
  %add31.1 = add nsw i64 %zx.1, -53
  br label %c8.1

c11.1:                                            ; preds = %fall9.1
  %add29.1 = add nsw i64 %zx.1, -46
  br label %c8.1

c8.1:                                             ; preds = %c11.1, %c10.1, %fall14.1, %c8
  %l5.0.1 = phi i64 [ 1, %c8 ], [ %add29.1, %c11.1 ], [ %add31.1, %c10.1 ], [ %add27.1, %fall14.1 ]
  %and35 = shl nsw i64 %l5.0, 6
  %shl33.1 = and i64 %and35, 16320
  %and35.1 = and i64 %l5.0.1, 255
  %or36.1 = or i64 %and35.1, %shl33.1
  %add.2 = add i64 %1, 2
  %p.2 = inttoptr i64 %add.2 to ptr
  %v.2 = load i8, ptr %p.2, align 1
  %zx.2 = zext i8 %v.2 to i64
  %cmp8.2 = icmp eq i8 %v.2, 95
  br i1 %cmp8.2, label %c8.2, label %fall9.2

fall9.2:                                          ; preds = %c8.1
  %add12.2 = add nuw nsw i64 %zx.2, 208
  %and.2 = and i64 %add12.2, 254
  %cmp13.2 = icmp ult i64 %and.2, 10
  br i1 %cmp13.2, label %c11.2, label %fall12.2

fall12.2:                                         ; preds = %fall9.2
  %add17.2 = add nuw nsw i64 %zx.2, 191
  %and18.2 = and i64 %add17.2, 254
  %cmp19.2 = icmp ult i64 %and18.2, 26
  br i1 %cmp19.2, label %c10.2, label %fall13.2

fall13.2:                                         ; preds = %fall12.2
  %bottom.2 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.2 = icmp eq i64 %bottom.2, 0
  br i1 %brif25.not.2, label %fall14.2, label %c2

fall14.2:                                         ; preds = %fall13.2
  %add27.2 = add nsw i64 %zx.2, -59
  br label %c8.2

c10.2:                                            ; preds = %fall12.2
  %add31.2 = add nsw i64 %zx.2, -53
  br label %c8.2

c11.2:                                            ; preds = %fall9.2
  %add29.2 = add nsw i64 %zx.2, -46
  br label %c8.2

c8.2:                                             ; preds = %c11.2, %c10.2, %fall14.2, %c8.1
  %l5.0.2 = phi i64 [ 1, %c8.1 ], [ %add29.2, %c11.2 ], [ %add31.2, %c10.2 ], [ %add27.2, %fall14.2 ]
  %add.3 = add i64 %1, 3
  %p.3 = inttoptr i64 %add.3 to ptr
  %v.3 = load i8, ptr %p.3, align 1
  %zx.3 = zext i8 %v.3 to i64
  %cmp8.3 = icmp eq i8 %v.3, 95
  br i1 %cmp8.3, label %c8.3, label %fall9.3

fall9.3:                                          ; preds = %c8.2
  %add12.3 = add nuw nsw i64 %zx.3, 208
  %and.3 = and i64 %add12.3, 254
  %cmp13.3 = icmp ult i64 %and.3, 10
  br i1 %cmp13.3, label %c11.3, label %fall12.3

fall12.3:                                         ; preds = %fall9.3
  %add17.3 = add nuw nsw i64 %zx.3, 191
  %and18.3 = and i64 %add17.3, 254
  %cmp19.3 = icmp ult i64 %and18.3, 26
  br i1 %cmp19.3, label %c10.3, label %fall13.3

fall13.3:                                         ; preds = %fall12.3
  %bottom.3 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.3 = icmp eq i64 %bottom.3, 0
  br i1 %brif25.not.3, label %fall14.3, label %c2

fall14.3:                                         ; preds = %fall13.3
  %add27.3 = add nsw i64 %zx.3, -59
  br label %c8.3

c10.3:                                            ; preds = %fall12.3
  %add31.3 = add nsw i64 %zx.3, -53
  br label %c8.3

c11.3:                                            ; preds = %fall9.3
  %add29.3 = add nsw i64 %zx.3, -46
  br label %c8.3

c8.3:                                             ; preds = %c11.3, %c10.3, %fall14.3, %c8.2
  %l5.0.3 = phi i64 [ 1, %c8.2 ], [ %add29.3, %c11.3 ], [ %add31.3, %c10.3 ], [ %add27.3, %fall14.3 ]
  %3 = shl nuw nsw i64 %or36.1, 12
  %and35.2 = shl nsw i64 %l5.0.2, 6
  %4 = and i64 %and35.2, 16320
  %shl33.3 = or i64 %3, %4
  %and35.3 = and i64 %l5.0.3, 255
  %or36.3 = or i64 %and35.3, %shl33.3
  %add.4 = add i64 %1, 4
  %p.4 = inttoptr i64 %add.4 to ptr
  %v.4 = load i8, ptr %p.4, align 1
  %zx.4 = zext i8 %v.4 to i64
  %cmp8.4 = icmp eq i8 %v.4, 95
  br i1 %cmp8.4, label %c8.4, label %fall9.4

fall9.4:                                          ; preds = %c8.3
  %add12.4 = add nuw nsw i64 %zx.4, 208
  %and.4 = and i64 %add12.4, 254
  %cmp13.4 = icmp ult i64 %and.4, 10
  br i1 %cmp13.4, label %c11.4, label %fall12.4

fall12.4:                                         ; preds = %fall9.4
  %add17.4 = add nuw nsw i64 %zx.4, 191
  %and18.4 = and i64 %add17.4, 254
  %cmp19.4 = icmp ult i64 %and18.4, 26
  br i1 %cmp19.4, label %c10.4, label %fall13.4

fall13.4:                                         ; preds = %fall12.4
  %bottom.4 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.4 = icmp eq i64 %bottom.4, 0
  br i1 %brif25.not.4, label %fall14.4, label %c2

fall14.4:                                         ; preds = %fall13.4
  %add27.4 = add nsw i64 %zx.4, -59
  br label %c8.4

c10.4:                                            ; preds = %fall12.4
  %add31.4 = add nsw i64 %zx.4, -53
  br label %c8.4

c11.4:                                            ; preds = %fall9.4
  %add29.4 = add nsw i64 %zx.4, -46
  br label %c8.4

c8.4:                                             ; preds = %c11.4, %c10.4, %fall14.4, %c8.3
  %l5.0.4 = phi i64 [ 1, %c8.3 ], [ %add29.4, %c11.4 ], [ %add31.4, %c10.4 ], [ %add27.4, %fall14.4 ]
  %add.5 = add i64 %1, 5
  %p.5 = inttoptr i64 %add.5 to ptr
  %v.5 = load i8, ptr %p.5, align 1
  %zx.5 = zext i8 %v.5 to i64
  %cmp8.5 = icmp eq i8 %v.5, 95
  br i1 %cmp8.5, label %c8.5, label %fall9.5

fall9.5:                                          ; preds = %c8.4
  %add12.5 = add nuw nsw i64 %zx.5, 208
  %and.5 = and i64 %add12.5, 254
  %cmp13.5 = icmp ult i64 %and.5, 10
  br i1 %cmp13.5, label %c11.5, label %fall12.5

fall12.5:                                         ; preds = %fall9.5
  %add17.5 = add nuw nsw i64 %zx.5, 191
  %and18.5 = and i64 %add17.5, 254
  %cmp19.5 = icmp ult i64 %and18.5, 26
  br i1 %cmp19.5, label %c10.5, label %fall13.5

fall13.5:                                         ; preds = %fall12.5
  %bottom.5 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.5 = icmp eq i64 %bottom.5, 0
  br i1 %brif25.not.5, label %fall14.5, label %c2

fall14.5:                                         ; preds = %fall13.5
  %add27.5 = add nsw i64 %zx.5, -59
  br label %c8.5

c10.5:                                            ; preds = %fall12.5
  %add31.5 = add nsw i64 %zx.5, -53
  br label %c8.5

c11.5:                                            ; preds = %fall9.5
  %add29.5 = add nsw i64 %zx.5, -46
  br label %c8.5

c8.5:                                             ; preds = %c11.5, %c10.5, %fall14.5, %c8.4
  %l5.0.5 = phi i64 [ 1, %c8.4 ], [ %add29.5, %c11.5 ], [ %add31.5, %c10.5 ], [ %add27.5, %fall14.5 ]
  %5 = shl nuw nsw i64 %or36.3, 12
  %and35.4 = shl nsw i64 %l5.0.4, 6
  %6 = and i64 %and35.4, 16320
  %shl33.5 = or i64 %5, %6
  %and35.5 = and i64 %l5.0.5, 255
  %or36.5 = or i64 %and35.5, %shl33.5
  %add.6 = add i64 %1, 6
  %p.6 = inttoptr i64 %add.6 to ptr
  %v.6 = load i8, ptr %p.6, align 1
  %zx.6 = zext i8 %v.6 to i64
  %cmp8.6 = icmp eq i8 %v.6, 95
  br i1 %cmp8.6, label %c8.6, label %fall9.6

fall9.6:                                          ; preds = %c8.5
  %add12.6 = add nuw nsw i64 %zx.6, 208
  %and.6 = and i64 %add12.6, 254
  %cmp13.6 = icmp ult i64 %and.6, 10
  br i1 %cmp13.6, label %c11.6, label %fall12.6

fall12.6:                                         ; preds = %fall9.6
  %add17.6 = add nuw nsw i64 %zx.6, 191
  %and18.6 = and i64 %add17.6, 254
  %cmp19.6 = icmp ult i64 %and18.6, 26
  br i1 %cmp19.6, label %c10.6, label %fall13.6

fall13.6:                                         ; preds = %fall12.6
  %bottom.6 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.6 = icmp eq i64 %bottom.6, 0
  br i1 %brif25.not.6, label %fall14.6, label %c2

fall14.6:                                         ; preds = %fall13.6
  %add27.6 = add nsw i64 %zx.6, -59
  br label %c8.6

c10.6:                                            ; preds = %fall12.6
  %add31.6 = add nsw i64 %zx.6, -53
  br label %c8.6

c11.6:                                            ; preds = %fall9.6
  %add29.6 = add nsw i64 %zx.6, -46
  br label %c8.6

c8.6:                                             ; preds = %c11.6, %c10.6, %fall14.6, %c8.5
  %l5.0.6 = phi i64 [ 1, %c8.5 ], [ %add29.6, %c11.6 ], [ %add31.6, %c10.6 ], [ %add27.6, %fall14.6 ]
  %add.7 = add i64 %1, 7
  %p.7 = inttoptr i64 %add.7 to ptr
  %v.7 = load i8, ptr %p.7, align 1
  %zx.7 = zext i8 %v.7 to i64
  %cmp8.7 = icmp eq i8 %v.7, 95
  br i1 %cmp8.7, label %c8.7, label %fall9.7

fall9.7:                                          ; preds = %c8.6
  %add12.7 = add nuw nsw i64 %zx.7, 208
  %and.7 = and i64 %add12.7, 254
  %cmp13.7 = icmp ult i64 %and.7, 10
  br i1 %cmp13.7, label %c11.7, label %fall12.7

fall12.7:                                         ; preds = %fall9.7
  %add17.7 = add nuw nsw i64 %zx.7, 191
  %and18.7 = and i64 %add17.7, 254
  %cmp19.7 = icmp ult i64 %and18.7, 26
  br i1 %cmp19.7, label %c10.7, label %fall13.7

fall13.7:                                         ; preds = %fall12.7
  %bottom.7 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.7 = icmp eq i64 %bottom.7, 0
  br i1 %brif25.not.7, label %fall14.7, label %c2

fall14.7:                                         ; preds = %fall13.7
  %add27.7 = add nsw i64 %zx.7, -59
  br label %c8.7

c10.7:                                            ; preds = %fall12.7
  %add31.7 = add nsw i64 %zx.7, -53
  br label %c8.7

c11.7:                                            ; preds = %fall9.7
  %add29.7 = add nsw i64 %zx.7, -46
  br label %c8.7

c8.7:                                             ; preds = %c11.7, %c10.7, %fall14.7, %c8.6
  %l5.0.7 = phi i64 [ 1, %c8.6 ], [ %add29.7, %c11.7 ], [ %add31.7, %c10.7 ], [ %add27.7, %fall14.7 ]
  %7 = shl i64 %or36.5, 12
  %and35.6 = shl nsw i64 %l5.0.6, 6
  %8 = and i64 %and35.6, 16320
  %shl33.7 = or i64 %7, %8
  %and35.7 = and i64 %l5.0.7, 255
  %or36.7 = or i64 %and35.7, %shl33.7
  %add.8 = add i64 %1, 8
  %p.8 = inttoptr i64 %add.8 to ptr
  %v.8 = load i8, ptr %p.8, align 1
  %zx.8 = zext i8 %v.8 to i64
  %cmp8.8 = icmp eq i8 %v.8, 95
  br i1 %cmp8.8, label %c8.8, label %fall9.8

fall9.8:                                          ; preds = %c8.7
  %add12.8 = add nuw nsw i64 %zx.8, 208
  %and.8 = and i64 %add12.8, 254
  %cmp13.8 = icmp ult i64 %and.8, 10
  br i1 %cmp13.8, label %c11.8, label %fall12.8

fall12.8:                                         ; preds = %fall9.8
  %add17.8 = add nuw nsw i64 %zx.8, 191
  %and18.8 = and i64 %add17.8, 254
  %cmp19.8 = icmp ult i64 %and18.8, 26
  br i1 %cmp19.8, label %c10.8, label %fall13.8

fall13.8:                                         ; preds = %fall12.8
  %bottom.8 = tail call i64 @ponytail.unknown.i64()
  %brif25.not.8 = icmp eq i64 %bottom.8, 0
  br i1 %brif25.not.8, label %fall14.8, label %c2

fall14.8:                                         ; preds = %fall13.8
  %add27.8 = add nsw i64 %zx.8, -59
  br label %c8.8

c10.8:                                            ; preds = %fall12.8
  %add31.8 = add nsw i64 %zx.8, -53
  br label %c8.8

c11.8:                                            ; preds = %fall9.8
  %add29.8 = add nsw i64 %zx.8, -46
  br label %c8.8

c8.8:                                             ; preds = %c11.8, %c10.8, %fall14.8, %c8.7
  %l5.0.8 = phi i64 [ 1, %c8.7 ], [ %add29.8, %c11.8 ], [ %add31.8, %c10.8 ], [ %add27.8, %fall14.8 ]
  %9 = shl i64 %or36.7, 14
  %and35.8 = shl nsw i64 %l5.0.8, 8
  %10 = and i64 %and35.8, 65280
  %shl = or i64 %9, %10
  %or = or disjoint i64 %shl, 14
  br label %c1

fall9:                                            ; preds = %c6.preheader
  %add12 = add nuw nsw i64 %zx, 208
  %and = and i64 %add12, 254
  %cmp13 = icmp ult i64 %and, 10
  br i1 %cmp13, label %c11, label %fall12

c10:                                              ; preds = %fall12
  %add31 = add nsw i64 %zx, -53
  br label %c8

c11:                                              ; preds = %fall9
  %add29 = add nsw i64 %zx, -46
  br label %c8

fall12:                                           ; preds = %fall9
  %add17 = add nuw nsw i64 %zx, 191
  %and18 = and i64 %add17, 254
  %cmp19 = icmp ult i64 %and18, 26
  br i1 %cmp19, label %c10, label %fall13

fall13:                                           ; preds = %fall12
  %bottom = tail call i64 @ponytail.unknown.i64()
  %brif25.not = icmp eq i64 %bottom, 0
  br i1 %brif25.not, label %fall14, label %c2

fall14:                                           ; preds = %fall13
  %add27 = add nsw i64 %zx, -59
  br label %c8
}

; Function Attrs: noreturn
define internal fastcc void @panic_fmt_32() unnamed_addr #21 {
entry:
  tail call void @soroban.trap()
  unreachable
}

declare i64 @soroban.storage_type(i64)

attributes #0 = { mustprogress nofree nosync nounwind willreturn memory(none) }
attributes #1 = { memory(inaccessiblemem: readwrite) }
attributes #2 = { noreturn }
attributes #3 = { "soroban.import"="b.m" "soroban.sig"="(Symbol, U32Val, U32Val) -> U32Val" }
attributes #4 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.1" "soroban.sig"="(i64) -> I64Object" }
attributes #6 = { memory(inaccessiblemem: readwrite) "soroban.import"="i.2" "soroban.sig"="(I64Object) -> i64" }
attributes #7 = { memory(inaccessiblemem: readwrite) "soroban.import"="m.1" "soroban.sig"="(MapObject, Val) -> Val" }
attributes #8 = { memory(inaccessiblemem: readwrite) "soroban.import"="m.4" "soroban.sig"="(MapObject, Val) -> Bool" }
attributes #9 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #10 = { "soroban.import"="m.a" "soroban.sig"="(MapObject, U32Val, U32Val, U32Val) -> Void" }
attributes #11 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.8" "soroban.sig"="(VecObject) -> Val" }
attributes #12 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.1" "soroban.sig"="(VecObject, U32Val) -> Val" }
attributes #13 = { memory(inaccessiblemem: readwrite) "soroban.import"="v.3" "soroban.sig"="(VecObject) -> U32Val" }
attributes #14 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #15 = { "soroban.import"="v.h" "soroban.sig"="(VecObject, U32Val, U32Val) -> Void" }
attributes #16 = { "spec.sig"="fn add(a: UdtEnum, b: UdtEnum) -> i64" }
attributes #17 = { "spec.sig"="fn recursive(a: UdtRecursive) -> Option<UdtRecursive>" }
attributes #18 = { "spec.sig"="fn recursive_enum(a: RecursiveEnum, key: u32) -> Result<Option<RecursiveEnum>, Error>" }
attributes #19 = { memory(write, inaccessiblemem: readwrite) "sdk.name"="<i64 as soroban_env_common::convert::TryFromVal<E,soroban_env_common::val::Val>>::try_from_val" }
attributes #20 = { noreturn "sdk.name"="core::slice::index::slice_index_fail | core::result::unwrap_failed | core::panicking::panic" }
attributes #21 = { noreturn "sdk.name"="core::panicking::panic_fmt" }

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
