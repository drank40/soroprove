; sdk 26.0.1 rustc 1.95.0; fingerprints 26.0.1+rustc1.95.0.txt: 5 of 17 helpers named, 1 by shape
; ModuleID = 'diver'
source_filename = "diver"

%Val = type { i64 }

@g0 = global i64 1048576
@g1 = constant i64 1048808
@g2 = constant i64 1048808
@g3 = constant i64 1048816

; Function Attrs: nounwind willreturn memory(none)
declare %Val @soroban.val.from_payload(i64) #0

; Function Attrs: nounwind willreturn memory(none)
declare i64 @soroban.val.payload(%Val) #0

; Function Attrs: nounwind willreturn memory(none)
declare i64 @soroban.storage_type(i64) #0

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @diver.unknown() #1

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @diver.unknown.i64() #1

; Function Attrs: noreturn
declare void @soroban.trap() #2

declare i64 @soroban.load8u(i64)

declare i64 @soroban.load8s(i64)

declare i64 @soroban.load16u(i64)

declare i64 @soroban.load16s(i64)

declare i64 @soroban.load32u(i64)

declare i64 @soroban.load32s(i64)

declare i64 @soroban.load64(i64)

declare void @soroban.store8(i64, i64)

declare void @soroban.store16(i64, i64)

declare void @soroban.store32(i64, i64)

declare void @soroban.store64(i64, i64)

declare %Val @buf.symbol_index_in_linear_memory(%Val, %Val, %Val) #3

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @int.obj_from_i64(i64) #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @int.obj_to_i64(%Val) #6

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_get(%Val, %Val) #7

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @map.map_has(%Val, %Val) #8

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) #9

declare %Val @map.map_unpack_to_linear_memory(%Val, %Val, %Val, %Val) #10

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_front(%Val) #11

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_get(%Val, %Val) #12

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @vec.vec_len(%Val) #13

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) #14

declare %Val @vec.vec_unpack_to_linear_memory(%Val, %Val, %Val) #15

define "spec.type"="i64" "wasm.type"="i64" %Val @add(%Val "spec.name"="a" "spec.type"="UdtEnum" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="UdtEnum" "wasm.type"="i64" %1) #16 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  %l6 = alloca i64, align 8
  %l7 = alloca i64, align 8
  %l8 = alloca i64, align 8
  %l9 = alloca i64, align 8
  %l10 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  %arg_payload1 = call i64 @soroban.val.payload(%Val %1)
  store i64 %arg_payload1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  store i64 0, ptr %l6, align 4
  store i64 0, ptr %l7, align 4
  store i64 0, ptr %l8, align 4
  store i64 0, ptr %l9, align 4
  store i64 0, ptr %l10, align 4
  %frame = alloca [64 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get, ptr %slot8, align 1
  %get2 = load i64, ptr %l0, align 4
  store i64 %get2, ptr %frame, align 1
  %slot16 = getelementptr i8, ptr %frame, i64 16
  %fp = ptrtoint ptr %slot16 to i64
  %fp3 = ptrtoint ptr %frame to i64
  call void @f13(i64 %fp, i64 %fp3)
  %slot164 = getelementptr i8, ptr %frame, i64 16
  %ld = load i8, ptr %slot164, align 1
  %zx = zext i8 %ld to i64
  store i64 %zx, ptr %l3, align 4
  %t = trunc i64 %zx to i32
  %cmp = icmp eq i32 %t, 4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c5, label %fall6

c1:                                               ; preds = %c2, %fall32
  %get184 = load i64, ptr %l1, align 4
  %to_val185 = call %Val @soroban.val.from_payload(i64 %get184)
  ret %Val %to_val185

c2:                                               ; preds = %fall31
  %get182 = load i64, ptr %l0, align 4
  %obj_from_i64 = call %Val @int.obj_from_i64(i64 %get182)
  %payload183 = call i64 @soroban.val.payload(%Val %obj_from_i64)
  store i64 %payload183, ptr %l1, align 4
  br label %c1

c3:                                               ; preds = %c19, %c20, %fall29, %c27, %fall26, %h24, %fall18, %fall17, %c15, %fall14, %h12
  call void @panic()
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %c8, %c9, %c10, %fall7, %fall7
  %get90 = load i64, ptr %l7, align 4
  %sel91 = trunc i64 %get90 to i32
  switch i32 %sel91, label %c19 [
    i32 0, label %c19
    i32 1, label %c21
    i32 2, label %c22
    i32 3, label %c23
  ]

c5:                                               ; preds = %fall6, %entry
  call void @soroban.trap()
  unreachable

fall6:                                            ; preds = %entry
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %ld5 = load i64, ptr %slot32, align 1
  store i64 %ld5, ptr %l4, align 4
  %slot24 = getelementptr i8, ptr %frame, i64 24
  %ld6 = load i64, ptr %slot24, align 1
  store i64 %ld6, ptr %l5, align 4
  %slot17 = getelementptr i8, ptr %frame, i64 17
  %ld7 = load i8, ptr %slot17, align 1
  %zx8 = zext i8 %ld7 to i64
  store i64 %zx8, ptr %l6, align 4
  %slot169 = getelementptr i8, ptr %frame, i64 16
  %fp10 = ptrtoint ptr %slot169 to i64
  %slot811 = getelementptr i8, ptr %frame, i64 8
  %fp12 = ptrtoint ptr %slot811 to i64
  call void @f13(i64 %fp10, i64 %fp12)
  %slot1613 = getelementptr i8, ptr %frame, i64 16
  %ld14 = load i8, ptr %slot1613, align 1
  %zx15 = zext i8 %ld14 to i64
  store i64 %zx15, ptr %l7, align 4
  %t16 = trunc i64 %zx15 to i32
  %cmp17 = icmp eq i32 %t16, 4
  %zext18 = zext i1 %cmp17 to i64
  %brif19 = icmp ne i64 %zext18, 0
  br i1 %brif19, label %c5, label %fall7

fall7:                                            ; preds = %fall6
  %slot3220 = getelementptr i8, ptr %frame, i64 32
  %ld21 = load i64, ptr %slot3220, align 1
  store i64 %ld21, ptr %l8, align 4
  %slot2422 = getelementptr i8, ptr %frame, i64 24
  %ld23 = load i64, ptr %slot2422, align 1
  store i64 %ld23, ptr %l9, align 4
  %slot1724 = getelementptr i8, ptr %frame, i64 17
  %ld25 = load i8, ptr %slot1724, align 1
  %zx26 = zext i8 %ld25 to i64
  store i64 %zx26, ptr %l10, align 4
  store i64 0, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  %get27 = load i64, ptr %l3, align 4
  %sel = trunc i64 %get27 to i32
  switch i32 %sel, label %c4 [
    i32 0, label %c4
    i32 1, label %c9
    i32 2, label %c10
    i32 3, label %c11
  ]

c8:                                               ; preds = %fall14
  %get73 = load i64, ptr %l1, align 4
  %cmp74 = icmp slt i64 %get73, 0
  %zext75 = zext i1 %cmp74 to i64
  %get76 = load i64, ptr %l5, align 4
  %get77 = load i64, ptr %l1, align 4
  %add78 = add i64 %get76, %get77
  store i64 %add78, ptr %l1, align 4
  %get79 = load i64, ptr %l5, align 4
  %cmp80 = icmp slt i64 %add78, %get79
  %zext81 = zext i1 %cmp80 to i64
  %t82 = trunc i64 %zext75 to i32
  %t83 = trunc i64 %zext81 to i32
  %xor84 = xor i32 %t82, %t83
  %z85 = zext i32 %xor84 to i64
  %t86 = trunc i64 %z85 to i32
  %eqz87 = icmp eq i32 %t86, 0
  %zext88 = zext i1 %eqz87 to i64
  %brif89 = icmp ne i64 %zext88, 0
  br i1 %brif89, label %c4, label %fall18

c9:                                               ; preds = %fall7
  %get59 = load i64, ptr %l4, align 4
  %cmp60 = icmp slt i64 %get59, 0
  %zext61 = zext i1 %cmp60 to i64
  %get62 = load i64, ptr %l5, align 4
  %get63 = load i64, ptr %l4, align 4
  %add64 = add i64 %get62, %get63
  store i64 %add64, ptr %l1, align 4
  %get65 = load i64, ptr %l5, align 4
  %cmp66 = icmp slt i64 %add64, %get65
  %zext67 = zext i1 %cmp66 to i64
  %t68 = trunc i64 %zext61 to i32
  %t69 = trunc i64 %zext67 to i32
  %xor = xor i32 %t68, %t69
  %z = zext i32 %xor to i64
  %t70 = trunc i64 %z to i32
  %eqz = icmp eq i32 %t70, 0
  %zext71 = zext i1 %eqz to i64
  %brif72 = icmp ne i64 %zext71, 0
  br i1 %brif72, label %c4, label %fall17

c10:                                              ; preds = %fall7
  %get58 = load i64, ptr %l6, align 4
  store i64 %get58, ptr %l1, align 4
  br label %c4

c11:                                              ; preds = %fall7
  %get28 = load i64, ptr %l4, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get28)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  store i64 %payload, ptr %l1, align 4
  %slot56 = getelementptr i8, ptr %frame, i64 56
  store i32 0, ptr %slot56, align 1
  %get29 = load i64, ptr %l4, align 4
  %slot48 = getelementptr i8, ptr %frame, i64 48
  store i64 %get29, ptr %slot48, align 1
  %get30 = load i64, ptr %l1, align 4
  %lshr = lshr i64 %get30, 32
  %slot60 = getelementptr i8, ptr %frame, i64 60
  %t31 = trunc i64 %lshr to i32
  store i32 %t31, ptr %slot60, align 1
  store i64 0, ptr %l1, align 4
  br label %h12

h12:                                              ; preds = %fall16, %c11
  %slot1632 = getelementptr i8, ptr %frame, i64 16
  %fp33 = ptrtoint ptr %slot1632 to i64
  %slot4834 = getelementptr i8, ptr %frame, i64 48
  %fp35 = ptrtoint ptr %slot4834 to i64
  call void @f25(i64 %fp33, i64 %fp35)
  %slot1636 = getelementptr i8, ptr %frame, i64 16
  %ld37 = load i64, ptr %slot1636, align 1
  store i64 %ld37, ptr %l4, align 4
  %cmp38 = icmp ugt i64 %ld37, 2
  %zext39 = zext i1 %cmp38 to i64
  %brif40 = icmp ne i64 %zext39, 0
  br i1 %brif40, label %c3, label %fall14

fall14:                                           ; preds = %h12
  %get41 = load i64, ptr %l4, align 4
  %sel42 = trunc i64 %get41 to i32
  switch i32 %sel42, label %c15 [
    i32 0, label %c15
    i32 1, label %c3
    i32 2, label %c8
  ]

c15:                                              ; preds = %fall14, %fall14
  %slot2443 = getelementptr i8, ptr %frame, i64 24
  %ld44 = load i64, ptr %slot2443, align 1
  store i64 %ld44, ptr %l4, align 4
  %cmp45 = icmp slt i64 %ld44, 0
  %zext46 = zext i1 %cmp45 to i64
  %get47 = load i64, ptr %l1, align 4
  %get48 = load i64, ptr %l4, align 4
  %add = add i64 %get47, %get48
  store i64 %add, ptr %l4, align 4
  %get49 = load i64, ptr %l1, align 4
  %cmp50 = icmp slt i64 %add, %get49
  %zext51 = zext i1 %cmp50 to i64
  %t52 = trunc i64 %zext46 to i32
  %t53 = trunc i64 %zext51 to i32
  %cmp54 = icmp ne i32 %t52, %t53
  %zext55 = zext i1 %cmp54 to i64
  %brif56 = icmp ne i64 %zext55, 0
  br i1 %brif56, label %c3, label %fall16

fall16:                                           ; preds = %c15
  %get57 = load i64, ptr %l4, align 4
  store i64 %get57, ptr %l1, align 4
  br label %h12

fall17:                                           ; preds = %c9
  br label %c3

fall18:                                           ; preds = %c8
  br label %c3

c19:                                              ; preds = %fall30, %c21, %c22, %c4, %c4
  %get162 = load i64, ptr %l0, align 4
  %cmp163 = icmp slt i64 %get162, 0
  %zext164 = zext i1 %cmp163 to i64
  %get165 = load i64, ptr %l1, align 4
  %get166 = load i64, ptr %l0, align 4
  %add167 = add i64 %get165, %get166
  store i64 %add167, ptr %l0, align 4
  %get168 = load i64, ptr %l1, align 4
  %cmp169 = icmp slt i64 %add167, %get168
  %zext170 = zext i1 %cmp169 to i64
  %t171 = trunc i64 %zext164 to i32
  %t172 = trunc i64 %zext170 to i32
  %xor173 = xor i32 %t171, %t172
  %z174 = zext i32 %xor173 to i64
  %brif175 = icmp ne i64 %z174, 0
  br i1 %brif175, label %c3, label %fall31

c20:                                              ; preds = %fall26
  %get148 = load i64, ptr %l0, align 4
  %cmp149 = icmp slt i64 %get148, 0
  %zext150 = zext i1 %cmp149 to i64
  %get151 = load i64, ptr %l9, align 4
  %get152 = load i64, ptr %l0, align 4
  %add153 = add i64 %get151, %get152
  store i64 %add153, ptr %l0, align 4
  %get154 = load i64, ptr %l9, align 4
  %cmp155 = icmp slt i64 %add153, %get154
  %zext156 = zext i1 %cmp155 to i64
  %t157 = trunc i64 %zext150 to i32
  %t158 = trunc i64 %zext156 to i32
  %xor159 = xor i32 %t157, %t158
  %z160 = zext i32 %xor159 to i64
  %brif161 = icmp ne i64 %z160, 0
  br i1 %brif161, label %c3, label %fall30

c21:                                              ; preds = %c4
  %get131 = load i64, ptr %l8, align 4
  %cmp132 = icmp slt i64 %get131, 0
  %zext133 = zext i1 %cmp132 to i64
  %get134 = load i64, ptr %l9, align 4
  %get135 = load i64, ptr %l8, align 4
  %add136 = add i64 %get134, %get135
  store i64 %add136, ptr %l0, align 4
  %get137 = load i64, ptr %l9, align 4
  %cmp138 = icmp slt i64 %add136, %get137
  %zext139 = zext i1 %cmp138 to i64
  %t140 = trunc i64 %zext133 to i32
  %t141 = trunc i64 %zext139 to i32
  %xor142 = xor i32 %t140, %t141
  %z143 = zext i32 %xor142 to i64
  %t144 = trunc i64 %z143 to i32
  %eqz145 = icmp eq i32 %t144, 0
  %zext146 = zext i1 %eqz145 to i64
  %brif147 = icmp ne i64 %zext146, 0
  br i1 %brif147, label %c19, label %fall29

c22:                                              ; preds = %c4
  %get130 = load i64, ptr %l10, align 4
  store i64 %get130, ptr %l0, align 4
  br label %c19

c23:                                              ; preds = %c4
  %get92 = load i64, ptr %l8, align 4
  %to_val93 = call %Val @soroban.val.from_payload(i64 %get92)
  %vec_len94 = call %Val @vec.vec_len(%Val %to_val93)
  %payload95 = call i64 @soroban.val.payload(%Val %vec_len94)
  store i64 %payload95, ptr %l0, align 4
  %slot5696 = getelementptr i8, ptr %frame, i64 56
  store i32 0, ptr %slot5696, align 1
  %get97 = load i64, ptr %l8, align 4
  %slot4898 = getelementptr i8, ptr %frame, i64 48
  store i64 %get97, ptr %slot4898, align 1
  %get99 = load i64, ptr %l0, align 4
  %lshr100 = lshr i64 %get99, 32
  %slot60101 = getelementptr i8, ptr %frame, i64 60
  %t102 = trunc i64 %lshr100 to i32
  store i32 %t102, ptr %slot60101, align 1
  store i64 0, ptr %l0, align 4
  br label %h24

h24:                                              ; preds = %fall28, %c23
  %slot16103 = getelementptr i8, ptr %frame, i64 16
  %fp104 = ptrtoint ptr %slot16103 to i64
  %slot48105 = getelementptr i8, ptr %frame, i64 48
  %fp106 = ptrtoint ptr %slot48105 to i64
  call void @f25(i64 %fp104, i64 %fp106)
  %slot16107 = getelementptr i8, ptr %frame, i64 16
  %ld108 = load i64, ptr %slot16107, align 1
  store i64 %ld108, ptr %l4, align 4
  %cmp109 = icmp ugt i64 %ld108, 2
  %zext110 = zext i1 %cmp109 to i64
  %brif111 = icmp ne i64 %zext110, 0
  br i1 %brif111, label %c3, label %fall26

fall26:                                           ; preds = %h24
  %get112 = load i64, ptr %l4, align 4
  %sel113 = trunc i64 %get112 to i32
  switch i32 %sel113, label %c27 [
    i32 0, label %c27
    i32 1, label %c3
    i32 2, label %c20
  ]

c27:                                              ; preds = %fall26, %fall26
  %slot24114 = getelementptr i8, ptr %frame, i64 24
  %ld115 = load i64, ptr %slot24114, align 1
  store i64 %ld115, ptr %l4, align 4
  %cmp116 = icmp slt i64 %ld115, 0
  %zext117 = zext i1 %cmp116 to i64
  %get118 = load i64, ptr %l0, align 4
  %get119 = load i64, ptr %l4, align 4
  %add120 = add i64 %get118, %get119
  store i64 %add120, ptr %l4, align 4
  %get121 = load i64, ptr %l0, align 4
  %cmp122 = icmp slt i64 %add120, %get121
  %zext123 = zext i1 %cmp122 to i64
  %t124 = trunc i64 %zext117 to i32
  %t125 = trunc i64 %zext123 to i32
  %cmp126 = icmp ne i32 %t124, %t125
  %zext127 = zext i1 %cmp126 to i64
  %brif128 = icmp ne i64 %zext127, 0
  br i1 %brif128, label %c3, label %fall28

fall28:                                           ; preds = %c27
  %get129 = load i64, ptr %l4, align 4
  store i64 %get129, ptr %l0, align 4
  br label %h24

fall29:                                           ; preds = %c21
  br label %c3

fall30:                                           ; preds = %c20
  br label %c19

fall31:                                           ; preds = %c19
  %get176 = load i64, ptr %l0, align 4
  %add177 = add i64 %get176, 36028797018963968
  %cmp178 = icmp ugt i64 %add177, 72057594037927935
  %zext179 = zext i1 %cmp178 to i64
  %brif180 = icmp ne i64 %zext179, 0
  br i1 %brif180, label %c2, label %fall32

fall32:                                           ; preds = %fall31
  %get181 = load i64, ptr %l0, align 4
  %shl = shl i64 %get181, 8
  %or = or i64 %shl, 7
  store i64 %or, ptr %l1, align 4
  br label %c1
}

define "spec.type"="Option<UdtRecursive>" "wasm.type"="i64" %Val @recursive(%Val "spec.name"="a" "spec.type"="UdtRecursive" "wasm.type"="i64" %0) #17 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %frame = alloca [32 x i8], align 1
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i32 2, ptr %slot8, align 1
  %slot81 = getelementptr i8, ptr %frame, i64 8
  %ld = load i32, ptr %slot81, align 1
  %zx = zext i32 %ld to i64
  %get = load i64, ptr %l0, align 4
  %slot82 = getelementptr i8, ptr %frame, i64 8
  %fp = ptrtoint ptr %slot82 to i64
  call void @f21(i64 %fp, i64 %get)
  %slot83 = getelementptr i8, ptr %frame, i64 8
  %ld4 = load i64, ptr %slot83, align 1
  %cmp = icmp eq i64 %ld4, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %c4, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %slot24 = getelementptr i8, ptr %frame, i64 24
  %ld5 = load i64, ptr %slot24, align 1
  store i64 %ld5, ptr %l0, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %ld5)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  %cmp6 = icmp ugt i64 %payload, 4294967295
  %zext7 = zext i1 %cmp6 to i64
  %brif8 = icmp ne i64 %zext7, 0
  br i1 %brif8, label %c4, label %fall5

c3:                                               ; preds = %fall6, %fall5
  %get36 = load i64, ptr %l0, align 4
  %to_val37 = call %Val @soroban.val.from_payload(i64 %get36)
  ret %Val %to_val37

c4:                                               ; preds = %fall2
  %get13 = load i64, ptr %l0, align 4
  %to_val14 = call %Val @soroban.val.from_payload(i64 %get13)
  %vec_front = call %Val @vec.vec_front(%Val %to_val14)
  %slot815 = getelementptr i8, ptr %frame, i64 8
  %fp16 = ptrtoint ptr %slot815 to i64
  %payload17 = call i64 @soroban.val.payload(%Val %vec_front)
  call void @f21(i64 %fp16, i64 %payload17)
  %slot818 = getelementptr i8, ptr %frame, i64 8
  %ld19 = load i64, ptr %slot818, align 1
  %cmp20 = icmp eq i64 %ld19, 1
  %zext21 = zext i1 %cmp20 to i64
  %brif22 = icmp ne i64 %zext21, 0
  br i1 %brif22, label %c1, label %fall6

fall5:                                            ; preds = %fall2
  %slot89 = getelementptr i8, ptr %frame, i64 8
  store i32 2, ptr %slot89, align 1
  %slot810 = getelementptr i8, ptr %frame, i64 8
  %ld11 = load i32, ptr %slot810, align 1
  %zx12 = zext i32 %ld11 to i64
  store i64 2, ptr %l0, align 4
  br label %c3

fall6:                                            ; preds = %c4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  %ld23 = load i64, ptr %slot16, align 1
  store i64 %ld23, ptr %l0, align 4
  %slot2424 = getelementptr i8, ptr %frame, i64 24
  %ld25 = load i64, ptr %slot2424, align 1
  store i64 %ld25, ptr %l2, align 4
  %slot826 = getelementptr i8, ptr %frame, i64 8
  store i32 2, ptr %slot826, align 1
  %slot827 = getelementptr i8, ptr %frame, i64 8
  %ld28 = load i32, ptr %slot827, align 1
  %zx29 = zext i32 %ld28 to i64
  %get30 = load i64, ptr %l2, align 4
  %slot1631 = getelementptr i8, ptr %frame, i64 16
  store i64 %get30, ptr %slot1631, align 1
  %get32 = load i64, ptr %l0, align 4
  %slot833 = getelementptr i8, ptr %frame, i64 8
  store i64 %get32, ptr %slot833, align 1
  %slot834 = getelementptr i8, ptr %frame, i64 8
  %fp35 = ptrtoint ptr %slot834 to i64
  %lc = call i64 @f28(i64 %fp35)
  store i64 %lc, ptr %l0, align 4
  br label %c3
}

define "spec.type"="Result<Option<RecursiveEnum>, Error>" "wasm.type"="i64" %Val @recursive_enum(%Val "spec.name"="a" "spec.type"="RecursiveEnum" "wasm.type"="i64" %0, %Val "spec.name"="key" "spec.type"="u32" "wasm.type"="i64" %1) #18 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  %arg_payload1 = call i64 @soroban.val.payload(%Val %1)
  store i64 %arg_payload1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24, align 1
  %slot242 = getelementptr i8, ptr %frame, i64 24
  %ld = load i32, ptr %slot242, align 1
  %zx = zext i32 %ld to i64
  %slot243 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot243, align 1
  %slot244 = getelementptr i8, ptr %frame, i64 24
  %ld5 = load i32, ptr %slot244, align 1
  %zx6 = zext i32 %ld5 to i64
  %get = load i64, ptr %l0, align 4
  %and = and i64 %get, 255
  %cmp = icmp ne i64 %and, 75
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall31, %c9, %fall29, %fall28, %fall27, %c10, %fall25, %c12, %c21, %fall22, %fall19, %fall18, %fall16, %fall15, %fall14, %c13, %c4, %fall5, %fall2, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %get7 = load i64, ptr %l0, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get7)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  store i64 %payload, ptr %l3, align 4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  store i32 0, ptr %slot16, align 1
  %get8 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get8, ptr %slot8, align 1
  %get9 = load i64, ptr %l3, align 4
  %lshr = lshr i64 %get9, 32
  %slot20 = getelementptr i8, ptr %frame, i64 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %slot2410 = getelementptr i8, ptr %frame, i64 24
  %fp = ptrtoint ptr %slot2410 to i64
  %slot811 = getelementptr i8, ptr %frame, i64 8
  %fp12 = ptrtoint ptr %slot811 to i64
  call void @f15(i64 %fp, i64 %fp12)
  %slot2413 = getelementptr i8, ptr %frame, i64 24
  %ld14 = load i64, ptr %slot2413, align 1
  %cmp15 = icmp ne i64 %ld14, 0
  %zext16 = zext i1 %cmp15 to i64
  %brif17 = icmp ne i64 %zext16, 0
  br i1 %brif17, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %ld18 = load i64, ptr %slot32, align 1
  store i64 %ld18, ptr %l0, align 4
  %t19 = trunc i64 %ld18 to i32
  %and20 = and i32 %t19, 255
  %z = zext i32 %and20 to i64
  store i64 %z, ptr %l4, align 4
  %t21 = trunc i64 %z to i32
  %cmp22 = icmp eq i32 %t21, 74
  %zext23 = zext i1 %cmp22 to i64
  %brif24 = icmp ne i64 %zext23, 0
  br i1 %brif24, label %c4, label %fall5

c4:                                               ; preds = %fall6, %fall3
  %get30 = load i64, ptr %l0, align 4
  %lc = call i64 @f16(i64 %get30, i64 1048792, i64 2)
  %lshr31 = lshr i64 %lc, 32
  store i64 %lshr31, ptr %l0, align 4
  %cmp32 = icmp ugt i64 %lshr31, 1
  %zext33 = zext i1 %cmp32 to i64
  %brif34 = icmp ne i64 %zext33, 0
  br i1 %brif34, label %c1, label %fall7

fall5:                                            ; preds = %fall3
  %get25 = load i64, ptr %l4, align 4
  %t26 = trunc i64 %get25 to i32
  %cmp27 = icmp ne i32 %t26, 14
  %zext28 = zext i1 %cmp27 to i64
  %brif29 = icmp ne i64 %zext28, 0
  br i1 %brif29, label %c1, label %fall6

fall6:                                            ; preds = %fall5
  br label %c4

fall7:                                            ; preds = %c4
  %get35 = load i64, ptr %l0, align 4
  %sel = trunc i64 %get35 to i32
  switch i32 %sel, label %c12 [
    i32 0, label %c12
    i32 1, label %c13
  ]

c8:                                               ; preds = %fall32, %fall30, %c11
  %get239 = load i64, ptr %l0, align 4
  %to_val240 = call %Val @soroban.val.from_payload(i64 %get239)
  ret %Val %to_val240

c9:                                               ; preds = %fall24, %fall24
  %slot16211 = getelementptr i8, ptr %frame, i64 16
  %ld212 = load i32, ptr %slot16211, align 1
  %zx213 = zext i32 %ld212 to i64
  %slot20214 = getelementptr i8, ptr %frame, i64 20
  %ld215 = load i32, ptr %slot20214, align 1
  %zx216 = zext i32 %ld215 to i64
  %lc217 = call i64 @f17(i64 %zx213, i64 %zx216)
  %brif218 = icmp ne i64 %lc217, 0
  br i1 %brif218, label %c1, label %fall31

c10:                                              ; preds = %fall24
  %slot16149 = getelementptr i8, ptr %frame, i64 16
  %ld150 = load i32, ptr %slot16149, align 1
  %zx151 = zext i32 %ld150 to i64
  %slot20152 = getelementptr i8, ptr %frame, i64 20
  %ld153 = load i32, ptr %slot20152, align 1
  %zx154 = zext i32 %ld153 to i64
  %lc155 = call i64 @f17(i64 %zx151, i64 %zx154)
  %t156 = trunc i64 %lc155 to i32
  %cmp157 = icmp ugt i32 %t156, 1
  %zext158 = zext i1 %cmp157 to i64
  %brif159 = icmp ne i64 %zext158, 0
  br i1 %brif159, label %c1, label %fall27

c11:                                              ; preds = %fall26, %fall17
  %slot24141 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24141, align 1
  %slot24142 = getelementptr i8, ptr %frame, i64 24
  %ld143 = load i32, ptr %slot24142, align 1
  %zx144 = zext i32 %ld143 to i64
  %slot24145 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24145, align 1
  %slot24146 = getelementptr i8, ptr %frame, i64 24
  %ld147 = load i32, ptr %slot24146, align 1
  %zx148 = zext i32 %ld147 to i64
  store i64 2, ptr %l0, align 4
  br label %c8

c12:                                              ; preds = %fall7, %fall7
  %slot16128 = getelementptr i8, ptr %frame, i64 16
  %ld129 = load i32, ptr %slot16128, align 1
  %zx130 = zext i32 %ld129 to i64
  %slot20131 = getelementptr i8, ptr %frame, i64 20
  %ld132 = load i32, ptr %slot20131, align 1
  %zx133 = zext i32 %ld132 to i64
  %lc134 = call i64 @f17(i64 %zx130, i64 %zx133)
  %brif135 = icmp ne i64 %lc134, 0
  br i1 %brif135, label %c1, label %fall25

c13:                                              ; preds = %fall7
  %slot1636 = getelementptr i8, ptr %frame, i64 16
  %ld37 = load i32, ptr %slot1636, align 1
  %zx38 = zext i32 %ld37 to i64
  %slot2039 = getelementptr i8, ptr %frame, i64 20
  %ld40 = load i32, ptr %slot2039, align 1
  %zx41 = zext i32 %ld40 to i64
  %lc42 = call i64 @f17(i64 %zx38, i64 %zx41)
  %t43 = trunc i64 %lc42 to i32
  %cmp44 = icmp ugt i32 %t43, 1
  %zext45 = zext i1 %cmp44 to i64
  %brif46 = icmp ne i64 %zext45, 0
  br i1 %brif46, label %c1, label %fall14

fall14:                                           ; preds = %c13
  %slot48 = getelementptr i8, ptr %frame, i64 48
  %fp47 = ptrtoint ptr %slot48 to i64
  %slot848 = getelementptr i8, ptr %frame, i64 8
  %fp49 = ptrtoint ptr %slot848 to i64
  call void @f15(i64 %fp47, i64 %fp49)
  %slot4850 = getelementptr i8, ptr %frame, i64 48
  %ld51 = load i64, ptr %slot4850, align 1
  %cmp52 = icmp ne i64 %ld51, 0
  %zext53 = zext i1 %cmp52 to i64
  %brif54 = icmp ne i64 %zext53, 0
  br i1 %brif54, label %c1, label %fall15

fall15:                                           ; preds = %fall14
  %slot56 = getelementptr i8, ptr %frame, i64 56
  %ld55 = load i64, ptr %slot56, align 1
  %slot2456 = getelementptr i8, ptr %frame, i64 24
  %fp57 = ptrtoint ptr %slot2456 to i64
  call void @f22(i64 %fp57, i64 %ld55)
  %slot2458 = getelementptr i8, ptr %frame, i64 24
  %ld59 = load i64, ptr %slot2458, align 1
  %cmp60 = icmp eq i64 %ld59, 1
  %zext61 = zext i1 %cmp60 to i64
  %brif62 = icmp ne i64 %zext61, 0
  br i1 %brif62, label %c1, label %fall16

fall16:                                           ; preds = %fall15
  %get63 = load i64, ptr %l1, align 4
  %and64 = and i64 %get63, 255
  %cmp65 = icmp ne i64 %and64, 4
  %zext66 = zext i1 %cmp65 to i64
  %brif67 = icmp ne i64 %zext66, 0
  br i1 %brif67, label %c1, label %fall17

fall17:                                           ; preds = %fall16
  %slot40 = getelementptr i8, ptr %frame, i64 40
  %ld68 = load i64, ptr %slot40, align 1
  store i64 %ld68, ptr %l0, align 4
  %get69 = load i64, ptr %l1, align 4
  %and70 = and i64 %get69, -4294967292
  store i64 %and70, ptr %l1, align 4
  %to_val71 = call %Val @soroban.val.from_payload(i64 %ld68)
  %to_val72 = call %Val @soroban.val.from_payload(i64 %and70)
  %map_has = call %Val @map.map_has(%Val %to_val71, %Val %to_val72)
  %payload73 = call i64 @soroban.val.payload(%Val %map_has)
  %cmp74 = icmp ne i64 %payload73, 1
  %zext75 = zext i1 %cmp74 to i64
  %brif76 = icmp ne i64 %zext75, 0
  br i1 %brif76, label %c11, label %fall18

fall18:                                           ; preds = %fall17
  %get77 = load i64, ptr %l0, align 4
  %get78 = load i64, ptr %l1, align 4
  %to_val79 = call %Val @soroban.val.from_payload(i64 %get77)
  %to_val80 = call %Val @soroban.val.from_payload(i64 %get78)
  %map_get = call %Val @map.map_get(%Val %to_val79, %Val %to_val80)
  %payload81 = call i64 @soroban.val.payload(%Val %map_get)
  store i64 %payload81, ptr %l0, align 4
  %and82 = and i64 %payload81, 255
  %cmp83 = icmp ne i64 %and82, 75
  %zext84 = zext i1 %cmp83 to i64
  %brif85 = icmp ne i64 %zext84, 0
  br i1 %brif85, label %c1, label %fall19

fall19:                                           ; preds = %fall18
  %get86 = load i64, ptr %l0, align 4
  %to_val87 = call %Val @soroban.val.from_payload(i64 %get86)
  %vec_len88 = call %Val @vec.vec_len(%Val %to_val87)
  %payload89 = call i64 @soroban.val.payload(%Val %vec_len88)
  store i64 %payload89, ptr %l1, align 4
  %slot1690 = getelementptr i8, ptr %frame, i64 16
  store i32 0, ptr %slot1690, align 1
  %get91 = load i64, ptr %l0, align 4
  %slot892 = getelementptr i8, ptr %frame, i64 8
  store i64 %get91, ptr %slot892, align 1
  %get93 = load i64, ptr %l1, align 4
  %lshr94 = lshr i64 %get93, 32
  %slot2095 = getelementptr i8, ptr %frame, i64 20
  %t96 = trunc i64 %lshr94 to i32
  store i32 %t96, ptr %slot2095, align 1
  %slot2497 = getelementptr i8, ptr %frame, i64 24
  %fp98 = ptrtoint ptr %slot2497 to i64
  %slot899 = getelementptr i8, ptr %frame, i64 8
  %fp100 = ptrtoint ptr %slot899 to i64
  call void @f15(i64 %fp98, i64 %fp100)
  %slot24101 = getelementptr i8, ptr %frame, i64 24
  %ld102 = load i64, ptr %slot24101, align 1
  %cmp103 = icmp ne i64 %ld102, 0
  %zext104 = zext i1 %cmp103 to i64
  %brif105 = icmp ne i64 %zext104, 0
  br i1 %brif105, label %c1, label %fall20

fall20:                                           ; preds = %fall19
  %slot32106 = getelementptr i8, ptr %frame, i64 32
  %ld107 = load i64, ptr %slot32106, align 1
  store i64 %ld107, ptr %l0, align 4
  %t108 = trunc i64 %ld107 to i32
  %and109 = and i32 %t108, 255
  %z110 = zext i32 %and109 to i64
  store i64 %z110, ptr %l4, align 4
  %t111 = trunc i64 %z110 to i32
  %cmp112 = icmp eq i32 %t111, 74
  %zext113 = zext i1 %cmp112 to i64
  %brif114 = icmp ne i64 %zext113, 0
  br i1 %brif114, label %c21, label %fall22

c21:                                              ; preds = %fall23, %fall20
  %get120 = load i64, ptr %l0, align 4
  %lc121 = call i64 @f16(i64 %get120, i64 1048792, i64 2)
  %lshr122 = lshr i64 %lc121, 32
  store i64 %lshr122, ptr %l0, align 4
  %cmp123 = icmp ugt i64 %lshr122, 1
  %zext124 = zext i1 %cmp123 to i64
  %brif125 = icmp ne i64 %zext124, 0
  br i1 %brif125, label %c1, label %fall24

fall22:                                           ; preds = %fall20
  %get115 = load i64, ptr %l4, align 4
  %t116 = trunc i64 %get115 to i32
  %cmp117 = icmp ne i32 %t116, 14
  %zext118 = zext i1 %cmp117 to i64
  %brif119 = icmp ne i64 %zext118, 0
  br i1 %brif119, label %c1, label %fall23

fall23:                                           ; preds = %fall22
  br label %c21

fall24:                                           ; preds = %c21
  %get126 = load i64, ptr %l0, align 4
  %sel127 = trunc i64 %get126 to i32
  switch i32 %sel127, label %c9 [
    i32 0, label %c9
    i32 1, label %c10
  ]

fall25:                                           ; preds = %c12
  %get136 = load i64, ptr %l1, align 4
  %and137 = and i64 %get136, 255
  %cmp138 = icmp ne i64 %and137, 4
  %zext139 = zext i1 %cmp138 to i64
  %brif140 = icmp ne i64 %zext139, 0
  br i1 %brif140, label %c1, label %fall26

fall26:                                           ; preds = %fall25
  br label %c11

fall27:                                           ; preds = %c10
  %slot48160 = getelementptr i8, ptr %frame, i64 48
  %fp161 = ptrtoint ptr %slot48160 to i64
  %slot8162 = getelementptr i8, ptr %frame, i64 8
  %fp163 = ptrtoint ptr %slot8162 to i64
  call void @f15(i64 %fp161, i64 %fp163)
  %slot48164 = getelementptr i8, ptr %frame, i64 48
  %ld165 = load i64, ptr %slot48164, align 1
  %cmp166 = icmp ne i64 %ld165, 0
  %zext167 = zext i1 %cmp166 to i64
  %brif168 = icmp ne i64 %zext167, 0
  br i1 %brif168, label %c1, label %fall28

fall28:                                           ; preds = %fall27
  %slot56169 = getelementptr i8, ptr %frame, i64 56
  %ld170 = load i64, ptr %slot56169, align 1
  %slot24171 = getelementptr i8, ptr %frame, i64 24
  %fp172 = ptrtoint ptr %slot24171 to i64
  call void @f22(i64 %fp172, i64 %ld170)
  %slot24173 = getelementptr i8, ptr %frame, i64 24
  %ld174 = load i64, ptr %slot24173, align 1
  %cmp175 = icmp eq i64 %ld174, 1
  %zext176 = zext i1 %cmp175 to i64
  %brif177 = icmp ne i64 %zext176, 0
  br i1 %brif177, label %c1, label %fall29

fall29:                                           ; preds = %fall28
  %slot40178 = getelementptr i8, ptr %frame, i64 40
  %ld179 = load i64, ptr %slot40178, align 1
  store i64 %ld179, ptr %l0, align 4
  %slot32180 = getelementptr i8, ptr %frame, i64 32
  %ld181 = load i64, ptr %slot32180, align 1
  store i64 %ld181, ptr %l1, align 4
  %slot24182 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24182, align 1
  %slot24183 = getelementptr i8, ptr %frame, i64 24
  %ld184 = load i32, ptr %slot24183, align 1
  %zx185 = zext i32 %ld184 to i64
  %slot24186 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24186, align 1
  %slot24187 = getelementptr i8, ptr %frame, i64 24
  %ld188 = load i32, ptr %slot24187, align 1
  %zx189 = zext i32 %ld188 to i64
  %slot24190 = getelementptr i8, ptr %frame, i64 24
  %fp191 = ptrtoint ptr %slot24190 to i64
  call void @f30(i64 %fp191, i64 1048780, i64 9)
  %slot24192 = getelementptr i8, ptr %frame, i64 24
  %ld193 = load i32, ptr %slot24192, align 1
  %zx194 = zext i32 %ld193 to i64
  %brif195 = icmp ne i64 %zx194, 0
  br i1 %brif195, label %c1, label %fall30

fall30:                                           ; preds = %fall29
  %slot32196 = getelementptr i8, ptr %frame, i64 32
  %ld197 = load i64, ptr %slot32196, align 1
  store i64 %ld197, ptr %l3, align 4
  %get198 = load i64, ptr %l0, align 4
  %slot32199 = getelementptr i8, ptr %frame, i64 32
  store i64 %get198, ptr %slot32199, align 1
  %get200 = load i64, ptr %l1, align 4
  %slot24201 = getelementptr i8, ptr %frame, i64 24
  store i64 %get200, ptr %slot24201, align 1
  %slot24202 = getelementptr i8, ptr %frame, i64 24
  %fp203 = ptrtoint ptr %slot24202 to i64
  %lc204 = call i64 @f28(i64 %fp203)
  %slot32205 = getelementptr i8, ptr %frame, i64 32
  store i64 %lc204, ptr %slot32205, align 1
  %get206 = load i64, ptr %l3, align 4
  %slot24207 = getelementptr i8, ptr %frame, i64 24
  store i64 %get206, ptr %slot24207, align 1
  %slot24208 = getelementptr i8, ptr %frame, i64 24
  %fp209 = ptrtoint ptr %slot24208 to i64
  %lc210 = call i64 @Guest_vec_new_from_slice(i64 %fp209, i64 2)
  store i64 %lc210, ptr %l0, align 4
  br label %c8

fall31:                                           ; preds = %c9
  %slot24219 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24219, align 1
  %slot24220 = getelementptr i8, ptr %frame, i64 24
  %ld221 = load i32, ptr %slot24220, align 1
  %zx222 = zext i32 %ld221 to i64
  %slot24223 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24223, align 1
  %slot24224 = getelementptr i8, ptr %frame, i64 24
  %ld225 = load i32, ptr %slot24224, align 1
  %zx226 = zext i32 %ld225 to i64
  %slot24227 = getelementptr i8, ptr %frame, i64 24
  %fp228 = ptrtoint ptr %slot24227 to i64
  call void @f30(i64 %fp228, i64 1048768, i64 12)
  %slot24229 = getelementptr i8, ptr %frame, i64 24
  %ld230 = load i32, ptr %slot24229, align 1
  %zx231 = zext i32 %ld230 to i64
  %brif232 = icmp ne i64 %zx231, 0
  br i1 %brif232, label %c1, label %fall32

fall32:                                           ; preds = %fall31
  %slot32233 = getelementptr i8, ptr %frame, i64 32
  %ld234 = load i64, ptr %slot32233, align 1
  %slot24235 = getelementptr i8, ptr %frame, i64 24
  store i64 %ld234, ptr %slot24235, align 1
  %slot24236 = getelementptr i8, ptr %frame, i64 24
  %fp237 = ptrtoint ptr %slot24236 to i64
  %lc238 = call i64 @Guest_vec_new_from_slice(i64 %fp237, i64 1)
  store i64 %lc238, ptr %l0, align 4
  br label %c8
}

define void @f13(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  %l6 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  store i64 0, ptr %l6, align 4
  %frame = alloca [64 x i8], align 1
  %slot24 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24, align 1
  %slot241 = getelementptr i8, ptr %frame, i64 24
  %ld = load i32, ptr %slot241, align 1
  %zx = zext i32 %ld to i64
  %slot242 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot242, align 1
  %slot243 = getelementptr i8, ptr %frame, i64 24
  %ld4 = load i32, ptr %slot243, align 1
  %zx5 = zext i32 %ld4 to i64
  %get = load i64, ptr %l1, align 4
  %ld6 = call i64 @soroban.load64(i64 %get)
  store i64 %ld6, ptr %l3, align 4
  %and = and i64 %ld6, 255
  %cmp = icmp eq i64 %and, 75
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c4, %c7, %c8, %fall3
  ret void

c2:                                               ; preds = %entry
  %get8 = load i64, ptr %l3, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get8)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  store i64 %payload, ptr %l4, align 4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  store i32 0, ptr %slot16, align 1
  %get9 = load i64, ptr %l3, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get9, ptr %slot8, align 1
  %get10 = load i64, ptr %l4, align 4
  %lshr = lshr i64 %get10, 32
  %slot20 = getelementptr i8, ptr %frame, i64 20
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot20, align 1
  %slot2411 = getelementptr i8, ptr %frame, i64 24
  %fp = ptrtoint ptr %slot2411 to i64
  %slot812 = getelementptr i8, ptr %frame, i64 8
  %fp13 = ptrtoint ptr %slot812 to i64
  call void @f15(i64 %fp, i64 %fp13)
  %slot2414 = getelementptr i8, ptr %frame, i64 24
  %ld15 = load i64, ptr %slot2414, align 1
  %cmp16 = icmp ne i64 %ld15, 0
  %zext17 = zext i1 %cmp16 to i64
  %brif18 = icmp ne i64 %zext17, 0
  br i1 %brif18, label %c8, label %fall9

fall3:                                            ; preds = %entry
  %get7 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get7, i64 4)
  br label %c1

c4:                                               ; preds = %c5, %fall28
  %get223 = load i64, ptr %l0, align 4
  %get224 = load i64, ptr %l6, align 4
  %ea = add i64 %get223, 24
  call void @soroban.store64(i64 %ea, i64 %get224)
  %get225 = load i64, ptr %l0, align 4
  %get226 = load i64, ptr %l3, align 4
  %ea227 = add i64 %get225, 16
  call void @soroban.store64(i64 %ea227, i64 %get226)
  %get228 = load i64, ptr %l0, align 4
  %get229 = load i64, ptr %l4, align 4
  %ea230 = add i64 %get228, 8
  call void @soroban.store64(i64 %ea230, i64 %get229)
  %get231 = load i64, ptr %l0, align 4
  %get232 = load i64, ptr %l1, align 4
  %ea233 = add i64 %get231, 1
  call void @soroban.store8(i64 %ea233, i64 %get232)
  %get234 = load i64, ptr %l0, align 4
  %get235 = load i64, ptr %l5, align 4
  call void @soroban.store8(i64 %get234, i64 %get235)
  br label %c1

c5:                                               ; preds = %c6, %fall32
  br label %c4

c6:                                               ; preds = %fall41, %fall18
  br label %c5

c7:                                               ; preds = %fall40, %c36, %fall34, %fall33, %c14, %fall31, %fall30, %fall29, %c15, %fall27, %fall26, %fall25, %c21, %fall19, %c16, %c17, %c10
  %get222 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get222, i64 4)
  br label %c1

c8:                                               ; preds = %fall11, %c2
  %get221 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get221, i64 4)
  br label %c1

fall9:                                            ; preds = %c2
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %ld19 = load i64, ptr %slot32, align 1
  store i64 %ld19, ptr %l3, align 4
  %t20 = trunc i64 %ld19 to i32
  %and21 = and i32 %t20, 255
  %z = zext i32 %and21 to i64
  store i64 %z, ptr %l1, align 4
  %t22 = trunc i64 %z to i32
  %cmp23 = icmp eq i32 %t22, 74
  %zext24 = zext i1 %cmp23 to i64
  %brif25 = icmp ne i64 %zext24, 0
  br i1 %brif25, label %c10, label %fall11

c10:                                              ; preds = %fall12, %fall9
  %get31 = load i64, ptr %l3, align 4
  %lc = call i64 @f16(i64 %get31, i64 1048692, i64 4)
  %lshr32 = lshr i64 %lc, 32
  store i64 %lshr32, ptr %l3, align 4
  %cmp33 = icmp ugt i64 %lshr32, 3
  %zext34 = zext i1 %cmp33 to i64
  %brif35 = icmp ne i64 %zext34, 0
  br i1 %brif35, label %c7, label %fall13

fall11:                                           ; preds = %fall9
  %get26 = load i64, ptr %l1, align 4
  %t27 = trunc i64 %get26 to i32
  %cmp28 = icmp ne i32 %t27, 14
  %zext29 = zext i1 %cmp28 to i64
  %brif30 = icmp ne i64 %zext29, 0
  br i1 %brif30, label %c8, label %fall12

fall12:                                           ; preds = %fall11
  br label %c10

fall13:                                           ; preds = %c10
  %get36 = load i64, ptr %l3, align 4
  %sel = trunc i64 %get36 to i32
  switch i32 %sel, label %c17 [
    i32 0, label %c17
    i32 1, label %c16
    i32 2, label %c15
    i32 3, label %c14
  ]

c14:                                              ; preds = %fall13
  %slot16157 = getelementptr i8, ptr %frame, i64 16
  %ld158 = load i32, ptr %slot16157, align 1
  %zx159 = zext i32 %ld158 to i64
  %slot20160 = getelementptr i8, ptr %frame, i64 20
  %ld161 = load i32, ptr %slot20160, align 1
  %zx162 = zext i32 %ld161 to i64
  %lc163 = call i64 @f17(i64 %zx159, i64 %zx162)
  %t164 = trunc i64 %lc163 to i32
  %cmp165 = icmp ugt i32 %t164, 1
  %zext166 = zext i1 %cmp165 to i64
  %brif167 = icmp ne i64 %zext166, 0
  br i1 %brif167, label %c7, label %fall33

c15:                                              ; preds = %fall13
  %slot16113 = getelementptr i8, ptr %frame, i64 16
  %ld114 = load i32, ptr %slot16113, align 1
  %zx115 = zext i32 %ld114 to i64
  %slot20116 = getelementptr i8, ptr %frame, i64 20
  %ld117 = load i32, ptr %slot20116, align 1
  %zx118 = zext i32 %ld117 to i64
  %lc119 = call i64 @f17(i64 %zx115, i64 %zx118)
  %t120 = trunc i64 %lc119 to i32
  %cmp121 = icmp ugt i32 %t120, 1
  %zext122 = zext i1 %cmp121 to i64
  %brif123 = icmp ne i64 %zext122, 0
  br i1 %brif123, label %c7, label %fall29

c16:                                              ; preds = %fall13
  %slot1645 = getelementptr i8, ptr %frame, i64 16
  %ld46 = load i32, ptr %slot1645, align 1
  %zx47 = zext i32 %ld46 to i64
  %slot2048 = getelementptr i8, ptr %frame, i64 20
  %ld49 = load i32, ptr %slot2048, align 1
  %zx50 = zext i32 %ld49 to i64
  %lc51 = call i64 @f17(i64 %zx47, i64 %zx50)
  %t52 = trunc i64 %lc51 to i32
  %cmp53 = icmp ugt i32 %t52, 1
  %zext54 = zext i1 %cmp53 to i64
  %brif55 = icmp ne i64 %zext54, 0
  br i1 %brif55, label %c7, label %fall19

c17:                                              ; preds = %fall13, %fall13
  %slot1637 = getelementptr i8, ptr %frame, i64 16
  %ld38 = load i32, ptr %slot1637, align 1
  %zx39 = zext i32 %ld38 to i64
  %slot2040 = getelementptr i8, ptr %frame, i64 20
  %ld41 = load i32, ptr %slot2040, align 1
  %zx42 = zext i32 %ld41 to i64
  %lc43 = call i64 @f17(i64 %zx39, i64 %zx42)
  %brif44 = icmp ne i64 %lc43, 0
  br i1 %brif44, label %c7, label %fall18

fall18:                                           ; preds = %c17
  store i64 0, ptr %l5, align 4
  br label %c6

fall19:                                           ; preds = %c16
  %slot2456 = getelementptr i8, ptr %frame, i64 24
  %fp57 = ptrtoint ptr %slot2456 to i64
  %slot858 = getelementptr i8, ptr %frame, i64 8
  %fp59 = ptrtoint ptr %slot858 to i64
  call void @f15(i64 %fp57, i64 %fp59)
  %slot2460 = getelementptr i8, ptr %frame, i64 24
  %ld61 = load i64, ptr %slot2460, align 1
  %cmp62 = icmp ne i64 %ld61, 0
  %zext63 = zext i1 %cmp62 to i64
  %brif64 = icmp ne i64 %zext63, 0
  br i1 %brif64, label %c7, label %fall20

fall20:                                           ; preds = %fall19
  %slot3265 = getelementptr i8, ptr %frame, i64 32
  %ld66 = load i64, ptr %slot3265, align 1
  store i64 %ld66, ptr %l3, align 4
  store i64 0, ptr %l1, align 4
  br label %h22

c21:                                              ; preds = %h22
  %get82 = load i64, ptr %l3, align 4
  %and83 = and i64 %get82, 255
  %cmp84 = icmp ne i64 %and83, 76
  %zext85 = zext i1 %cmp84 to i64
  %brif86 = icmp ne i64 %zext85, 0
  br i1 %brif86, label %c7, label %fall25

h22:                                              ; preds = %fall24, %fall20
  %get67 = load i64, ptr %l1, align 4
  %t68 = trunc i64 %get67 to i32
  %cmp69 = icmp eq i32 %t68, 24
  %zext70 = zext i1 %cmp69 to i64
  %brif71 = icmp ne i64 %zext70, 0
  br i1 %brif71, label %c21, label %fall24

fall24:                                           ; preds = %h22
  %get72 = load i64, ptr %l1, align 4
  %slot2473 = getelementptr i8, ptr %frame, i64 24
  %fp74 = ptrtoint ptr %slot2473 to i64
  %t75 = trunc i64 %fp74 to i32
  %t76 = trunc i64 %get72 to i32
  %add = add i32 %t75, %t76
  %z77 = zext i32 %add to i64
  call void @soroban.store64(i64 %z77, i64 2)
  %get78 = load i64, ptr %l1, align 4
  %t79 = trunc i64 %get78 to i32
  %add80 = add i32 %t79, 8
  %z81 = zext i32 %add80 to i64
  store i64 %z81, ptr %l1, align 4
  br label %h22

fall25:                                           ; preds = %c21
  %get87 = load i64, ptr %l3, align 4
  %slot2488 = getelementptr i8, ptr %frame, i64 24
  %fp89 = ptrtoint ptr %slot2488 to i64
  call void @f18(i64 %get87, i64 1048728, i64 3, i64 %fp89, i64 3)
  %slot2490 = getelementptr i8, ptr %frame, i64 24
  %ld91 = load i64, ptr %slot2490, align 1
  %slot48 = getelementptr i8, ptr %frame, i64 48
  %fp92 = ptrtoint ptr %slot48 to i64
  call void @i64_try_from_val(i64 %fp92, i64 %ld91)
  %slot4893 = getelementptr i8, ptr %frame, i64 48
  %ld94 = load i32, ptr %slot4893, align 1
  %zx95 = zext i32 %ld94 to i64
  %brif96 = icmp ne i64 %zx95, 0
  br i1 %brif96, label %c7, label %fall26

fall26:                                           ; preds = %fall25
  %slot56 = getelementptr i8, ptr %frame, i64 56
  %ld97 = load i64, ptr %slot56, align 1
  store i64 %ld97, ptr %l4, align 4
  %slot3298 = getelementptr i8, ptr %frame, i64 32
  %ld99 = load i64, ptr %slot3298, align 1
  %slot48100 = getelementptr i8, ptr %frame, i64 48
  %fp101 = ptrtoint ptr %slot48100 to i64
  call void @i64_try_from_val(i64 %fp101, i64 %ld99)
  %slot48102 = getelementptr i8, ptr %frame, i64 48
  %ld103 = load i32, ptr %slot48102, align 1
  %zx104 = zext i32 %ld103 to i64
  %brif105 = icmp ne i64 %zx104, 0
  br i1 %brif105, label %c7, label %fall27

fall27:                                           ; preds = %fall26
  %slot40 = getelementptr i8, ptr %frame, i64 40
  %ld106 = load i64, ptr %slot40, align 1
  store i64 %ld106, ptr %l6, align 4
  %and107 = and i64 %ld106, 255
  %cmp108 = icmp ne i64 %and107, 75
  %zext109 = zext i1 %cmp108 to i64
  %brif110 = icmp ne i64 %zext109, 0
  br i1 %brif110, label %c7, label %fall28

fall28:                                           ; preds = %fall27
  %slot56111 = getelementptr i8, ptr %frame, i64 56
  %ld112 = load i64, ptr %slot56111, align 1
  store i64 %ld112, ptr %l3, align 4
  store i64 1, ptr %l5, align 4
  br label %c4

fall29:                                           ; preds = %c15
  %slot24124 = getelementptr i8, ptr %frame, i64 24
  %fp125 = ptrtoint ptr %slot24124 to i64
  %slot8126 = getelementptr i8, ptr %frame, i64 8
  %fp127 = ptrtoint ptr %slot8126 to i64
  call void @f15(i64 %fp125, i64 %fp127)
  %slot24128 = getelementptr i8, ptr %frame, i64 24
  %ld129 = load i64, ptr %slot24128, align 1
  %cmp130 = icmp ne i64 %ld129, 0
  %zext131 = zext i1 %cmp130 to i64
  %brif132 = icmp ne i64 %zext131, 0
  br i1 %brif132, label %c7, label %fall30

fall30:                                           ; preds = %fall29
  %slot32133 = getelementptr i8, ptr %frame, i64 32
  %ld134 = load i64, ptr %slot32133, align 1
  store i64 %ld134, ptr %l3, align 4
  %and135 = and i64 %ld134, 255
  %cmp136 = icmp ne i64 %and135, 4
  %zext137 = zext i1 %cmp136 to i64
  %brif138 = icmp ne i64 %zext137, 0
  br i1 %brif138, label %c7, label %fall31

fall31:                                           ; preds = %fall30
  %get139 = load i64, ptr %l3, align 4
  %lshr140 = lshr i64 %get139, 32
  store i64 %lshr140, ptr %l1, align 4
  %t141 = trunc i64 %lshr140 to i32
  %cmp142 = icmp eq i32 %t141, 15
  %zext143 = zext i1 %cmp142 to i64
  %t144 = trunc i64 %zext143 to i32
  %sel145 = icmp ne i32 %t144, 0
  %select = select i1 %sel145, i64 15, i64 9
  %get146 = load i64, ptr %l1, align 4
  %t147 = trunc i64 %get146 to i32
  %cmp148 = icmp eq i32 %t147, 10
  %zext149 = zext i1 %cmp148 to i64
  %t150 = trunc i64 %zext149 to i32
  %sel151 = icmp ne i32 %t150, 0
  %select152 = select i1 %sel151, i64 10, i64 %select
  store i64 %select152, ptr %l1, align 4
  %t153 = trunc i64 %select152 to i32
  %cmp154 = icmp eq i32 %t153, 9
  %zext155 = zext i1 %cmp154 to i64
  %brif156 = icmp ne i64 %zext155, 0
  br i1 %brif156, label %c7, label %fall32

fall32:                                           ; preds = %fall31
  store i64 2, ptr %l5, align 4
  br label %c5

fall33:                                           ; preds = %c14
  %slot24168 = getelementptr i8, ptr %frame, i64 24
  %fp169 = ptrtoint ptr %slot24168 to i64
  %slot8170 = getelementptr i8, ptr %frame, i64 8
  %fp171 = ptrtoint ptr %slot8170 to i64
  call void @f15(i64 %fp169, i64 %fp171)
  %slot24172 = getelementptr i8, ptr %frame, i64 24
  %ld173 = load i64, ptr %slot24172, align 1
  %cmp174 = icmp ne i64 %ld173, 0
  %zext175 = zext i1 %cmp174 to i64
  %brif176 = icmp ne i64 %zext175, 0
  br i1 %brif176, label %c7, label %fall34

fall34:                                           ; preds = %fall33
  %slot32177 = getelementptr i8, ptr %frame, i64 32
  %ld178 = load i64, ptr %slot32177, align 1
  store i64 %ld178, ptr %l3, align 4
  %and179 = and i64 %ld178, 255
  %cmp180 = icmp ne i64 %and179, 75
  %zext181 = zext i1 %cmp180 to i64
  %brif182 = icmp ne i64 %zext181, 0
  br i1 %brif182, label %c7, label %fall35

fall35:                                           ; preds = %fall34
  store i64 0, ptr %l1, align 4
  br label %h37

c36:                                              ; preds = %h37
  %get199 = load i64, ptr %l3, align 4
  %slot48200 = getelementptr i8, ptr %frame, i64 48
  %fp201 = ptrtoint ptr %slot48200 to i64
  %shl = shl i64 %fp201, 32
  %or = or i64 %shl, 4
  %to_val202 = call %Val @soroban.val.from_payload(i64 %get199)
  %to_val203 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_unpack_to_linear_memory = call %Val @vec.vec_unpack_to_linear_memory(%Val %to_val202, %Val %to_val203, %Val %v_u32_2)
  %slot48204 = getelementptr i8, ptr %frame, i64 48
  %ld205 = load i64, ptr %slot48204, align 1
  %slot24206 = getelementptr i8, ptr %frame, i64 24
  %fp207 = ptrtoint ptr %slot24206 to i64
  call void @i64_try_from_val(i64 %fp207, i64 %ld205)
  %slot24208 = getelementptr i8, ptr %frame, i64 24
  %ld209 = load i64, ptr %slot24208, align 1
  %cmp210 = icmp eq i64 %ld209, 1
  %zext211 = zext i1 %cmp210 to i64
  %brif212 = icmp ne i64 %zext211, 0
  br i1 %brif212, label %c7, label %fall40

h37:                                              ; preds = %fall39, %fall35
  %get183 = load i64, ptr %l1, align 4
  %t184 = trunc i64 %get183 to i32
  %cmp185 = icmp eq i32 %t184, 16
  %zext186 = zext i1 %cmp185 to i64
  %brif187 = icmp ne i64 %zext186, 0
  br i1 %brif187, label %c36, label %fall39

fall39:                                           ; preds = %h37
  %get188 = load i64, ptr %l1, align 4
  %slot48189 = getelementptr i8, ptr %frame, i64 48
  %fp190 = ptrtoint ptr %slot48189 to i64
  %t191 = trunc i64 %fp190 to i32
  %t192 = trunc i64 %get188 to i32
  %add193 = add i32 %t191, %t192
  %z194 = zext i32 %add193 to i64
  call void @soroban.store64(i64 %z194, i64 2)
  %get195 = load i64, ptr %l1, align 4
  %t196 = trunc i64 %get195 to i32
  %add197 = add i32 %t196, 8
  %z198 = zext i32 %add197 to i64
  store i64 %z198, ptr %l1, align 4
  br label %h37

fall40:                                           ; preds = %c36
  %slot56213 = getelementptr i8, ptr %frame, i64 56
  %ld214 = load i64, ptr %slot56213, align 1
  store i64 %ld214, ptr %l3, align 4
  %and215 = and i64 %ld214, 255
  %cmp216 = icmp ne i64 %and215, 75
  %zext217 = zext i1 %cmp216 to i64
  %brif218 = icmp ne i64 %zext217, 0
  br i1 %brif218, label %c7, label %fall41

fall41:                                           ; preds = %fall40
  %slot32219 = getelementptr i8, ptr %frame, i64 32
  %ld220 = load i64, ptr %slot32219, align 1
  store i64 %ld220, ptr %l4, align 4
  store i64 3, ptr %l5, align 4
  br label %c6
}

define void @panic_fmt() #19 {
entry:
  ret void
}

define void @f15(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 2, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %ea = add i64 %get, 8
  %ld = call i64 @soroban.load32u(i64 %ea)
  store i64 %ld, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %ea2 = add i64 %get1, 12
  %ld3 = call i64 @soroban.load32u(i64 %ea2)
  %t = trunc i64 %ld to i32
  %t4 = trunc i64 %ld3 to i32
  %cmp = icmp uge i32 %t, %t4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get17 = load i64, ptr %l0, align 4
  %get18 = load i64, ptr %l2, align 4
  call void @soroban.store64(i64 %get17, i64 %get18)
  ret void

fall2:                                            ; preds = %entry
  %get5 = load i64, ptr %l0, align 4
  %get6 = load i64, ptr %l1, align 4
  %ld7 = call i64 @soroban.load64(i64 %get6)
  %get8 = load i64, ptr %l3, align 4
  %t9 = trunc i64 %get8 to i32
  %z = zext i32 %t9 to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %ld7)
  %to_val10 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %to_val10)
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  %ea11 = add i64 %get5, 8
  call void @soroban.store64(i64 %ea11, i64 %payload)
  %get12 = load i64, ptr %l1, align 4
  %get13 = load i64, ptr %l3, align 4
  %t14 = trunc i64 %get13 to i32
  %add = add i32 %t14, 1
  %z15 = zext i32 %add to i64
  %ea16 = add i64 %get12, 8
  call void @soroban.store32(i64 %ea16, i64 %z15)
  store i64 0, ptr %l2, align 4
  br label %c1
}

define "wasm.type"="i64" i64 @f16(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %t = trunc i64 %get1 to i32
  %z = zext i32 %t to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %get2 = load i64, ptr %l2, align 4
  %t3 = trunc i64 %get2 to i32
  %z4 = zext i32 %t3 to i64
  %shl5 = shl i64 %z4, 32
  %or6 = or i64 %shl5, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %to_val7 = call %Val @soroban.val.from_payload(i64 %or)
  %to_val8 = call %Val @soroban.val.from_payload(i64 %or6)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val, %Val %to_val7, %Val %to_val8)
  %payload = call i64 @soroban.val.payload(%Val %symbol_index_in_linear_memory)
  ret i64 %payload
}

define "wasm.type"="i32" i64 @f17(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l1, align 4
  %get1 = load i64, ptr %l0, align 4
  %t = trunc i64 %get to i32
  %t2 = trunc i64 %get1 to i32
  %cmp = icmp ult i32 %t, %t2
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  call void @panic()
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %get3 = load i64, ptr %l1, align 4
  %get4 = load i64, ptr %l0, align 4
  %t5 = trunc i64 %get3 to i32
  %t6 = trunc i64 %get4 to i32
  %sub = sub i32 %t5, %t6
  %z = zext i32 %sub to i64
  ret i64 %z
}

define void @f18(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 %3, ptr %l3, align 4
  store i64 %4, ptr %l4, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l4, align 4
  %t = trunc i64 %get to i32
  %t2 = trunc i64 %get1 to i32
  %cmp = icmp eq i32 %t, %t2
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l1, align 4
  %t5 = trunc i64 %get4 to i32
  %z = zext i32 %t5 to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %get6 = load i64, ptr %l3, align 4
  %t7 = trunc i64 %get6 to i32
  %z8 = zext i32 %t7 to i64
  %shl9 = shl i64 %z8, 32
  %or10 = or i64 %shl9, 4
  %get11 = load i64, ptr %l2, align 4
  %t12 = trunc i64 %get11 to i32
  %z13 = zext i32 %t12 to i64
  %shl14 = shl i64 %z13, 32
  %or15 = or i64 %shl14, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get3)
  %to_val16 = call %Val @soroban.val.from_payload(i64 %or)
  %to_val17 = call %Val @soroban.val.from_payload(i64 %or10)
  %to_val18 = call %Val @soroban.val.from_payload(i64 %or15)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %to_val16, %Val %to_val17, %Val %to_val18)
  ret void

fall2:                                            ; preds = %entry
  call void @soroban.trap()
  unreachable
}

define void @i64_try_from_val(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) #20 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %get = load i64, ptr %l1, align 4
  %t = trunc i64 %get to i32
  %and = and i32 %t, 255
  %z = zext i32 %and to i64
  store i64 %z, ptr %l2, align 4
  %t1 = trunc i64 %z to i32
  %cmp = icmp eq i32 %t1, 65
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %c4, %fall5
  %get9 = load i64, ptr %l0, align 4
  %get10 = load i64, ptr %l3, align 4
  call void @soroban.store64(i64 %get9, i64 %get10)
  %get11 = load i64, ptr %l0, align 4
  %get12 = load i64, ptr %l1, align 4
  %ea = add i64 %get11, 8
  call void @soroban.store64(i64 %ea, i64 %get12)
  ret void

c2:                                               ; preds = %entry
  store i64 0, ptr %l3, align 4
  %get8 = load i64, ptr %l1, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get8)
  %obj_to_i64 = call i64 @int.obj_to_i64(%Val %to_val)
  store i64 %obj_to_i64, ptr %l1, align 4
  br label %c1

fall3:                                            ; preds = %entry
  %get2 = load i64, ptr %l2, align 4
  %t3 = trunc i64 %get2 to i32
  %cmp4 = icmp eq i32 %t3, 7
  %zext5 = zext i1 %cmp4 to i64
  %brif6 = icmp ne i64 %zext5, 0
  br i1 %brif6, label %c4, label %fall5

c4:                                               ; preds = %fall3
  %get7 = load i64, ptr %l1, align 4
  %ashr = ashr i64 %get7, 8
  store i64 %ashr, ptr %l1, align 4
  store i64 0, ptr %l3, align 4
  br label %c1

fall5:                                            ; preds = %fall3
  store i64 1, ptr %l3, align 4
  store i64 34359740419, ptr %l1, align 4
  br label %c1
}

define void @panic() #21 {
entry:
  call void @panic_fmt_32()
  call void @soroban.trap()
  unreachable
}

define void @f21(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  %frame = alloca [16 x i8], align 1
  store i64 0, ptr %l3, align 4
  br label %h2

c1:                                               ; preds = %h2
  store i64 1, ptr %l4, align 4
  %get8 = load i64, ptr %l1, align 4
  %and = and i64 %get8, 255
  %cmp9 = icmp ne i64 %and, 76
  %zext10 = zext i1 %cmp9 to i64
  %brif11 = icmp ne i64 %zext10, 0
  br i1 %brif11, label %c5, label %fall6

h2:                                               ; preds = %fall4, %entry
  %get = load i64, ptr %l3, align 4
  %t = trunc i64 %get to i32
  %cmp = icmp eq i32 %t, 16
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall4

fall4:                                            ; preds = %h2
  %get1 = load i64, ptr %l3, align 4
  %fp = ptrtoint ptr %frame to i64
  %t2 = trunc i64 %fp to i32
  %t3 = trunc i64 %get1 to i32
  %add = add i32 %t2, %t3
  %z = zext i32 %add to i64
  call void @soroban.store64(i64 %z, i64 2)
  %get4 = load i64, ptr %l3, align 4
  %t5 = trunc i64 %get4 to i32
  %add6 = add i32 %t5, 8
  %z7 = zext i32 %add6 to i64
  store i64 %z7, ptr %l3, align 4
  br label %h2

c5:                                               ; preds = %fall10, %c7, %fall8, %c1
  %get36 = load i64, ptr %l0, align 4
  %get37 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get36, i64 %get37)
  ret void

fall6:                                            ; preds = %c1
  %get12 = load i64, ptr %l1, align 4
  %fp13 = ptrtoint ptr %frame to i64
  call void @f18(i64 %get12, i64 1048752, i64 2, i64 %fp13, i64 2)
  %ld = load i64, ptr %frame, align 1
  store i64 %ld, ptr %l1, align 4
  %t14 = trunc i64 %ld to i32
  %and15 = and i32 %t14, 255
  %z16 = zext i32 %and15 to i64
  store i64 %z16, ptr %l3, align 4
  %t17 = trunc i64 %z16 to i32
  %cmp18 = icmp eq i32 %t17, 74
  %zext19 = zext i1 %cmp18 to i64
  %brif20 = icmp ne i64 %zext19, 0
  br i1 %brif20, label %c7, label %fall8

c7:                                               ; preds = %fall9, %fall6
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld26 = load i64, ptr %slot8, align 1
  store i64 %ld26, ptr %l5, align 4
  %and27 = and i64 %ld26, 255
  %cmp28 = icmp ne i64 %and27, 75
  %zext29 = zext i1 %cmp28 to i64
  %brif30 = icmp ne i64 %zext29, 0
  br i1 %brif30, label %c5, label %fall10

fall8:                                            ; preds = %fall6
  %get21 = load i64, ptr %l3, align 4
  %t22 = trunc i64 %get21 to i32
  %cmp23 = icmp ne i32 %t22, 14
  %zext24 = zext i1 %cmp23 to i64
  %brif25 = icmp ne i64 %zext24, 0
  br i1 %brif25, label %c5, label %fall9

fall9:                                            ; preds = %fall8
  br label %c7

fall10:                                           ; preds = %c7
  %get31 = load i64, ptr %l0, align 4
  %get32 = load i64, ptr %l5, align 4
  %ea = add i64 %get31, 16
  call void @soroban.store64(i64 %ea, i64 %get32)
  %get33 = load i64, ptr %l0, align 4
  %get34 = load i64, ptr %l1, align 4
  %ea35 = add i64 %get33, 8
  call void @soroban.store64(i64 %ea35, i64 %get34)
  store i64 0, ptr %l4, align 4
  br label %c5
}

define void @f22(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  %frame = alloca [16 x i8], align 1
  store i64 0, ptr %l3, align 4
  br label %h2

c1:                                               ; preds = %h2
  store i64 1, ptr %l4, align 4
  %get8 = load i64, ptr %l1, align 4
  %and = and i64 %get8, 255
  %cmp9 = icmp ne i64 %and, 76
  %zext10 = zext i1 %cmp9 to i64
  %brif11 = icmp ne i64 %zext10, 0
  br i1 %brif11, label %c5, label %fall6

h2:                                               ; preds = %fall4, %entry
  %get = load i64, ptr %l3, align 4
  %t = trunc i64 %get to i32
  %cmp = icmp eq i32 %t, 16
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall4

fall4:                                            ; preds = %h2
  %get1 = load i64, ptr %l3, align 4
  %fp = ptrtoint ptr %frame to i64
  %t2 = trunc i64 %fp to i32
  %t3 = trunc i64 %get1 to i32
  %add = add i32 %t2, %t3
  %z = zext i32 %add to i64
  call void @soroban.store64(i64 %z, i64 2)
  %get4 = load i64, ptr %l3, align 4
  %t5 = trunc i64 %get4 to i32
  %add6 = add i32 %t5, 8
  %z7 = zext i32 %add6 to i64
  store i64 %z7, ptr %l3, align 4
  br label %h2

c5:                                               ; preds = %fall10, %c7, %fall8, %c1
  %get36 = load i64, ptr %l0, align 4
  %get37 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get36, i64 %get37)
  ret void

fall6:                                            ; preds = %c1
  %get12 = load i64, ptr %l1, align 4
  %fp13 = ptrtoint ptr %frame to i64
  call void @f18(i64 %get12, i64 1048752, i64 2, i64 %fp13, i64 2)
  %ld = load i64, ptr %frame, align 1
  store i64 %ld, ptr %l1, align 4
  %t14 = trunc i64 %ld to i32
  %and15 = and i32 %t14, 255
  %z16 = zext i32 %and15 to i64
  store i64 %z16, ptr %l3, align 4
  %t17 = trunc i64 %z16 to i32
  %cmp18 = icmp eq i32 %t17, 74
  %zext19 = zext i1 %cmp18 to i64
  %brif20 = icmp ne i64 %zext19, 0
  br i1 %brif20, label %c7, label %fall8

c7:                                               ; preds = %fall9, %fall6
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld26 = load i64, ptr %slot8, align 1
  store i64 %ld26, ptr %l5, align 4
  %and27 = and i64 %ld26, 255
  %cmp28 = icmp ne i64 %and27, 76
  %zext29 = zext i1 %cmp28 to i64
  %brif30 = icmp ne i64 %zext29, 0
  br i1 %brif30, label %c5, label %fall10

fall8:                                            ; preds = %fall6
  %get21 = load i64, ptr %l3, align 4
  %t22 = trunc i64 %get21 to i32
  %cmp23 = icmp ne i32 %t22, 14
  %zext24 = zext i1 %cmp23 to i64
  %brif25 = icmp ne i64 %zext24, 0
  br i1 %brif25, label %c5, label %fall9

fall9:                                            ; preds = %fall8
  br label %c7

fall10:                                           ; preds = %c7
  %get31 = load i64, ptr %l0, align 4
  %get32 = load i64, ptr %l5, align 4
  %ea = add i64 %get31, 16
  call void @soroban.store64(i64 %ea, i64 %get32)
  %get33 = load i64, ptr %l0, align 4
  %get34 = load i64, ptr %l1, align 4
  %ea35 = add i64 %get33, 8
  call void @soroban.store64(i64 %ea35, i64 %get34)
  store i64 0, ptr %l4, align 4
  br label %c5
}

define void @f23() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %frame = alloca [16 x i8], align 1
  %fp = ptrtoint ptr %frame to i64
  store i64 %fp, ptr %l0, align 4
  %slot12 = getelementptr i8, ptr %frame, i64 12
  store i32 2, ptr %slot12, align 1
  %slot121 = getelementptr i8, ptr %frame, i64 12
  %ld = load i32, ptr %slot121, align 1
  %zx = zext i32 %ld to i64
  ret void
}

define void @f24() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %frame = alloca [16 x i8], align 1
  %fp = ptrtoint ptr %frame to i64
  store i64 %fp, ptr %l0, align 4
  %slot12 = getelementptr i8, ptr %frame, i64 12
  store i32 1, ptr %slot12, align 1
  %slot121 = getelementptr i8, ptr %frame, i64 12
  %ld = load i32, ptr %slot121, align 1
  %zx = zext i32 %ld to i64
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i32 3, ptr %slot8, align 1
  %slot82 = getelementptr i8, ptr %frame, i64 8
  %ld3 = load i32, ptr %slot82, align 1
  %zx4 = zext i32 %ld3 to i64
  ret void
}

define void @f25(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  %frame = alloca [16 x i8], align 1
  store i64 2, ptr %l3, align 4
  %get = load i64, ptr %l1, align 4
  %ea = add i64 %get, 8
  %ld = call i64 @soroban.load32u(i64 %ea)
  store i64 %ld, ptr %l4, align 4
  %get1 = load i64, ptr %l1, align 4
  %ea2 = add i64 %get1, 12
  %ld3 = call i64 @soroban.load32u(i64 %ea2)
  %t = trunc i64 %ld to i32
  %t4 = trunc i64 %ld3 to i32
  %cmp = icmp uge i32 %t, %t4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get19 = load i64, ptr %l0, align 4
  %get20 = load i64, ptr %l3, align 4
  call void @soroban.store64(i64 %get19, i64 %get20)
  ret void

fall2:                                            ; preds = %entry
  %get5 = load i64, ptr %l1, align 4
  %ld6 = call i64 @soroban.load64(i64 %get5)
  %get7 = load i64, ptr %l4, align 4
  %t8 = trunc i64 %get7 to i32
  %z = zext i32 %t8 to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %ld6)
  %to_val9 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %to_val9)
  %fp = ptrtoint ptr %frame to i64
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  call void @i64_try_from_val(i64 %fp, i64 %payload)
  %ld10 = load i64, ptr %frame, align 1
  store i64 %ld10, ptr %l3, align 4
  %get11 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld12 = load i64, ptr %slot8, align 1
  %ea13 = add i64 %get11, 8
  call void @soroban.store64(i64 %ea13, i64 %ld12)
  %get14 = load i64, ptr %l1, align 4
  %get15 = load i64, ptr %l4, align 4
  %t16 = trunc i64 %get15 to i32
  %add = add i32 %t16, 1
  %z17 = zext i32 %add to i64
  %ea18 = add i64 %get14, 8
  call void @soroban.store32(i64 %ea18, i64 %z17)
  br label %c1
}

define "wasm.type"="i64" i64 @f28(i64 "wasm.type"="i32" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %t = trunc i64 %get to i32
  %z = zext i32 %t to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %v_u32_1048752 = call %Val @soroban.val.from_payload(i64 4504355541614596)
  %to_val1 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %Map__a____b__ = call %Val @map.map_new_from_linear_memory(%Val %v_u32_1048752, %Val %to_val1, %Val %v_u32_2)
  %payload = call i64 @soroban.val.payload(%Val %Map__a____b__)
  ret i64 %payload
}

define void @f30(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  %l6 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  store i64 0, ptr %l6, align 4
  %get = load i64, ptr %l2, align 4
  %t = trunc i64 %get to i32
  %cmp = icmp ugt i32 %t, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall7
  %get81 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get81, i64 0)
  %get82 = load i64, ptr %l0, align 4
  %get83 = load i64, ptr %l3, align 4
  %ea = add i64 %get82, 8
  call void @soroban.store64(i64 %ea, i64 %get83)
  ret void

c2:                                               ; preds = %fall13, %entry
  %get70 = load i64, ptr %l1, align 4
  %t71 = trunc i64 %get70 to i32
  %z72 = zext i32 %t71 to i64
  %shl73 = shl i64 %z72, 32
  %or74 = or i64 %shl73, 4
  %get75 = load i64, ptr %l2, align 4
  %t76 = trunc i64 %get75 to i32
  %z77 = zext i32 %t76 to i64
  %shl78 = shl i64 %z77, 32
  %or79 = or i64 %shl78, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or74)
  %to_val80 = call %Val @soroban.val.from_payload(i64 %or79)
  %symbol_new_from_linear_memory = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val80)
  %payload = call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  store i64 %payload, ptr %l3, align 4
  br label %c1

fall3:                                            ; preds = %entry
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  br label %h4

h4:                                               ; preds = %c8, %fall3
  %get1 = load i64, ptr %l4, align 4
  %t2 = trunc i64 %get1 to i32
  %cmp3 = icmp ne i32 %t2, 9
  %zext4 = zext i1 %cmp3 to i64
  %brif5 = icmp ne i64 %zext4, 0
  br i1 %brif5, label %c6, label %fall7

c6:                                               ; preds = %h4
  store i64 1, ptr %l5, align 4
  %get7 = load i64, ptr %l1, align 4
  %get8 = load i64, ptr %l4, align 4
  %t9 = trunc i64 %get7 to i32
  %t10 = trunc i64 %get8 to i32
  %add = add i32 %t9, %t10
  %z = zext i32 %add to i64
  %ld = call i64 @soroban.load8u(i64 %z)
  store i64 %ld, ptr %l6, align 4
  %t11 = trunc i64 %ld to i32
  %cmp12 = icmp eq i32 %t11, 95
  %zext13 = zext i1 %cmp12 to i64
  %brif14 = icmp ne i64 %zext13, 0
  br i1 %brif14, label %c8, label %fall9

fall7:                                            ; preds = %h4
  %get6 = load i64, ptr %l3, align 4
  %shl = shl i64 %get6, 8
  %or = or i64 %shl, 14
  store i64 %or, ptr %l3, align 4
  br label %c1

c8:                                               ; preds = %c10, %c11, %fall14, %c6
  %get59 = load i64, ptr %l3, align 4
  %shl60 = shl i64 %get59, 6
  %get61 = load i64, ptr %l5, align 4
  %t62 = trunc i64 %get61 to i32
  %z63 = zext i32 %t62 to i64
  %and64 = and i64 %z63, 255
  %or65 = or i64 %shl60, %and64
  store i64 %or65, ptr %l3, align 4
  %get66 = load i64, ptr %l4, align 4
  %t67 = trunc i64 %get66 to i32
  %add68 = add i32 %t67, 1
  %z69 = zext i32 %add68 to i64
  store i64 %z69, ptr %l4, align 4
  br label %h4

fall9:                                            ; preds = %c6
  %get15 = load i64, ptr %l6, align 4
  %t16 = trunc i64 %get15 to i32
  %add17 = add i32 %t16, -48
  %z18 = zext i32 %add17 to i64
  %t19 = trunc i64 %z18 to i32
  %and = and i32 %t19, 255
  %z20 = zext i32 %and to i64
  %t21 = trunc i64 %z20 to i32
  %cmp22 = icmp ult i32 %t21, 10
  %zext23 = zext i1 %cmp22 to i64
  %brif24 = icmp ne i64 %zext23, 0
  br i1 %brif24, label %c11, label %fall12

c10:                                              ; preds = %fall12
  %get55 = load i64, ptr %l6, align 4
  %t56 = trunc i64 %get55 to i32
  %add57 = add i32 %t56, -53
  %z58 = zext i32 %add57 to i64
  store i64 %z58, ptr %l5, align 4
  br label %c8

c11:                                              ; preds = %fall9
  %get51 = load i64, ptr %l6, align 4
  %t52 = trunc i64 %get51 to i32
  %add53 = add i32 %t52, -46
  %z54 = zext i32 %add53 to i64
  store i64 %z54, ptr %l5, align 4
  br label %c8

fall12:                                           ; preds = %fall9
  %get25 = load i64, ptr %l6, align 4
  %t26 = trunc i64 %get25 to i32
  %add27 = add i32 %t26, -65
  %z28 = zext i32 %add27 to i64
  %t29 = trunc i64 %z28 to i32
  %and30 = and i32 %t29, 255
  %z31 = zext i32 %and30 to i64
  %t32 = trunc i64 %z31 to i32
  %cmp33 = icmp ult i32 %t32, 26
  %zext34 = zext i1 %cmp33 to i64
  %brif35 = icmp ne i64 %zext34, 0
  br i1 %brif35, label %c10, label %fall13

fall13:                                           ; preds = %fall12
  %get36 = load i64, ptr %l6, align 4
  %t37 = trunc i64 %get36 to i32
  %add38 = add i32 %t37, -97
  %z39 = zext i32 %add38 to i64
  %t40 = trunc i64 %z39 to i32
  %and41 = and i32 %t40, 255
  %z42 = zext i32 %and41 to i64
  %t43 = trunc i64 %z42 to i32
  %cmp44 = icmp uge i32 %t43, 26
  %zext45 = zext i1 %cmp44 to i64
  %brif46 = icmp ne i64 %zext45, 0
  br i1 %brif46, label %c2, label %fall14

fall14:                                           ; preds = %fall13
  %get47 = load i64, ptr %l6, align 4
  %t48 = trunc i64 %get47 to i32
  %add49 = add i32 %t48, -59
  %z50 = zext i32 %add49 to i64
  store i64 %z50, ptr %l5, align 4
  br label %c8
}

define "wasm.type"="i64" i64 @Guest_vec_new_from_slice(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) #22 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %t = trunc i64 %get to i32
  %z = zext i32 %t to i64
  %shl = shl i64 %z, 32
  %or = or i64 %shl, 4
  %get1 = load i64, ptr %l1, align 4
  %t2 = trunc i64 %get1 to i32
  %z3 = zext i32 %t2 to i64
  %shl4 = shl i64 %z3, 32
  %or5 = or i64 %shl4, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val6 = call %Val @soroban.val.from_payload(i64 %or5)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %to_val6)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  ret i64 %payload
}

define void @panic_fmt_32() #19 {
entry:
  call void @soroban.trap()
  unreachable
}

attributes #0 = { nounwind willreturn memory(none) }
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
attributes #19 = { "sdk.name"="core::panicking::panic_fmt" }
attributes #20 = { "sdk.name"="<i64 as soroban_env_common::convert::TryFromVal<E,soroban_env_common::val::Val>>::try_from_val" }
attributes #21 = { "sdk.name"="core::slice::index::slice_index_fail | core::result::unwrap_failed | core::panicking::panic" }
attributes #22 = { "sdk.name"="<soroban_env_guest::guest::Guest as soroban_env_common::env::EnvBase>::vec_new_from_slice" }

!soroban.spec = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9}
!soroban.keys = !{!10}
!soroban.rodata = !{!11}

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
!10 = !{!"1048752 a b"}
!11 = !{!"1048576 537045635631f3b0ab40690d48b4537045635631aff793ba9e4dde9a537045635631eb9f12269a76282a53704563563116276438ffc9b1f8537045635631c81291fed713f59c537045635631ff7b5620ab0ddc64537045635631e16f55dbd4379814556474415564744255647443556474440000620010000400000066001000040000006a001000040000006e0010000400000061626300940010000100000095001000010000009600100001000000940010000100000095001000010000004e6f74526563757273697665526563757273697665000000c00010000c000000cc00100009000000"}
