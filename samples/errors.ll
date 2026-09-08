; ModuleID = 'ponytail'
source_filename = "ponytail"

%Val = type { i64 }

declare %Val @soroban.val.from_payload(i64)

declare i64 @soroban.val.payload(%Val)

declare i64 @soroban.storage_type(i64)

declare %Val @ponytail.unknown()

declare i64 @ponytail.unknown.i64()

declare %Val @context.fail_with_error(%Val) #0

declare %Val @ledger.put_contract_data(%Val, %Val, i64) #1

define %Val @hello(%Val %0) {
entry:
  %l0 = alloca i64, align 8
  %l1 = alloca i64, align 8
  %arg_payload = call i64 @soroban.val.payload(%Val %0)
  store i64 %arg_payload, ptr %l0, align 4
  store i64 0, ptr %l1, align 4
  %get = load i64, ptr %l0, align 4
  %cmp = icmp ugt i64 %get, 21474836479
  %zext = zext i1 %cmp to i64
  %brif = icmp ne i64 %zext, 0
  br i1 %brif, label %c1, label %fall2

c1:                                               ; preds = %fall3, %fall2, %entry
  unreachable

fall2:                                            ; preds = %entry
  %get1 = load i64, ptr %l0, align 4
  %and = and i64 %get1, 255
  %cmp2 = icmp ne i64 %and, 4
  %zext3 = zext i1 %cmp2 to i64
  %brif4 = icmp ne i64 %zext3, 0
  br i1 %brif4, label %c1, label %fall3

fall3:                                            ; preds = %fall2
  %get5 = load i64, ptr %l0, align 4
  %lshr = lshr i64 %get5, 32
  %and6 = and i64 %lshr, 255
  store i64 %and6, ptr %l1, align 4
  %cmp7 = icmp eq i64 %and6, 5
  %zext8 = zext i1 %cmp7 to i64
  %brif9 = icmp ne i64 %zext8, 0
  br i1 %brif9, label %c1, label %fall4

fall4:                                            ; preds = %fall3
  %v_Symbol__persisted__ = call %Val @soroban.val.from_payload(i64 3867323444879862030)
  %v_true = call %Val @soroban.val.from_payload(i64 1)
  %Persistent = call i64 @soroban.storage_type(i64 1)
  %put_contract_data = call %Val @ledger.put_contract_data(%Val %v_Symbol__persisted__, %Val %v_true, i64 %Persistent)
  store i64 4294967299, ptr %l0, align 4
  %get10 = load i64, ptr %l1, align 4
  %sel = trunc i64 %get10 to i32
  switch i32 %sel, label %c7 [
    i32 0, label %c6
    i32 1, label %c5
    i32 2, label %c9
    i32 3, label %c8
  ]

c5:                                               ; preds = %c6, %fall4
  %get11 = load i64, ptr %l0, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get11)
  ret %Val %to_val

c6:                                               ; preds = %fall4
  store i64 196144296974, ptr %l0, align 4
  br label %c5

c7:                                               ; preds = %fall4
  call void @f3(i64 38654705667)
  unreachable

c8:                                               ; preds = %fall4
  call void @f4()
  unreachable

c9:                                               ; preds = %fall4
  call void @f3(i64 4294967299)
  unreachable
}

define void @f3(i64 %0) {
entry:
  %l0 = alloca i64, align 8
  store i64 %0, ptr %l0, align 4
  %get = load i64, ptr %l0, align 4
  %to_val = call %Val @soroban.val.from_payload(i64 %get)
  %fail_with_error = call %Val @context.fail_with_error(%Val %to_val)
  ret void
}

define void @f4() {
entry:
  unreachable
}

attributes #0 = { "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #1 = { "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
