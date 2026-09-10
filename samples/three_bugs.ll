; sdk 25.3.2 rustc 1.97.1; fingerprints 25.3.2.txt: 4 of 43 helpers named, 3 by shape
; ModuleID = 'ponytail'
source_filename = "ponytail"

%Val = type { i64 }

@g0 = global i64 1048576
@g1 = constant i64 1048680

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

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val) #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.fail_with_error(%Val) #4

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.has_contract_data(%Val, i64) #5

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) #6

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val) #7

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val) #8

define "spec.type"="Result<Symbol, Error>" "wasm.type"="i64" %Val @pick(%Val "spec.name"="f" "spec.type"="Flag" "wasm.type"="i64" %0) #9 {
entry:
  %l0 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  call void @panic_fmt_33()
  %get = load i64, ptr %l0, align 4
  %lc = call i64 @f11(i64 %get)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define "spec.type"="bool" "wasm.type"="i64" %Val @read(%Val "spec.name"="a" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="Address" "wasm.type"="i64" %1) #10 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  %arg_payload1 = call i64 @soroban.val.payload(%Val %1)
  store i64 %arg_payload1, ptr %l1, align 4
  call void @panic_fmt_33()
  %get = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %lc = call i64 @f14(i64 %get, i64 %get2)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define "wasm.type"="i64" %Val @set_flag() #11 {
entry:
  call void @panic_fmt_33()
  call void @f17()
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define "wasm.type"="i32" i64 @f6(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %lc = call i64 @f7(i64 %get1, i64 %get2)
  %lc3 = call i64 @f27(i64 %get, i64 %lc, i64 1)
  ret i64 %lc3
}

define "wasm.type"="i64" i64 @f7(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [48 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  %cmp = icmp ne i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c4, label %fall5

c1:                                               ; preds = %c3
  %get62 = load i64, ptr %l3, align 4
  ret i64 %get62

c2:                                               ; preds = %fall10, %fall8, %c4, %fall6, %fall5
  call void @soroban.trap()
  unreachable

c3:                                               ; preds = %fall9, %fall7
  %slot4056 = getelementptr i8, ptr %frame, i64 40
  %ld57 = load i64, ptr %slot4056, align 1
  store i64 %ld57, ptr %l3, align 4
  %slot3258 = getelementptr i8, ptr %frame, i64 32
  %ld59 = load i64, ptr %slot3258, align 1
  %eqz = icmp eq i64 %ld59, 0
  %zext60 = zext i1 %eqz to i64
  %brif61 = icmp ne i64 %zext60, 0
  br i1 %brif61, label %c1, label %fall10

c4:                                               ; preds = %entry
  %get24 = load i64, ptr %l0, align 4
  %slot3225 = getelementptr i8, ptr %frame, i64 32
  %fp26 = ptrtoint ptr %slot3225 to i64
  call void @Symbol_try_from_val(i64 %fp26, i64 %get24, i64 1048656)
  %slot3227 = getelementptr i8, ptr %frame, i64 32
  %ld28 = load i32, ptr %slot3227, align 1
  %zx29 = zext i32 %ld28 to i64
  %brif30 = icmp ne i64 %zx29, 0
  br i1 %brif30, label %c2, label %fall8

fall5:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %fp = ptrtoint ptr %slot32 to i64
  call void @Symbol_try_from_val(i64 %fp, i64 %get1, i64 1048672)
  %slot322 = getelementptr i8, ptr %frame, i64 32
  %ld3 = load i32, ptr %slot322, align 1
  %zx = zext i32 %ld3 to i64
  %brif4 = icmp ne i64 %zx, 0
  br i1 %brif4, label %c2, label %fall6

fall6:                                            ; preds = %fall5
  %slot40 = getelementptr i8, ptr %frame, i64 40
  %ld5 = load i64, ptr %slot40, align 1
  %slot24 = getelementptr i8, ptr %frame, i64 24
  store i64 %ld5, ptr %slot24, align 1
  %slot246 = getelementptr i8, ptr %frame, i64 24
  %fp7 = ptrtoint ptr %slot246 to i64
  %lc = call i64 @f25(i64 %fp7)
  store i64 %lc, ptr %l3, align 4
  %get8 = load i64, ptr %l1, align 4
  %add = add i64 %get8, 8
  %get9 = load i64, ptr %l0, align 4
  %slot3210 = getelementptr i8, ptr %frame, i64 32
  %fp11 = ptrtoint ptr %slot3210 to i64
  call void @f28(i64 %fp11, i64 %add, i64 %get9)
  %slot3212 = getelementptr i8, ptr %frame, i64 32
  %ld13 = load i32, ptr %slot3212, align 1
  %zx14 = zext i32 %ld13 to i64
  %brif15 = icmp ne i64 %zx14, 0
  br i1 %brif15, label %c2, label %fall7

fall7:                                            ; preds = %fall6
  %slot4016 = getelementptr i8, ptr %frame, i64 40
  %ld17 = load i64, ptr %slot4016, align 1
  %slot16 = getelementptr i8, ptr %frame, i64 16
  store i64 %ld17, ptr %slot16, align 1
  %get18 = load i64, ptr %l3, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get18, ptr %slot8, align 1
  %get19 = load i64, ptr %l0, align 4
  %slot3220 = getelementptr i8, ptr %frame, i64 32
  %fp21 = ptrtoint ptr %slot3220 to i64
  %slot822 = getelementptr i8, ptr %frame, i64 8
  %fp23 = ptrtoint ptr %slot822 to i64
  call void @f31(i64 %fp21, i64 %fp23, i64 %get19)
  br label %c3

fall8:                                            ; preds = %c4
  %slot4031 = getelementptr i8, ptr %frame, i64 40
  %ld32 = load i64, ptr %slot4031, align 1
  %slot2433 = getelementptr i8, ptr %frame, i64 24
  store i64 %ld32, ptr %slot2433, align 1
  %slot2434 = getelementptr i8, ptr %frame, i64 24
  %fp35 = ptrtoint ptr %slot2434 to i64
  %lc36 = call i64 @f25(i64 %fp35)
  store i64 %lc36, ptr %l3, align 4
  %get37 = load i64, ptr %l0, align 4
  %get38 = load i64, ptr %l1, align 4
  %add39 = add i64 %get38, 8
  %slot3240 = getelementptr i8, ptr %frame, i64 32
  %fp41 = ptrtoint ptr %slot3240 to i64
  call void @f18(i64 %fp41, i64 %get37, i64 %add39)
  %slot3242 = getelementptr i8, ptr %frame, i64 32
  %ld43 = load i32, ptr %slot3242, align 1
  %zx44 = zext i32 %ld43 to i64
  %brif45 = icmp ne i64 %zx44, 0
  br i1 %brif45, label %c2, label %fall9

fall9:                                            ; preds = %fall8
  %slot4046 = getelementptr i8, ptr %frame, i64 40
  %ld47 = load i64, ptr %slot4046, align 1
  %slot1648 = getelementptr i8, ptr %frame, i64 16
  store i64 %ld47, ptr %slot1648, align 1
  %get49 = load i64, ptr %l3, align 4
  %slot850 = getelementptr i8, ptr %frame, i64 8
  store i64 %get49, ptr %slot850, align 1
  %get51 = load i64, ptr %l0, align 4
  %slot3252 = getelementptr i8, ptr %frame, i64 32
  %fp53 = ptrtoint ptr %slot3252 to i64
  %slot854 = getelementptr i8, ptr %frame, i64 8
  %fp55 = ptrtoint ptr %slot854 to i64
  call void @f31(i64 %fp53, i64 %fp55, i64 %get51)
  br label %c3

fall10:                                           ; preds = %c3
  br label %c2
}

define void @f8(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  call void @f9(i64 %get, i64 %get1, i64 %get2, i64 1)
  ret void
}

define void @f9(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i64" %3) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 %3, ptr %l3, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %lc = call i64 @Symbol_new(i64 %get1, i64 %get2)
  %get3 = load i64, ptr %l2, align 4
  %get4 = load i64, ptr %l0, align 4
  %lc5 = call i64 @f39(i64 %get3, i64 %get4)
  %get6 = load i64, ptr %l3, align 4
  %lc7 = call i64 @f38(i64 %get, i64 %lc, i64 %lc5, i64 %get6)
  ret void
}

define "wasm.type"="i64" i64 @Symbol_new(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) #12 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %fp = ptrtoint ptr %frame to i64
  call void @f34(i64 %fp, i64 %get, i64 %get1)
  %ld = load i64, ptr %frame, align 1
  %cmp = icmp ne i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld2 = load i64, ptr %slot8, align 1
  store i64 %ld2, ptr %l3, align 4
  %get3 = load i64, ptr %l3, align 4
  ret i64 %get3

fall2:                                            ; preds = %entry
  call void @soroban.trap()
  unreachable
}

define "wasm.type"="i64" i64 @f11(i64 "wasm.type"="i64" %0) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %frame = alloca [32 x i8], align 1
  %get = load i64, ptr %l0, align 4
  %cmp = icmp ugt i64 %get, 21474836479
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %fall4
  %get10 = load i64, ptr %l2, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %fp = ptrtoint ptr %slot8 to i64
  call void @f12(i64 %fp, i64 %get10)
  %slot811 = getelementptr i8, ptr %frame, i64 8
  %ld = load i64, ptr %slot811, align 1
  %slot16 = getelementptr i8, ptr %frame, i64 16
  %ld12 = load i64, ptr %slot16, align 1
  %slot31 = getelementptr i8, ptr %frame, i64 31
  %fp13 = ptrtoint ptr %slot31 to i64
  %lc = call i64 @f13(i64 %ld, i64 %ld12, i64 %fp13)
  store i64 %lc, ptr %l0, align 4
  %get14 = load i64, ptr %l0, align 4
  ret i64 %get14

c2:                                               ; preds = %fall5, %fall3, %entry
  call void @soroban.trap()
  unreachable

fall3:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %and = and i64 %get1, 255
  %cmp2 = icmp ne i64 %and, 4
  %zext3 = zext i1 %cmp2 to i64
  %brif4 = icmp ne i64 %zext3, 0
  br i1 %brif4, label %c2, label %fall4

fall4:                                            ; preds = %fall3
  %get5 = load i64, ptr %l0, align 4
  %lshr = lshr i64 %get5, 32
  store i64 %lshr, ptr %l2, align 4
  %and6 = and i64 %lshr, 255
  %cmp7 = icmp ne i64 %and6, 255
  %zext8 = zext i1 %cmp7 to i64
  %brif9 = icmp ne i64 %zext8, 0
  br i1 %brif9, label %c1, label %fall5

fall5:                                            ; preds = %fall4
  br label %c2
}

define void @f12(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %and = and i64 %get, 255
  %sel = trunc i64 %and to i32
  switch i32 %sel, label %c4 [
    i32 0, label %c2
    i32 1, label %c6
    i32 2, label %c5
    i32 3, label %c3
  ]

c1:                                               ; preds = %c2, %c4, %c6
  ret void

c2:                                               ; preds = %entry
  %get4 = load i64, ptr %l0, align 4
  %ea5 = add i64 %get4, 8
  call void @soroban.store64(i64 %ea5, i64 9742)
  %get6 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get6, i64 0)
  br label %c1

c3:                                               ; preds = %entry
  call void @f50(i64 1048577, i64 14, i64 1048604)
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %entry
  %get2 = load i64, ptr %l0, align 4
  %ea = add i64 %get2, 8
  call void @soroban.store64(i64 %ea, i64 10766)
  %get3 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get3, i64 0)
  br label %c1

c5:                                               ; preds = %entry
  %slot15 = getelementptr i8, ptr %frame, i64 15
  %fp = ptrtoint ptr %slot15 to i64
  %lc = call i64 @f37(i64 %fp, i64 4294967299)
  call void @soroban.trap()
  unreachable

c6:                                               ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get1, i64 1)
  br label %c1
}

define "wasm.type"="i64" i64 @f13(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get, ptr %slot8, align 1
  %get1 = load i64, ptr %l0, align 4
  store i64 %get1, ptr %frame, align 1
  %get2 = load i64, ptr %l2, align 4
  %fp = ptrtoint ptr %frame to i64
  %lc = call i64 @f19(i64 %get2, i64 %fp)
  store i64 %lc, ptr %l1, align 4
  %get3 = load i64, ptr %l1, align 4
  ret i64 %get3
}

define "wasm.type"="i64" i64 @f14(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %frame = alloca [48 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  store i64 %get, ptr %slot16, align 1
  %get1 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get1, ptr %slot8, align 1
  %slot24 = getelementptr i8, ptr %frame, i64 24
  %fp = ptrtoint ptr %slot24 to i64
  %slot47 = getelementptr i8, ptr %frame, i64 47
  %fp2 = ptrtoint ptr %slot47 to i64
  %slot83 = getelementptr i8, ptr %frame, i64 8
  %fp4 = ptrtoint ptr %slot83 to i64
  call void @f35(i64 %fp, i64 %fp2, i64 %fp4)
  %slot245 = getelementptr i8, ptr %frame, i64 24
  %ld = load i64, ptr %slot245, align 1
  %cmp = icmp eq i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %slot32 = getelementptr i8, ptr %frame, i64 32
  %ld6 = load i64, ptr %slot32, align 1
  store i64 %ld6, ptr %l1, align 4
  %slot247 = getelementptr i8, ptr %frame, i64 24
  %fp8 = ptrtoint ptr %slot247 to i64
  %slot479 = getelementptr i8, ptr %frame, i64 47
  %fp10 = ptrtoint ptr %slot479 to i64
  %slot1611 = getelementptr i8, ptr %frame, i64 16
  %fp12 = ptrtoint ptr %slot1611 to i64
  call void @f35(i64 %fp8, i64 %fp10, i64 %fp12)
  %slot2413 = getelementptr i8, ptr %frame, i64 24
  %ld14 = load i64, ptr %slot2413, align 1
  %cmp15 = icmp eq i64 %ld14, 1
  %zext16 = zext i1 %cmp15 to i64
  %brif17 = icmp ne i64 %zext16, 0
  br i1 %brif17, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get18 = load i64, ptr %l1, align 4
  %slot3219 = getelementptr i8, ptr %frame, i64 32
  %ld20 = load i64, ptr %slot3219, align 1
  %lc = call i64 @f15(i64 %get18, i64 %ld20)
  %slot4721 = getelementptr i8, ptr %frame, i64 47
  %fp22 = ptrtoint ptr %slot4721 to i64
  %lc23 = call i64 @f16(i64 %lc, i64 %fp22)
  store i64 %lc23, ptr %l1, align 4
  %get24 = load i64, ptr %l1, align 4
  ret i64 %get24
}

define "wasm.type"="i32" i64 @f15(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [32 x i8], align 1
  %slot31 = getelementptr i8, ptr %frame, i64 31
  %fp = ptrtoint ptr %slot31 to i64
  call void @f24(i64 %fp)
  %get = load i64, ptr %l1, align 4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  store i64 %get, ptr %slot16, align 1
  %get1 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %get1, ptr %slot8, align 1
  store i64 0, ptr %frame, align 1
  %slot312 = getelementptr i8, ptr %frame, i64 31
  %fp3 = ptrtoint ptr %slot312 to i64
  %fp4 = ptrtoint ptr %frame to i64
  %lc = call i64 @f6(i64 %fp3, i64 %fp4)
  store i64 %lc, ptr %l3, align 4
  %get5 = load i64, ptr %l3, align 4
  ret i64 %get5
}

define "wasm.type"="i64" i64 @f16(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l0, align 4
  %slot15 = getelementptr i8, ptr %frame, i64 15
  %t = trunc i64 %get to i8
  store i8 %t, ptr %slot15, align 1
  %get1 = load i64, ptr %l1, align 4
  %slot152 = getelementptr i8, ptr %frame, i64 15
  %fp = ptrtoint ptr %slot152 to i64
  %lc = call i64 @f39(i64 %fp, i64 %get1)
  store i64 %lc, ptr %l3, align 4
  %get3 = load i64, ptr %l3, align 4
  ret i64 %get3
}

define void @f17() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %frame = alloca [16 x i8], align 1
  %slot15 = getelementptr i8, ptr %frame, i64 15
  %fp = ptrtoint ptr %slot15 to i64
  call void @f24(i64 %fp)
  %slot151 = getelementptr i8, ptr %frame, i64 15
  %fp2 = ptrtoint ptr %slot151 to i64
  call void @f8(i64 %fp2, i64 1048624, i64 1048576)
  ret void
}

define void @f18(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l1, align 4
  %fp = ptrtoint ptr %frame to i64
  call void @f28(i64 %fp, i64 %get, i64 %get1)
  store i64 1, ptr %l4, align 4
  %ld = load i32, ptr %frame, align 1
  %zx = zext i32 %ld to i64
  %brif = icmp ne i64 %zx, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall3, %fall2, %entry
  %get16 = load i64, ptr %l0, align 4
  %get17 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get16, i64 %get17)
  ret void

fall2:                                            ; preds = %entry
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld2 = load i64, ptr %slot8, align 1
  store i64 %ld2, ptr %l5, align 4
  %get3 = load i64, ptr %l2, align 4
  %add = add i64 %get3, 8
  %get4 = load i64, ptr %l1, align 4
  %fp5 = ptrtoint ptr %frame to i64
  call void @f28(i64 %fp5, i64 %add, i64 %get4)
  %ld6 = load i32, ptr %frame, align 1
  %zx7 = zext i32 %ld6 to i64
  %brif8 = icmp ne i64 %zx7, 0
  br i1 %brif8, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %slot89 = getelementptr i8, ptr %frame, i64 8
  %ld10 = load i64, ptr %slot89, align 1
  %slot811 = getelementptr i8, ptr %frame, i64 8
  store i64 %ld10, ptr %slot811, align 1
  %get12 = load i64, ptr %l5, align 4
  store i64 %get12, ptr %frame, align 1
  %get13 = load i64, ptr %l0, align 4
  %get14 = load i64, ptr %l1, align 4
  %fp15 = ptrtoint ptr %frame to i64
  %lc = call i64 @f36(i64 %get14, i64 1048636, i64 2, i64 %fp15, i64 2)
  %ea = add i64 %get13, 8
  call void @soroban.store64(i64 %ea, i64 %lc)
  store i64 0, ptr %l4, align 4
  br label %c1
}

define "wasm.type"="i64" i64 @f19(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [16 x i8], align 1
  store i64 4294967299, ptr %l3, align 4
  %get = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load32u(i64 %get)
  %brif = icmp ne i64 %ld, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %fall3
  %lc = call i64 @f49()
  call void @soroban.trap()
  unreachable

c2:                                               ; preds = %fall4, %entry
  %get6 = load i64, ptr %l3, align 4
  ret i64 %get6

fall3:                                            ; preds = %entry
  %get1 = load i64, ptr %l1, align 4
  %add = add i64 %get1, 8
  %get2 = load i64, ptr %l0, align 4
  %fp = ptrtoint ptr %frame to i64
  call void @f28(i64 %fp, i64 %add, i64 %get2)
  %ld3 = load i64, ptr %frame, align 1
  %cmp = icmp eq i64 %ld3, 1
  %zext = zext i1 %cmp to i64
  %brif4 = icmp ne i64 %zext, 0
  br i1 %brif4, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld5 = load i64, ptr %slot8, align 1
  store i64 %ld5, ptr %l3, align 4
  br label %c2
}

define void @panic_fmt(i64 "wasm.type"="i32" %0) #13 {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  call void @soroban.trap()
  unreachable
}

define void @f24(i64 "wasm.type"="i32" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  ret void
}

define "wasm.type"="i64" i64 @f25(i64 "wasm.type"="i32" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  ret i64 %ld
}

define void @f26(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %ld, ptr %slot8, align 1
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %slot83 = getelementptr i8, ptr %frame, i64 8
  %fp = ptrtoint ptr %slot83 to i64
  call void @f32(i64 %get1, i64 %get2, i64 %fp)
  ret void
}

define "wasm.type"="i32" i64 @f27(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  %lc = call i64 @f44(i64 %get, i64 %get1, i64 %get2)
  %lc3 = call i64 @f48(i64 %lc)
  ret i64 %lc3
}

define void @f28(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get, i64 0)
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load64(i64 %get2)
  %ea = add i64 %get1, 8
  call void @soroban.store64(i64 %ea, i64 %ld)
  ret void
}

define void @Symbol_try_from_val(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) #14 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %get1 = load i64, ptr %l2, align 4
  %fp = ptrtoint ptr %frame to i64
  call void @f26(i64 %fp, i64 %get, i64 %get1)
  store i64 1, ptr %l4, align 4
  %ld = load i32, ptr %frame, align 1
  %zx = zext i32 %ld to i64
  %brif = icmp ne i64 %zx, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get4, i64 %get5)
  ret void

fall2:                                            ; preds = %entry
  %get2 = load i64, ptr %l0, align 4
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld3 = load i64, ptr %slot8, align 1
  %ea = add i64 %get2, 8
  call void @soroban.store64(i64 %ea, i64 %ld3)
  store i64 0, ptr %l4, align 4
  br label %c1
}

define void @f30(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l2, align 4
  %ea = add i64 %get, 8
  %ld = call i64 @soroban.load64(i64 %ea)
  %slot8 = getelementptr i8, ptr %frame, i64 8
  store i64 %ld, ptr %slot8, align 1
  %get1 = load i64, ptr %l2, align 4
  %ld2 = call i64 @soroban.load64(i64 %get1)
  store i64 %ld2, ptr %frame, align 1
  %get3 = load i64, ptr %l1, align 4
  %fp = ptrtoint ptr %frame to i64
  %lc = call i64 @f40(i64 %get3, i64 %fp, i64 2)
  store i64 %lc, ptr %l4, align 4
  %get4 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get4, i64 0)
  %get5 = load i64, ptr %l0, align 4
  %get6 = load i64, ptr %l4, align 4
  %ea7 = add i64 %get5, 8
  call void @soroban.store64(i64 %ea7, i64 %get6)
  ret void
}

define void @f31(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  call void @f30(i64 %get, i64 %get1, i64 %get2)
  ret void
}

define void @f32(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  %l5 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 0, ptr %l5, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load32u(i64 %get)
  store i64 %ld, ptr %l4, align 4
  %get1 = load i64, ptr %l2, align 4
  %ea = add i64 %get1, 4
  %ld2 = call i64 @soroban.load32u(i64 %ea)
  store i64 %ld2, ptr %l2, align 4
  %fp = ptrtoint ptr %frame to i64
  call void @f46(i64 %fp, i64 %ld, i64 %ld2)
  %ld3 = load i32, ptr %frame, align 1
  %zx = zext i32 %ld3 to i64
  %cmp = icmp ne i64 %zx, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall3
  %get8 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get8, i64 0)
  %get9 = load i64, ptr %l0, align 4
  %get10 = load i64, ptr %l5, align 4
  %ea11 = add i64 %get9, 8
  call void @soroban.store64(i64 %ea11, i64 %get10)
  ret void

c2:                                               ; preds = %entry
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %ld7 = load i64, ptr %slot8, align 1
  store i64 %ld7, ptr %l5, align 4
  br label %c1

fall3:                                            ; preds = %entry
  %get4 = load i64, ptr %l1, align 4
  %get5 = load i64, ptr %l4, align 4
  %get6 = load i64, ptr %l2, align 4
  %lc = call i64 @f42(i64 %get4, i64 %get5, i64 %get6)
  store i64 %lc, ptr %l5, align 4
  br label %c1
}

define void @panic_fmt_33() #13 {
entry:
  ret void
}

define void @f34(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get, i64 0)
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load64(i64 %get2)
  %ea = add i64 %get1, 8
  call void @soroban.store64(i64 %ea, i64 %ld)
  ret void
}

define void @f35(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  store i64 1, ptr %l3, align 4
  %get = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  store i64 %ld, ptr %l4, align 4
  %and = and i64 %ld, 255
  %cmp = icmp ne i64 %and, 77
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l3, align 4
  call void @soroban.store64(i64 %get3, i64 %get4)
  ret void

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l4, align 4
  %ea = add i64 %get1, 8
  call void @soroban.store64(i64 %ea, i64 %get2)
  store i64 0, ptr %l3, align 4
  br label %c1
}

define "wasm.type"="i64" i64 @f36(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) {
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
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  %get3 = load i64, ptr %l3, align 4
  %get4 = load i64, ptr %l4, align 4
  %lc = call i64 @f41(i64 %get, i64 %get1, i64 %get2, i64 %get3, i64 %get4)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f37(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %lc = call i64 @f43(i64 %get, i64 %get1)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f38(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2, i64 "wasm.type"="i64" %3) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 %3, ptr %l3, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  %get3 = load i64, ptr %l3, align 4
  %lc = call i64 @f45(i64 %get, i64 %get1, i64 %get2, i64 %get3)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f39(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %ld = call i64 @soroban.load8u(i64 %get)
  ret i64 %ld
}

define "wasm.type"="i64" i64 @f40(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %shl = shl i64 %get, 32
  %or = or i64 %shl, 4
  %get1 = load i64, ptr %l2, align 4
  %shl2 = shl i64 %get1, 32
  %or3 = or i64 %shl2, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %or3)
  %vec_new_from_linear_memory = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %to_val4)
  %payload = call i64 @soroban.val.payload(%Val %vec_new_from_linear_memory)
  ret i64 %payload
}

define "wasm.type"="i64" i64 @f41(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) {
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
  %get2 = load i64, ptr %l1, align 4
  %shl = shl i64 %get2, 32
  %or = or i64 %shl, 4
  %get3 = load i64, ptr %l3, align 4
  %shl4 = shl i64 %get3, 32
  %or5 = or i64 %shl4, 4
  %get6 = load i64, ptr %l2, align 4
  %shl7 = shl i64 %get6, 32
  %or8 = or i64 %shl7, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val9 = call %Val @soroban.val.from_payload(i64 %or5)
  %to_val10 = call %Val @soroban.val.from_payload(i64 %or8)
  %map_new_from_linear_memory = call %Val @map.map_new_from_linear_memory(%Val %to_val, %Val %to_val9, %Val %to_val10)
  %payload = call i64 @soroban.val.payload(%Val %map_new_from_linear_memory)
  ret i64 %payload

fall2:                                            ; preds = %entry
  call void @soroban.trap()
  unreachable
}

define "wasm.type"="i64" i64 @f42(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %shl = shl i64 %get, 32
  %or = or i64 %shl, 4
  %get1 = load i64, ptr %l2, align 4
  %shl2 = shl i64 %get1, 32
  %or3 = or i64 %shl2, 4
  %to_val = call %Val @soroban.val.from_payload(i64 %or)
  %to_val4 = call %Val @soroban.val.from_payload(i64 %or3)
  %symbol_new_from_linear_memory = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val4)
  %payload = call i64 @soroban.val.payload(%Val %symbol_new_from_linear_memory)
  ret i64 %payload
}

define "wasm.type"="i64" i64 @f43(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l1, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %fail_with_error = call %Val @context.fail_with_error(%Val %to_val)
  %payload = call i64 @soroban.val.payload(%Val %fail_with_error)
  ret i64 %payload
}

define "wasm.type"="i64" i64 @f44(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %get1 = load i64, ptr %l2, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %has_contract_data = call %Val @ledger.has_contract_data(%Val %to_val, i64 %get1)
  %payload = call i64 @soroban.val.payload(%Val %has_contract_data)
  ret i64 %payload
}

define "wasm.type"="i64" i64 @f45(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2, i64 "wasm.type"="i64" %3) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 %3, ptr %l3, align 4
  %get = load i64, ptr %l1, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l3, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %to_val3 = call %Val @soroban.val.from_payload(i64 %get1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %to_val, %Val %to_val3, i64 %get2)
  %payload = call i64 @soroban.val.payload(%Val %put_contract_data)
  ret i64 %payload
}

define void @f46(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  %l4 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  store i64 0, ptr %l4, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l2, align 4
  %cmp = icmp ugt i64 %get, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall9, %fall7
  ret void

c2:                                               ; preds = %entry
  %get25 = load i64, ptr %l0, align 4
  %get26 = load i64, ptr %l2, align 4
  %ea27 = add i64 %get25, 8
  call void @soroban.store32(i64 %ea27, i64 %get26)
  %get28 = load i64, ptr %l0, align 4
  %ea29 = add i64 %get28, 4
  call void @soroban.store8(i64 %ea29, i64 0)
  %get30 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get30, i64 1)
  br label %c1

fall3:                                            ; preds = %entry
  store i64 0, ptr %l4, align 4
  br label %h4

h4:                                               ; preds = %c8, %fall3
  %get1 = load i64, ptr %l2, align 4
  %brif2 = icmp ne i64 %get1, 0
  br i1 %brif2, label %c6, label %fall7

c6:                                               ; preds = %h4
  %get6 = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load8u(i64 %get6)
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %fp = ptrtoint ptr %slot8 to i64
  call void @f47(i64 %fp, i64 %ld)
  %slot87 = getelementptr i8, ptr %frame, i64 8
  %ld8 = load i8, ptr %slot87, align 1
  %zx = zext i8 %ld8 to i64
  %cmp9 = icmp eq i64 %zx, 255
  %zext10 = zext i1 %cmp9 to i64
  %brif11 = icmp ne i64 %zext10, 0
  br i1 %brif11, label %c8, label %fall9

fall7:                                            ; preds = %h4
  %get3 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get3, i64 0)
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l4, align 4
  %shl = shl i64 %get5, 8
  %or = or i64 %shl, 14
  %ea = add i64 %get4, 8
  call void @soroban.store64(i64 %ea, i64 %or)
  br label %c1

c8:                                               ; preds = %c6
  %get17 = load i64, ptr %l2, align 4
  %add = add i64 %get17, -1
  store i64 %add, ptr %l2, align 4
  %get18 = load i64, ptr %l1, align 4
  %add19 = add i64 %get18, 1
  store i64 %add19, ptr %l1, align 4
  %get20 = load i64, ptr %l4, align 4
  %shl21 = shl i64 %get20, 6
  %slot9 = getelementptr i8, ptr %frame, i64 9
  %ld22 = load i8, ptr %slot9, align 1
  %zx23 = zext i8 %ld22 to i64
  %or24 = or i64 %shl21, %zx23
  store i64 %or24, ptr %l4, align 4
  br label %h4

fall9:                                            ; preds = %c6
  %get12 = load i64, ptr %l0, align 4
  %slot813 = getelementptr i8, ptr %frame, i64 8
  %ld14 = load i64, ptr %slot813, align 1
  %ea15 = add i64 %get12, 4
  call void @soroban.store64(i64 %ea15, i64 %ld14)
  %get16 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get16, i64 1)
  br label %c1
}

define void @f47(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 1, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %and = and i64 %get, 255
  %cmp = icmp eq i64 %and, 95
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %c3, %c4, %c7, %entry
  %get27 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get27, i64 255)
  %get28 = load i64, ptr %l0, align 4
  %get29 = load i64, ptr %l2, align 4
  %ea30 = add i64 %get28, 1
  call void @soroban.store8(i64 %ea30, i64 %get29)
  ret void

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l1, align 4
  %add = add i64 %get1, -48
  %and2 = and i64 %add, 255
  %cmp3 = icmp ult i64 %and2, 10
  %zext4 = zext i1 %cmp3 to i64
  %brif5 = icmp ne i64 %zext4, 0
  br i1 %brif5, label %c4, label %fall5

c3:                                               ; preds = %fall5
  %get25 = load i64, ptr %l1, align 4
  %add26 = add i64 %get25, -53
  store i64 %add26, ptr %l2, align 4
  br label %c1

c4:                                               ; preds = %fall2
  %get23 = load i64, ptr %l1, align 4
  %add24 = add i64 %get23, -46
  store i64 %add24, ptr %l2, align 4
  br label %c1

fall5:                                            ; preds = %fall2
  %get6 = load i64, ptr %l1, align 4
  %add7 = add i64 %get6, -65
  %and8 = and i64 %add7, 255
  %cmp9 = icmp ult i64 %and8, 26
  %zext10 = zext i1 %cmp9 to i64
  %brif11 = icmp ne i64 %zext10, 0
  br i1 %brif11, label %c3, label %fall6

fall6:                                            ; preds = %fall5
  %get12 = load i64, ptr %l1, align 4
  %add13 = add i64 %get12, -97
  %and14 = and i64 %add13, 255
  %cmp15 = icmp ult i64 %and14, 26
  %zext16 = zext i1 %cmp15 to i64
  %brif17 = icmp ne i64 %zext16, 0
  br i1 %brif17, label %c7, label %fall8

c7:                                               ; preds = %fall6
  %get21 = load i64, ptr %l1, align 4
  %add22 = add i64 %get21, -59
  store i64 %add22, ptr %l2, align 4
  br label %c1

fall8:                                            ; preds = %fall6
  %get18 = load i64, ptr %l0, align 4
  %get19 = load i64, ptr %l1, align 4
  %ea = add i64 %get18, 1
  call void @soroban.store8(i64 %ea, i64 %get19)
  %get20 = load i64, ptr %l0, align 4
  call void @soroban.store8(i64 %get20, i64 1)
  ret void
}

define "wasm.type"="i32" i64 @f48(i64 "wasm.type"="i64" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp eq i64 %get, 1
  %zext = zext i1 %cmp to i64
  ret i64 %zext
}

define "wasm.type"="i64" i64 @f49() {
entry:
  ret i64 34359740419
}

define void @f50(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %shl = shl i64 %get1, 1
  %or = or i64 %shl, 1
  %get2 = load i64, ptr %l2, align 4
  call void @f51(i64 %get, i64 %or, i64 %get2)
  call void @soroban.trap()
  unreachable
}

define void @f51(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %frame = alloca [32 x i8], align 1
  %get = load i64, ptr %l1, align 4
  %slot16 = getelementptr i8, ptr %frame, i64 16
  %t = trunc i64 %get to i32
  store i32 %t, ptr %slot16, align 1
  %get1 = load i64, ptr %l0, align 4
  %slot12 = getelementptr i8, ptr %frame, i64 12
  %t2 = trunc i64 %get1 to i32
  store i32 %t2, ptr %slot12, align 1
  %slot28 = getelementptr i8, ptr %frame, i64 28
  store i16 1, ptr %slot28, align 1
  %get3 = load i64, ptr %l2, align 4
  %slot24 = getelementptr i8, ptr %frame, i64 24
  %t4 = trunc i64 %get3 to i32
  store i32 %t4, ptr %slot24, align 1
  %slot125 = getelementptr i8, ptr %frame, i64 12
  %fp = ptrtoint ptr %slot125 to i64
  %slot20 = getelementptr i8, ptr %frame, i64 20
  %t6 = trunc i64 %fp to i32
  store i32 %t6, ptr %slot20, align 1
  %slot207 = getelementptr i8, ptr %frame, i64 20
  %fp8 = ptrtoint ptr %slot207 to i64
  call void @panic_fmt(i64 %fp8)
  call void @soroban.trap()
  unreachable
}

attributes #0 = { nounwind willreturn memory(none) }
attributes #1 = { memory(inaccessiblemem: readwrite) }
attributes #2 = { noreturn }
attributes #3 = { "soroban.import"="b.j" "soroban.sig"="(U32Val, U32Val) -> SymbolObject" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #5 = { memory(inaccessiblemem: readwrite) "soroban.import"="l.0" "soroban.sig"="(Val, StorageType) -> Bool" }
attributes #6 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #7 = { "soroban.import"="m.9" "soroban.sig"="(U32Val, U32Val, U32Val) -> MapObject" }
attributes #8 = { "soroban.import"="v.g" "soroban.sig"="(U32Val, U32Val) -> VecObject" }
attributes #9 = { "spec.sig"="fn pick(f: Flag) -> Result<Symbol, Error>" }
attributes #10 = { "spec.sig"="fn read(a: Address, b: Address) -> bool" }
attributes #11 = { "spec.sig"="fn set_flag()" }
attributes #12 = { "sdk.name"="<soroban_sdk::symbol::Symbol>::new" }
attributes #13 = { "sdk.name"="core::panicking::panic_fmt" }
attributes #14 = { "sdk.name"="<soroban_sdk::symbol::Symbol as soroban_env_common::convert::TryFromVal<soroban_sdk::env::Env, &str>>::try_from_val" }

!soroban.spec = !{!0, !1, !2, !3, !4, !5, !6}
!soroban.rodata = !{!7}

!0 = !{!"enum Flag { A = 0, B = 1, C = 2, D = 3, E = 4 }"}
!1 = !{!"error Error { AnError = 1 }"}
!2 = !{!"union DataKey { Pair(PairKey), Single(Address) }"}
!3 = !{!"struct PairKey { a: Address, b: Address }"}
!4 = !{!"fn pick(f: Flag) -> Result<Symbol, Error>"}
!5 = !{!"fn read(a: Address, b: Address) -> bool"}
!6 = !{!"fn set_flag()"}
!7 = !{!"1048576 016578706c696369742070616e69637372632f6c69622e72730000000f0010000a0000003c0000000d000000000000000e2b0000000000006162000038001000010000003900100001000000506169724c0010000400000053696e676c6500005800100006000000"}
