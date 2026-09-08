; ModuleID = 'ponytail'
source_filename = "ponytail"

%Val = type { i64 }

declare %Val @soroban.val.from_payload(i64)

declare i64 @soroban.val.payload(%Val)

declare %Val @ponytail.unknown()

declare i64 @ponytail.unknown.i64()

declare %Val @buf.symbol_new_from_linear_memory(%Val, %Val)

declare %Val @context.fail_with_error(%Val)

declare %Val @ledger.has_contract_data(%Val, i64)

declare %Val @ledger.put_contract_data(%Val, %Val, i64)

declare %Val @map.map_new_from_linear_memory(%Val, %Val, %Val)

declare %Val @vec.vec_new_from_linear_memory(%Val, %Val)

define %Val @pick(%Val %0) {
entry:
  %l0 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  call void @f33()
  %get = load i64, ptr %l0, align 4
  %lc = call i64 @f11(i64 %get)
  %bottom = call %Val @ponytail.unknown()
  ret %Val %bottom
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
  %bottom = call %Val @ponytail.unknown()
  ret %Val %bottom
}

define %Val @set_flag() {
entry:
  call void @f33()
  call void @f17()
  %bottom = call %Val @ponytail.unknown()
  ret %Val %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 48
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l1, align 4
  %bottom1 = call i64 @ponytail.unknown.i64()
  %cmp = icmp ne i64 %bottom1, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c4, label %fall5

c1:                                               ; preds = %dead12, %c3
  %get62 = load i64, ptr %l2, align 4
  %add63 = add i64 %get62, 48
  %get64 = load i64, ptr %l3, align 4
  %bottom65 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom65

c2:                                               ; preds = %fall11, %fall9, %c4, %fall6, %fall5
  unreachable

c3:                                               ; preds = %fall10, %fall7
  %get56 = load i64, ptr %l2, align 4
  %bottom57 = call i64 @ponytail.unknown.i64()
  store i64 %bottom57, ptr %l3, align 4
  %get58 = load i64, ptr %l2, align 4
  %bottom59 = call i64 @ponytail.unknown.i64()
  %eqz = icmp eq i64 %bottom59, 0
  %zext60 = zext i1 %eqz to i64
  %brif61 = icmp ne i64 %zext60, 0
  br i1 %brif61, label %c1, label %fall11

c4:                                               ; preds = %dead8, %entry
  %get28 = load i64, ptr %l2, align 4
  %add29 = add i64 %get28, 32
  %get30 = load i64, ptr %l0, align 4
  call void @f29(i64 %add29, i64 %get30, i64 1048656)
  %get31 = load i64, ptr %l2, align 4
  %bottom32 = call i64 @ponytail.unknown.i64()
  %brif33 = icmp ne i64 %bottom32, 0
  br i1 %brif33, label %c2, label %fall9

fall5:                                            ; preds = %entry
  %get2 = load i64, ptr %l2, align 4
  %add = add i64 %get2, 32
  %get3 = load i64, ptr %l0, align 4
  call void @f29(i64 %add, i64 %get3, i64 1048672)
  %get4 = load i64, ptr %l2, align 4
  %bottom5 = call i64 @ponytail.unknown.i64()
  %brif6 = icmp ne i64 %bottom5, 0
  br i1 %brif6, label %c2, label %fall6

fall6:                                            ; preds = %fall5
  %get7 = load i64, ptr %l2, align 4
  %get8 = load i64, ptr %l2, align 4
  %get9 = load i64, ptr %l2, align 4
  %add10 = add i64 %get9, 24
  %lc = call i64 @f25(i64 %add10)
  store i64 %lc, ptr %l3, align 4
  %get11 = load i64, ptr %l2, align 4
  %add12 = add i64 %get11, 32
  %get13 = load i64, ptr %l1, align 4
  %add14 = add i64 %get13, 8
  %get15 = load i64, ptr %l0, align 4
  call void @f28(i64 %add12, i64 %add14, i64 %get15)
  %get16 = load i64, ptr %l2, align 4
  %bottom17 = call i64 @ponytail.unknown.i64()
  %brif18 = icmp ne i64 %bottom17, 0
  br i1 %brif18, label %c2, label %fall7

fall7:                                            ; preds = %fall6
  %get19 = load i64, ptr %l2, align 4
  %get20 = load i64, ptr %l2, align 4
  %get21 = load i64, ptr %l2, align 4
  %get22 = load i64, ptr %l3, align 4
  %get23 = load i64, ptr %l2, align 4
  %add24 = add i64 %get23, 32
  %get25 = load i64, ptr %l2, align 4
  %add26 = add i64 %get25, 8
  %get27 = load i64, ptr %l0, align 4
  call void @f31(i64 %add24, i64 %add26, i64 %get27)
  br label %c3

fall9:                                            ; preds = %c4
  %get34 = load i64, ptr %l2, align 4
  %get35 = load i64, ptr %l2, align 4
  %get36 = load i64, ptr %l2, align 4
  %add37 = add i64 %get36, 24
  %lc38 = call i64 @f25(i64 %add37)
  store i64 %lc38, ptr %l3, align 4
  %get39 = load i64, ptr %l2, align 4
  %add40 = add i64 %get39, 32
  %get41 = load i64, ptr %l0, align 4
  %get42 = load i64, ptr %l1, align 4
  %add43 = add i64 %get42, 8
  call void @f18(i64 %add40, i64 %get41, i64 %add43)
  %get44 = load i64, ptr %l2, align 4
  %bottom45 = call i64 @ponytail.unknown.i64()
  %brif46 = icmp ne i64 %bottom45, 0
  br i1 %brif46, label %c2, label %fall10

fall10:                                           ; preds = %fall9
  %get47 = load i64, ptr %l2, align 4
  %get48 = load i64, ptr %l2, align 4
  %get49 = load i64, ptr %l2, align 4
  %get50 = load i64, ptr %l3, align 4
  %get51 = load i64, ptr %l2, align 4
  %add52 = add i64 %get51, 32
  %get53 = load i64, ptr %l2, align 4
  %add54 = add i64 %get53, 8
  %get55 = load i64, ptr %l0, align 4
  call void @f31(i64 %add52, i64 %add54, i64 %get55)
  br label %c3

fall11:                                           ; preds = %c3
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
  call void @f34(i64 %get, i64 %get1, i64 %get2)
  %get3 = load i64, ptr %l2, align 4
  %bottom4 = call i64 @ponytail.unknown.i64()
  %cmp = icmp ne i64 %bottom4, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %dead3, %entry
  %get5 = load i64, ptr %l2, align 4
  %bottom6 = call i64 @ponytail.unknown.i64()
  store i64 %bottom6, ptr %l3, align 4
  %get7 = load i64, ptr %l2, align 4
  %add = add i64 %get7, 16
  %get8 = load i64, ptr %l3, align 4
  %bottom9 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom9

fall2:                                            ; preds = %entry
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 32
  store i64 %sub, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp ugt i64 %get, 21474836479
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %dead6, %fall4
  %get10 = load i64, ptr %l1, align 4
  %add = add i64 %get10, 8
  %get11 = load i64, ptr %l2, align 4
  call void @f12(i64 %add, i64 %get11)
  %get12 = load i64, ptr %l1, align 4
  %get13 = load i64, ptr %l1, align 4
  %get14 = load i64, ptr %l1, align 4
  %add15 = add i64 %get14, 31
  %bottom16 = call i64 @ponytail.unknown.i64()
  %lc = call i64 @f13(i64 %get13, i64 %bottom16, i64 %add15)
  store i64 %lc, ptr %l0, align 4
  %get17 = load i64, ptr %l1, align 4
  %add18 = add i64 %get17, 32
  %get19 = load i64, ptr %l0, align 4
  %bottom20 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom20

c2:                                               ; preds = %fall5, %fall3, %entry
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l2, align 4
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
  %get7 = load i64, ptr %l2, align 4
  %add8 = add i64 %get7, 16
  ret void

c2:                                               ; preds = %dead11, %entry
  %get5 = load i64, ptr %l0, align 4
  %get6 = load i64, ptr %l0, align 4
  br label %c1

c3:                                               ; preds = %dead10, %entry
  call void @f50(i64 1048577, i64 14, i64 1048604)
  unreachable

c4:                                               ; preds = %dead9, %entry
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l0, align 4
  br label %c1

c5:                                               ; preds = %dead8, %entry
  %get2 = load i64, ptr %l2, align 4
  %add = add i64 %get2, 15
  %lc = call i64 @f37(i64 %add, i64 4294967299)
  unreachable

c6:                                               ; preds = %dead7, %entry
  %get1 = load i64, ptr %l0, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l3, align 4
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l2, align 4
  %get5 = load i64, ptr %l3, align 4
  %lc = call i64 @f19(i64 %get4, i64 %get5)
  store i64 %lc, ptr %l1, align 4
  %get6 = load i64, ptr %l3, align 4
  %add = add i64 %get6, 16
  %get7 = load i64, ptr %l1, align 4
  %bottom8 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom8
}

define i64 @f14(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 48
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l2, align 4
  %add = add i64 %get4, 24
  %get5 = load i64, ptr %l2, align 4
  %add6 = add i64 %get5, 47
  %get7 = load i64, ptr %l2, align 4
  %add8 = add i64 %get7, 8
  call void @f35(i64 %add, i64 %add6, i64 %add8)
  %get9 = load i64, ptr %l2, align 4
  %bottom10 = call i64 @ponytail.unknown.i64()
  %cmp = icmp eq i64 %bottom10, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %dead4, %fall2, %entry
  unreachable

fall2:                                            ; preds = %entry
  %get11 = load i64, ptr %l2, align 4
  %bottom12 = call i64 @ponytail.unknown.i64()
  store i64 %bottom12, ptr %l1, align 4
  %get13 = load i64, ptr %l2, align 4
  %add14 = add i64 %get13, 24
  %get15 = load i64, ptr %l2, align 4
  %add16 = add i64 %get15, 47
  %get17 = load i64, ptr %l2, align 4
  %add18 = add i64 %get17, 16
  call void @f35(i64 %add14, i64 %add16, i64 %add18)
  %get19 = load i64, ptr %l2, align 4
  %bottom20 = call i64 @ponytail.unknown.i64()
  %cmp21 = icmp eq i64 %bottom20, 1
  %zext22 = zext i1 %cmp21 to i64
  %brif23 = icmp ne i64 %zext22, 0
  br i1 %brif23, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get24 = load i64, ptr %l1, align 4
  %get25 = load i64, ptr %l2, align 4
  %bottom26 = call i64 @ponytail.unknown.i64()
  %lc = call i64 @f15(i64 %get25, i64 %bottom26)
  %get27 = load i64, ptr %l2, align 4
  %add28 = add i64 %get27, 47
  %lc29 = call i64 @f16(i64 %lc, i64 %add28)
  store i64 %lc29, ptr %l1, align 4
  %get30 = load i64, ptr %l2, align 4
  %add31 = add i64 %get30, 48
  %get32 = load i64, ptr %l1, align 4
  ret i64 %get32
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 32
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l2, align 4
  %add = add i64 %get, 31
  call void @f24(i64 %add)
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  %get3 = load i64, ptr %l2, align 4
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l2, align 4
  %get6 = load i64, ptr %l2, align 4
  %add7 = add i64 %get6, 31
  %get8 = load i64, ptr %l2, align 4
  %lc = call i64 @f6(i64 %add7, i64 %get8)
  store i64 %lc, ptr %l3, align 4
  %get9 = load i64, ptr %l2, align 4
  %add10 = add i64 %get9, 32
  %get11 = load i64, ptr %l3, align 4
  %bottom12 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom12
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l2, align 4
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l2, align 4
  %add = add i64 %get2, 15
  %get3 = load i64, ptr %l1, align 4
  %lc = call i64 @f39(i64 %add, i64 %get3)
  store i64 %lc, ptr %l3, align 4
  %get4 = load i64, ptr %l2, align 4
  %add5 = add i64 %get4, 16
  %get6 = load i64, ptr %l3, align 4
  %bottom7 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom7
}

define void @f17() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %add = add i64 %get, 15
  call void @f24(i64 %add)
  %get1 = load i64, ptr %l0, align 4
  %add2 = add i64 %get1, 15
  call void @f8(i64 %add2, i64 1048624, i64 1048576)
  %get3 = load i64, ptr %l0, align 4
  %add4 = add i64 %get3, 16
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l1, align 4
  call void @f28(i64 %get, i64 %get1, i64 %get2)
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l3, align 4
  %bottom4 = call i64 @ponytail.unknown.i64()
  %brif = icmp ne i64 %bottom4, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall3, %fall2, %entry
  %get20 = load i64, ptr %l0, align 4
  %get21 = load i64, ptr %l4, align 4
  %get22 = load i64, ptr %l3, align 4
  %add23 = add i64 %get22, 16
  ret void

fall2:                                            ; preds = %entry
  %get5 = load i64, ptr %l3, align 4
  %bottom6 = call i64 @ponytail.unknown.i64()
  store i64 %bottom6, ptr %l5, align 4
  %get7 = load i64, ptr %l3, align 4
  %get8 = load i64, ptr %l2, align 4
  %add = add i64 %get8, 8
  %get9 = load i64, ptr %l1, align 4
  call void @f28(i64 %get7, i64 %add, i64 %get9)
  %get10 = load i64, ptr %l3, align 4
  %bottom11 = call i64 @ponytail.unknown.i64()
  %brif12 = icmp ne i64 %bottom11, 0
  br i1 %brif12, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get13 = load i64, ptr %l3, align 4
  %get14 = load i64, ptr %l3, align 4
  %get15 = load i64, ptr %l3, align 4
  %get16 = load i64, ptr %l5, align 4
  %get17 = load i64, ptr %l0, align 4
  %get18 = load i64, ptr %l1, align 4
  %get19 = load i64, ptr %l3, align 4
  %lc = call i64 @f36(i64 %get18, i64 1048636, i64 2, i64 %get19, i64 2)
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l2, align 4
  store i64 4294967299, ptr %l3, align 4
  %get = load i64, ptr %l1, align 4
  %bottom1 = call i64 @ponytail.unknown.i64()
  %brif = icmp ne i64 %bottom1, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %dead5, %fall3
  %lc = call i64 @f49()
  unreachable

c2:                                               ; preds = %fall4, %entry
  %get10 = load i64, ptr %l2, align 4
  %add11 = add i64 %get10, 16
  %get12 = load i64, ptr %l3, align 4
  ret i64 %get12

fall3:                                            ; preds = %entry
  %get2 = load i64, ptr %l2, align 4
  %get3 = load i64, ptr %l1, align 4
  %add = add i64 %get3, 8
  %get4 = load i64, ptr %l0, align 4
  call void @f28(i64 %get2, i64 %add, i64 %get4)
  %get5 = load i64, ptr %l2, align 4
  %bottom6 = call i64 @ponytail.unknown.i64()
  %cmp = icmp eq i64 %bottom6, 1
  %zext = zext i1 %cmp to i64
  %brif7 = icmp ne i64 %zext, 0
  br i1 %brif7, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %get8 = load i64, ptr %l2, align 4
  %bottom9 = call i64 @ponytail.unknown.i64()
  store i64 %bottom9, ptr %l3, align 4
  br label %c2
}

define void @f23(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l0, align 4
  %get3 = load i64, ptr %l1, align 4
  %get4 = load i64, ptr %l3, align 4
  %add = add i64 %get4, 8
  call void @f32(i64 %get2, i64 %get3, i64 %add)
  %get5 = load i64, ptr %l3, align 4
  %add6 = add i64 %get5, 16
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l1, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l2, align 4
  call void @f26(i64 %get, i64 %get1, i64 %get2)
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l3, align 4
  %bottom4 = call i64 @ponytail.unknown.i64()
  %brif = icmp ne i64 %bottom4, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get7 = load i64, ptr %l0, align 4
  %get8 = load i64, ptr %l4, align 4
  %get9 = load i64, ptr %l3, align 4
  %add = add i64 %get9, 16
  ret void

fall2:                                            ; preds = %entry
  %get5 = load i64, ptr %l0, align 4
  %get6 = load i64, ptr %l3, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %get2 = load i64, ptr %l3, align 4
  %get3 = load i64, ptr %l2, align 4
  %get4 = load i64, ptr %l1, align 4
  %get5 = load i64, ptr %l3, align 4
  %lc = call i64 @f40(i64 %get4, i64 %get5, i64 2)
  store i64 %lc, ptr %l4, align 4
  %get6 = load i64, ptr %l0, align 4
  %get7 = load i64, ptr %l0, align 4
  %get8 = load i64, ptr %l4, align 4
  %get9 = load i64, ptr %l3, align 4
  %add = add i64 %get9, 16
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l2, align 4
  %bottom2 = call i64 @ponytail.unknown.i64()
  store i64 %bottom2, ptr %l4, align 4
  %get3 = load i64, ptr %l2, align 4
  %bottom4 = call i64 @ponytail.unknown.i64()
  store i64 %bottom4, ptr %l2, align 4
  call void @f46(i64 %bottom2, i64 %get3, i64 %bottom4)
  %get5 = load i64, ptr %l3, align 4
  %bottom6 = call i64 @ponytail.unknown.i64()
  %cmp = icmp ne i64 %bottom6, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall3
  %get12 = load i64, ptr %l0, align 4
  %get13 = load i64, ptr %l0, align 4
  %get14 = load i64, ptr %l5, align 4
  %get15 = load i64, ptr %l3, align 4
  %add = add i64 %get15, 16
  ret void

c2:                                               ; preds = %dead4, %entry
  %get10 = load i64, ptr %l3, align 4
  %bottom11 = call i64 @ponytail.unknown.i64()
  store i64 %bottom11, ptr %l5, align 4
  br label %c1

fall3:                                            ; preds = %entry
  %get7 = load i64, ptr %l1, align 4
  %get8 = load i64, ptr %l4, align 4
  %get9 = load i64, ptr %l2, align 4
  %lc = call i64 @f42(i64 %get7, i64 %get8, i64 %get9)
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
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l2, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  store i64 %bottom, ptr %l4, align 4
  %and = and i64 %bottom, 255
  %cmp = icmp ne i64 %and, 77
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall2, %entry
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l3, align 4
  ret void

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %get2 = load i64, ptr %l4, align 4
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
}

define i64 @f39(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %g = call %Val @vec.vec_new_from_linear_memory(%Val %to_val, %Val %to_val4)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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

c1:                                               ; preds = %dead3, %entry
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
  %"9" = call %Val @map.map_new_from_linear_memory(%Val %to_val, %Val %to_val9, %Val %to_val10)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

fall2:                                            ; preds = %entry
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
  %j = call %Val @buf.symbol_new_from_linear_memory(%Val %to_val, %Val %to_val4)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
}

define i64 @f43(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l1, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %"5" = call %Val @context.fail_with_error(%Val %to_val)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %"0" = call %Val @ledger.has_contract_data(%Val %to_val, i64 %get1)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %_ = call %Val @ledger.put_contract_data(%Val %to_val, %Val %to_val3, i64 %get2)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l2, align 4
  %cmp = icmp ugt i64 %get, 9
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

c1:                                               ; preds = %c2, %fall10, %fall7
  %get30 = load i64, ptr %l3, align 4
  %add31 = add i64 %get30, 16
  ret void

c2:                                               ; preds = %lc5, %entry
  %get26 = load i64, ptr %l0, align 4
  %get27 = load i64, ptr %l2, align 4
  %get28 = load i64, ptr %l0, align 4
  %get29 = load i64, ptr %l0, align 4
  br label %c1

fall3:                                            ; preds = %entry
  store i64 0, ptr %l4, align 4
  br label %h4

h4:                                               ; preds = %c9, %fall3
  %get1 = load i64, ptr %l2, align 4
  %brif2 = icmp ne i64 %get1, 0
  br i1 %brif2, label %c6, label %fall7

lc5:                                              ; preds = %dead12
  br label %c2

c6:                                               ; preds = %dead8, %h4
  %get6 = load i64, ptr %l3, align 4
  %add = add i64 %get6, 8
  %get7 = load i64, ptr %l1, align 4
  %bottom8 = call i64 @ponytail.unknown.i64()
  call void @f47(i64 %get7, i64 %bottom8)
  %get9 = load i64, ptr %l3, align 4
  %bottom10 = call i64 @ponytail.unknown.i64()
  %cmp11 = icmp eq i64 %bottom10, 255
  %zext12 = zext i1 %cmp11 to i64
  %brif13 = icmp ne i64 %zext12, 0
  br i1 %brif13, label %c9, label %fall10

fall7:                                            ; preds = %h4
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l0, align 4
  %get5 = load i64, ptr %l4, align 4
  %shl = shl i64 %get5, 8
  %or = or i64 %shl, 14
  br label %c1

c9:                                               ; preds = %dead11, %c6
  %get17 = load i64, ptr %l2, align 4
  %add18 = add i64 %get17, -1
  store i64 %add18, ptr %l2, align 4
  %get19 = load i64, ptr %l1, align 4
  %add20 = add i64 %get19, 1
  store i64 %add20, ptr %l1, align 4
  %get21 = load i64, ptr %l4, align 4
  %shl22 = shl i64 %get21, 6
  %get23 = load i64, ptr %l3, align 4
  %bottom24 = call i64 @ponytail.unknown.i64()
  %or25 = or i64 %get23, %bottom24
  store i64 %or25, ptr %l4, align 4
  br label %h4

fall10:                                           ; preds = %c6
  %get14 = load i64, ptr %l0, align 4
  %get15 = load i64, ptr %l3, align 4
  %get16 = load i64, ptr %l0, align 4
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
  %get28 = load i64, ptr %l0, align 4
  %get29 = load i64, ptr %l2, align 4
  ret void

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l1, align 4
  %add = add i64 %get1, -48
  %and2 = and i64 %add, 255
  %cmp3 = icmp ult i64 %and2, 10
  %zext4 = zext i1 %cmp3 to i64
  %brif5 = icmp ne i64 %zext4, 0
  br i1 %brif5, label %c4, label %fall5

c3:                                               ; preds = %dead11, %fall5
  %get25 = load i64, ptr %l1, align 4
  %add26 = add i64 %get25, -53
  store i64 %add26, ptr %l2, align 4
  br label %c1

c4:                                               ; preds = %dead10, %fall2
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

c7:                                               ; preds = %dead9, %fall6
  %get21 = load i64, ptr %l1, align 4
  %add22 = add i64 %get21, -59
  store i64 %add22, ptr %l2, align 4
  br label %c1

fall8:                                            ; preds = %fall6
  %get18 = load i64, ptr %l0, align 4
  %get19 = load i64, ptr %l1, align 4
  %get20 = load i64, ptr %l0, align 4
  ret void
}

define i64 @f48(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp eq i64 %get, 1
  %zext = zext i1 %cmp to i64
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
}

define i64 @f49() {
entry:
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 32
  store i64 %sub, ptr %l3, align 4
  %get = load i64, ptr %l3, align 4
  %get1 = load i64, ptr %l1, align 4
  %get2 = load i64, ptr %l3, align 4
  %get3 = load i64, ptr %l0, align 4
  %get4 = load i64, ptr %l3, align 4
  %get5 = load i64, ptr %l3, align 4
  %get6 = load i64, ptr %l2, align 4
  %get7 = load i64, ptr %l3, align 4
  %get8 = load i64, ptr %l3, align 4
  %add = add i64 %get8, 12
  %get9 = load i64, ptr %l3, align 4
  %add10 = add i64 %get9, 20
  call void @f23(i64 %add10)
  unreachable
}
