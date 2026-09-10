; ModuleID = 'ponytail'
source_filename = "ponytail"

%Val = type { i64 }

@g0 = global i64 1048576
@g1 = constant i64 1048604
@g2 = constant i64 1048604
@g3 = constant i64 1048608

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

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @context.fail_with_error(%Val) #3

; Function Attrs: memory(inaccessiblemem: readwrite)
declare %Val @ledger.put_contract_data(%Val, %Val, i64) #4

define "spec.type"="Result<Symbol, Error>" "wasm.type"="i64" %Val @hello(%Val "spec.name"="flag" "spec.type"="Flag" "wasm.type"="i64" %0) #5 {
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
  call void @soroban.trap()
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
  call void @soroban.trap()
  unreachable

c8:                                               ; preds = %fall4
  call void @f4()
  call void @soroban.trap()
  unreachable

c9:                                               ; preds = %fall4
  call void @f3(i64 4294967299)
  call void @soroban.trap()
  unreachable
}

define void @f3(i64 "wasm.type"="i64" %0) {
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
  call void @soroban.trap()
  unreachable
}

attributes #0 = { nounwind willreturn memory(none) }
attributes #1 = { memory(inaccessiblemem: readwrite) }
attributes #2 = { noreturn }
attributes #3 = { memory(inaccessiblemem: readwrite) "soroban.import"="x.5" "soroban.sig"="(Error) -> Void" }
attributes #4 = { memory(inaccessiblemem: readwrite) "soroban.import"="l._" "soroban.sig"="(Val, Val, StorageType) -> Void" }
attributes #5 = { "spec.sig"="fn hello(flag: Flag) -> Result<Symbol, Error>" }

!soroban.spec = !{!0, !1, !2}

!0 = !{!"enum Flag { A = 0, B = 1, C = 2, D = 3, E = 4 }"}
!1 = !{!"error Error { AnError = 1 }"}
!2 = !{!"fn hello(flag: Flag) -> Result<Symbol, Error>"}
