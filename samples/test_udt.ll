; sdk 26.0.1 rustc 1.95.0; fingerprints 26.0.1+rustc1.95.0.txt: 5 of 17 helpers named, 1 by shape
; ModuleID = 'ponytail'
source_filename = "ponytail"

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
declare %Val @ponytail.unknown() #1

; Function Attrs: memory(inaccessiblemem: readwrite)
declare i64 @ponytail.unknown.i64() #1

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
  %cmp = icmp eq i64 %zx, 4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c5, label %fall6

c1:                                               ; preds = %c2, %fall32
  %get161 = load i64, ptr %l1, align 4
  %to_val162 = call %Val @soroban.val.from_payload(i64 %get161)
  ret %Val %to_val162

c2:                                               ; preds = %fall31
  %get159 = load i64, ptr %l0, align 4
  %obj_from_i64 = call %Val @int.obj_from_i64(i64 %get159)
  %payload160 = call i64 @soroban.val.payload(%Val %obj_from_i64)
  store i64 %payload160, ptr %l1, align 4
  br label %c1

c3:                                               ; preds = %c19, %c20, %fall29, %c27, %fall26, %h24, %fall18, %fall17, %c15, %fall14, %h12
  call void @panic()
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %c8, %c9, %c10, %fall7, %fall7
  %get79 = load i64, ptr %l7, align 4
  %sel80 = trunc i64 %get79 to i32
  switch i32 %sel80, label %c19 [
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
  %cmp16 = icmp eq i64 %zx15, 4
  %zext17 = zext i1 %cmp16 to i64
  %brif18 = icmp ne i64 %zext17, 0
  br i1 %brif18, label %c5, label %fall7

fall7:                                            ; preds = %fall6
  %slot3219 = getelementptr i8, ptr %frame, i64 32
  %ld20 = load i64, ptr %slot3219, align 1
  store i64 %ld20, ptr %l8, align 4
  %slot2421 = getelementptr i8, ptr %frame, i64 24
  %ld22 = load i64, ptr %slot2421, align 1
  store i64 %ld22, ptr %l9, align 4
  %slot1723 = getelementptr i8, ptr %frame, i64 17
  %ld24 = load i8, ptr %slot1723, align 1
  %zx25 = zext i8 %ld24 to i64
  store i64 %zx25, ptr %l10, align 4
  store i64 0, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  %get26 = load i64, ptr %l3, align 4
  %sel = trunc i64 %get26 to i32
  switch i32 %sel, label %c4 [
    i32 0, label %c4
    i32 1, label %c9
    i32 2, label %c10
    i32 3, label %c11
  ]

c8:                                               ; preds = %fall14
  %get66 = load i64, ptr %l1, align 4
  %cmp67 = icmp slt i64 %get66, 0
  %zext68 = zext i1 %cmp67 to i64
  %get69 = load i64, ptr %l5, align 4
  %get70 = load i64, ptr %l1, align 4
  %add71 = add i64 %get69, %get70
  store i64 %add71, ptr %l1, align 4
  %get72 = load i64, ptr %l5, align 4
  %cmp73 = icmp slt i64 %add71, %get72
  %zext74 = zext i1 %cmp73 to i64
  %xor75 = xor i64 %zext68, %zext74
  %eqz76 = icmp eq i64 %xor75, 0
  %zext77 = zext i1 %eqz76 to i64
  %brif78 = icmp ne i64 %zext77, 0
  br i1 %brif78, label %c4, label %fall18

c9:                                               ; preds = %fall7
  %get55 = load i64, ptr %l4, align 4
  %cmp56 = icmp slt i64 %get55, 0
  %zext57 = zext i1 %cmp56 to i64
  %get58 = load i64, ptr %l5, align 4
  %get59 = load i64, ptr %l4, align 4
  %add60 = add i64 %get58, %get59
  store i64 %add60, ptr %l1, align 4
  %get61 = load i64, ptr %l5, align 4
  %cmp62 = icmp slt i64 %add60, %get61
  %zext63 = zext i1 %cmp62 to i64
  %xor = xor i64 %zext57, %zext63
  %eqz = icmp eq i64 %xor, 0
  %zext64 = zext i1 %eqz to i64
  %brif65 = icmp ne i64 %zext64, 0
  br i1 %brif65, label %c4, label %fall17

c10:                                              ; preds = %fall7
  %get54 = load i64, ptr %l6, align 4
  store i64 %get54, ptr %l1, align 4
  br label %c4

c11:                                              ; preds = %fall7
  %get27 = load i64, ptr %l4, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get27)
  %vec_len = call %Val @vec.vec_len(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %vec_len)
  store i64 %payload, ptr %l1, align 4
  %slot56 = getelementptr i8, ptr %frame, i64 56
  store i32 0, ptr %slot56, align 1
  %get28 = load i64, ptr %l4, align 4
  %slot48 = getelementptr i8, ptr %frame, i64 48
  store i64 %get28, ptr %slot48, align 1
  %get29 = load i64, ptr %l1, align 4
  %lshr = lshr i64 %get29, 32
  %slot60 = getelementptr i8, ptr %frame, i64 60
  %t = trunc i64 %lshr to i32
  store i32 %t, ptr %slot60, align 1
  store i64 0, ptr %l1, align 4
  br label %h12

h12:                                              ; preds = %fall16, %c11
  %slot1630 = getelementptr i8, ptr %frame, i64 16
  %fp31 = ptrtoint ptr %slot1630 to i64
  %slot4832 = getelementptr i8, ptr %frame, i64 48
  %fp33 = ptrtoint ptr %slot4832 to i64
  call void @f25(i64 %fp31, i64 %fp33)
  %slot1634 = getelementptr i8, ptr %frame, i64 16
  %ld35 = load i64, ptr %slot1634, align 1
  store i64 %ld35, ptr %l4, align 4
  %cmp36 = icmp ugt i64 %ld35, 2
  %zext37 = zext i1 %cmp36 to i64
  %brif38 = icmp ne i64 %zext37, 0
  br i1 %brif38, label %c3, label %fall14

fall14:                                           ; preds = %h12
  %get39 = load i64, ptr %l4, align 4
  %sel40 = trunc i64 %get39 to i32
  switch i32 %sel40, label %c15 [
    i32 0, label %c15
    i32 1, label %c3
    i32 2, label %c8
  ]

c15:                                              ; preds = %fall14, %fall14
  %slot2441 = getelementptr i8, ptr %frame, i64 24
  %ld42 = load i64, ptr %slot2441, align 1
  store i64 %ld42, ptr %l4, align 4
  %cmp43 = icmp slt i64 %ld42, 0
  %zext44 = zext i1 %cmp43 to i64
  %get45 = load i64, ptr %l1, align 4
  %get46 = load i64, ptr %l4, align 4
  %add = add i64 %get45, %get46
  store i64 %add, ptr %l4, align 4
  %get47 = load i64, ptr %l1, align 4
  %cmp48 = icmp slt i64 %add, %get47
  %zext49 = zext i1 %cmp48 to i64
  %cmp50 = icmp ne i64 %zext44, %zext49
  %zext51 = zext i1 %cmp50 to i64
  %brif52 = icmp ne i64 %zext51, 0
  br i1 %brif52, label %c3, label %fall16

fall16:                                           ; preds = %c15
  %get53 = load i64, ptr %l4, align 4
  store i64 %get53, ptr %l1, align 4
  br label %h12

fall17:                                           ; preds = %c9
  br label %c3

fall18:                                           ; preds = %c8
  br label %c3

c19:                                              ; preds = %fall30, %c21, %c22, %c4, %c4
  %get142 = load i64, ptr %l0, align 4
  %cmp143 = icmp slt i64 %get142, 0
  %zext144 = zext i1 %cmp143 to i64
  %get145 = load i64, ptr %l1, align 4
  %get146 = load i64, ptr %l0, align 4
  %add147 = add i64 %get145, %get146
  store i64 %add147, ptr %l0, align 4
  %get148 = load i64, ptr %l1, align 4
  %cmp149 = icmp slt i64 %add147, %get148
  %zext150 = zext i1 %cmp149 to i64
  %xor151 = xor i64 %zext144, %zext150
  %brif152 = icmp ne i64 %xor151, 0
  br i1 %brif152, label %c3, label %fall31

c20:                                              ; preds = %fall26
  %get131 = load i64, ptr %l0, align 4
  %cmp132 = icmp slt i64 %get131, 0
  %zext133 = zext i1 %cmp132 to i64
  %get134 = load i64, ptr %l9, align 4
  %get135 = load i64, ptr %l0, align 4
  %add136 = add i64 %get134, %get135
  store i64 %add136, ptr %l0, align 4
  %get137 = load i64, ptr %l9, align 4
  %cmp138 = icmp slt i64 %add136, %get137
  %zext139 = zext i1 %cmp138 to i64
  %xor140 = xor i64 %zext133, %zext139
  %brif141 = icmp ne i64 %xor140, 0
  br i1 %brif141, label %c3, label %fall30

c21:                                              ; preds = %c4
  %get118 = load i64, ptr %l8, align 4
  %cmp119 = icmp slt i64 %get118, 0
  %zext120 = zext i1 %cmp119 to i64
  %get121 = load i64, ptr %l9, align 4
  %get122 = load i64, ptr %l8, align 4
  %add123 = add i64 %get121, %get122
  store i64 %add123, ptr %l0, align 4
  %get124 = load i64, ptr %l9, align 4
  %cmp125 = icmp slt i64 %add123, %get124
  %zext126 = zext i1 %cmp125 to i64
  %xor127 = xor i64 %zext120, %zext126
  %eqz128 = icmp eq i64 %xor127, 0
  %zext129 = zext i1 %eqz128 to i64
  %brif130 = icmp ne i64 %zext129, 0
  br i1 %brif130, label %c19, label %fall29

c22:                                              ; preds = %c4
  %get117 = load i64, ptr %l10, align 4
  store i64 %get117, ptr %l0, align 4
  br label %c19

c23:                                              ; preds = %c4
  %get81 = load i64, ptr %l8, align 4
  %to_val82 = call %Val @soroban.val.from_payload(i64 %get81)
  %vec_len83 = call %Val @vec.vec_len(%Val %to_val82)
  %payload84 = call i64 @soroban.val.payload(%Val %vec_len83)
  store i64 %payload84, ptr %l0, align 4
  %slot5685 = getelementptr i8, ptr %frame, i64 56
  store i32 0, ptr %slot5685, align 1
  %get86 = load i64, ptr %l8, align 4
  %slot4887 = getelementptr i8, ptr %frame, i64 48
  store i64 %get86, ptr %slot4887, align 1
  %get88 = load i64, ptr %l0, align 4
  %lshr89 = lshr i64 %get88, 32
  %slot6090 = getelementptr i8, ptr %frame, i64 60
  %t91 = trunc i64 %lshr89 to i32
  store i32 %t91, ptr %slot6090, align 1
  store i64 0, ptr %l0, align 4
  br label %h24

h24:                                              ; preds = %fall28, %c23
  %slot1692 = getelementptr i8, ptr %frame, i64 16
  %fp93 = ptrtoint ptr %slot1692 to i64
  %slot4894 = getelementptr i8, ptr %frame, i64 48
  %fp95 = ptrtoint ptr %slot4894 to i64
  call void @f25(i64 %fp93, i64 %fp95)
  %slot1696 = getelementptr i8, ptr %frame, i64 16
  %ld97 = load i64, ptr %slot1696, align 1
  store i64 %ld97, ptr %l4, align 4
  %cmp98 = icmp ugt i64 %ld97, 2
  %zext99 = zext i1 %cmp98 to i64
  %brif100 = icmp ne i64 %zext99, 0
  br i1 %brif100, label %c3, label %fall26

fall26:                                           ; preds = %h24
  %get101 = load i64, ptr %l4, align 4
  %sel102 = trunc i64 %get101 to i32
  switch i32 %sel102, label %c27 [
    i32 0, label %c27
    i32 1, label %c3
    i32 2, label %c20
  ]

c27:                                              ; preds = %fall26, %fall26
  %slot24103 = getelementptr i8, ptr %frame, i64 24
  %ld104 = load i64, ptr %slot24103, align 1
  store i64 %ld104, ptr %l4, align 4
  %cmp105 = icmp slt i64 %ld104, 0
  %zext106 = zext i1 %cmp105 to i64
  %get107 = load i64, ptr %l0, align 4
  %get108 = load i64, ptr %l4, align 4
  %add109 = add i64 %get107, %get108
  store i64 %add109, ptr %l4, align 4
  %get110 = load i64, ptr %l0, align 4
  %cmp111 = icmp slt i64 %add109, %get110
  %zext112 = zext i1 %cmp111 to i64
  %cmp113 = icmp ne i64 %zext106, %zext112
  %zext114 = zext i1 %cmp113 to i64
  %brif115 = icmp ne i64 %zext114, 0
  br i1 %brif115, label %c3, label %fall28

fall28:                                           ; preds = %c27
  %get116 = load i64, ptr %l4, align 4
  store i64 %get116, ptr %l0, align 4
  br label %h24

fall29:                                           ; preds = %c21
  br label %c3

fall30:                                           ; preds = %c20
  br label %c19

fall31:                                           ; preds = %c19
  %get153 = load i64, ptr %l0, align 4
  %add154 = add i64 %get153, 36028797018963968
  %cmp155 = icmp ugt i64 %add154, 72057594037927935
  %zext156 = zext i1 %cmp155 to i64
  %brif157 = icmp ne i64 %zext156, 0
  br i1 %brif157, label %c2, label %fall32

fall32:                                           ; preds = %fall31
  %get158 = load i64, ptr %l0, align 4
  %shl = shl i64 %get158, 8
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
  %and19 = and i64 %ld18, 255
  store i64 %and19, ptr %l4, align 4
  %cmp20 = icmp eq i64 %and19, 74
  %zext21 = zext i1 %cmp20 to i64
  %brif22 = icmp ne i64 %zext21, 0
  br i1 %brif22, label %c4, label %fall5

c4:                                               ; preds = %fall6, %fall3
  %get27 = load i64, ptr %l0, align 4
  %lc = call i64 @f16(i64 %get27, i64 1048792, i64 2)
  %lshr28 = lshr i64 %lc, 32
  store i64 %lshr28, ptr %l0, align 4
  %cmp29 = icmp ugt i64 %lshr28, 1
  %zext30 = zext i1 %cmp29 to i64
  %brif31 = icmp ne i64 %zext30, 0
  br i1 %brif31, label %c1, label %fall7

fall5:                                            ; preds = %fall3
  %get23 = load i64, ptr %l4, align 4
  %cmp24 = icmp ne i64 %get23, 14
  %zext25 = zext i1 %cmp24 to i64
  %brif26 = icmp ne i64 %zext25, 0
  br i1 %brif26, label %c1, label %fall6

fall6:                                            ; preds = %fall5
  br label %c4

fall7:                                            ; preds = %c4
  %get32 = load i64, ptr %l0, align 4
  %sel = trunc i64 %get32 to i32
  switch i32 %sel, label %c12 [
    i32 0, label %c12
    i32 1, label %c13
  ]

c8:                                               ; preds = %fall32, %fall30, %c11
  %get230 = load i64, ptr %l0, align 4
  %to_val231 = call %Val @soroban.val.from_payload(i64 %get230)
  ret %Val %to_val231

c9:                                               ; preds = %fall24, %fall24
  %slot16202 = getelementptr i8, ptr %frame, i64 16
  %ld203 = load i32, ptr %slot16202, align 1
  %zx204 = zext i32 %ld203 to i64
  %slot20205 = getelementptr i8, ptr %frame, i64 20
  %ld206 = load i32, ptr %slot20205, align 1
  %zx207 = zext i32 %ld206 to i64
  %lc208 = call i64 @f17(i64 %zx204, i64 %zx207)
  %brif209 = icmp ne i64 %lc208, 0
  br i1 %brif209, label %c1, label %fall31

c10:                                              ; preds = %fall24
  %slot16141 = getelementptr i8, ptr %frame, i64 16
  %ld142 = load i32, ptr %slot16141, align 1
  %zx143 = zext i32 %ld142 to i64
  %slot20144 = getelementptr i8, ptr %frame, i64 20
  %ld145 = load i32, ptr %slot20144, align 1
  %zx146 = zext i32 %ld145 to i64
  %lc147 = call i64 @f17(i64 %zx143, i64 %zx146)
  %cmp148 = icmp ugt i64 %lc147, 1
  %zext149 = zext i1 %cmp148 to i64
  %brif150 = icmp ne i64 %zext149, 0
  br i1 %brif150, label %c1, label %fall27

c11:                                              ; preds = %fall26, %fall17
  %slot24133 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24133, align 1
  %slot24134 = getelementptr i8, ptr %frame, i64 24
  %ld135 = load i32, ptr %slot24134, align 1
  %zx136 = zext i32 %ld135 to i64
  %slot24137 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24137, align 1
  %slot24138 = getelementptr i8, ptr %frame, i64 24
  %ld139 = load i32, ptr %slot24138, align 1
  %zx140 = zext i32 %ld139 to i64
  store i64 2, ptr %l0, align 4
  br label %c8

c12:                                              ; preds = %fall7, %fall7
  %slot16120 = getelementptr i8, ptr %frame, i64 16
  %ld121 = load i32, ptr %slot16120, align 1
  %zx122 = zext i32 %ld121 to i64
  %slot20123 = getelementptr i8, ptr %frame, i64 20
  %ld124 = load i32, ptr %slot20123, align 1
  %zx125 = zext i32 %ld124 to i64
  %lc126 = call i64 @f17(i64 %zx122, i64 %zx125)
  %brif127 = icmp ne i64 %lc126, 0
  br i1 %brif127, label %c1, label %fall25

c13:                                              ; preds = %fall7
  %slot1633 = getelementptr i8, ptr %frame, i64 16
  %ld34 = load i32, ptr %slot1633, align 1
  %zx35 = zext i32 %ld34 to i64
  %slot2036 = getelementptr i8, ptr %frame, i64 20
  %ld37 = load i32, ptr %slot2036, align 1
  %zx38 = zext i32 %ld37 to i64
  %lc39 = call i64 @f17(i64 %zx35, i64 %zx38)
  %cmp40 = icmp ugt i64 %lc39, 1
  %zext41 = zext i1 %cmp40 to i64
  %brif42 = icmp ne i64 %zext41, 0
  br i1 %brif42, label %c1, label %fall14

fall14:                                           ; preds = %c13
  %slot48 = getelementptr i8, ptr %frame, i64 48
  %fp43 = ptrtoint ptr %slot48 to i64
  %slot844 = getelementptr i8, ptr %frame, i64 8
  %fp45 = ptrtoint ptr %slot844 to i64
  call void @f15(i64 %fp43, i64 %fp45)
  %slot4846 = getelementptr i8, ptr %frame, i64 48
  %ld47 = load i64, ptr %slot4846, align 1
  %cmp48 = icmp ne i64 %ld47, 0
  %zext49 = zext i1 %cmp48 to i64
  %brif50 = icmp ne i64 %zext49, 0
  br i1 %brif50, label %c1, label %fall15

fall15:                                           ; preds = %fall14
  %slot56 = getelementptr i8, ptr %frame, i64 56
  %ld51 = load i64, ptr %slot56, align 1
  %slot2452 = getelementptr i8, ptr %frame, i64 24
  %fp53 = ptrtoint ptr %slot2452 to i64
  call void @f22(i64 %fp53, i64 %ld51)
  %slot2454 = getelementptr i8, ptr %frame, i64 24
  %ld55 = load i64, ptr %slot2454, align 1
  %cmp56 = icmp eq i64 %ld55, 1
  %zext57 = zext i1 %cmp56 to i64
  %brif58 = icmp ne i64 %zext57, 0
  br i1 %brif58, label %c1, label %fall16

fall16:                                           ; preds = %fall15
  %get59 = load i64, ptr %l1, align 4
  %and60 = and i64 %get59, 255
  %cmp61 = icmp ne i64 %and60, 4
  %zext62 = zext i1 %cmp61 to i64
  %brif63 = icmp ne i64 %zext62, 0
  br i1 %brif63, label %c1, label %fall17

fall17:                                           ; preds = %fall16
  %slot40 = getelementptr i8, ptr %frame, i64 40
  %ld64 = load i64, ptr %slot40, align 1
  store i64 %ld64, ptr %l0, align 4
  %get65 = load i64, ptr %l1, align 4
  %and66 = and i64 %get65, -4294967292
  store i64 %and66, ptr %l1, align 4
  %to_val67 = call %Val @soroban.val.from_payload(i64 %ld64)
  %to_val68 = call %Val @soroban.val.from_payload(i64 %and66)
  %map_has = call %Val @map.map_has(%Val %to_val67, %Val %to_val68)
  %payload69 = call i64 @soroban.val.payload(%Val %map_has)
  %cmp70 = icmp ne i64 %payload69, 1
  %zext71 = zext i1 %cmp70 to i64
  %brif72 = icmp ne i64 %zext71, 0
  br i1 %brif72, label %c11, label %fall18

fall18:                                           ; preds = %fall17
  %get73 = load i64, ptr %l0, align 4
  %get74 = load i64, ptr %l1, align 4
  %to_val75 = call %Val @soroban.val.from_payload(i64 %get73)
  %to_val76 = call %Val @soroban.val.from_payload(i64 %get74)
  %map_get = call %Val @map.map_get(%Val %to_val75, %Val %to_val76)
  %payload77 = call i64 @soroban.val.payload(%Val %map_get)
  store i64 %payload77, ptr %l0, align 4
  %and78 = and i64 %payload77, 255
  %cmp79 = icmp ne i64 %and78, 75
  %zext80 = zext i1 %cmp79 to i64
  %brif81 = icmp ne i64 %zext80, 0
  br i1 %brif81, label %c1, label %fall19

fall19:                                           ; preds = %fall18
  %get82 = load i64, ptr %l0, align 4
  %to_val83 = call %Val @soroban.val.from_payload(i64 %get82)
  %vec_len84 = call %Val @vec.vec_len(%Val %to_val83)
  %payload85 = call i64 @soroban.val.payload(%Val %vec_len84)
  store i64 %payload85, ptr %l1, align 4
  %slot1686 = getelementptr i8, ptr %frame, i64 16
  store i32 0, ptr %slot1686, align 1
  %get87 = load i64, ptr %l0, align 4
  %slot888 = getelementptr i8, ptr %frame, i64 8
  store i64 %get87, ptr %slot888, align 1
  %get89 = load i64, ptr %l1, align 4
  %lshr90 = lshr i64 %get89, 32
  %slot2091 = getelementptr i8, ptr %frame, i64 20
  %t92 = trunc i64 %lshr90 to i32
  store i32 %t92, ptr %slot2091, align 1
  %slot2493 = getelementptr i8, ptr %frame, i64 24
  %fp94 = ptrtoint ptr %slot2493 to i64
  %slot895 = getelementptr i8, ptr %frame, i64 8
  %fp96 = ptrtoint ptr %slot895 to i64
  call void @f15(i64 %fp94, i64 %fp96)
  %slot2497 = getelementptr i8, ptr %frame, i64 24
  %ld98 = load i64, ptr %slot2497, align 1
  %cmp99 = icmp ne i64 %ld98, 0
  %zext100 = zext i1 %cmp99 to i64
  %brif101 = icmp ne i64 %zext100, 0
  br i1 %brif101, label %c1, label %fall20

fall20:                                           ; preds = %fall19
  %slot32102 = getelementptr i8, ptr %frame, i64 32
  %ld103 = load i64, ptr %slot32102, align 1
  store i64 %ld103, ptr %l0, align 4
  %and104 = and i64 %ld103, 255
  store i64 %and104, ptr %l4, align 4
  %cmp105 = icmp eq i64 %and104, 74
  %zext106 = zext i1 %cmp105 to i64
  %brif107 = icmp ne i64 %zext106, 0
  br i1 %brif107, label %c21, label %fall22

c21:                                              ; preds = %fall23, %fall20
  %get112 = load i64, ptr %l0, align 4
  %lc113 = call i64 @f16(i64 %get112, i64 1048792, i64 2)
  %lshr114 = lshr i64 %lc113, 32
  store i64 %lshr114, ptr %l0, align 4
  %cmp115 = icmp ugt i64 %lshr114, 1
  %zext116 = zext i1 %cmp115 to i64
  %brif117 = icmp ne i64 %zext116, 0
  br i1 %brif117, label %c1, label %fall24

fall22:                                           ; preds = %fall20
  %get108 = load i64, ptr %l4, align 4
  %cmp109 = icmp ne i64 %get108, 14
  %zext110 = zext i1 %cmp109 to i64
  %brif111 = icmp ne i64 %zext110, 0
  br i1 %brif111, label %c1, label %fall23

fall23:                                           ; preds = %fall22
  br label %c21

fall24:                                           ; preds = %c21
  %get118 = load i64, ptr %l0, align 4
  %sel119 = trunc i64 %get118 to i32
  switch i32 %sel119, label %c9 [
    i32 0, label %c9
    i32 1, label %c10
  ]

fall25:                                           ; preds = %c12
  %get128 = load i64, ptr %l1, align 4
  %and129 = and i64 %get128, 255
  %cmp130 = icmp ne i64 %and129, 4
  %zext131 = zext i1 %cmp130 to i64
  %brif132 = icmp ne i64 %zext131, 0
  br i1 %brif132, label %c1, label %fall26

fall26:                                           ; preds = %fall25
  br label %c11

fall27:                                           ; preds = %c10
  %slot48151 = getelementptr i8, ptr %frame, i64 48
  %fp152 = ptrtoint ptr %slot48151 to i64
  %slot8153 = getelementptr i8, ptr %frame, i64 8
  %fp154 = ptrtoint ptr %slot8153 to i64
  call void @f15(i64 %fp152, i64 %fp154)
  %slot48155 = getelementptr i8, ptr %frame, i64 48
  %ld156 = load i64, ptr %slot48155, align 1
  %cmp157 = icmp ne i64 %ld156, 0
  %zext158 = zext i1 %cmp157 to i64
  %brif159 = icmp ne i64 %zext158, 0
  br i1 %brif159, label %c1, label %fall28

fall28:                                           ; preds = %fall27
  %slot56160 = getelementptr i8, ptr %frame, i64 56
  %ld161 = load i64, ptr %slot56160, align 1
  %slot24162 = getelementptr i8, ptr %frame, i64 24
  %fp163 = ptrtoint ptr %slot24162 to i64
  call void @f22(i64 %fp163, i64 %ld161)
  %slot24164 = getelementptr i8, ptr %frame, i64 24
  %ld165 = load i64, ptr %slot24164, align 1
  %cmp166 = icmp eq i64 %ld165, 1
  %zext167 = zext i1 %cmp166 to i64
  %brif168 = icmp ne i64 %zext167, 0
  br i1 %brif168, label %c1, label %fall29

fall29:                                           ; preds = %fall28
  %slot40169 = getelementptr i8, ptr %frame, i64 40
  %ld170 = load i64, ptr %slot40169, align 1
  store i64 %ld170, ptr %l0, align 4
  %slot32171 = getelementptr i8, ptr %frame, i64 32
  %ld172 = load i64, ptr %slot32171, align 1
  store i64 %ld172, ptr %l1, align 4
  %slot24173 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24173, align 1
  %slot24174 = getelementptr i8, ptr %frame, i64 24
  %ld175 = load i32, ptr %slot24174, align 1
  %zx176 = zext i32 %ld175 to i64
  %slot24177 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24177, align 1
  %slot24178 = getelementptr i8, ptr %frame, i64 24
  %ld179 = load i32, ptr %slot24178, align 1
  %zx180 = zext i32 %ld179 to i64
  %slot24181 = getelementptr i8, ptr %frame, i64 24
  %fp182 = ptrtoint ptr %slot24181 to i64
  call void @f30(i64 %fp182, i64 1048780, i64 9)
  %slot24183 = getelementptr i8, ptr %frame, i64 24
  %ld184 = load i32, ptr %slot24183, align 1
  %zx185 = zext i32 %ld184 to i64
  %brif186 = icmp ne i64 %zx185, 0
  br i1 %brif186, label %c1, label %fall30

fall30:                                           ; preds = %fall29
  %slot32187 = getelementptr i8, ptr %frame, i64 32
  %ld188 = load i64, ptr %slot32187, align 1
  store i64 %ld188, ptr %l3, align 4
  %get189 = load i64, ptr %l0, align 4
  %slot32190 = getelementptr i8, ptr %frame, i64 32
  store i64 %get189, ptr %slot32190, align 1
  %get191 = load i64, ptr %l1, align 4
  %slot24192 = getelementptr i8, ptr %frame, i64 24
  store i64 %get191, ptr %slot24192, align 1
  %slot24193 = getelementptr i8, ptr %frame, i64 24
  %fp194 = ptrtoint ptr %slot24193 to i64
  %lc195 = call i64 @f28(i64 %fp194)
  %slot32196 = getelementptr i8, ptr %frame, i64 32
  store i64 %lc195, ptr %slot32196, align 1
  %get197 = load i64, ptr %l3, align 4
  %slot24198 = getelementptr i8, ptr %frame, i64 24
  store i64 %get197, ptr %slot24198, align 1
  %slot24199 = getelementptr i8, ptr %frame, i64 24
  %fp200 = ptrtoint ptr %slot24199 to i64
  %lc201 = call i64 @Guest_vec_new_from_slice(i64 %fp200, i64 2)
  store i64 %lc201, ptr %l0, align 4
  br label %c8

fall31:                                           ; preds = %c9
  %slot24210 = getelementptr i8, ptr %frame, i64 24
  store i32 1, ptr %slot24210, align 1
  %slot24211 = getelementptr i8, ptr %frame, i64 24
  %ld212 = load i32, ptr %slot24211, align 1
  %zx213 = zext i32 %ld212 to i64
  %slot24214 = getelementptr i8, ptr %frame, i64 24
  store i32 3, ptr %slot24214, align 1
  %slot24215 = getelementptr i8, ptr %frame, i64 24
  %ld216 = load i32, ptr %slot24215, align 1
  %zx217 = zext i32 %ld216 to i64
  %slot24218 = getelementptr i8, ptr %frame, i64 24
  %fp219 = ptrtoint ptr %slot24218 to i64
  call void @f30(i64 %fp219, i64 1048768, i64 12)
  %slot24220 = getelementptr i8, ptr %frame, i64 24
  %ld221 = load i32, ptr %slot24220, align 1
  %zx222 = zext i32 %ld221 to i64
  %brif223 = icmp ne i64 %zx222, 0
  br i1 %brif223, label %c1, label %fall32

fall32:                                           ; preds = %fall31
  %slot32224 = getelementptr i8, ptr %frame, i64 32
  %ld225 = load i64, ptr %slot32224, align 1
  %slot24226 = getelementptr i8, ptr %frame, i64 24
  store i64 %ld225, ptr %slot24226, align 1
  %slot24227 = getelementptr i8, ptr %frame, i64 24
  %fp228 = ptrtoint ptr %slot24227 to i64
  %lc229 = call i64 @Guest_vec_new_from_slice(i64 %fp228, i64 1)
  store i64 %lc229, ptr %l0, align 4
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
  %get197 = load i64, ptr %l0, align 4
  %get198 = load i64, ptr %l6, align 4
  %ea = add i64 %get197, 24
  call void @soroban.store64(i64 %ea, i64 %get198)
  %get199 = load i64, ptr %l0, align 4
  %get200 = load i64, ptr %l3, align 4
  %ea201 = add i64 %get199, 16
  call void @soroban.store64(i64 %ea201, i64 %get200)
  %get202 = load i64, ptr %l0, align 4
  %get203 = load i64, ptr %l4, align 4
  %ea204 = add i64 %get202, 8
  call void @soroban.store64(i64 %ea204, i64 %get203)
  %get205 = load i64, ptr %l0, align 4
  %get206 = load i64, ptr %l1, align 4
  %ea207 = add i64 %get205, 1
  call void @soroban.store8(i64 %ea207, i64 %get206)
  %get208 = load i64, ptr %l0, align 4
  %get209 = load i64, ptr %l5, align 4
  call void @soroban.store8(i64 %get208, i64 %get209)
  br label %c1

c5:                                               ; preds = %c6, %fall32
  br label %c4

c6:                                               ; preds = %fall41, %fall18
  br label %c5

c7:                                               ; preds = %fall40, %c36, %fall34, %fall33, %c14, %fall31, %fall30, %fall29, %c15, %fall27, %fall26, %fall25, %c21, %fall19, %c16, %c17, %c10
  %get196 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get196, i64 4)
  br label %c1

c8:                                               ; preds = %fall11, %c2
  %get195 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get195, i64 4)
  br label %c1

fall9:                                            ; preds = %c2
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %ld19 = load i64, ptr %slot32, align 1
  store i64 %ld19, ptr %l3, align 4
  %and20 = and i64 %ld19, 255
  store i64 %and20, ptr %l1, align 4
  %cmp21 = icmp eq i64 %and20, 74
  %zext22 = zext i1 %cmp21 to i64
  %brif23 = icmp ne i64 %zext22, 0
  br i1 %brif23, label %c10, label %fall11

c10:                                              ; preds = %fall12, %fall9
  %get28 = load i64, ptr %l3, align 4
  %lc = call i64 @f16(i64 %get28, i64 1048692, i64 4)
  %lshr29 = lshr i64 %lc, 32
  store i64 %lshr29, ptr %l3, align 4
  %cmp30 = icmp ugt i64 %lshr29, 3
  %zext31 = zext i1 %cmp30 to i64
  %brif32 = icmp ne i64 %zext31, 0
  br i1 %brif32, label %c7, label %fall13

fall11:                                           ; preds = %fall9
  %get24 = load i64, ptr %l1, align 4
  %cmp25 = icmp ne i64 %get24, 14
  %zext26 = zext i1 %cmp25 to i64
  %brif27 = icmp ne i64 %zext26, 0
  br i1 %brif27, label %c8, label %fall12

fall12:                                           ; preds = %fall11
  br label %c10

fall13:                                           ; preds = %c10
  %get33 = load i64, ptr %l3, align 4
  %sel = trunc i64 %get33 to i32
  switch i32 %sel, label %c17 [
    i32 0, label %c17
    i32 1, label %c16
    i32 2, label %c15
    i32 3, label %c14
  ]

c14:                                              ; preds = %fall13
  %slot16138 = getelementptr i8, ptr %frame, i64 16
  %ld139 = load i32, ptr %slot16138, align 1
  %zx140 = zext i32 %ld139 to i64
  %slot20141 = getelementptr i8, ptr %frame, i64 20
  %ld142 = load i32, ptr %slot20141, align 1
  %zx143 = zext i32 %ld142 to i64
  %lc144 = call i64 @f17(i64 %zx140, i64 %zx143)
  %cmp145 = icmp ugt i64 %lc144, 1
  %zext146 = zext i1 %cmp145 to i64
  %brif147 = icmp ne i64 %zext146, 0
  br i1 %brif147, label %c7, label %fall33

c15:                                              ; preds = %fall13
  %slot16103 = getelementptr i8, ptr %frame, i64 16
  %ld104 = load i32, ptr %slot16103, align 1
  %zx105 = zext i32 %ld104 to i64
  %slot20106 = getelementptr i8, ptr %frame, i64 20
  %ld107 = load i32, ptr %slot20106, align 1
  %zx108 = zext i32 %ld107 to i64
  %lc109 = call i64 @f17(i64 %zx105, i64 %zx108)
  %cmp110 = icmp ugt i64 %lc109, 1
  %zext111 = zext i1 %cmp110 to i64
  %brif112 = icmp ne i64 %zext111, 0
  br i1 %brif112, label %c7, label %fall29

c16:                                              ; preds = %fall13
  %slot1642 = getelementptr i8, ptr %frame, i64 16
  %ld43 = load i32, ptr %slot1642, align 1
  %zx44 = zext i32 %ld43 to i64
  %slot2045 = getelementptr i8, ptr %frame, i64 20
  %ld46 = load i32, ptr %slot2045, align 1
  %zx47 = zext i32 %ld46 to i64
  %lc48 = call i64 @f17(i64 %zx44, i64 %zx47)
  %cmp49 = icmp ugt i64 %lc48, 1
  %zext50 = zext i1 %cmp49 to i64
  %brif51 = icmp ne i64 %zext50, 0
  br i1 %brif51, label %c7, label %fall19

c17:                                              ; preds = %fall13, %fall13
  %slot1634 = getelementptr i8, ptr %frame, i64 16
  %ld35 = load i32, ptr %slot1634, align 1
  %zx36 = zext i32 %ld35 to i64
  %slot2037 = getelementptr i8, ptr %frame, i64 20
  %ld38 = load i32, ptr %slot2037, align 1
  %zx39 = zext i32 %ld38 to i64
  %lc40 = call i64 @f17(i64 %zx36, i64 %zx39)
  %brif41 = icmp ne i64 %lc40, 0
  br i1 %brif41, label %c7, label %fall18

fall18:                                           ; preds = %c17
  store i64 0, ptr %l5, align 4
  br label %c6

fall19:                                           ; preds = %c16
  %slot2452 = getelementptr i8, ptr %frame, i64 24
  %fp53 = ptrtoint ptr %slot2452 to i64
  %slot854 = getelementptr i8, ptr %frame, i64 8
  %fp55 = ptrtoint ptr %slot854 to i64
  call void @f15(i64 %fp53, i64 %fp55)
  %slot2456 = getelementptr i8, ptr %frame, i64 24
  %ld57 = load i64, ptr %slot2456, align 1
  %cmp58 = icmp ne i64 %ld57, 0
  %zext59 = zext i1 %cmp58 to i64
  %brif60 = icmp ne i64 %zext59, 0
  br i1 %brif60, label %c7, label %fall20

fall20:                                           ; preds = %fall19
  %slot3261 = getelementptr i8, ptr %frame, i64 32
  %ld62 = load i64, ptr %slot3261, align 1
  store i64 %ld62, ptr %l3, align 4
  store i64 0, ptr %l1, align 4
  br label %h22

c21:                                              ; preds = %h22
  %get72 = load i64, ptr %l3, align 4
  %and73 = and i64 %get72, 255
  %cmp74 = icmp ne i64 %and73, 76
  %zext75 = zext i1 %cmp74 to i64
  %brif76 = icmp ne i64 %zext75, 0
  br i1 %brif76, label %c7, label %fall25

h22:                                              ; preds = %fall24, %fall20
  %get63 = load i64, ptr %l1, align 4
  %cmp64 = icmp eq i64 %get63, 24
  %zext65 = zext i1 %cmp64 to i64
  %brif66 = icmp ne i64 %zext65, 0
  br i1 %brif66, label %c21, label %fall24

fall24:                                           ; preds = %h22
  %get67 = load i64, ptr %l1, align 4
  %slot2468 = getelementptr i8, ptr %frame, i64 24
  %fp69 = ptrtoint ptr %slot2468 to i64
  %add = add i64 %fp69, %get67
  call void @soroban.store64(i64 %add, i64 2)
  %get70 = load i64, ptr %l1, align 4
  %add71 = add i64 %get70, 8
  store i64 %add71, ptr %l1, align 4
  br label %h22

fall25:                                           ; preds = %c21
  %get77 = load i64, ptr %l3, align 4
  %slot2478 = getelementptr i8, ptr %frame, i64 24
  %fp79 = ptrtoint ptr %slot2478 to i64
  call void @f18(i64 %get77, i64 1048728, i64 3, i64 %fp79, i64 3)
  %slot2480 = getelementptr i8, ptr %frame, i64 24
  %ld81 = load i64, ptr %slot2480, align 1
  %slot48 = getelementptr i8, ptr %frame, i64 48
  %fp82 = ptrtoint ptr %slot48 to i64
  call void @i64_try_from_val(i64 %fp82, i64 %ld81)
  %slot4883 = getelementptr i8, ptr %frame, i64 48
  %ld84 = load i32, ptr %slot4883, align 1
  %zx85 = zext i32 %ld84 to i64
  %brif86 = icmp ne i64 %zx85, 0
  br i1 %brif86, label %c7, label %fall26

fall26:                                           ; preds = %fall25
  %slot56 = getelementptr i8, ptr %frame, i64 56
  %ld87 = load i64, ptr %slot56, align 1
  store i64 %ld87, ptr %l4, align 4
  %slot3288 = getelementptr i8, ptr %frame, i64 32
  %ld89 = load i64, ptr %slot3288, align 1
  %slot4890 = getelementptr i8, ptr %frame, i64 48
  %fp91 = ptrtoint ptr %slot4890 to i64
  call void @i64_try_from_val(i64 %fp91, i64 %ld89)
  %slot4892 = getelementptr i8, ptr %frame, i64 48
  %ld93 = load i32, ptr %slot4892, align 1
  %zx94 = zext i32 %ld93 to i64
  %brif95 = icmp ne i64 %zx94, 0
  br i1 %brif95, label %c7, label %fall27

fall27:                                           ; preds = %fall26
  %slot40 = getelementptr i8, ptr %frame, i64 40
  %ld96 = load i64, ptr %slot40, align 1
  store i64 %ld96, ptr %l6, align 4
  %and97 = and i64 %ld96, 255
  %cmp98 = icmp ne i64 %and97, 75
  %zext99 = zext i1 %cmp98 to i64
  %brif100 = icmp ne i64 %zext99, 0
  br i1 %brif100, label %c7, label %fall28

fall28:                                           ; preds = %fall27
  %slot56101 = getelementptr i8, ptr %frame, i64 56
  %ld102 = load i64, ptr %slot56101, align 1
  store i64 %ld102, ptr %l3, align 4
  store i64 1, ptr %l5, align 4
  br label %c4

fall29:                                           ; preds = %c15
  %slot24113 = getelementptr i8, ptr %frame, i64 24
  %fp114 = ptrtoint ptr %slot24113 to i64
  %slot8115 = getelementptr i8, ptr %frame, i64 8
  %fp116 = ptrtoint ptr %slot8115 to i64
  call void @f15(i64 %fp114, i64 %fp116)
  %slot24117 = getelementptr i8, ptr %frame, i64 24
  %ld118 = load i64, ptr %slot24117, align 1
  %cmp119 = icmp ne i64 %ld118, 0
  %zext120 = zext i1 %cmp119 to i64
  %brif121 = icmp ne i64 %zext120, 0
  br i1 %brif121, label %c7, label %fall30

fall30:                                           ; preds = %fall29
  %slot32122 = getelementptr i8, ptr %frame, i64 32
  %ld123 = load i64, ptr %slot32122, align 1
  store i64 %ld123, ptr %l3, align 4
  %and124 = and i64 %ld123, 255
  %cmp125 = icmp ne i64 %and124, 4
  %zext126 = zext i1 %cmp125 to i64
  %brif127 = icmp ne i64 %zext126, 0
  br i1 %brif127, label %c7, label %fall31

fall31:                                           ; preds = %fall30
  %get128 = load i64, ptr %l3, align 4
  %lshr129 = lshr i64 %get128, 32
  store i64 %lshr129, ptr %l1, align 4
  %cmp130 = icmp eq i64 %lshr129, 15
  %zext131 = zext i1 %cmp130 to i64
  %get132 = load i64, ptr %l1, align 4
  %cmp133 = icmp eq i64 %get132, 10
  %zext134 = zext i1 %cmp133 to i64
  %bottom = call i64 @ponytail.unknown.i64()
  store i64 %bottom, ptr %l1, align 4
  %cmp135 = icmp eq i64 %bottom, 9
  %zext136 = zext i1 %cmp135 to i64
  %brif137 = icmp ne i64 %zext136, 0
  br i1 %brif137, label %c7, label %fall32

fall32:                                           ; preds = %fall31
  store i64 2, ptr %l5, align 4
  br label %c5

fall33:                                           ; preds = %c14
  %slot24148 = getelementptr i8, ptr %frame, i64 24
  %fp149 = ptrtoint ptr %slot24148 to i64
  %slot8150 = getelementptr i8, ptr %frame, i64 8
  %fp151 = ptrtoint ptr %slot8150 to i64
  call void @f15(i64 %fp149, i64 %fp151)
  %slot24152 = getelementptr i8, ptr %frame, i64 24
  %ld153 = load i64, ptr %slot24152, align 1
  %cmp154 = icmp ne i64 %ld153, 0
  %zext155 = zext i1 %cmp154 to i64
  %brif156 = icmp ne i64 %zext155, 0
  br i1 %brif156, label %c7, label %fall34

fall34:                                           ; preds = %fall33
  %slot32157 = getelementptr i8, ptr %frame, i64 32
  %ld158 = load i64, ptr %slot32157, align 1
  store i64 %ld158, ptr %l3, align 4
  %and159 = and i64 %ld158, 255
  %cmp160 = icmp ne i64 %and159, 75
  %zext161 = zext i1 %cmp160 to i64
  %brif162 = icmp ne i64 %zext161, 0
  br i1 %brif162, label %c7, label %fall35

fall35:                                           ; preds = %fall34
  store i64 0, ptr %l1, align 4
  br label %h37

c36:                                              ; preds = %h37
  %get173 = load i64, ptr %l3, align 4
  %slot48174 = getelementptr i8, ptr %frame, i64 48
  %fp175 = ptrtoint ptr %slot48174 to i64
  %shl = shl i64 %fp175, 32
  %or = or i64 %shl, 4
  %to_val176 = call %Val @soroban.val.from_payload(i64 %get173)
  %to_val177 = call %Val @soroban.val.from_payload(i64 %or)
  %v_u32_2 = call %Val @soroban.val.from_payload(i64 8589934596)
  %vec_unpack_to_linear_memory = call %Val @vec.vec_unpack_to_linear_memory(%Val %to_val176, %Val %to_val177, %Val %v_u32_2)
  %slot48178 = getelementptr i8, ptr %frame, i64 48
  %ld179 = load i64, ptr %slot48178, align 1
  %slot24180 = getelementptr i8, ptr %frame, i64 24
  %fp181 = ptrtoint ptr %slot24180 to i64
  call void @i64_try_from_val(i64 %fp181, i64 %ld179)
  %slot24182 = getelementptr i8, ptr %frame, i64 24
  %ld183 = load i64, ptr %slot24182, align 1
  %cmp184 = icmp eq i64 %ld183, 1
  %zext185 = zext i1 %cmp184 to i64
  %brif186 = icmp ne i64 %zext185, 0
  br i1 %brif186, label %c7, label %fall40

h37:                                              ; preds = %fall39, %fall35
  %get163 = load i64, ptr %l1, align 4
  %cmp164 = icmp eq i64 %get163, 16
  %zext165 = zext i1 %cmp164 to i64
  %brif166 = icmp ne i64 %zext165, 0
  br i1 %brif166, label %c36, label %fall39

fall39:                                           ; preds = %h37
  %get167 = load i64, ptr %l1, align 4
  %slot48168 = getelementptr i8, ptr %frame, i64 48
  %fp169 = ptrtoint ptr %slot48168 to i64
  %add170 = add i64 %fp169, %get167
  call void @soroban.store64(i64 %add170, i64 2)
  %get171 = load i64, ptr %l1, align 4
  %add172 = add i64 %get171, 8
  store i64 %add172, ptr %l1, align 4
  br label %h37

fall40:                                           ; preds = %c36
  %slot56187 = getelementptr i8, ptr %frame, i64 56
  %ld188 = load i64, ptr %slot56187, align 1
  store i64 %ld188, ptr %l3, align 4
  %and189 = and i64 %ld188, 255
  %cmp190 = icmp ne i64 %and189, 75
  %zext191 = zext i1 %cmp190 to i64
  %brif192 = icmp ne i64 %zext191, 0
  br i1 %brif192, label %c7, label %fall41

fall41:                                           ; preds = %fall40
  %slot32193 = getelementptr i8, ptr %frame, i64 32
  %ld194 = load i64, ptr %slot32193, align 1
  store i64 %ld194, ptr %l4, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  %brif = icmp ne i64 %bottom, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get13 = load i64, ptr %l0, align 4
  %get14 = load i64, ptr %l2, align 4
  call void @soroban.store64(i64 %get13, i64 %get14)
  ret void

fall2:                                            ; preds = %entry
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l1, align 4
  %ld6 = call i64 @soroban.load64(i64 %get5)
  %get7 = load i64, ptr %l3, align 4
  %shl = shl i64 %get7, 32
  %or = or i64 %shl, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %ld6)
  %to_val8 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %to_val8)
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  %ea9 = add i64 %get4, 8
  call void @soroban.store64(i64 %ea9, i64 %payload)
  %get10 = load i64, ptr %l1, align 4
  %get11 = load i64, ptr %l3, align 4
  %add = add i64 %get11, 1
  %ea12 = add i64 %get10, 8
  call void @soroban.store32(i64 %ea12, i64 %add)
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
  %shl = shl i64 %get1, 32
  %or = or i64 %shl, 4
  %get2 = load i64, ptr %l2, align 4
  %shl3 = shl i64 %get2, 32
  %or4 = or i64 %shl3, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %to_val5 = call %Val @soroban.val.from_payload(i64 %or)
  %to_val6 = call %Val @soroban.val.from_payload(i64 %or4)
  %symbol_index_in_linear_memory = call %Val @buf.symbol_index_in_linear_memory(%Val %to_val, %Val %to_val5, %Val %to_val6)
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
  %cmp = icmp ult i64 %get, %get1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  call void @panic()
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %get2 = load i64, ptr %l1, align 4
  %get3 = load i64, ptr %l0, align 4
  %sub = sub i64 %get2, %get3
  ret i64 %sub
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
  %cmp = icmp eq i64 %get, %get1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  %get2 = load i64, ptr %l0, align 4
  %get3 = load i64, ptr %l1, align 4
  %shl = shl i64 %get3, 32
  %or = or i64 %shl, 4
  %get4 = load i64, ptr %l3, align 4
  %shl5 = shl i64 %get4, 32
  %or6 = or i64 %shl5, 4
  %get7 = load i64, ptr %l2, align 4
  %shl8 = shl i64 %get7, 32
  %or9 = or i64 %shl8, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get2)
  %to_val10 = call %Val @soroban.val.from_payload(i64 %or)
  %to_val11 = call %Val @soroban.val.from_payload(i64 %or6)
  %to_val12 = call %Val @soroban.val.from_payload(i64 %or9)
  %map_unpack_to_linear_memory = call %Val @map.map_unpack_to_linear_memory(%Val %to_val, %Val %to_val10, %Val %to_val11, %Val %to_val12)
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
  %and = and i64 %get, 255
  store i64 %and, ptr %l2, align 4
  %cmp = icmp eq i64 %and, 65
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %c4, %fall5
  %get7 = load i64, ptr %l0, align 4
  %get8 = load i64, ptr %l3, align 4
  call void @soroban.store64(i64 %get7, i64 %get8)
  %get9 = load i64, ptr %l0, align 4
  %get10 = load i64, ptr %l1, align 4
  %ea = add i64 %get9, 8
  call void @soroban.store64(i64 %ea, i64 %get10)
  ret void

c2:                                               ; preds = %entry
  store i64 0, ptr %l3, align 4
  %get6 = load i64, ptr %l1, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get6)
  %obj_to_i64 = call i64 @int.obj_to_i64(%Val %to_val)
  store i64 %obj_to_i64, ptr %l1, align 4
  br label %c1

fall3:                                            ; preds = %entry
  %get1 = load i64, ptr %l2, align 4
  %cmp2 = icmp eq i64 %get1, 7
  %zext3 = zext i1 %cmp2 to i64
  %brif4 = icmp ne i64 %zext3, 0
  br i1 %brif4, label %c4, label %fall5

c4:                                               ; preds = %fall3
  %get5 = load i64, ptr %l1, align 4
  %ashr = ashr i64 %get5, 8
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
  %get4 = load i64, ptr %l1, align 4
  %and = and i64 %get4, 255
  %cmp5 = icmp ne i64 %and, 76
  %zext6 = zext i1 %cmp5 to i64
  %brif7 = icmp ne i64 %zext6, 0
  br i1 %brif7, label %c5, label %fall6

h2:                                               ; preds = %fall4, %entry
  %get = load i64, ptr %l3, align 4
  %cmp = icmp eq i64 %get, 16
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall4

fall4:                                            ; preds = %h2
  %get1 = load i64, ptr %l3, align 4
  %fp = ptrtoint ptr %frame to i64
  %add = add i64 %fp, %get1
  call void @soroban.store64(i64 %add, i64 2)
  %get2 = load i64, ptr %l3, align 4
  %add3 = add i64 %get2, 8
  store i64 %add3, ptr %l3, align 4
  br label %h2

c5:                                               ; preds = %fall10, %c7, %fall8, %c1
  %get28 = load i64, ptr %l0, align 4
  %get29 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get28, i64 %get29)
  ret void

fall6:                                            ; preds = %c1
  %get8 = load i64, ptr %l1, align 4
  %fp9 = ptrtoint ptr %frame to i64
  call void @f18(i64 %get8, i64 1048752, i64 2, i64 %fp9, i64 2)
  %ld = load i64, ptr %frame, align 1
  store i64 %ld, ptr %l1, align 4
  %and10 = and i64 %ld, 255
  store i64 %and10, ptr %l3, align 4
  %cmp11 = icmp eq i64 %and10, 74
  %zext12 = zext i1 %cmp11 to i64
  %brif13 = icmp ne i64 %zext12, 0
  br i1 %brif13, label %c7, label %fall8

c7:                                               ; preds = %fall9, %fall6
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld18 = load i64, ptr %slot8, align 1
  store i64 %ld18, ptr %l5, align 4
  %and19 = and i64 %ld18, 255
  %cmp20 = icmp ne i64 %and19, 75
  %zext21 = zext i1 %cmp20 to i64
  %brif22 = icmp ne i64 %zext21, 0
  br i1 %brif22, label %c5, label %fall10

fall8:                                            ; preds = %fall6
  %get14 = load i64, ptr %l3, align 4
  %cmp15 = icmp ne i64 %get14, 14
  %zext16 = zext i1 %cmp15 to i64
  %brif17 = icmp ne i64 %zext16, 0
  br i1 %brif17, label %c5, label %fall9

fall9:                                            ; preds = %fall8
  br label %c7

fall10:                                           ; preds = %c7
  %get23 = load i64, ptr %l0, align 4
  %get24 = load i64, ptr %l5, align 4
  %ea = add i64 %get23, 16
  call void @soroban.store64(i64 %ea, i64 %get24)
  %get25 = load i64, ptr %l0, align 4
  %get26 = load i64, ptr %l1, align 4
  %ea27 = add i64 %get25, 8
  call void @soroban.store64(i64 %ea27, i64 %get26)
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
  %get4 = load i64, ptr %l1, align 4
  %and = and i64 %get4, 255
  %cmp5 = icmp ne i64 %and, 76
  %zext6 = zext i1 %cmp5 to i64
  %brif7 = icmp ne i64 %zext6, 0
  br i1 %brif7, label %c5, label %fall6

h2:                                               ; preds = %fall4, %entry
  %get = load i64, ptr %l3, align 4
  %cmp = icmp eq i64 %get, 16
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall4

fall4:                                            ; preds = %h2
  %get1 = load i64, ptr %l3, align 4
  %fp = ptrtoint ptr %frame to i64
  %add = add i64 %fp, %get1
  call void @soroban.store64(i64 %add, i64 2)
  %get2 = load i64, ptr %l3, align 4
  %add3 = add i64 %get2, 8
  store i64 %add3, ptr %l3, align 4
  br label %h2

c5:                                               ; preds = %fall10, %c7, %fall8, %c1
  %get28 = load i64, ptr %l0, align 4
  %get29 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get28, i64 %get29)
  ret void

fall6:                                            ; preds = %c1
  %get8 = load i64, ptr %l1, align 4
  %fp9 = ptrtoint ptr %frame to i64
  call void @f18(i64 %get8, i64 1048752, i64 2, i64 %fp9, i64 2)
  %ld = load i64, ptr %frame, align 1
  store i64 %ld, ptr %l1, align 4
  %and10 = and i64 %ld, 255
  store i64 %and10, ptr %l3, align 4
  %cmp11 = icmp eq i64 %and10, 74
  %zext12 = zext i1 %cmp11 to i64
  %brif13 = icmp ne i64 %zext12, 0
  br i1 %brif13, label %c7, label %fall8

c7:                                               ; preds = %fall9, %fall6
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld18 = load i64, ptr %slot8, align 1
  store i64 %ld18, ptr %l5, align 4
  %and19 = and i64 %ld18, 255
  %cmp20 = icmp ne i64 %and19, 76
  %zext21 = zext i1 %cmp20 to i64
  %brif22 = icmp ne i64 %zext21, 0
  br i1 %brif22, label %c5, label %fall10

fall8:                                            ; preds = %fall6
  %get14 = load i64, ptr %l3, align 4
  %cmp15 = icmp ne i64 %get14, 14
  %zext16 = zext i1 %cmp15 to i64
  %brif17 = icmp ne i64 %zext16, 0
  br i1 %brif17, label %c5, label %fall9

fall9:                                            ; preds = %fall8
  br label %c7

fall10:                                           ; preds = %c7
  %get23 = load i64, ptr %l0, align 4
  %get24 = load i64, ptr %l5, align 4
  %ea = add i64 %get23, 16
  call void @soroban.store64(i64 %ea, i64 %get24)
  %get25 = load i64, ptr %l0, align 4
  %get26 = load i64, ptr %l1, align 4
  %ea27 = add i64 %get25, 8
  call void @soroban.store64(i64 %ea27, i64 %get26)
  store i64 0, ptr %l4, align 4
  br label %c5
}

define void @f23() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l0, align 4
  %ea = add i64 %sub, 12
  call void @soroban.store32(i64 %ea, i64 2)
  %get = load i64, ptr %l0, align 4
  %ea1 = add i64 %get, 12
  %ld = call i64 @soroban.load32u(i64 %ea1)
  ret void
}

define void @f24() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l0, align 4
  %ea = add i64 %sub, 12
  call void @soroban.store32(i64 %ea, i64 1)
  %get = load i64, ptr %l0, align 4
  %ea1 = add i64 %get, 12
  %ld = call i64 @soroban.load32u(i64 %ea1)
  %get2 = load i64, ptr %l0, align 4
  %ea3 = add i64 %get2, 8
  call void @soroban.store32(i64 %ea3, i64 3)
  %get4 = load i64, ptr %l0, align 4
  %ea5 = add i64 %get4, 8
  %ld6 = call i64 @soroban.load32u(i64 %ea5)
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
  %bottom = call i64 @ponytail.unknown.i64()
  %brif = icmp ne i64 %bottom, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get15 = load i64, ptr %l0, align 4
  %get16 = load i64, ptr %l3, align 4
  call void @soroban.store64(i64 %get15, i64 %get16)
  ret void

fall2:                                            ; preds = %entry
  %get4 = load i64, ptr %l1, align 4
  %ld5 = call i64 @soroban.load64(i64 %get4)
  %get6 = load i64, ptr %l4, align 4
  %shl = shl i64 %get6, 32
  %or = or i64 %shl, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %ld5)
  %to_val7 = call %Val @soroban.val.from_payload(i64 %or)
  %vec_get = call %Val @vec.vec_get(%Val %to_val, %Val %to_val7)
  %fp = ptrtoint ptr %frame to i64
  %payload = call i64 @soroban.val.payload(%Val %vec_get)
  call void @i64_try_from_val(i64 %fp, i64 %payload)
  %ld8 = load i64, ptr %frame, align 1
  store i64 %ld8, ptr %l3, align 4
  %get9 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld10 = load i64, ptr %slot8, align 1
  %ea11 = add i64 %get9, 8
  call void @soroban.store64(i64 %ea11, i64 %ld10)
  %get12 = load i64, ptr %l1, align 4
  %get13 = load i64, ptr %l4, align 4
  %add = add i64 %get13, 1
  %ea14 = add i64 %get12, 8
  call void @soroban.store32(i64 %ea14, i64 %add)
  br label %c1
}

define "wasm.type"="i64" i64 @f28(i64 "wasm.type"="i32" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %shl = shl i64 %get, 32
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
  %cmp = icmp ugt i64 %get, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall7
  %get46 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get46, i64 0)
  %get47 = load i64, ptr %l0, align 4
  %get48 = load i64, ptr %l3, align 4
  %ea = add i64 %get47, 8
  call void @soroban.store64(i64 %ea, i64 %get48)
  ret void

c2:                                               ; preds = %fall13, %entry
  %get39 = load i64, ptr %l1, align 4
  %shl40 = shl i64 %get39, 32
  %or41 = or i64 %shl40, 4
  %get42 = load i64, ptr %l2, align 4
  %shl43 = shl i64 %get42, 32
  %or44 = or i64 %shl43, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or41)
  %to_val45 = call %Val @soroban.val.from_payload(i64 %or44)
  %symbol_new_from_linear_memory = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val45)
  %payload = call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  store i64 %payload, ptr %l3, align 4
  br label %c1

fall3:                                            ; preds = %entry
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  br label %h4

h4:                                               ; preds = %c8, %fall3
  %get1 = load i64, ptr %l4, align 4
  %cmp2 = icmp ne i64 %get1, 9
  %zext3 = zext i1 %cmp2 to i64
  %brif4 = icmp ne i64 %zext3, 0
  br i1 %brif4, label %c6, label %fall7

c6:                                               ; preds = %h4
  store i64 1, ptr %l5, align 4
  %get6 = load i64, ptr %l1, align 4
  %get7 = load i64, ptr %l4, align 4
  %add = add i64 %get6, %get7
  %ld = call i64 @soroban.load8u(i64 %add)
  store i64 %ld, ptr %l6, align 4
  %cmp8 = icmp eq i64 %ld, 95
  %zext9 = zext i1 %cmp8 to i64
  %brif10 = icmp ne i64 %zext9, 0
  br i1 %brif10, label %c8, label %fall9

fall7:                                            ; preds = %h4
  %get5 = load i64, ptr %l3, align 4
  %shl = shl i64 %get5, 8
  %or = or i64 %shl, 14
  store i64 %or, ptr %l3, align 4
  br label %c1

c8:                                               ; preds = %c10, %c11, %fall14, %c6
  %get32 = load i64, ptr %l3, align 4
  %shl33 = shl i64 %get32, 6
  %get34 = load i64, ptr %l5, align 4
  %and35 = and i64 %get34, 255
  %or36 = or i64 %shl33, %and35
  store i64 %or36, ptr %l3, align 4
  %get37 = load i64, ptr %l4, align 4
  %add38 = add i64 %get37, 1
  store i64 %add38, ptr %l4, align 4
  br label %h4

fall9:                                            ; preds = %c6
  %get11 = load i64, ptr %l6, align 4
  %add12 = add i64 %get11, -48
  %and = and i64 %add12, 255
  %cmp13 = icmp ult i64 %and, 10
  %zext14 = zext i1 %cmp13 to i64
  %brif15 = icmp ne i64 %zext14, 0
  br i1 %brif15, label %c11, label %fall12

c10:                                              ; preds = %fall12
  %get30 = load i64, ptr %l6, align 4
  %add31 = add i64 %get30, -53
  store i64 %add31, ptr %l5, align 4
  br label %c8

c11:                                              ; preds = %fall9
  %get28 = load i64, ptr %l6, align 4
  %add29 = add i64 %get28, -46
  store i64 %add29, ptr %l5, align 4
  br label %c8

fall12:                                           ; preds = %fall9
  %get16 = load i64, ptr %l6, align 4
  %add17 = add i64 %get16, -65
  %and18 = and i64 %add17, 255
  %cmp19 = icmp ult i64 %and18, 26
  %zext20 = zext i1 %cmp19 to i64
  %brif21 = icmp ne i64 %zext20, 0
  br i1 %brif21, label %c10, label %fall13

fall13:                                           ; preds = %fall12
  %get22 = load i64, ptr %l6, align 4
  %add23 = add i64 %get22, -97
  %and24 = and i64 %add23, 255
  %bottom = call i64 @ponytail.unknown.i64()
  %brif25 = icmp ne i64 %bottom, 0
  br i1 %brif25, label %c2, label %fall14

fall14:                                           ; preds = %fall13
  %get26 = load i64, ptr %l6, align 4
  %add27 = add i64 %get26, -59
  store i64 %add27, ptr %l5, align 4
  br label %c8
}

define "wasm.type"="i64" i64 @Guest_vec_new_from_slice(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) #22 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %shl = shl i64 %get, 32
  %or = or i64 %shl, 4
  %get1 = load i64, ptr %l1, align 4
  %shl2 = shl i64 %get1, 32
  %or3 = or i64 %shl2, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %or3)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %to_val4)
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
