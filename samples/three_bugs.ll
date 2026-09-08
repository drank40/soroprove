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

define %Val @pick(%Val %0) {
entry:
  %l0 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  call void @f33()
  %get = load i64, ptr %l0, align 4
  %lc = call i64 @f11(i64 %get)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define %Val @read(%Val %0, %Val %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  %arg_payload1 = call i64 @soroban.val.payload(%Val %1)
  store i64 %arg_payload1, ptr %l1, align 4
  call void @f33()
  %get = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  %lc = call i64 @f14(i64 %get, i64 %get2)
  %to_val = call %Val @soroban.val.from_payload(i64 %lc)
  ret %Val %to_val
}

define %Val @set_flag() {
entry:
  call void @f33()
  call void @f17()
  %v_void = call %Val @soroban.val.from_payload(i64 2)
  ret %Val %v_void
}

define i64 @f6(i64 %0, i64 %1) {
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

define i64 @f7(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 48
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  %cmp = icmp ne i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c4, label %fall5

c1:                                               ; preds = %c3
  %get80 = load i64, ptr %l2, align 4
  %add81 = add i64 %get80, 48
  store i64 %add81, ptr @g0, align 4
  %get82 = load i64, ptr %l3, align 4
  ret i64 %get82

c2:                                               ; preds = %fall10, %fall8, %c4, %fall6, %fall5
  call void @soroban.trap()
  unreachable

c3:                                               ; preds = %fall9, %fall7
  %get72 = load i64, ptr %l2, align 4
  %ea73 = add i64 %get72, 40
  %ld74 = call i64 @soroban.load64(i64 %ea73)
  store i64 %ld74, ptr %l3, align 4
  %get75 = load i64, ptr %l2, align 4
  %ea76 = add i64 %get75, 32
  %ld77 = call i64 @soroban.load64(i64 %ea76)
  %eqz = icmp eq i64 %ld77, 0
  %zext78 = zext i1 %eqz to i64
  %brif79 = icmp ne i64 %zext78, 0
  br i1 %brif79, label %c1, label %fall10

c4:                                               ; preds = %entry
  %get35 = load i64, ptr %l2, align 4
  %add36 = add i64 %get35, 32
  %get37 = load i64, ptr %l0, align 4
  call void @f29(i64 %add36, i64 %get37, i64 1048656)
  %get38 = load i64, ptr %l2, align 4
  %ea39 = add i64 %get38, 32
  %ld40 = call i64 @soroban.load32u(i64 %ea39)
  %brif41 = icmp ne i64 %ld40, 0
  br i1 %brif41, label %c2, label %fall8

fall5:                                            ; preds = %entry
  %get1 = load i64, ptr %l2, align 4
  %add = add i64 %get1, 32
  %get2 = load i64, ptr %l0, align 4
  call void @f29(i64 %add, i64 %get2, i64 1048672)
  %get3 = load i64, ptr %l2, align 4
  %ea = add i64 %get3, 32
  %ld4 = call i64 @soroban.load32u(i64 %ea)
  %brif5 = icmp ne i64 %ld4, 0
  br i1 %brif5, label %c2, label %fall6

fall6:                                            ; preds = %fall5
  %get6 = load i64, ptr %l2, align 4
  %get7 = load i64, ptr %l2, align 4
  %ea8 = add i64 %get7, 40
  %ld9 = call i64 @soroban.load64(i64 %ea8)
  %ea10 = add i64 %get6, 24
  call void @soroban.store64(i64 %ea10, i64 %ld9)
  %get11 = load i64, ptr %l2, align 4
  %add12 = add i64 %get11, 24
  %lc = call i64 @f25(i64 %add12)
  store i64 %lc, ptr %l3, align 4
  %get13 = load i64, ptr %l2, align 4
  %add14 = add i64 %get13, 32
  %get15 = load i64, ptr %l1, align 4
  %add16 = add i64 %get15, 8
  %get17 = load i64, ptr %l0, align 4
  call void @f28(i64 %add14, i64 %add16, i64 %get17)
  %get18 = load i64, ptr %l2, align 4
  %ea19 = add i64 %get18, 32
  %ld20 = call i64 @soroban.load32u(i64 %ea19)
  %brif21 = icmp ne i64 %ld20, 0
  br i1 %brif21, label %c2, label %fall7

fall7:                                            ; preds = %fall6
  %get22 = load i64, ptr %l2, align 4
  %get23 = load i64, ptr %l2, align 4
  %ea24 = add i64 %get23, 40
  %ld25 = call i64 @soroban.load64(i64 %ea24)
  %ea26 = add i64 %get22, 16
  call void @soroban.store64(i64 %ea26, i64 %ld25)
  %get27 = load i64, ptr %l2, align 4
  %get28 = load i64, ptr %l3, align 4
  %ea29 = add i64 %get27, 8
  call void @soroban.store64(i64 %ea29, i64 %get28)
  %get30 = load i64, ptr %l2, align 4
  %add31 = add i64 %get30, 32
  %get32 = load i64, ptr %l2, align 4
  %add33 = add i64 %get32, 8
  %get34 = load i64, ptr %l0, align 4
  call void @f31(i64 %add31, i64 %add33, i64 %get34)
  br label %c3

fall8:                                            ; preds = %c4
  %get42 = load i64, ptr %l2, align 4
  %get43 = load i64, ptr %l2, align 4
  %ea44 = add i64 %get43, 40
  %ld45 = call i64 @soroban.load64(i64 %ea44)
  %ea46 = add i64 %get42, 24
  call void @soroban.store64(i64 %ea46, i64 %ld45)
  %get47 = load i64, ptr %l2, align 4
  %add48 = add i64 %get47, 24
  %lc49 = call i64 @f25(i64 %add48)
  store i64 %lc49, ptr %l3, align 4
  %get50 = load i64, ptr %l2, align 4
  %add51 = add i64 %get50, 32
  %get52 = load i64, ptr %l0, align 4
  %get53 = load i64, ptr %l1, align 4
  %add54 = add i64 %get53, 8
  call void @f18(i64 %add51, i64 %get52, i64 %add54)
  %get55 = load i64, ptr %l2, align 4
  %ea56 = add i64 %get55, 32
  %ld57 = call i64 @soroban.load32u(i64 %ea56)
  %brif58 = icmp ne i64 %ld57, 0
  br i1 %brif58, label %c2, label %fall9

fall9:                                            ; preds = %fall8
  %get59 = load i64, ptr %l2, align 4
  %get60 = load i64, ptr %l2, align 4
  %ea61 = add i64 %get60, 40
  %ld62 = call i64 @soroban.load64(i64 %ea61)
  %ea63 = add i64 %get59, 16
  call void @soroban.store64(i64 %ea63, i64 %ld62)
  %get64 = load i64, ptr %l2, align 4
  %get65 = load i64, ptr %l3, align 4
  %ea66 = add i64 %get64, 8
  call void @soroban.store64(i64 %ea66, i64 %get65)
  %get67 = load i64, ptr %l2, align 4
  %add68 = add i64 %get67, 32
  %get69 = load i64, ptr %l2, align 4
  %add70 = add i64 %get69, 8
  %get71 = load i64, ptr %l0, align 4
  call void @f31(i64 %add68, i64 %add70, i64 %get71)
  br label %c3

fall10:                                           ; preds = %c3
  br label %c2
}

define void @f8(i64 %0, i64 %1, i64 %2) {
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

define void @f9(i64 %0, i64 %1, i64 %2, i64 %3) {
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
  %lc = call i64 @f10(i64 %get1, i64 %get2)
  %get3 = load i64, ptr %l2, align 4
  %get4 = load i64, ptr %l0, align 4
  %lc5 = call i64 @f39(i64 %get3, i64 %get4)
  %get6 = load i64, ptr %l3, align 4
  %lc7 = call i64 @f38(i64 %get, i64 %lc, i64 %lc5, i64 %get6)
  ret void
}

define i64 @f10(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  call void @f34(i64 %get, i64 %get1, i64 %get2)
  %get3 = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load64(i64 %get3)
  %cmp = icmp ne i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %entry
  %get4 = load i64, ptr %l2, align 4
  %ea = add i64 %get4, 8
  %ld5 = call i64 @soroban.load64(i64 %ea)
  store i64 %ld5, ptr %l3, align 4
  %get6 = load i64, ptr %l2, align 4
  %add = add i64 %get6, 16
  store i64 %add, ptr @g0, align 4
  %get7 = load i64, ptr %l3, align 4
  ret i64 %get7

fall2:                                            ; preds = %entry
  call void @soroban.trap()
  unreachable
}

define i64 @f11(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 32
  store i64 %sub, ptr %l1, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp ugt i64 %get, 21474836479
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %fall4
  %get10 = load i64, ptr %l1, align 4
  %add = add i64 %get10, 8
  %get11 = load i64, ptr %l2, align 4
  call void @f12(i64 %add, i64 %get11)
  %get12 = load i64, ptr %l1, align 4
  %ea = add i64 %get12, 8
  %ld = call i64 @soroban.load64(i64 %ea)
  %get13 = load i64, ptr %l1, align 4
  %ea14 = add i64 %get13, 16
  %ld15 = call i64 @soroban.load64(i64 %ea14)
  %get16 = load i64, ptr %l1, align 4
  %add17 = add i64 %get16, 31
  %lc = call i64 @f13(i64 %ld, i64 %ld15, i64 %add17)
  store i64 %lc, ptr %l0, align 4
  %get18 = load i64, ptr %l1, align 4
  %add19 = add i64 %get18, 32
  store i64 %add19, ptr @g0, align 4
  %get20 = load i64, ptr %l0, align 4
  ret i64 %get20

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

define void @f12(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
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
  %get8 = load i64, ptr %l2, align 4
  %add9 = add i64 %get8, 16
  store i64 %add9, ptr @g0, align 4
  ret void

c2:                                               ; preds = %entry
  %get5 = load i64, ptr %l0, align 4
  %ea6 = add i64 %get5, 8
  call void @soroban.store64(i64 %ea6, i64 9742)
  %get7 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get7, i64 0)
  br label %c1

c3:                                               ; preds = %entry
  call void @f50(i64 1048577, i64 14, i64 1048604)
  call void @soroban.trap()
  unreachable

c4:                                               ; preds = %entry
  %get3 = load i64, ptr %l0, align 4
  %ea = add i64 %get3, 8
  call void @soroban.store64(i64 %ea, i64 10766)
  %get4 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get4, i64 0)
  br label %c1

c5:                                               ; preds = %entry
  %get2 = load i64, ptr %l2, align 4
  %add = add i64 %get2, 15
  %lc = call i64 @f37(i64 %add, i64 4294967299)
  call void @soroban.trap()
  unreachable

c6:                                               ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get1, i64 1)
  br label %c1
}

define i64 @f13(i64 %0, i64 %1, i64 %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %ea = add i64 %get, 8
  call void @soroban.store64(i64 %ea, i64 %get1)
  %get2 = load i64, ptr %l3, align 4
  %get3 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get2, i64 %get3)
  %get4 = load i64, ptr %l2, align 4
  %get5 = load i64, ptr %l3, align 4
  %lc = call i64 @f19(i64 %get4, i64 %get5)
  store i64 %lc, ptr %l1, align 4
  %get6 = load i64, ptr %l3, align 4
  %add = add i64 %get6, 16
  store i64 %add, ptr @g0, align 4
  %get7 = load i64, ptr %l1, align 4
  ret i64 %get7
}

define i64 @f14(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 48
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l1, align 4
  %ea = add i64 %get, 16
  call void @soroban.store64(i64 %ea, i64 %get1)
  %get2 = load i64, ptr %l2, align 4
  %get3 = load i64, ptr %l0, align 4
  %ea4 = add i64 %get2, 8
  call void @soroban.store64(i64 %ea4, i64 %get3)
  %get5 = load i64, ptr %l2, align 4
  %add = add i64 %get5, 24
  %get6 = load i64, ptr %l2, align 4
  %add7 = add i64 %get6, 47
  %get8 = load i64, ptr %l2, align 4
  %add9 = add i64 %get8, 8
  call void @f35(i64 %add, i64 %add7, i64 %add9)
  %get10 = load i64, ptr %l2, align 4
  %ea11 = add i64 %get10, 24
  %ld = call i64 @soroban.load64(i64 %ea11)
  %cmp = icmp eq i64 %ld, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  call void @soroban.trap()
  unreachable

fall2:                                            ; preds = %entry
  %get12 = load i64, ptr %l2, align 4
  %ea13 = add i64 %get12, 32
  %ld14 = call i64 @soroban.load64(i64 %ea13)
  store i64 %ld14, ptr %l1, align 4
  %get15 = load i64, ptr %l2, align 4
  %add16 = add i64 %get15, 24
  %get17 = load i64, ptr %l2, align 4
  %add18 = add i64 %get17, 47
  %get19 = load i64, ptr %l2, align 4
  %add20 = add i64 %get19, 16
  call void @f35(i64 %add16, i64 %add18, i64 %add20)
  %get21 = load i64, ptr %l2, align 4
  %ea22 = add i64 %get21, 24
  %ld23 = call i64 @soroban.load64(i64 %ea22)
  %cmp24 = icmp eq i64 %ld23, 1
  %zext25 = zext i1 %cmp24 to i64
  %brif26 = icmp ne i64 %zext25, 0
  br i1 %brif26, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get27 = load i64, ptr %l1, align 4
  %get28 = load i64, ptr %l2, align 4
  %ea29 = add i64 %get28, 32
  %ld30 = call i64 @soroban.load64(i64 %ea29)
  %lc = call i64 @f15(i64 %get27, i64 %ld30)
  %get31 = load i64, ptr %l2, align 4
  %add32 = add i64 %get31, 47
  %lc33 = call i64 @f16(i64 %lc, i64 %add32)
  store i64 %lc33, ptr %l1, align 4
  %get34 = load i64, ptr %l2, align 4
  %add35 = add i64 %get34, 48
  store i64 %add35, ptr @g0, align 4
  %get36 = load i64, ptr %l1, align 4
  ret i64 %get36
}

define i64 @f15(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 32
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l2, align 4
  %add = add i64 %get, 31
  call void @f24(i64 %add)
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  %ea = add i64 %get1, 16
  call void @soroban.store64(i64 %ea, i64 %get2)
  %get3 = load i64, ptr %l2, align 4
  %get4 = load i64, ptr %l0, align 4
  %ea5 = add i64 %get3, 8
  call void @soroban.store64(i64 %ea5, i64 %get4)
  %get6 = load i64, ptr %l2, align 4
  call void @soroban.store64(i64 %get6, i64 0)
  %get7 = load i64, ptr %l2, align 4
  %add8 = add i64 %get7, 31
  %get9 = load i64, ptr %l2, align 4
  %lc = call i64 @f6(i64 %add8, i64 %get9)
  store i64 %lc, ptr %l3, align 4
  %get10 = load i64, ptr %l2, align 4
  %add11 = add i64 %get10, 32
  store i64 %add11, ptr @g0, align 4
  %get12 = load i64, ptr %l3, align 4
  ret i64 %get12
}

define i64 @f16(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l0, align 4
  %ea = add i64 %get, 15
  call void @soroban.store8(i64 %ea, i64 %get1)
  %get2 = load i64, ptr %l2, align 4
  %add = add i64 %get2, 15
  %get3 = load i64, ptr %l1, align 4
  %lc = call i64 @f39(i64 %add, i64 %get3)
  store i64 %lc, ptr %l3, align 4
  %get4 = load i64, ptr %l2, align 4
  %add5 = add i64 %get4, 16
  store i64 %add5, ptr @g0, align 4
  %get6 = load i64, ptr %l3, align 4
  ret i64 %get6
}

define void @f17() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l0, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l0, align 4
  %add = add i64 %get, 15
  call void @f24(i64 %add)
  %get1 = load i64, ptr %l0, align 4
  %add2 = add i64 %get1, 15
  call void @f8(i64 %add2, i64 1048624, i64 1048576)
  %get3 = load i64, ptr %l0, align 4
  %add4 = add i64 %get3, 16
  store i64 %add4, ptr @g0, align 4
  ret void
}

define void @f18(i64 %0, i64 %1, i64 %2) {
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
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  call void @f28(i64 %get, i64 %get1, i64 %get2)
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l3, align 4
  %ld = call i64 @soroban.load32u(i64 %get3)
  %brif = icmp ne i64 %ld, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall3, %fall2, %entry
  %get23 = load i64, ptr %l0, align 4
  %get24 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get23, i64 %get24)
  %get25 = load i64, ptr %l3, align 4
  %add26 = add i64 %get25, 16
  store i64 %add26, ptr @g0, align 4
  ret void

fall2:                                            ; preds = %entry
  %get4 = load i64, ptr %l3, align 4
  %ea = add i64 %get4, 8
  %ld5 = call i64 @soroban.load64(i64 %ea)
  store i64 %ld5, ptr %l5, align 4
  %get6 = load i64, ptr %l3, align 4
  %get7 = load i64, ptr %l2, align 4
  %add = add i64 %get7, 8
  %get8 = load i64, ptr %l1, align 4
  call void @f28(i64 %get6, i64 %add, i64 %get8)
  %get9 = load i64, ptr %l3, align 4
  %ld10 = call i64 @soroban.load32u(i64 %get9)
  %brif11 = icmp ne i64 %ld10, 0
  br i1 %brif11, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get12 = load i64, ptr %l3, align 4
  %get13 = load i64, ptr %l3, align 4
  %ea14 = add i64 %get13, 8
  %ld15 = call i64 @soroban.load64(i64 %ea14)
  %ea16 = add i64 %get12, 8
  call void @soroban.store64(i64 %ea16, i64 %ld15)
  %get17 = load i64, ptr %l3, align 4
  %get18 = load i64, ptr %l5, align 4
  call void @soroban.store64(i64 %get17, i64 %get18)
  %get19 = load i64, ptr %l0, align 4
  %get20 = load i64, ptr %l1, align 4
  %get21 = load i64, ptr %l3, align 4
  %lc = call i64 @f36(i64 %get20, i64 1048636, i64 2, i64 %get21, i64 2)
  %ea22 = add i64 %get19, 8
  call void @soroban.store64(i64 %ea22, i64 %lc)
  store i64 0, ptr %l4, align 4
  br label %c1
}

define i64 @f19(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l2, align 4
  store i64 %sub, ptr @g0, align 4
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
  %get9 = load i64, ptr %l2, align 4
  %add10 = add i64 %get9, 16
  store i64 %add10, ptr @g0, align 4
  %get11 = load i64, ptr %l3, align 4
  ret i64 %get11

fall3:                                            ; preds = %entry
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  %add = add i64 %get2, 8
  %get3 = load i64, ptr %l0, align 4
  call void @f28(i64 %get1, i64 %add, i64 %get3)
  %get4 = load i64, ptr %l2, align 4
  %ld5 = call i64 @soroban.load64(i64 %get4)
  %cmp = icmp eq i64 %ld5, 1
  %zext = zext i1 %cmp to i64
  %brif6 = icmp ne i64 %zext, 0
  br i1 %brif6, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %get7 = load i64, ptr %l2, align 4
  %ea = add i64 %get7, 8
  %ld8 = call i64 @soroban.load64(i64 %ea)
  store i64 %ld8, ptr %l3, align 4
  br label %c2
}

define void @f23(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  call void @soroban.trap()
  unreachable
}

define void @f24(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  ret void
}

define i64 @f25(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %ld = call i64 @soroban.load64(i64 %get)
  ret i64 %ld
}

define void @f26(i64 %0, i64 %1, i64 %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load64(i64 %get1)
  %ea = add i64 %get, 8
  call void @soroban.store64(i64 %ea, i64 %ld)
  %get2 = load i64, ptr %l0, align 4
  %get3 = load i64, ptr %l1, align 4
  %get4 = load i64, ptr %l3, align 4
  %add = add i64 %get4, 8
  call void @f32(i64 %get2, i64 %get3, i64 %add)
  %get5 = load i64, ptr %l3, align 4
  %add6 = add i64 %get5, 16
  store i64 %add6, ptr @g0, align 4
  ret void
}

define i64 @f27(i64 %0, i64 %1, i64 %2) {
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

define void @f28(i64 %0, i64 %1, i64 %2) {
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

define void @f29(i64 %0, i64 %1, i64 %2) {
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
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  call void @f26(i64 %get, i64 %get1, i64 %get2)
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l3, align 4
  %ld = call i64 @soroban.load32u(i64 %get3)
  %brif = icmp ne i64 %ld, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get8 = load i64, ptr %l0, align 4
  %get9 = load i64, ptr %l4, align 4
  call void @soroban.store64(i64 %get8, i64 %get9)
  %get10 = load i64, ptr %l3, align 4
  %add = add i64 %get10, 16
  store i64 %add, ptr @g0, align 4
  ret void

fall2:                                            ; preds = %entry
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l3, align 4
  %ea = add i64 %get5, 8
  %ld6 = call i64 @soroban.load64(i64 %ea)
  %ea7 = add i64 %get4, 8
  call void @soroban.store64(i64 %ea7, i64 %ld6)
  store i64 0, ptr %l4, align 4
  br label %c1
}

define void @f30(i64 %0, i64 %1, i64 %2) {
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
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %ea = add i64 %get1, 8
  %ld = call i64 @soroban.load64(i64 %ea)
  %ea2 = add i64 %get, 8
  call void @soroban.store64(i64 %ea2, i64 %ld)
  %get3 = load i64, ptr %l3, align 4
  %get4 = load i64, ptr %l2, align 4
  %ld5 = call i64 @soroban.load64(i64 %get4)
  call void @soroban.store64(i64 %get3, i64 %ld5)
  %get6 = load i64, ptr %l1, align 4
  %get7 = load i64, ptr %l3, align 4
  %lc = call i64 @f40(i64 %get6, i64 %get7, i64 2)
  store i64 %lc, ptr %l4, align 4
  %get8 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get8, i64 0)
  %get9 = load i64, ptr %l0, align 4
  %get10 = load i64, ptr %l4, align 4
  %ea11 = add i64 %get9, 8
  call void @soroban.store64(i64 %ea11, i64 %get10)
  %get12 = load i64, ptr %l3, align 4
  %add = add i64 %get12, 16
  store i64 %add, ptr @g0, align 4
  ret void
}

define void @f31(i64 %0, i64 %1, i64 %2) {
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

define void @f32(i64 %0, i64 %1, i64 %2) {
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
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %ld = call i64 @soroban.load32u(i64 %get1)
  store i64 %ld, ptr %l4, align 4
  %get2 = load i64, ptr %l2, align 4
  %ea = add i64 %get2, 4
  %ld3 = call i64 @soroban.load32u(i64 %ea)
  store i64 %ld3, ptr %l2, align 4
  call void @f46(i64 %get, i64 %ld, i64 %ld3)
  %get4 = load i64, ptr %l3, align 4
  %ld5 = call i64 @soroban.load32u(i64 %get4)
  %cmp = icmp ne i64 %ld5, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall3
  %get12 = load i64, ptr %l0, align 4
  call void @soroban.store64(i64 %get12, i64 0)
  %get13 = load i64, ptr %l0, align 4
  %get14 = load i64, ptr %l5, align 4
  %ea15 = add i64 %get13, 8
  call void @soroban.store64(i64 %ea15, i64 %get14)
  %get16 = load i64, ptr %l3, align 4
  %add = add i64 %get16, 16
  store i64 %add, ptr @g0, align 4
  ret void

c2:                                               ; preds = %entry
  %get9 = load i64, ptr %l3, align 4
  %ea10 = add i64 %get9, 8
  %ld11 = call i64 @soroban.load64(i64 %ea10)
  store i64 %ld11, ptr %l5, align 4
  br label %c1

fall3:                                            ; preds = %entry
  %get6 = load i64, ptr %l1, align 4
  %get7 = load i64, ptr %l4, align 4
  %get8 = load i64, ptr %l2, align 4
  %lc = call i64 @f42(i64 %get6, i64 %get7, i64 %get8)
  store i64 %lc, ptr %l5, align 4
  br label %c1
}

define void @f33() {
entry:
  ret void
}

define void @f34(i64 %0, i64 %1, i64 %2) {
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

define void @f35(i64 %0, i64 %1, i64 %2) {
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

define i64 @f36(i64 %0, i64 %1, i64 %2, i64 %3, i64 %4) {
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

define i64 @f37(i64 %0, i64 %1) {
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

define i64 @f38(i64 %0, i64 %1, i64 %2, i64 %3) {
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

define i64 @f39(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %ld = call i64 @soroban.load8u(i64 %get)
  ret i64 %ld
}

define i64 @f40(i64 %0, i64 %1, i64 %2) {
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

define i64 @f41(i64 %0, i64 %1, i64 %2, i64 %3, i64 %4) {
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

define i64 @f42(i64 %0, i64 %1, i64 %2) {
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

define i64 @f43(i64 %0, i64 %1) {
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

define i64 @f44(i64 %0, i64 %1, i64 %2) {
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

define i64 @f45(i64 %0, i64 %1, i64 %2, i64 %3) {
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

define void @f46(i64 %0, i64 %1, i64 %2) {
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
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 16
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l2, align 4
  %cmp = icmp ugt i64 %get, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall9, %fall7
  %get36 = load i64, ptr %l3, align 4
  %add37 = add i64 %get36, 16
  store i64 %add37, ptr @g0, align 4
  ret void

c2:                                               ; preds = %entry
  %get30 = load i64, ptr %l0, align 4
  %get31 = load i64, ptr %l2, align 4
  %ea32 = add i64 %get30, 8
  call void @soroban.store32(i64 %ea32, i64 %get31)
  %get33 = load i64, ptr %l0, align 4
  %ea34 = add i64 %get33, 4
  call void @soroban.store8(i64 %ea34, i64 0)
  %get35 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get35, i64 1)
  br label %c1

fall3:                                            ; preds = %entry
  store i64 0, ptr %l4, align 4
  br label %h4

h4:                                               ; preds = %c8, %fall3
  %get1 = load i64, ptr %l2, align 4
  %brif2 = icmp ne i64 %get1, 0
  br i1 %brif2, label %c6, label %fall7

c6:                                               ; preds = %h4
  %get6 = load i64, ptr %l3, align 4
  %add = add i64 %get6, 8
  %get7 = load i64, ptr %l1, align 4
  %ld = call i64 @soroban.load8u(i64 %get7)
  call void @f47(i64 %add, i64 %ld)
  %get8 = load i64, ptr %l3, align 4
  %ea9 = add i64 %get8, 8
  %ld10 = call i64 @soroban.load8u(i64 %ea9)
  %cmp11 = icmp eq i64 %ld10, 255
  %zext12 = zext i1 %cmp11 to i64
  %brif13 = icmp ne i64 %zext12, 0
  br i1 %brif13, label %c8, label %fall9

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
  %get20 = load i64, ptr %l2, align 4
  %add21 = add i64 %get20, -1
  store i64 %add21, ptr %l2, align 4
  %get22 = load i64, ptr %l1, align 4
  %add23 = add i64 %get22, 1
  store i64 %add23, ptr %l1, align 4
  %get24 = load i64, ptr %l4, align 4
  %shl25 = shl i64 %get24, 6
  %get26 = load i64, ptr %l3, align 4
  %ea27 = add i64 %get26, 9
  %ld28 = call i64 @soroban.load8u(i64 %ea27)
  %or29 = or i64 %shl25, %ld28
  store i64 %or29, ptr %l4, align 4
  br label %h4

fall9:                                            ; preds = %c6
  %get14 = load i64, ptr %l0, align 4
  %get15 = load i64, ptr %l3, align 4
  %ea16 = add i64 %get15, 8
  %ld17 = call i64 @soroban.load64(i64 %ea16)
  %ea18 = add i64 %get14, 4
  call void @soroban.store64(i64 %ea18, i64 %ld17)
  %get19 = load i64, ptr %l0, align 4
  call void @soroban.store32(i64 %get19, i64 1)
  br label %c1
}

define void @f47(i64 %0, i64 %1) {
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

define i64 @f48(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp eq i64 %get, 1
  %zext = zext i1 %cmp to i64
  ret i64 %zext
}

define i64 @f49() {
entry:
  ret i64 34359740419
}

define void @f50(i64 %0, i64 %1, i64 %2) {
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

define void @f51(i64 %0, i64 %1, i64 %2) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %l3 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 %2, ptr %l2, align 4
  store i64 0, ptr %l3, align 4
  %g0 = load i64, ptr @g0, align 4
  %sub = sub i64 %g0, 32
  store i64 %sub, ptr %l3, align 4
  store i64 %sub, ptr @g0, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %ea = add i64 %get, 16
  call void @soroban.store32(i64 %ea, i64 %get1)
  %get2 = load i64, ptr %l3, align 4
  %get3 = load i64, ptr %l0, align 4
  %ea4 = add i64 %get2, 12
  call void @soroban.store32(i64 %ea4, i64 %get3)
  %get5 = load i64, ptr %l3, align 4
  %ea6 = add i64 %get5, 28
  call void @soroban.store16(i64 %ea6, i64 1)
  %get7 = load i64, ptr %l3, align 4
  %get8 = load i64, ptr %l2, align 4
  %ea9 = add i64 %get7, 24
  call void @soroban.store32(i64 %ea9, i64 %get8)
  %get10 = load i64, ptr %l3, align 4
  %get11 = load i64, ptr %l3, align 4
  %add = add i64 %get11, 12
  %ea12 = add i64 %get10, 20
  call void @soroban.store32(i64 %ea12, i64 %add)
  %get13 = load i64, ptr %l3, align 4
  %add14 = add i64 %get13, 20
  call void @f23(i64 %add14)
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
