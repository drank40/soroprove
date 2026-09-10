; ModuleID = 'ponytail'
source_filename = "ponytail"

%Val = type { i64 }

@g0 = global i64 1048576
@g1 = constant i64 1048652

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

define "spec.type"="bool" "wasm.type"="i64" %Val @read(%Val "spec.name"="a" "spec.type"="Address" "wasm.type"="i64" %0, %Val "spec.name"="b" "spec.type"="Address" "wasm.type"="i64" %1) #9 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  %arg_payload1 = call i64 @soroban.val.payload(%Val %1)
  store i64 %arg_payload1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %lc = call i64 @f7(i64 %get, i64 %get2)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define "spec.type"="Result<Symbol, Error>" "wasm.type"="i64" %Val @pick(%Val "spec.name"="f" "spec.type"="Flag" "wasm.type"="i64" %0) #10 {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %frame = alloca [16 x i8], align 1
  %get = load i64, ptr %l0, align 4
  %and = and i64 %get, 255
  %cmp = icmp ne i64 %and, 4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c6, label %fall7

c1:                                               ; preds = %c2, %c3, %fall8
  %get6 = load i64, ptr %l0, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get6)
  ret %Val %to_val

c2:                                               ; preds = %fall8, %fall8
  store i64 9742, ptr %l0, align 4
  br label %c1

c3:                                               ; preds = %fall8
  store i64 10766, ptr %l0, align 4
  br label %c1

c4:                                               ; preds = %fall8
  call void @f24(i64 1048576, i64 14, i64 1048604)
  call void @soroban.trap()
  unreachable

c5:                                               ; preds = %fall8
  %slot15 = getelementptr i8, ptr %frame, i64 15
  %fp = ptrtoint ptr %slot15 to i64
  %lc = call i64 @f15(i64 %fp, i64 4294967299)
  call void @soroban.trap()
  unreachable

c6:                                               ; preds = %fall7, %entry
  call void @soroban.trap()
  unreachable

fall7:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %lshr = lshr i64 %get1, 32
  store i64 %lshr, ptr %l2, align 4
  %cmp2 = icmp ugt i64 %lshr, 4
  %zext3 = zext i1 %cmp2 to i64
  %brif4 = icmp ne i64 %zext3, 0
  br i1 %brif4, label %c6, label %fall8

fall8:                                            ; preds = %fall7
  store i64 4294967299, ptr %l0, align 4
  %get5 = load i64, ptr %l2, align 4
  %sel = trunc i64 %get5 to i32
  switch i32 %sel, label %c2 [
    i32 0, label %c2
    i32 1, label %c1
    i32 2, label %c5
    i32 3, label %c4
    i32 4, label %c3
  ]
}

define "wasm.type"="i64" %Val @set_flag() #11 {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %frame = alloca [16 x i8], align 1
  %slot15 = getelementptr i8, ptr %frame, i64 15
  %fp = ptrtoint ptr %slot15 to i64
  %lc = call i64 @f16(i64 %fp, i64 11022, i64 1, i64 1)
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define "wasm.type"="i64" i64 @f7(i64 "wasm.type"="i64" %0, i64 "wasm.type"="i64" %1) {
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
  %frame = alloca [32 x i8], align 1
  %get = load i64, ptr %l0, align 4
  %and = and i64 %get, 255
  %cmp = icmp ne i64 %and, 77
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall3, %fall2, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l1, align 4
  %and2 = and i64 %get1, 255
  %cmp3 = icmp ne i64 %and2, 77
  %zext4 = zext i1 %cmp3 to i64
  %brif5 = icmp ne i64 %zext4, 0
  br i1 %brif5, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %slot8 = getelementptr i8, ptr %frame, i64 8
  %fp = ptrtoint ptr %slot8 to i64
  %slot31 = getelementptr i8, ptr %frame, i64 31
  %fp6 = ptrtoint ptr %slot31 to i64
  call void @f14(i64 %fp, i64 %fp6, i64 1048644)
  %slot87 = getelementptr i8, ptr %frame, i64 8
  %ld = load i64, ptr %slot87, align 1
  %cmp8 = icmp eq i64 %ld, 1
  %zext9 = zext i1 %cmp8 to i64
  %brif10 = icmp ne i64 %zext9, 0
  br i1 %brif10, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %slot16 = getelementptr i8, ptr %frame, i64 16
  %ld11 = load i64, ptr %slot16, align 1
  store i64 %ld11, ptr %l3, align 4
  %get12 = load i64, ptr %l1, align 4
  %slot1613 = getelementptr i8, ptr %frame, i64 16
  store i64 %get12, ptr %slot1613, align 1
  %get14 = load i64, ptr %l0, align 4
  %slot815 = getelementptr i8, ptr %frame, i64 8
  store i64 %get14, ptr %slot815, align 1
  %slot3116 = getelementptr i8, ptr %frame, i64 31
  %fp17 = ptrtoint ptr %slot3116 to i64
  %slot818 = getelementptr i8, ptr %frame, i64 8
  %fp19 = ptrtoint ptr %slot818 to i64
  %lc = call i64 @f13(i64 %fp17, i64 1048624, i64 2, i64 %fp19, i64 2)
  %slot1620 = getelementptr i8, ptr %frame, i64 16
  store i64 %lc, ptr %slot1620, align 1
  %get21 = load i64, ptr %l3, align 4
  %slot822 = getelementptr i8, ptr %frame, i64 8
  store i64 %get21, ptr %slot822, align 1
  %slot3123 = getelementptr i8, ptr %frame, i64 31
  %fp24 = ptrtoint ptr %slot3123 to i64
  %slot825 = getelementptr i8, ptr %frame, i64 8
  %fp26 = ptrtoint ptr %slot825 to i64
  %lc27 = call i64 @f12(i64 %fp24, i64 %fp26, i64 2)
  %slot3128 = getelementptr i8, ptr %frame, i64 31
  %fp29 = ptrtoint ptr %slot3128 to i64
  %lc30 = call i64 @f11(i64 %fp29, i64 %lc27, i64 1)
  store i64 %lc30, ptr %l4, align 4
  %get31 = load i64, ptr %l4, align 4
  ret i64 %get31
}

define void @f10(i64 "wasm.type"="i32" %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  call void @soroban.trap()
  unreachable
}

define "wasm.type"="i32" i64 @f11(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2) {
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
  %lc = call i64 @f21(i64 %get, i64 %get1, i64 %get2)
  %cmp = icmp eq i64 %lc, 1
  %zext = zext i1 %cmp to i64
  ret i64 %zext
}

define "wasm.type"="i64" i64 @f12(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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
  %lc = call i64 @f17(i64 %get, i64 %get1, i64 %get2)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f13(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) {
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
  %lc = call i64 @f18(i64 %get, i64 %get1, i64 %get2, i64 %get3, i64 %get4)
  ret i64 %lc
}

define void @f14(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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
  call void @f23(i64 %fp, i64 %ld, i64 %ld2)
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
  %lc = call i64 @f19(i64 %get4, i64 %get5, i64 %get6)
  store i64 %lc, ptr %l5, align 4
  br label %c1
}

define "wasm.type"="i64" i64 @f15(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %lc = call i64 @f20(i64 %get, i64 %get1)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f16(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2, i64 "wasm.type"="i64" %3) {
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
  %lc = call i64 @f22(i64 %get, i64 %get1, i64 %get2, i64 %get3)
  ret i64 %lc
}

define "wasm.type"="i64" i64 @f17(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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

define "wasm.type"="i64" i64 @f18(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2, i64 "wasm.type"="i32" %3, i64 "wasm.type"="i32" %4) {
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

define "wasm.type"="i64" i64 @f19(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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

define "wasm.type"="i64" i64 @f20(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1) {
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

define "wasm.type"="i64" i64 @f21(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2) {
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

define "wasm.type"="i64" i64 @f22(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i64" %1, i64 "wasm.type"="i64" %2, i64 "wasm.type"="i64" %3) {
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

define void @f23(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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
  %get = load i64, ptr %l2, align 4
  %cmp = icmp ugt i64 %get, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c4, label %fall5

c1:                                               ; preds = %c2, %fall7
  %get49 = load i64, ptr %l0, align 4
  %get50 = load i64, ptr %l3, align 4
  %ea51 = add i64 %get49, 8
  call void @soroban.store64(i64 %ea51, i64 %get50)
  %get52 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get52, i64 0)
  ret void

c2:                                               ; preds = %c10
  %get46 = load i64, ptr %l3, align 4
  %shl47 = shl i64 %get46, 8
  %or48 = or i64 %shl47, 14
  store i64 %or48, ptr %l3, align 4
  br label %c1

c3:                                               ; preds = %c4, %c16
  %get45 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get45, i64 1)
  ret void

c4:                                               ; preds = %entry
  %get40 = load i64, ptr %l0, align 4
  %get41 = load i64, ptr %l2, align 4
  %ea42 = add i64 %get40, 8
  call void @soroban.store32(i64 %ea42, i64 %get41)
  %get43 = load i64, ptr %l0, align 4
  %ea44 = add i64 %get43, 4
  call void @soroban.store8(i64 %ea44, i64 0)
  br label %c3

fall5:                                            ; preds = %entry
  %get1 = load i64, ptr %l2, align 4
  %brif2 = icmp ne i64 %get1, 0
  br i1 %brif2, label %c6, label %fall7

c6:                                               ; preds = %fall5
  store i64 0, ptr %l3, align 4
  br label %h8

fall7:                                            ; preds = %fall5
  store i64 14, ptr %l3, align 4
  br label %c1

h8:                                               ; preds = %fall18, %c6
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load8u(i64 %get3)
  store i64 %ld, ptr %l5, align 4
  %cmp4 = icmp eq i64 %ld, 95
  %zext5 = zext i1 %cmp4 to i64
  %brif6 = icmp ne i64 %zext5, 0
  br i1 %brif6, label %c10, label %fall11

c10:                                              ; preds = %c12, %c13, %fall17, %h8
  %get29 = load i64, ptr %l3, align 4
  %shl30 = shl i64 %get29, 6
  %get31 = load i64, ptr %l4, align 4
  %and32 = and i64 %get31, 255
  %or33 = or i64 %shl30, %and32
  store i64 %or33, ptr %l3, align 4
  %get34 = load i64, ptr %l1, align 4
  %add35 = add i64 %get34, 1
  store i64 %add35, ptr %l1, align 4
  %get36 = load i64, ptr %l2, align 4
  %add37 = add i64 %get36, -1
  store i64 %add37, ptr %l2, align 4
  %eqz = icmp eq i64 %add37, 0
  %zext38 = zext i1 %eqz to i64
  %brif39 = icmp ne i64 %zext38, 0
  br i1 %brif39, label %c2, label %fall18

fall11:                                           ; preds = %h8
  %get7 = load i64, ptr %l5, align 4
  %add = add i64 %get7, -48
  %and = and i64 %add, 255
  %cmp8 = icmp ult i64 %and, 10
  %zext9 = zext i1 %cmp8 to i64
  %brif10 = icmp ne i64 %zext9, 0
  br i1 %brif10, label %c13, label %fall14

c12:                                              ; preds = %fall14
  %get27 = load i64, ptr %l5, align 4
  %add28 = add i64 %get27, -53
  store i64 %add28, ptr %l4, align 4
  br label %c10

c13:                                              ; preds = %fall11
  %get25 = load i64, ptr %l5, align 4
  %add26 = add i64 %get25, -46
  store i64 %add26, ptr %l4, align 4
  br label %c10

fall14:                                           ; preds = %fall11
  %get11 = load i64, ptr %l5, align 4
  %add12 = add i64 %get11, -65
  %and13 = and i64 %add12, 255
  %cmp14 = icmp ult i64 %and13, 26
  %zext15 = zext i1 %cmp14 to i64
  %brif16 = icmp ne i64 %zext15, 0
  br i1 %brif16, label %c12, label %fall15

fall15:                                           ; preds = %fall14
  %get17 = load i64, ptr %l5, align 4
  %add18 = add i64 %get17, -97
  %and19 = and i64 %add18, 255
  %bottom = call i64 @ponytail.unknown.i64()
  %brif20 = icmp ne i64 %bottom, 0
  br i1 %brif20, label %c16, label %fall17

c16:                                              ; preds = %fall15
  %get23 = load i64, ptr %l0, align 4
  %get24 = load i64, ptr %l5, align 4
  %shl = shl i64 %get24, 8
  %or = or i64 %shl, 1
  %ea = add i64 %get23, 4
  call void @soroban.store64(i64 %ea, i64 %or)
  br label %c3

fall17:                                           ; preds = %fall15
  %get21 = load i64, ptr %l5, align 4
  %add22 = add i64 %get21, -59
  store i64 %add22, ptr %l4, align 4
  br label %c10

fall18:                                           ; preds = %c10
  br label %h8
}

define void @f24(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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
  call void @f25(i64 %get, i64 %or, i64 %get2)
  call void @soroban.trap()
  unreachable
}

define void @f25(i64 "wasm.type"="i32" %0, i64 "wasm.type"="i32" %1, i64 "wasm.type"="i32" %2) {
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
  call void @f10(i64 %fp8)
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
attributes #9 = { "spec.sig"="fn read(a: Address, b: Address) -> bool" }
attributes #10 = { "spec.sig"="fn pick(f: Flag) -> Result<Symbol, Error>" }
attributes #11 = { "spec.sig"="fn set_flag()" }

!soroban.spec = !{!0, !1, !2, !3, !4, !5, !6}
!soroban.rodata = !{!7}

!0 = !{!"enum Flag { A = 0, B = 1, C = 2, D = 3, E = 4 }"}
!1 = !{!"error Error { AnError = 1 }"}
!2 = !{!"union DataKey { Pair(PairKey), Single(Address) }"}
!3 = !{!"struct PairKey { a: Address, b: Address }"}
!4 = !{!"fn pick(f: Flag) -> Result<Symbol, Error>"}
!5 = !{!"fn read(a: Address, b: Address) -> bool"}
!6 = !{!"fn set_flag()"}
!7 = !{!"1048576 6578706c696369742070616e69637372632f6c69622e7273000000000e0010000a0000003c0000000d000000616200002c001000010000002d00100001000000506169724000100004000000"}
