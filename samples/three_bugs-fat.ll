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

define %Val @read(%Val %0, %Val %1) {
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
  %bottom = call %Val @ponytail.unknown()
  ret %Val %bottom

exit:                                             ; No predecessors!
  %bottom3 = call %Val @ponytail.unknown()
  ret %Val %bottom3
}

define %Val @pick(%Val %0) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %l2 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  store i64 0, ptr %l2, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %and = and i64 %get, 255
  %cmp = icmp ne i64 %and, 4
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c6, label %fall7

exit:                                             ; No predecessors!
  %bottom10 = call %Val @ponytail.unknown()
  ret %Val %bottom10

c1:                                               ; preds = %c2, %c3, %fall8
  %get7 = load i64, ptr %l1, align 4
  %add8 = add i64 %get7, 16
  %get9 = load i64, ptr %l0, align 4
  %bottom11 = call %Val @ponytail.unknown()
  ret %Val %bottom11

c2:                                               ; preds = %dead13, %fall8, %fall8
  store i64 9742, ptr %l0, align 4
  br label %c1

c3:                                               ; preds = %dead12, %fall8
  store i64 10766, ptr %l0, align 4
  br label %c1

c4:                                               ; preds = %dead11, %fall8
  call void @f24(i64 1048576, i64 14, i64 1048604)
  unreachable

c5:                                               ; preds = %dead10, %fall8
  %get6 = load i64, ptr %l1, align 4
  %add = add i64 %get6, 15
  %lc = call i64 @f15(i64 %add, i64 4294967299)
  unreachable

c6:                                               ; preds = %dead9, %fall7, %entry
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

dead9:                                            ; No predecessors!
  br label %c6

dead10:                                           ; No predecessors!
  br label %c5

dead11:                                           ; No predecessors!
  br label %c4

dead12:                                           ; No predecessors!
  br label %c3

dead13:                                           ; No predecessors!
  br label %c2
}

define %Val @set_flag() {
entry:
  %l0 = alloca i64, align 8
  store i64 0, ptr %l0, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 16
  store i64 %sub, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %add = add i64 %get, 15
  %lc = call i64 @f16(i64 %add, i64 11022, i64 1, i64 1)
  %get1 = load i64, ptr %l0, align 4
  %add2 = add i64 %get1, 16
  %bottom3 = call %Val @ponytail.unknown()
  ret %Val %bottom3

exit:                                             ; No predecessors!
  %bottom4 = call %Val @ponytail.unknown()
  ret %Val %bottom4
}

define i64 @f7(i64 %0, i64 %1) {
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
  %bottom = call i64 @ponytail.unknown.i64()
  %sub = sub i64 %bottom, 32
  store i64 %sub, ptr %l2, align 4
  %get = load i64, ptr %l0, align 4
  %and = and i64 %get, 255
  %cmp = icmp ne i64 %and, 77
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

exit:                                             ; No predecessors!
  %bottom38 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom38

c1:                                               ; preds = %dead5, %fall3, %fall2, %entry
  unreachable

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l1, align 4
  %and2 = and i64 %get1, 255
  %cmp3 = icmp ne i64 %and2, 77
  %zext4 = zext i1 %cmp3 to i64
  %brif5 = icmp ne i64 %zext4, 0
  br i1 %brif5, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get6 = load i64, ptr %l2, align 4
  %add = add i64 %get6, 8
  %get7 = load i64, ptr %l2, align 4
  %add8 = add i64 %get7, 31
  call void @f14(i64 %add, i64 %add8, i64 1048644)
  %get9 = load i64, ptr %l2, align 4
  %bottom10 = call i64 @ponytail.unknown.i64()
  %cmp11 = icmp eq i64 %bottom10, 1
  %zext12 = zext i1 %cmp11 to i64
  %brif13 = icmp ne i64 %zext12, 0
  br i1 %brif13, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %get14 = load i64, ptr %l2, align 4
  %bottom15 = call i64 @ponytail.unknown.i64()
  store i64 %bottom15, ptr %l3, align 4
  %get16 = load i64, ptr %l2, align 4
  %get17 = load i64, ptr %l1, align 4
  %get18 = load i64, ptr %l2, align 4
  %get19 = load i64, ptr %l0, align 4
  %get20 = load i64, ptr %l2, align 4
  %get21 = load i64, ptr %l2, align 4
  %add22 = add i64 %get21, 31
  %get23 = load i64, ptr %l2, align 4
  %add24 = add i64 %get23, 8
  %lc = call i64 @f13(i64 %add22, i64 1048624, i64 2, i64 %add24, i64 2)
  %get25 = load i64, ptr %l2, align 4
  %get26 = load i64, ptr %l3, align 4
  %get27 = load i64, ptr %l2, align 4
  %add28 = add i64 %get27, 31
  %get29 = load i64, ptr %l2, align 4
  %add30 = add i64 %get29, 31
  %get31 = load i64, ptr %l2, align 4
  %add32 = add i64 %get31, 8
  %lc33 = call i64 @f12(i64 %add30, i64 %add32, i64 2)
  %lc34 = call i64 @f11(i64 %add28, i64 %lc33, i64 1)
  store i64 %lc34, ptr %l4, align 4
  %get35 = load i64, ptr %l2, align 4
  %add36 = add i64 %get35, 32
  %get37 = load i64, ptr %l4, align 4
  ret i64 %get37

dead5:                                            ; No predecessors!
  br label %c1

dead6:                                            ; No predecessors!
  %bottom39 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom39
}

define void @f10(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  unreachable

exit:                                             ; No predecessors!
  ret void

dead1:                                            ; No predecessors!
  ret void
}

define i64 @f11(i64 %0, i64 %1, i64 %2) {
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

exit:                                             ; No predecessors!
  %bottom3 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom3
}

define i64 @f12(i64 %0, i64 %1, i64 %2) {
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

exit:                                             ; No predecessors!
  %bottom3 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom3
}

define i64 @f13(i64 %0, i64 %1, i64 %2, i64 %3, i64 %4) {
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

exit:                                             ; No predecessors!
  %bottom5 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom5
}

define void @f14(i64 %0, i64 %1, i64 %2) {
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
  call void @f23(i64 %bottom2, i64 %get3, i64 %bottom4)
  %get5 = load i64, ptr %l3, align 4
  %bottom6 = call i64 @ponytail.unknown.i64()
  %cmp = icmp ne i64 %bottom6, 1
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c2, label %fall3

exit:                                             ; No predecessors!
  ret void

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
  %lc = call i64 @f19(i64 %get7, i64 %get8, i64 %get9)
  store i64 %lc, ptr %l5, align 4
  br label %c1

dead4:                                            ; No predecessors!
  br label %c2
}

define i64 @f15(i64 %0, i64 %1) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  store i64 %1, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %get1 = load i64, ptr %l1, align 4
  %lc = call i64 @f20(i64 %get, i64 %get1)
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

exit:                                             ; No predecessors!
  %bottom2 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom2
}

define i64 @f16(i64 %0, i64 %1, i64 %2, i64 %3) {
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
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

exit:                                             ; No predecessors!
  %bottom4 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom4
}

define i64 @f17(i64 %0, i64 %1, i64 %2) {
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

exit:                                             ; No predecessors!
  %bottom5 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom5
}

define i64 @f18(i64 %0, i64 %1, i64 %2, i64 %3, i64 %4) {
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

exit:                                             ; No predecessors!
  %bottom = call i64 @ponytail.unknown.i64()
  ret i64 %bottom

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
  %bottom11 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom11

fall2:                                            ; preds = %entry
  unreachable

dead3:                                            ; No predecessors!
  br label %c1
}

define i64 @f19(i64 %0, i64 %1, i64 %2) {
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

exit:                                             ; No predecessors!
  %bottom5 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom5
}

define i64 @f20(i64 %0, i64 %1) {
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

exit:                                             ; No predecessors!
  %bottom1 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom1
}

define i64 @f21(i64 %0, i64 %1, i64 %2) {
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

exit:                                             ; No predecessors!
  %bottom2 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom2
}

define i64 @f22(i64 %0, i64 %1, i64 %2, i64 %3) {
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

exit:                                             ; No predecessors!
  %bottom4 = call i64 @ponytail.unknown.i64()
  ret i64 %bottom4
}

define void @f23(i64 %0, i64 %1, i64 %2) {
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

exit:                                             ; No predecessors!
  ret void

c1:                                               ; preds = %c2, %fall7
  %get48 = load i64, ptr %l0, align 4
  %get49 = load i64, ptr %l3, align 4
  %get50 = load i64, ptr %l0, align 4
  ret void

c2:                                               ; preds = %dead24, %c11
  %get45 = load i64, ptr %l3, align 4
  %shl46 = shl i64 %get45, 8
  %or47 = or i64 %shl46, 14
  store i64 %or47, ptr %l3, align 4
  br label %c1

c3:                                               ; preds = %c4, %c17
  %get44 = load i64, ptr %l0, align 4
  ret void

c4:                                               ; preds = %lc10, %entry
  %get41 = load i64, ptr %l0, align 4
  %get42 = load i64, ptr %l2, align 4
  %get43 = load i64, ptr %l0, align 4
  br label %c3

fall5:                                            ; preds = %entry
  %get1 = load i64, ptr %l2, align 4
  %brif2 = icmp ne i64 %get1, 0
  br i1 %brif2, label %c6, label %fall7

c6:                                               ; preds = %dead8, %fall5
  store i64 0, ptr %l3, align 4
  br label %h9

fall7:                                            ; preds = %fall5
  store i64 14, ptr %l3, align 4
  br label %c1

dead8:                                            ; No predecessors!
  br label %c6

h9:                                               ; preds = %fall22, %c6
  store i64 1, ptr %l4, align 4
  %get3 = load i64, ptr %l1, align 4
  %bottom = call i64 @ponytail.unknown.i64()
  store i64 %bottom, ptr %l5, align 4
  %cmp4 = icmp eq i64 %bottom, 95
  %zext5 = zext i1 %cmp4 to i64
  %brif6 = icmp ne i64 %zext5, 0
  br i1 %brif6, label %c11, label %fall12

lc10:                                             ; preds = %dead23
  br label %c4

c11:                                              ; preds = %c13, %c14, %fall18, %h9
  %get30 = load i64, ptr %l3, align 4
  %shl31 = shl i64 %get30, 6
  %get32 = load i64, ptr %l4, align 4
  %and33 = and i64 %get32, 255
  %or34 = or i64 %shl31, %and33
  store i64 %or34, ptr %l3, align 4
  %get35 = load i64, ptr %l1, align 4
  %add36 = add i64 %get35, 1
  store i64 %add36, ptr %l1, align 4
  %get37 = load i64, ptr %l2, align 4
  %add38 = add i64 %get37, -1
  store i64 %add38, ptr %l2, align 4
  %eqz = icmp eq i64 %add38, 0
  %zext39 = zext i1 %eqz to i64
  %brif40 = icmp ne i64 %zext39, 0
  br i1 %brif40, label %c2, label %fall22

fall12:                                           ; preds = %h9
  %get7 = load i64, ptr %l5, align 4
  %add = add i64 %get7, -48
  %and = and i64 %add, 255
  %cmp8 = icmp ult i64 %and, 10
  %zext9 = zext i1 %cmp8 to i64
  %brif10 = icmp ne i64 %zext9, 0
  br i1 %brif10, label %c14, label %fall15

c13:                                              ; preds = %dead21, %fall15
  %get28 = load i64, ptr %l5, align 4
  %add29 = add i64 %get28, -53
  store i64 %add29, ptr %l4, align 4
  br label %c11

c14:                                              ; preds = %dead20, %fall12
  %get26 = load i64, ptr %l5, align 4
  %add27 = add i64 %get26, -46
  store i64 %add27, ptr %l4, align 4
  br label %c11

fall15:                                           ; preds = %fall12
  %get11 = load i64, ptr %l5, align 4
  %add12 = add i64 %get11, -65
  %and13 = and i64 %add12, 255
  %cmp14 = icmp ult i64 %and13, 26
  %zext15 = zext i1 %cmp14 to i64
  %brif16 = icmp ne i64 %zext15, 0
  br i1 %brif16, label %c13, label %fall16

fall16:                                           ; preds = %fall15
  %get17 = load i64, ptr %l5, align 4
  %add18 = add i64 %get17, -97
  %and19 = and i64 %add18, 255
  %bottom20 = call i64 @ponytail.unknown.i64()
  %brif21 = icmp ne i64 %bottom20, 0
  br i1 %brif21, label %c17, label %fall18

c17:                                              ; preds = %dead19, %fall16
  %get24 = load i64, ptr %l0, align 4
  %get25 = load i64, ptr %l5, align 4
  %shl = shl i64 %get25, 8
  %or = or i64 %shl, 1
  br label %c3

fall18:                                           ; preds = %fall16
  %get22 = load i64, ptr %l5, align 4
  %add23 = add i64 %get22, -59
  store i64 %add23, ptr %l4, align 4
  br label %c11

dead19:                                           ; No predecessors!
  br label %c17

dead20:                                           ; No predecessors!
  br label %c14

dead21:                                           ; No predecessors!
  br label %c13

fall22:                                           ; preds = %c11
  br label %h9

dead23:                                           ; No predecessors!
  br label %lc10

dead24:                                           ; No predecessors!
  br label %c2
}

define void @f24(i64 %0, i64 %1, i64 %2) {
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
  unreachable

exit:                                             ; No predecessors!
  ret void

dead1:                                            ; No predecessors!
  ret void
}

define void @f25(i64 %0, i64 %1, i64 %2) {
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
  call void @f10(i64 %add10)
  unreachable

exit:                                             ; No predecessors!
  ret void

dead1:                                            ; No predecessors!
  ret void
}
