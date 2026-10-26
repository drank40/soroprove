(module
  (type (;0;) (func (param i64 i64) (result i64)))
  (type (;1;) (func (param i64) (result i64)))
  (type (;2;) (func (param i32)))
  (type (;3;) (func (param i32 i64)))
  (type (;4;) (func (param i64 i64)))
  (type (;5;) (func (param i64 i64 i64)))
  (type (;6;) (func (param i64 i64 i64 i64) (result i64)))
  (type (;7;) (func (param i32 i64 i64 i64 i64)))
  (type (;8;) (func (param i64 i64 i64) (result i64)))
  (type (;9;) (func (result i64)))
  (type (;10;) (func (param i64 i64 i64 i64 i64)))
  (type (;11;) (func (param i32 i64 i64 i32)))
  (type (;12;) (func (param i64 i64) (result i32)))
  (type (;13;) (func (param i32 i32) (result i64)))
  (type (;14;) (func (param i32 i32 i64 i64 i64 i64 i64 i64)))
  (type (;15;) (func (param i64 i64 i64 i64)))
  (type (;16;) (func (param i32 i64 i64)))
  (type (;17;) (func (param i32 i32 i32)))
  (type (;18;) (func (param i64 i64 i64 i64 i64) (result i64)))
  (type (;19;) (func (param i32 i64 i64 i64 i64 i32)))
  (import "l" "1" (func (;0;) (type 0)))
  (import "l" "_" (func (;1;) (type 8)))
  (import "d" "_" (func (;2;) (type 8)))
  (import "x" "7" (func (;3;) (type 9)))
  (import "x" "0" (func (;4;) (type 0)))
  (import "a" "0" (func (;5;) (type 1)))
  (import "v" "g" (func (;6;) (type 0)))
  (import "l" "0" (func (;7;) (type 0)))
  (import "i" "8" (func (;8;) (type 1)))
  (import "i" "7" (func (;9;) (type 1)))
  (import "i" "6" (func (;10;) (type 0)))
  (import "b" "j" (func (;11;) (type 0)))
  (func (;12;) (type 0) (param i64 i64) (result i64)
    (local i32 i32)
    global.get 0
    i32.const 16
    i32.sub
    local.tee 2
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          block  ;; label = @4
            block  ;; label = @5
              block  ;; label = @6
                block  ;; label = @7
                  block  ;; label = @8
                    block  ;; label = @9
                      local.get 0
                      i32.wrap_i64
                      i32.const 1
                      i32.sub
                      br_table 1 (;@8;) 2 (;@7;) 3 (;@6;) 4 (;@5;) 5 (;@4;) 0 (;@9;)
                    end
                    local.get 2
                    i32.const 1048576
                    i32.const 6
                    call 38
                    br 5 (;@3;)
                  end
                  local.get 2
                  i32.const 1048582
                  i32.const 6
                  call 38
                  br 4 (;@3;)
                end
                local.get 2
                i32.const 1048588
                i32.const 11
                call 38
                br 3 (;@3;)
              end
              local.get 2
              i32.const 1048599
              i32.const 8
              call 38
              br 2 (;@3;)
            end
            local.get 2
            i32.const 1048607
            i32.const 8
            call 38
            br 1 (;@3;)
          end
          local.get 2
          i32.const 1048615
          i32.const 6
          call 38
          local.get 2
          i32.load
          br_if 1 (;@2;)
          local.get 2
          i64.load offset=8
          local.set 0
          local.get 2
          local.get 1
          i64.store offset=8
          local.get 2
          local.get 0
          i64.store
          local.get 2
          i32.const 2
          call 20
          local.set 0
          br 2 (;@1;)
        end
        local.get 2
        i32.load
        br_if 0 (;@2;)
        local.get 2
        i64.load offset=8
        local.set 0
        global.get 0
        i32.const 16
        i32.sub
        local.tee 3
        global.set 0
        local.get 3
        local.get 0
        i64.store offset=8
        local.get 3
        i32.const 8
        i32.add
        i32.const 1
        call 20
        local.set 0
        local.get 2
        i64.const 0
        i64.store
        local.get 2
        local.get 0
        i64.store offset=8
        local.get 3
        i32.const 16
        i32.add
        global.set 0
        local.get 2
        i64.load offset=8
        local.set 0
        local.get 2
        i64.load
        i64.eqz
        br_if 1 (;@1;)
      end
      unreachable
    end
    local.get 2
    i32.const 16
    i32.add
    global.set 0
    local.get 0)
  (func (;13;) (type 12) (param i64 i64) (result i32)
    local.get 0
    local.get 1
    call 7
    i64.const 1
    i64.eq)
  (func (;14;) (type 3) (param i32 i64)
    (local i32 i64)
    local.get 0
    block (result i64)  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          local.get 1
          i32.wrap_i64
          i32.const 255
          i32.and
          local.tee 2
          i32.const 69
          i32.ne
          if  ;; label = @4
            local.get 2
            i32.const 11
            i32.ne
            br_if 2 (;@2;)
            local.get 0
            local.get 1
            i64.const 63
            i64.shr_s
            i64.store offset=24
            local.get 0
            local.get 1
            i64.const 8
            i64.shr_s
            i64.store offset=16
            br 1 (;@3;)
          end
          local.get 1
          call 8
          local.set 3
          local.get 1
          call 9
          local.set 1
          local.get 0
          local.get 3
          i64.store offset=24
          local.get 0
          local.get 1
          i64.store offset=16
        end
        i64.const 0
        br 1 (;@1;)
      end
      local.get 0
      i64.const 34359740419
      i64.store offset=8
      i64.const 1
    end
    i64.store)
  (func (;15;) (type 4) (param i64 i64)
    local.get 0
    local.get 1
    call 12
    local.get 1
    i64.const 2
    call 1
    drop)
  (func (;16;) (type 5) (param i64 i64 i64)
    local.get 0
    local.get 2
    local.get 1
    local.get 2
    i64.const 2
    call 17)
  (func (;17;) (type 10) (param i64 i64 i64 i64 i64)
    local.get 0
    local.get 1
    call 12
    local.get 2
    local.get 3
    call 18
    local.get 4
    call 1
    drop)
  (func (;18;) (type 0) (param i64 i64) (result i64)
    (local i32)
    global.get 0
    i32.const 16
    i32.sub
    local.tee 2
    global.set 0
    local.get 2
    local.get 0
    local.get 1
    call 37
    local.get 2
    i64.load
    i64.const 1
    i64.eq
    if  ;; label = @1
      unreachable
    end
    local.get 2
    i64.load offset=8
    local.get 2
    i32.const 16
    i32.add
    global.set 0)
  (func (;19;) (type 10) (param i64 i64 i64 i64 i64)
    (local i32 i32)
    global.get 0
    i32.const 48
    i32.sub
    local.tee 6
    global.set 0
    local.get 6
    local.get 3
    local.get 4
    call 18
    i64.store offset=16
    local.get 6
    local.get 2
    i64.store offset=8
    local.get 6
    local.get 1
    i64.store
    loop  ;; label = @1
      local.get 5
      i32.const 24
      i32.eq
      if  ;; label = @2
        block  ;; label = @3
          i32.const 0
          local.set 5
          loop  ;; label = @4
            local.get 5
            i32.const 24
            i32.ne
            if  ;; label = @5
              local.get 6
              i32.const 24
              i32.add
              local.get 5
              i32.add
              local.get 5
              local.get 6
              i32.add
              i64.load
              i64.store
              local.get 5
              i32.const 8
              i32.add
              local.set 5
              br 1 (;@4;)
            end
          end
          local.get 0
          i64.const 65154533130155790
          local.get 6
          i32.const 24
          i32.add
          i32.const 3
          call 20
          call 2
          i64.const 255
          i64.and
          i64.const 2
          i64.ne
          br_if 0 (;@3;)
          local.get 6
          i32.const 48
          i32.add
          global.set 0
          return
        end
      else
        local.get 6
        i32.const 24
        i32.add
        local.get 5
        i32.add
        i64.const 2
        i64.store
        local.get 5
        i32.const 8
        i32.add
        local.set 5
        br 1 (;@1;)
      end
    end
    unreachable)
  (func (;20;) (type 13) (param i32 i32) (result i64)
    local.get 0
    i64.extend_i32_u
    i64.const 32
    i64.shl
    i64.const 4
    i64.or
    local.get 1
    i64.extend_i32_u
    i64.const 32
    i64.shl
    i64.const 4
    i64.or
    call 6)
  (func (;21;) (type 14) (param i32 i32 i64 i64 i64 i64 i64 i64)
    (local i32 i32 i64)
    global.get 0
    i32.const 96
    i32.sub
    local.tee 8
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        local.get 3
        local.get 5
        i64.xor
        local.get 3
        local.get 3
        local.get 5
        i64.sub
        local.get 2
        local.get 4
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        local.tee 10
        i64.xor
        i64.and
        i64.const 0
        i64.lt_s
        br_if 0 (;@2;)
        local.get 7
        local.get 10
        i64.xor
        local.get 10
        local.get 10
        local.get 7
        i64.sub
        local.get 2
        local.get 4
        i64.sub
        local.tee 2
        local.get 6
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        local.tee 3
        i64.xor
        i64.and
        i64.const 0
        i64.lt_s
        br_if 0 (;@2;)
        block (result i64)  ;; label = @3
          local.get 2
          local.get 6
          i64.sub
          local.tee 6
          local.get 1
          i32.load
          local.tee 9
          i64.load
          i64.gt_u
          local.get 3
          local.get 9
          i64.load offset=8
          local.tee 2
          i64.gt_s
          local.get 2
          local.get 3
          i64.eq
          select
          i32.eqz
          if  ;; label = @4
            local.get 8
            i32.const 0
            i32.store offset=92
            local.get 8
            i32.const -64
            i32.sub
            local.get 1
            i32.load offset=8
            local.tee 1
            i64.load
            local.tee 2
            local.get 1
            i64.load offset=8
            local.tee 7
            local.get 6
            local.get 3
            local.get 8
            i32.const 92
            i32.add
            call 48
            local.get 8
            i32.load offset=92
            br_if 2 (;@2;)
            local.get 8
            i64.load offset=64
            local.set 6
            local.get 8
            i64.load offset=72
            br 1 (;@3;)
          end
          local.get 8
          i32.const 0
          i32.store offset=60
          local.get 8
          i32.const 32
          i32.add
          local.get 1
          i32.load offset=4
          local.tee 9
          i64.load
          local.get 9
          i64.load offset=8
          local.get 6
          local.get 3
          local.get 8
          i32.const 60
          i32.add
          call 48
          local.get 8
          i32.load offset=60
          br_if 1 (;@2;)
          local.get 8
          i64.load offset=32
          local.set 6
          local.get 1
          i32.load offset=8
          local.tee 1
          i64.load offset=8
          local.set 7
          local.get 1
          i64.load
          local.set 2
          local.get 8
          i64.load offset=40
        end
        local.set 3
        local.get 8
        i32.const 0
        i32.store offset=28
        local.get 8
        local.get 2
        local.get 7
        local.get 4
        local.get 5
        local.get 8
        i32.const 28
        i32.add
        call 48
        local.get 8
        i32.load offset=28
        br_if 0 (;@2;)
        local.get 8
        i64.load offset=8
        local.tee 2
        local.get 3
        i64.xor
        i64.const -1
        i64.xor
        local.get 2
        local.get 8
        i64.load
        local.tee 4
        local.get 6
        i64.add
        local.tee 5
        local.get 4
        i64.lt_u
        i64.extend_i32_u
        local.get 2
        local.get 3
        i64.add
        i64.add
        local.tee 3
        i64.xor
        i64.and
        i64.const 0
        i64.ge_s
        br_if 1 (;@1;)
      end
      unreachable
    end
    local.get 0
    local.get 5
    i64.store
    local.get 0
    local.get 3
    i64.store offset=8
    local.get 8
    i32.const 96
    i32.add
    global.set 0)
  (func (;22;) (type 3) (param i32 i64)
    (local i32 i64)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 2
    global.set 0
    block  ;; label = @1
      local.get 0
      i64.const 5
      local.get 1
      call 12
      local.tee 1
      i64.const 1
      call 13
      if (result i64)  ;; label = @2
        local.get 2
        local.get 1
        i64.const 1
        call 0
        call 14
        local.get 2
        i64.load
        i64.const 1
        i64.eq
        br_if 1 (;@1;)
        local.get 2
        i64.load offset=24
        local.set 3
        local.get 2
        i64.load offset=16
      else
        i64.const 0
      end
      i64.store
      local.get 0
      local.get 3
      i64.store offset=8
      local.get 2
      i32.const 32
      i32.add
      global.set 0
      return
    end
    unreachable)
  (func (;23;) (type 5) (param i64 i64 i64)
    i64.const 5
    local.get 0
    local.get 1
    local.get 2
    i64.const 1
    call 17)
  (func (;24;) (type 5) (param i64 i64 i64)
    i64.const 0
    call 53
    local.get 0
    local.get 1
    local.get 2
    call 25)
  (func (;25;) (type 15) (param i64 i64 i64 i64)
    local.get 0
    call 3
    local.get 1
    local.get 2
    local.get 3
    call 19)
  (func (;26;) (type 5) (param i64 i64 i64)
    i64.const 1
    call 53
    local.get 0
    local.get 1
    local.get 2
    call 25)
  (func (;27;) (type 3) (param i32 i64)
    (local i32)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 2
    global.set 0
    local.get 2
    call 3
    i64.store
    local.get 2
    local.get 1
    i64.const 696753673873934
    local.get 2
    i32.const 1
    call 20
    call 2
    call 14
    local.get 2
    i64.load
    i64.const 1
    i64.eq
    if  ;; label = @1
      unreachable
    end
    local.get 2
    i64.load offset=16
    local.set 1
    local.get 0
    local.get 2
    i64.load offset=24
    i64.store offset=8
    local.get 0
    local.get 1
    i64.store
    local.get 2
    i32.const 32
    i32.add
    global.set 0)
  (func (;28;) (type 2) (param i32)
    local.get 0
    i64.const 0
    call 53
    call 27)
  (func (;29;) (type 2) (param i32)
    local.get 0
    i64.const 1
    call 53
    call 27)
  (func (;30;) (type 2) (param i32)
    local.get 0
    i64.const 3
    call 54)
  (func (;31;) (type 2) (param i32)
    local.get 0
    i64.const 4
    call 54)
  (func (;32;) (type 4) (param i64 i64)
    i64.const 3
    local.get 0
    local.get 1
    call 16)
  (func (;33;) (type 4) (param i64 i64)
    i64.const 4
    local.get 0
    local.get 1
    call 16)
  (func (;34;) (type 2) (param i32)
    local.get 0
    i64.const 2
    call 54)
  (func (;35;) (type 4) (param i64 i64)
    i64.const 2
    local.get 0
    local.get 1
    call 16)
  (func (;36;) (type 6) (param i64 i64 i64 i64) (result i64)
    (local i32 i32)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 4
    global.set 0
    local.get 4
    i32.const 16
    i32.add
    local.tee 5
    local.get 0
    local.get 1
    call 37
    block  ;; label = @1
      local.get 4
      i32.load offset=16
      i32.eqz
      if  ;; label = @2
        local.get 4
        i64.load offset=24
        local.set 0
        local.get 5
        local.get 2
        local.get 3
        call 37
        local.get 4
        i64.load offset=16
        i64.const 1
        i64.ne
        br_if 1 (;@1;)
      end
      unreachable
    end
    local.get 4
    local.get 4
    i64.load offset=24
    i64.store offset=8
    local.get 4
    local.get 0
    i64.store
    local.get 4
    i32.const 2
    call 20
    local.get 4
    i32.const 32
    i32.add
    global.set 0)
  (func (;37;) (type 16) (param i32 i64 i64)
    local.get 1
    i64.const 63
    i64.shr_s
    local.get 2
    i64.xor
    i64.const 0
    i64.ne
    local.get 1
    i64.const -36028797018963968
    i64.sub
    i64.const 72057594037927935
    i64.gt_u
    i32.or
    if (result i64)  ;; label = @1
      local.get 2
      local.get 1
      call 10
    else
      local.get 1
      i64.const 8
      i64.shl
      i64.const 11
      i64.or
    end
    local.set 1
    local.get 0
    i64.const 0
    i64.store
    local.get 0
    local.get 1
    i64.store offset=8)
  (func (;38;) (type 17) (param i32 i32 i32)
    (local i32 i32 i32 i64)
    block (result i64)  ;; label = @1
      block  ;; label = @2
        local.get 2
        i32.const 9
        i32.gt_u
        br_if 0 (;@2;)
        local.get 2
        local.set 4
        local.get 1
        local.set 5
        loop  ;; label = @3
          local.get 6
          i64.const 8
          i64.shl
          i64.const 14
          i64.or
          local.get 4
          i32.eqz
          br_if 2 (;@1;)
          drop
          block (result i32)  ;; label = @4
            i32.const 1
            local.get 5
            i32.load8_u
            local.tee 3
            i32.const 95
            i32.eq
            br_if 0 (;@4;)
            drop
            block  ;; label = @5
              local.get 3
              i32.const 48
              i32.sub
              i32.const 255
              i32.and
              i32.const 10
              i32.ge_u
              if  ;; label = @6
                local.get 3
                i32.const 65
                i32.sub
                i32.const 255
                i32.and
                i32.const 26
                i32.lt_u
                br_if 1 (;@5;)
                local.get 3
                i32.const 97
                i32.sub
                i32.const 255
                i32.and
                i32.const 26
                i32.ge_u
                br_if 4 (;@2;)
                local.get 3
                i32.const 59
                i32.sub
                br 2 (;@4;)
              end
              local.get 3
              i32.const 46
              i32.sub
              br 1 (;@4;)
            end
            local.get 3
            i32.const 53
            i32.sub
          end
          i64.extend_i32_u
          i64.const 255
          i64.and
          local.get 6
          i64.const 6
          i64.shl
          i64.or
          local.set 6
          local.get 4
          i32.const 1
          i32.sub
          local.set 4
          local.get 5
          i32.const 1
          i32.add
          local.set 5
          br 0 (;@3;)
        end
        unreachable
      end
      local.get 1
      i64.extend_i32_u
      i64.const 32
      i64.shl
      i64.const 4
      i64.or
      local.get 2
      i64.extend_i32_u
      i64.const 32
      i64.shl
      i64.const 4
      i64.or
      call 11
    end
    local.set 6
    local.get 0
    i64.const 0
    i64.store
    local.get 0
    local.get 6
    i64.store offset=8)
  (func (;39;) (type 0) (param i64 i64) (result i64)
    block  ;; label = @1
      local.get 0
      i64.const 255
      i64.and
      i64.const 77
      i64.ne
      local.get 1
      i64.const 255
      i64.and
      i64.const 77
      i64.ne
      i32.or
      i32.eqz
      if  ;; label = @2
        local.get 0
        local.get 1
        call 4
        i64.const 0
        i64.ge_s
        br_if 1 (;@1;)
        i64.const 0
        local.get 0
        call 15
        i64.const 1
        local.get 1
        call 15
        i64.const 0
        i64.const 0
        call 35
        i64.const 0
        i64.const 0
        call 32
        i64.const 0
        i64.const 0
        call 33
        i64.const 2
        return
      end
      unreachable
    end
    unreachable)
  (func (;40;) (type 1) (param i64) (result i64)
    (local i32)
    global.get 0
    i32.const 16
    i32.sub
    local.tee 1
    global.set 0
    local.get 0
    i64.const 255
    i64.and
    i64.const 77
    i64.ne
    if  ;; label = @1
      unreachable
    end
    local.get 1
    local.get 0
    call 22
    local.get 1
    i64.load
    local.get 1
    i64.load offset=8
    call 18
    local.get 1
    i32.const 16
    i32.add
    global.set 0)
  (func (;41;) (type 18) (param i64 i64 i64 i64 i64) (result i64)
    (local i32 i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    global.get 0
    i32.const 352
    i32.sub
    local.tee 5
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          block  ;; label = @4
            block  ;; label = @5
              local.get 0
              i64.const 255
              i64.and
              i64.const 77
              i64.ne
              br_if 0 (;@5;)
              local.get 5
              i32.const 320
              i32.add
              local.tee 6
              local.get 1
              call 14
              local.get 5
              i64.load offset=320
              i64.const 1
              i64.eq
              br_if 0 (;@5;)
              local.get 5
              i64.load offset=344
              local.set 12
              local.get 5
              i64.load offset=336
              local.set 14
              local.get 6
              local.get 2
              call 14
              local.get 5
              i64.load offset=320
              i64.const 1
              i64.eq
              br_if 0 (;@5;)
              local.get 5
              i64.load offset=344
              local.set 16
              local.get 5
              i64.load offset=336
              local.set 17
              local.get 6
              local.get 3
              call 14
              local.get 5
              i64.load offset=320
              i64.const 1
              i64.eq
              br_if 0 (;@5;)
              local.get 5
              i64.load offset=344
              local.set 1
              local.get 5
              i64.load offset=336
              local.set 13
              local.get 6
              local.get 4
              call 14
              local.get 5
              i64.load offset=320
              i64.const 1
              i64.eq
              br_if 0 (;@5;)
              local.get 5
              i64.load offset=344
              local.set 4
              local.get 5
              i64.load offset=336
              local.set 18
              local.get 0
              call 5
              drop
              local.get 6
              call 30
              local.get 5
              i64.load offset=320
              local.set 10
              local.get 5
              i64.load offset=328
              local.set 9
              local.get 6
              call 31
              block  ;; label = @6
                local.get 10
                local.get 5
                i64.load offset=320
                local.tee 15
                i64.or
                local.get 9
                local.get 5
                i64.load offset=328
                local.tee 11
                i64.or
                i64.or
                i64.eqz
                if  ;; label = @7
                  local.get 13
                  local.set 2
                  local.get 1
                  local.set 3
                  br 1 (;@6;)
                end
                local.get 5
                i32.const 0
                i32.store offset=316
                local.get 5
                i32.const 288
                i32.add
                local.get 14
                local.get 12
                local.get 15
                local.get 11
                local.get 5
                i32.const 316
                i32.add
                call 48
                local.get 5
                i32.load offset=316
                local.get 9
                local.get 10
                i64.or
                i64.eqz
                i32.or
                br_if 4 (;@2;)
                local.get 5
                i64.load offset=288
                local.tee 2
                local.get 5
                i64.load offset=296
                local.tee 3
                i64.const -9223372036854775808
                i64.xor
                i64.or
                i64.eqz
                local.get 9
                local.get 10
                i64.and
                i64.const -1
                i64.eq
                i32.and
                br_if 4 (;@2;)
                local.get 5
                i32.const 272
                i32.add
                local.get 2
                local.get 3
                local.get 10
                local.get 9
                call 51
                local.get 5
                i64.load offset=272
                local.tee 2
                local.get 13
                i64.gt_u
                local.get 5
                i64.load offset=280
                local.tee 3
                local.get 1
                i64.gt_s
                local.get 1
                local.get 3
                i64.eq
                select
                if  ;; label = @7
                  local.get 5
                  i32.const 0
                  i32.store offset=268
                  local.get 5
                  i32.const 240
                  i32.add
                  local.get 13
                  local.get 1
                  local.get 10
                  local.get 9
                  local.get 5
                  i32.const 268
                  i32.add
                  call 48
                  local.get 5
                  i32.load offset=268
                  local.get 11
                  local.get 15
                  i64.or
                  i64.eqz
                  i32.or
                  br_if 5 (;@2;)
                  local.get 5
                  i64.load offset=240
                  local.tee 2
                  local.get 5
                  i64.load offset=248
                  local.tee 3
                  i64.const -9223372036854775808
                  i64.xor
                  i64.or
                  i64.eqz
                  local.get 11
                  local.get 15
                  i64.and
                  i64.const -1
                  i64.eq
                  i32.and
                  br_if 5 (;@2;)
                  local.get 5
                  i32.const 224
                  i32.add
                  local.get 2
                  local.get 3
                  local.get 15
                  local.get 11
                  call 51
                  local.get 14
                  local.get 5
                  i64.load offset=224
                  local.tee 14
                  i64.lt_u
                  local.get 5
                  i64.load offset=232
                  local.tee 4
                  local.get 12
                  i64.gt_s
                  local.get 4
                  local.get 12
                  i64.eq
                  select
                  br_if 6 (;@1;)
                  local.get 13
                  local.set 2
                  local.get 1
                  local.set 3
                  local.get 14
                  local.get 17
                  i64.lt_u
                  local.get 4
                  local.tee 12
                  local.get 16
                  i64.lt_s
                  local.get 4
                  local.get 16
                  i64.eq
                  select
                  i32.eqz
                  br_if 1 (;@6;)
                  br 6 (;@1;)
                end
                local.get 2
                local.get 18
                i64.lt_u
                local.get 3
                local.get 4
                i64.lt_s
                local.get 3
                local.get 4
                i64.eq
                select
                br_if 5 (;@1;)
              end
              local.get 2
              i64.const 0
              i64.ne
              local.get 3
              i64.const 0
              i64.gt_s
              local.get 3
              i64.eqz
              select
              i32.eqz
              local.get 14
              i64.eqz
              local.get 12
              i64.const 0
              i64.lt_s
              local.get 12
              i64.eqz
              select
              i32.or
              br_if 4 (;@1;)
              i64.const 0
              call 53
              i64.const 1
              call 53
              local.set 4
              local.get 0
              call 3
              local.get 14
              local.get 12
              call 19
              local.get 4
              local.get 0
              call 3
              local.get 2
              local.get 3
              call 19
              local.get 5
              i32.const 320
              i32.add
              local.tee 6
              call 28
              local.get 5
              i64.load offset=328
              local.set 12
              local.get 5
              i64.load offset=320
              local.set 14
              local.get 6
              call 29
              local.get 5
              i64.load offset=328
              local.set 16
              local.get 5
              i64.load offset=320
              local.set 17
              local.get 6
              call 34
              local.get 5
              i64.load offset=328
              local.set 3
              local.get 5
              i64.load offset=320
              local.set 13
              local.get 10
              i64.eqz
              local.get 9
              i64.const 0
              i64.lt_s
              local.get 9
              i64.eqz
              select
              i32.const 1
              local.get 15
              i64.const 0
              i64.ne
              local.get 11
              i64.const 0
              i64.gt_s
              local.get 11
              i64.eqz
              select
              select
              if  ;; label = @6
                local.get 5
                i32.const 0
                i32.store offset=220
                local.get 5
                i32.const 192
                i32.add
                local.get 14
                local.get 12
                local.get 17
                local.get 16
                local.get 5
                i32.const 220
                i32.add
                call 48
                local.get 5
                i32.load offset=220
                br_if 4 (;@2;)
                local.get 5
                i64.load offset=200
                local.tee 1
                i64.const 0
                i64.lt_s
                br_if 2 (;@4;)
                local.get 5
                i64.load offset=192
                local.set 4
                local.get 1
                i64.eqz
                i32.eqz
                if  ;; label = @7
                  local.get 5
                  i32.const 176
                  i32.add
                  local.get 1
                  local.get 1
                  i64.clz
                  local.get 4
                  i64.clz
                  i64.const -64
                  i64.sub
                  local.get 1
                  i64.const 0
                  i64.ne
                  select
                  local.tee 1
                  i64.const 62
                  i64.and
                  local.tee 10
                  i64.shl
                  local.get 4
                  i64.const 1
                  i64.shr_u
                  local.get 1
                  i32.wrap_i64
                  local.tee 8
                  i32.const 62
                  i32.and
                  i32.const 63
                  i32.xor
                  i64.extend_i32_u
                  i64.shr_u
                  i64.or
                  local.tee 2
                  call 42
                  local.tee 1
                  i64.const 0
                  local.get 1
                  i64.const 0
                  call 47
                  local.get 1
                  i64.eqz
                  local.get 2
                  local.get 5
                  i64.load offset=176
                  local.tee 11
                  i64.lt_u
                  local.tee 7
                  local.get 5
                  i64.load offset=184
                  local.tee 9
                  i64.const 0
                  i64.ne
                  local.get 9
                  i64.eqz
                  select
                  i32.or
                  br_if 5 (;@2;)
                  global.get 0
                  i32.const 32
                  i32.sub
                  local.tee 6
                  global.set 0
                  local.get 6
                  local.get 2
                  local.get 11
                  i64.sub
                  local.tee 2
                  i64.const 32
                  i64.shl
                  local.get 4
                  local.get 10
                  i64.shl
                  local.tee 15
                  i64.const 32
                  i64.shr_u
                  i64.or
                  local.tee 10
                  local.get 2
                  i64.const 32
                  i64.shr_u
                  local.get 9
                  local.get 7
                  i64.extend_i32_u
                  i64.add
                  i64.const 32
                  i64.shl
                  i64.sub
                  local.tee 18
                  local.get 1
                  i64.const 1
                  i64.shl
                  local.tee 11
                  i64.const 0
                  call 49
                  local.get 6
                  i64.load
                  local.set 2
                  local.get 5
                  i32.const 160
                  i32.add
                  local.tee 7
                  local.get 6
                  i64.load offset=8
                  i64.store offset=8
                  local.get 7
                  local.get 2
                  i64.store
                  local.get 6
                  i32.const 32
                  i32.add
                  global.set 0
                  local.get 5
                  i32.const 128
                  i32.add
                  local.get 5
                  i64.load offset=168
                  local.tee 4
                  i64.const 0
                  local.get 5
                  i64.load offset=160
                  local.tee 2
                  i64.const 0
                  call 47
                  local.get 5
                  i32.const 144
                  i32.add
                  local.get 2
                  i64.const 0
                  local.get 2
                  i64.const 0
                  call 47
                  local.get 4
                  local.get 5
                  i64.load offset=136
                  i64.or
                  i64.const 0
                  i64.ne
                  local.get 5
                  i64.load offset=152
                  local.tee 19
                  local.get 5
                  i64.load offset=128
                  local.tee 9
                  local.get 9
                  i64.add
                  i64.add
                  local.tee 9
                  local.get 19
                  i64.lt_u
                  i32.or
                  br_if 5 (;@2;)
                  local.get 5
                  i64.load offset=144
                  local.set 19
                  local.get 5
                  i32.const 112
                  i32.add
                  local.get 2
                  local.get 4
                  local.get 11
                  i64.const 0
                  call 47
                  local.get 5
                  i32.const 96
                  i32.add
                  local.get 2
                  local.get 1
                  i64.const 32
                  i64.shl
                  i64.add
                  local.tee 11
                  local.get 19
                  local.get 15
                  i64.const 4294967295
                  i64.and
                  local.get 10
                  local.get 5
                  i64.load offset=112
                  local.tee 15
                  i64.sub
                  local.tee 20
                  i64.const 32
                  i64.shl
                  i64.or
                  i64.gt_u
                  local.get 18
                  local.get 5
                  i64.load offset=120
                  i64.sub
                  local.get 10
                  local.get 15
                  i64.lt_u
                  i64.extend_i32_u
                  i64.sub
                  i64.const 32
                  i64.shl
                  local.get 20
                  i64.const 32
                  i64.shr_u
                  i64.or
                  local.tee 10
                  local.get 9
                  i64.lt_u
                  local.get 9
                  local.get 10
                  i64.eq
                  select
                  i64.extend_i32_u
                  local.tee 9
                  i64.sub
                  local.get 2
                  local.get 11
                  i64.gt_u
                  i64.extend_i32_u
                  local.get 4
                  local.get 1
                  i64.const 32
                  i64.shr_u
                  i64.add
                  i64.add
                  local.get 9
                  local.get 11
                  i64.gt_u
                  i64.extend_i32_u
                  i64.sub
                  local.get 8
                  i32.const 1
                  i32.shr_u
                  call 52
                  local.get 5
                  i64.load offset=104
                  local.set 2
                  local.get 5
                  i64.load offset=96
                  local.set 4
                  br 4 (;@3;)
                end
                i64.const 0
                local.set 2
                local.get 4
                call 42
                local.set 4
                br 3 (;@3;)
              end
              local.get 5
              i32.const 0
              i32.store offset=92
              local.get 5
              i32.const -64
              i32.sub
              local.get 14
              local.get 12
              local.get 13
              local.get 3
              local.get 5
              i32.const 92
              i32.add
              call 48
              local.get 5
              i32.load offset=92
              br_if 3 (;@2;)
              local.get 5
              i64.load offset=72
              local.set 1
              local.get 5
              i64.load offset=64
              local.set 2
              local.get 5
              i32.const 0
              i32.store offset=60
              local.get 5
              i32.const 32
              i32.add
              local.get 17
              local.get 16
              local.get 13
              local.get 3
              local.get 5
              i32.const 60
              i32.add
              call 48
              local.get 5
              i32.load offset=60
              br_if 3 (;@2;)
              local.get 5
              i64.load offset=40
              local.set 4
              local.get 5
              i64.load offset=32
              local.set 18
              local.get 5
              i32.const 16
              i32.add
              local.get 2
              local.get 1
              local.get 10
              local.get 9
              call 51
              local.get 5
              local.get 18
              local.get 4
              local.get 15
              local.get 11
              call 51
              local.get 5
              i64.load offset=8
              local.tee 1
              local.get 5
              i64.load offset=24
              local.tee 2
              local.get 5
              i64.load
              local.tee 4
              local.get 5
              i64.load offset=16
              local.tee 9
              i64.lt_u
              local.get 1
              local.get 2
              i64.lt_s
              local.get 1
              local.get 2
              i64.eq
              select
              local.tee 6
              select
              local.set 2
              local.get 4
              local.get 9
              local.get 6
              select
              local.set 4
              br 2 (;@3;)
            end
            unreachable
          end
          unreachable
        end
        local.get 2
        local.get 3
        i64.xor
        local.get 2
        local.get 2
        local.get 3
        i64.sub
        local.get 4
        local.get 13
        i64.lt_u
        i64.extend_i32_u
        i64.sub
        local.tee 1
        i64.xor
        i64.and
        i64.const 0
        i64.lt_s
        br_if 0 (;@2;)
        local.get 5
        i32.const 320
        i32.add
        local.tee 6
        local.get 0
        call 22
        local.get 5
        i64.load offset=328
        local.set 2
        local.get 5
        i64.load offset=320
        local.set 3
        local.get 6
        call 34
        local.get 1
        local.get 2
        i64.xor
        i64.const -1
        i64.xor
        local.get 2
        local.get 3
        local.get 4
        local.get 13
        i64.sub
        local.tee 4
        i64.add
        local.tee 13
        local.get 3
        i64.lt_u
        i64.extend_i32_u
        local.get 1
        local.get 2
        i64.add
        i64.add
        local.tee 9
        i64.xor
        i64.and
        i64.const 0
        i64.lt_s
        br_if 0 (;@2;)
        local.get 5
        i64.load offset=328
        local.set 2
        local.get 5
        i64.load offset=320
        local.set 3
        local.get 0
        local.get 13
        local.get 9
        call 23
        local.get 1
        local.get 2
        i64.xor
        i64.const -1
        i64.xor
        local.get 2
        local.get 3
        local.get 4
        i64.add
        local.tee 0
        local.get 3
        i64.lt_u
        i64.extend_i32_u
        local.get 1
        local.get 2
        i64.add
        i64.add
        local.tee 1
        i64.xor
        i64.and
        i64.const 0
        i64.lt_s
        br_if 0 (;@2;)
        local.get 0
        local.get 1
        call 35
        local.get 14
        local.get 12
        call 32
        local.get 17
        local.get 16
        call 33
        local.get 5
        i32.const 352
        i32.add
        global.set 0
        i64.const 2
        return
      end
      unreachable
    end
    unreachable)
  (func (;42;) (type 1) (param i64) (result i64)
    (local i64 i64 i64)
    block  ;; label = @1
      local.get 0
      i64.const 4
      i64.ge_u
      if  ;; label = @2
        i64.const 1
        i64.const 64
        local.get 0
        i64.clz
        i64.sub
        i64.const 1
        i64.shr_u
        i64.shl
        local.set 1
        loop  ;; label = @3
          local.get 0
          local.get 1
          local.tee 2
          call 46
          local.tee 1
          local.get 2
          i64.gt_u
          br_if 0 (;@3;)
        end
        loop  ;; label = @3
          local.get 2
          local.get 1
          local.tee 3
          i64.le_u
          br_if 2 (;@1;)
          local.get 0
          local.get 1
          call 46
          local.set 1
          local.get 3
          local.set 2
          br 0 (;@3;)
        end
        unreachable
      end
      local.get 0
      i64.const 0
      i64.ne
      i64.extend_i32_u
      local.set 2
    end
    local.get 2)
  (func (;43;) (type 9) (result i64)
    (local i32 i64)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 0
    global.set 0
    local.get 0
    call 30
    local.get 0
    i32.const 16
    i32.add
    call 31
    local.get 0
    i64.load
    local.get 0
    i64.load offset=8
    local.get 0
    i64.load offset=16
    local.get 0
    i64.load offset=24
    call 36
    local.get 0
    i32.const 32
    i32.add
    global.set 0)
  (func (;44;) (type 6) (param i64 i64 i64 i64) (result i64)
    (local i32 i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    global.get 0
    i32.const 336
    i32.sub
    local.tee 4
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          local.get 0
          i64.const 255
          i64.and
          i64.const 77
          i64.ne
          br_if 0 (;@3;)
          i32.const 1
          i32.const 2
          i32.const 0
          local.get 1
          i32.wrap_i64
          i32.const 255
          i32.and
          local.tee 5
          select
          local.get 5
          i32.const 1
          i32.eq
          select
          local.tee 7
          i32.const 2
          i32.eq
          br_if 0 (;@3;)
          local.get 4
          i32.const 240
          i32.add
          local.tee 5
          local.get 2
          call 14
          local.get 4
          i64.load offset=240
          i64.const 1
          i64.eq
          br_if 0 (;@3;)
          local.get 4
          i64.load offset=264
          local.set 1
          local.get 4
          i64.load offset=256
          local.set 2
          local.get 5
          local.get 3
          call 14
          local.get 4
          i64.load offset=240
          i64.const 1
          i64.eq
          br_if 0 (;@3;)
          local.get 4
          i64.load offset=264
          local.set 13
          local.get 4
          i64.load offset=256
          local.set 15
          local.get 0
          call 5
          drop
          local.get 5
          call 30
          local.get 4
          i64.load offset=240
          local.set 11
          local.get 4
          i64.load offset=248
          local.set 10
          local.get 5
          call 31
          local.get 11
          local.get 4
          i64.load offset=240
          local.tee 16
          local.get 7
          i32.const 1
          i32.and
          local.tee 5
          select
          local.tee 9
          local.get 2
          i64.lt_u
          local.tee 6
          local.get 10
          local.get 4
          i64.load offset=248
          local.tee 17
          local.get 5
          select
          local.tee 3
          local.get 1
          i64.lt_s
          local.get 1
          local.get 3
          i64.eq
          select
          br_if 2 (;@1;)
          local.get 4
          i32.const 0
          i32.store offset=236
          local.get 4
          i32.const 208
          i32.add
          local.get 16
          local.get 11
          local.get 5
          select
          local.get 17
          local.get 10
          local.get 5
          select
          local.get 2
          local.get 1
          local.get 4
          i32.const 236
          i32.add
          call 48
          local.get 4
          i32.load offset=236
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=216
          local.set 12
          local.get 4
          i64.load offset=208
          local.set 8
          local.get 4
          i32.const 0
          i32.store offset=204
          local.get 4
          i32.const 176
          i32.add
          local.get 8
          local.get 12
          i64.const 1000
          i64.const 0
          local.get 4
          i32.const 204
          i32.add
          call 48
          local.get 4
          i32.load offset=204
          br_if 1 (;@2;)
          local.get 1
          local.get 3
          i64.xor
          local.get 3
          local.get 3
          local.get 1
          i64.sub
          local.get 6
          i64.extend_i32_u
          i64.sub
          local.tee 8
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=184
          local.set 3
          local.get 4
          i64.load offset=176
          local.set 12
          local.get 4
          i32.const 0
          i32.store offset=172
          local.get 4
          i32.const 144
          i32.add
          local.get 9
          local.get 2
          i64.sub
          local.get 8
          i64.const 997
          i64.const 0
          local.get 4
          i32.const 172
          i32.add
          call 48
          local.get 4
          i32.load offset=172
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=144
          local.tee 9
          local.get 4
          i64.load offset=152
          local.tee 8
          i64.or
          i64.eqz
          local.get 12
          local.get 3
          i64.const -9223372036854775808
          i64.xor
          i64.or
          i64.eqz
          local.get 8
          local.get 9
          i64.and
          i64.const -1
          i64.eq
          i32.and
          i32.or
          br_if 1 (;@2;)
          local.get 4
          i32.const 128
          i32.add
          local.get 12
          local.get 3
          local.get 9
          local.get 8
          call 51
          local.get 4
          i64.load offset=136
          local.tee 3
          i64.const -1
          i64.xor
          local.get 3
          local.get 3
          local.get 4
          i64.load offset=128
          i64.const 1
          i64.add
          local.tee 8
          i64.eqz
          i64.extend_i32_u
          i64.add
          local.tee 9
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 1 (;@2;)
          local.get 8
          local.get 15
          i64.gt_u
          local.get 9
          local.get 13
          i64.gt_s
          local.get 9
          local.get 13
          i64.eq
          select
          br_if 2 (;@1;)
          block (result i64)  ;; label = @4
            local.get 5
            i32.eqz
            if  ;; label = @5
              i64.const 0
              call 53
              local.set 14
              local.get 2
              local.set 3
              local.get 1
              local.set 13
              i64.const 0
              local.set 12
              i64.const 0
              br 1 (;@4;)
            end
            i64.const 0
            local.set 3
            i64.const 1
            call 53
            local.set 14
            i64.const 0
            local.set 13
            local.get 1
            local.set 12
            local.get 2
          end
          local.set 15
          local.get 14
          local.get 0
          call 3
          local.get 8
          local.get 9
          call 19
          local.get 4
          i32.const 240
          i32.add
          local.tee 5
          call 28
          local.get 4
          i64.load offset=248
          local.set 9
          local.get 4
          i64.load offset=240
          local.set 14
          local.get 5
          call 29
          local.get 4
          i64.load offset=248
          local.set 8
          local.get 4
          i64.load offset=240
          local.set 18
          local.get 4
          i64.const 0
          i64.store offset=280
          local.get 4
          i64.const 997
          i64.store offset=272
          local.get 4
          i64.const 0
          i64.store offset=296
          local.get 4
          i64.const 1000
          i64.store offset=288
          local.get 4
          i64.const 0
          i64.store offset=312
          local.get 4
          i64.const 0
          i64.store offset=304
          local.get 4
          local.get 4
          i32.const 288
          i32.add
          i32.store offset=332
          local.get 4
          local.get 4
          i32.const 272
          i32.add
          i32.store offset=328
          local.get 4
          local.get 4
          i32.const 304
          i32.add
          i32.store offset=324
          local.get 5
          local.get 4
          i32.const 324
          i32.add
          local.tee 6
          local.get 14
          local.get 9
          local.get 11
          local.get 10
          local.get 15
          local.get 12
          call 21
          local.get 4
          i64.load offset=248
          local.set 19
          local.get 4
          i64.load offset=240
          local.set 20
          local.get 5
          local.get 6
          local.get 18
          local.get 8
          local.get 16
          local.get 17
          local.get 3
          local.get 13
          call 21
          local.get 4
          i32.const 0
          i32.store offset=124
          local.get 4
          i32.const 96
          i32.add
          local.get 11
          local.get 10
          i64.const 1000
          i64.const 0
          local.get 4
          i32.const 124
          i32.add
          call 48
          local.get 4
          i32.load offset=124
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=248
          local.set 11
          local.get 4
          i64.load offset=240
          local.set 10
          local.get 4
          i64.load offset=104
          local.set 21
          local.get 4
          i64.load offset=96
          local.set 22
          local.get 4
          i32.const 0
          i32.store offset=92
          local.get 4
          i32.const -64
          i32.sub
          local.get 16
          local.get 17
          i64.const 1000
          i64.const 0
          local.get 4
          i32.const 92
          i32.add
          call 48
          local.get 4
          i32.load offset=92
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=72
          local.set 16
          local.get 4
          i64.load offset=64
          local.set 17
          local.get 4
          i32.const 0
          i32.store offset=60
          local.get 4
          i32.const 32
          i32.add
          local.get 20
          local.get 19
          local.get 10
          local.get 11
          local.get 4
          i32.const 60
          i32.add
          call 48
          local.get 4
          i32.load offset=60
          br_if 1 (;@2;)
          local.get 4
          i64.load offset=40
          local.set 11
          local.get 4
          i64.load offset=32
          local.get 4
          i32.const 0
          i32.store offset=28
          local.get 4
          local.get 22
          local.get 21
          local.get 17
          local.get 16
          local.get 4
          i32.const 28
          i32.add
          call 48
          local.get 4
          i32.load offset=28
          br_if 1 (;@2;)
          local.get 4
          i64.load
          i64.lt_u
          local.get 11
          local.get 4
          i64.load offset=8
          local.tee 10
          i64.lt_s
          local.get 10
          local.get 11
          i64.eq
          select
          br_if 2 (;@1;)
          block  ;; label = @4
            local.get 7
            i32.const 1
            i32.and
            i32.eqz
            if  ;; label = @5
              local.get 0
              local.get 2
              local.get 1
              call 26
              br 1 (;@4;)
            end
            local.get 0
            local.get 2
            local.get 1
            call 24
          end
          local.get 9
          local.get 12
          i64.xor
          local.get 9
          local.get 9
          local.get 12
          i64.sub
          local.get 14
          local.get 15
          i64.lt_u
          i64.extend_i32_u
          i64.sub
          local.tee 0
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 1 (;@2;)
          local.get 8
          local.get 13
          i64.xor
          local.get 8
          local.get 8
          local.get 13
          i64.sub
          local.get 3
          local.get 18
          i64.gt_u
          i64.extend_i32_u
          i64.sub
          local.tee 1
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 1 (;@2;)
          local.get 14
          local.get 15
          i64.sub
          local.tee 2
          i64.eqz
          local.get 0
          i64.const 0
          i64.lt_s
          local.get 0
          i64.eqz
          select
          br_if 2 (;@1;)
          local.get 18
          local.get 3
          i64.sub
          local.tee 3
          i64.eqz
          local.get 1
          i64.const 0
          i64.lt_s
          local.get 1
          i64.eqz
          select
          br_if 2 (;@1;)
          local.get 2
          local.get 0
          call 32
          local.get 3
          local.get 1
          call 33
          local.get 4
          i32.const 336
          i32.add
          global.set 0
          i64.const 2
          return
        end
        unreachable
      end
      unreachable
    end
    unreachable)
  (func (;45;) (type 6) (param i64 i64 i64 i64) (result i64)
    (local i32 i32 i32 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
    global.get 0
    i32.const 128
    i32.sub
    local.tee 4
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          local.get 0
          i64.const 255
          i64.and
          i64.const 77
          i64.ne
          br_if 0 (;@3;)
          local.get 4
          i32.const 96
          i32.add
          local.tee 5
          local.get 1
          call 14
          local.get 4
          i64.load offset=96
          i64.const 1
          i64.eq
          br_if 0 (;@3;)
          local.get 4
          i64.load offset=120
          local.set 1
          local.get 4
          i64.load offset=112
          local.set 10
          local.get 5
          local.get 2
          call 14
          local.get 4
          i64.load offset=96
          i64.const 1
          i64.eq
          br_if 0 (;@3;)
          local.get 4
          i64.load offset=120
          local.set 7
          local.get 4
          i64.load offset=112
          local.set 13
          local.get 5
          local.get 3
          call 14
          local.get 4
          i64.load offset=96
          i64.const 1
          i64.eq
          br_if 0 (;@3;)
          local.get 4
          i64.load offset=120
          local.set 11
          local.get 4
          i64.load offset=112
          local.set 14
          local.get 0
          call 5
          drop
          local.get 5
          local.get 0
          call 22
          local.get 4
          i64.load offset=96
          local.get 10
          i64.lt_u
          local.get 4
          i64.load offset=104
          local.tee 2
          local.get 1
          i64.lt_s
          local.get 1
          local.get 2
          i64.eq
          select
          br_if 1 (;@2;)
          local.get 4
          i32.const 0
          i32.store offset=92
          local.get 5
          call 28
          local.get 4
          i32.const -64
          i32.sub
          local.get 4
          i64.load offset=96
          local.tee 17
          local.get 4
          i64.load offset=104
          local.tee 15
          local.get 10
          local.get 1
          local.get 4
          i32.const 92
          i32.add
          call 48
          local.get 5
          call 29
          local.get 4
          i64.load offset=104
          local.set 12
          local.get 4
          i64.load offset=96
          local.set 16
          local.get 5
          call 34
          local.get 4
          i32.load offset=92
          br_if 2 (;@1;)
          local.get 4
          i64.load offset=96
          local.tee 8
          local.get 4
          i64.load offset=104
          local.tee 9
          i64.or
          i64.eqz
          br_if 2 (;@1;)
          local.get 8
          local.get 9
          i64.and
          i64.const -1
          i64.eq
          local.tee 6
          local.get 4
          i64.load offset=64
          local.tee 2
          local.get 4
          i64.load offset=72
          local.tee 3
          i64.const -9223372036854775808
          i64.xor
          i64.or
          i64.eqz
          i32.and
          br_if 2 (;@1;)
          local.get 4
          i32.const 48
          i32.add
          local.get 2
          local.get 3
          local.get 8
          local.get 9
          call 51
          local.get 4
          i32.const 0
          i32.store offset=44
          local.get 4
          i32.const 16
          i32.add
          local.get 16
          local.get 12
          local.get 10
          local.get 1
          local.get 4
          i32.const 44
          i32.add
          call 48
          local.get 4
          i32.load offset=44
          br_if 2 (;@1;)
          local.get 4
          i64.load offset=16
          local.tee 18
          local.get 4
          i64.load offset=24
          local.tee 19
          i64.const -9223372036854775808
          i64.xor
          i64.or
          i64.eqz
          local.get 6
          i32.and
          br_if 2 (;@1;)
          local.get 4
          i64.load offset=56
          local.set 2
          local.get 4
          i64.load offset=48
          local.set 3
          local.get 4
          local.get 18
          local.get 19
          local.get 8
          local.get 9
          call 51
          local.get 3
          local.get 13
          i64.lt_u
          local.get 2
          local.get 7
          i64.lt_s
          local.get 2
          local.get 7
          i64.eq
          select
          br_if 1 (;@2;)
          local.get 4
          i64.load
          local.tee 9
          local.get 14
          i64.lt_u
          local.get 4
          i64.load offset=8
          local.tee 8
          local.get 11
          i64.lt_s
          local.get 8
          local.get 11
          i64.eq
          select
          br_if 1 (;@2;)
          local.get 5
          local.get 0
          call 22
          local.get 4
          i64.load offset=96
          local.tee 13
          local.get 10
          i64.lt_u
          local.tee 6
          local.get 4
          i64.load offset=104
          local.tee 7
          local.get 1
          i64.lt_s
          local.get 1
          local.get 7
          i64.eq
          select
          br_if 1 (;@2;)
          local.get 5
          call 34
          local.get 1
          local.get 7
          i64.xor
          local.get 7
          local.get 7
          local.get 1
          i64.sub
          local.get 6
          i64.extend_i32_u
          i64.sub
          local.tee 14
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 2 (;@1;)
          local.get 4
          i64.load offset=104
          local.set 7
          local.get 4
          i64.load offset=96
          local.set 11
          local.get 0
          local.get 13
          local.get 10
          i64.sub
          local.get 14
          call 23
          local.get 1
          local.get 7
          i64.xor
          local.get 7
          local.get 7
          local.get 1
          i64.sub
          local.get 10
          local.get 11
          i64.gt_u
          i64.extend_i32_u
          i64.sub
          local.tee 1
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 2 (;@1;)
          local.get 11
          local.get 10
          i64.sub
          local.get 1
          call 35
          local.get 0
          local.get 3
          local.get 2
          call 24
          local.get 0
          local.get 9
          local.get 8
          call 26
          local.get 2
          local.get 15
          i64.xor
          local.get 15
          local.get 15
          local.get 2
          i64.sub
          local.get 3
          local.get 17
          i64.gt_u
          i64.extend_i32_u
          i64.sub
          local.tee 0
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 2 (;@1;)
          local.get 17
          local.get 3
          i64.sub
          local.get 0
          call 32
          local.get 8
          local.get 12
          i64.xor
          local.get 12
          local.get 12
          local.get 8
          i64.sub
          local.get 9
          local.get 16
          i64.gt_u
          i64.extend_i32_u
          i64.sub
          local.tee 0
          i64.xor
          i64.and
          i64.const 0
          i64.lt_s
          br_if 2 (;@1;)
          local.get 16
          local.get 9
          i64.sub
          local.get 0
          call 33
          local.get 3
          local.get 2
          local.get 9
          local.get 8
          call 36
          local.get 4
          i32.const 128
          i32.add
          global.set 0
          return
        end
        unreachable
      end
      unreachable
    end
    unreachable)
  (func (;46;) (type 0) (param i64 i64) (result i64)
    block  ;; label = @1
      local.get 1
      i64.eqz
      i32.eqz
      if  ;; label = @2
        local.get 0
        local.get 1
        i64.div_u
        local.tee 0
        local.get 1
        i64.add
        local.tee 1
        local.get 0
        i64.ge_u
        br_if 1 (;@1;)
      end
      unreachable
    end
    local.get 1
    i64.const 1
    i64.shr_u)
  (func (;47;) (type 7) (param i32 i64 i64 i64 i64)
    (local i64 i64 i64 i64 i64 i64)
    local.get 0
    local.get 3
    i64.const 4294967295
    i64.and
    local.tee 5
    local.get 1
    i64.const 4294967295
    i64.and
    local.tee 6
    i64.mul
    local.tee 7
    local.get 6
    local.get 3
    i64.const 32
    i64.shr_u
    local.tee 8
    i64.mul
    local.tee 6
    local.get 5
    local.get 1
    i64.const 32
    i64.shr_u
    local.tee 9
    i64.mul
    i64.add
    local.tee 5
    i64.const 32
    i64.shl
    i64.add
    local.tee 10
    i64.store
    local.get 0
    local.get 7
    local.get 10
    i64.gt_u
    i64.extend_i32_u
    local.get 8
    local.get 9
    i64.mul
    local.get 5
    local.get 6
    i64.lt_u
    i64.extend_i32_u
    i64.const 32
    i64.shl
    local.get 5
    i64.const 32
    i64.shr_u
    i64.or
    i64.add
    i64.add
    local.get 1
    local.get 4
    i64.mul
    local.get 2
    local.get 3
    i64.mul
    i64.add
    i64.add
    i64.store offset=8)
  (func (;48;) (type 19) (param i32 i64 i64 i64 i64 i32)
    (local i32 i32 i32 i64 i64)
    global.get 0
    i32.const 96
    i32.sub
    local.tee 6
    global.set 0
    block  ;; label = @1
      local.get 1
      local.get 2
      i64.or
      i64.eqz
      local.get 3
      local.get 4
      i64.or
      i64.eqz
      i32.or
      br_if 0 (;@1;)
      i64.const 0
      local.get 3
      i64.sub
      local.get 3
      local.get 4
      i64.const 0
      i64.lt_s
      local.tee 7
      select
      local.set 9
      i64.const 0
      local.get 1
      i64.sub
      local.get 1
      local.get 2
      i64.const 0
      i64.lt_s
      local.tee 8
      select
      local.set 10
      i64.const 0
      local.get 4
      local.get 3
      i64.const 0
      i64.ne
      i64.extend_i32_u
      i64.add
      i64.sub
      local.get 4
      local.get 7
      select
      local.set 3
      local.get 2
      local.get 4
      i64.xor
      local.set 4
      i64.const 0
      block (result i64)  ;; label = @2
        i64.const 0
        local.get 2
        local.get 1
        i64.const 0
        i64.ne
        i64.extend_i32_u
        i64.add
        i64.sub
        local.get 2
        local.get 8
        select
        local.tee 1
        i64.eqz
        i32.eqz
        if  ;; label = @3
          local.get 3
          i64.eqz
          i32.eqz
          if  ;; label = @4
            local.get 6
            i32.const 80
            i32.add
            local.get 9
            local.get 3
            local.get 10
            local.get 1
            call 47
            i32.const 1
            local.set 7
            local.get 6
            i64.load offset=88
            local.set 1
            local.get 6
            i64.load offset=80
            br 2 (;@2;)
          end
          local.get 6
          i32.const -64
          i32.sub
          local.get 10
          i64.const 0
          local.get 9
          local.get 3
          call 47
          local.get 6
          i32.const 48
          i32.add
          local.get 1
          i64.const 0
          local.get 9
          local.get 3
          call 47
          local.get 6
          i64.load offset=56
          i64.const 0
          i64.ne
          local.get 6
          i64.load offset=48
          local.tee 2
          local.get 6
          i64.load offset=72
          i64.add
          local.tee 1
          local.get 2
          i64.lt_u
          i32.or
          local.set 7
          local.get 6
          i64.load offset=64
          br 1 (;@2;)
        end
        local.get 3
        i64.eqz
        i32.eqz
        if  ;; label = @3
          local.get 6
          i32.const 32
          i32.add
          local.get 9
          i64.const 0
          local.get 10
          local.get 1
          call 47
          local.get 6
          i32.const 16
          i32.add
          local.get 3
          i64.const 0
          local.get 10
          local.get 1
          call 47
          local.get 6
          i64.load offset=24
          i64.const 0
          i64.ne
          local.get 6
          i64.load offset=16
          local.tee 2
          local.get 6
          i64.load offset=40
          i64.add
          local.tee 1
          local.get 2
          i64.lt_u
          i32.or
          local.set 7
          local.get 6
          i64.load offset=32
          br 1 (;@2;)
        end
        local.get 6
        local.get 9
        local.get 3
        local.get 10
        local.get 1
        call 47
        i32.const 0
        local.set 7
        local.get 6
        i64.load offset=8
        local.set 1
        local.get 6
        i64.load
      end
      local.tee 2
      i64.sub
      local.get 2
      local.get 4
      i64.const 0
      i64.lt_s
      local.tee 8
      select
      local.set 9
      i64.const 0
      local.get 1
      local.get 2
      i64.const 0
      i64.ne
      i64.extend_i32_u
      i64.add
      i64.sub
      local.get 1
      local.get 8
      select
      local.tee 10
      local.get 4
      i64.xor
      i64.const 0
      i64.ge_s
      br_if 0 (;@1;)
      i32.const 1
      local.set 7
    end
    local.get 0
    local.get 9
    i64.store
    local.get 5
    local.get 7
    i32.store
    local.get 0
    local.get 10
    i64.store offset=8
    local.get 6
    i32.const 96
    i32.add
    global.set 0)
  (func (;49;) (type 7) (param i32 i64 i64 i64 i64)
    (local i32 i32 i32 i32 i64 i64 i64 i64 i64)
    global.get 0
    i32.const 176
    i32.sub
    local.tee 5
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        block  ;; label = @3
          block  ;; label = @4
            block  ;; label = @5
              block  ;; label = @6
                block  ;; label = @7
                  local.get 4
                  i64.clz
                  local.get 3
                  i64.clz
                  i64.const -64
                  i64.sub
                  local.get 4
                  i64.const 0
                  i64.ne
                  select
                  i32.wrap_i64
                  local.tee 7
                  local.get 2
                  i64.clz
                  local.get 1
                  i64.clz
                  i64.const -64
                  i64.sub
                  local.get 2
                  i64.const 0
                  i64.ne
                  select
                  i32.wrap_i64
                  local.tee 6
                  i32.gt_u
                  if  ;; label = @8
                    local.get 6
                    i32.const 63
                    i32.gt_u
                    br_if 1 (;@7;)
                    local.get 7
                    i32.const 95
                    i32.gt_u
                    br_if 2 (;@6;)
                    local.get 7
                    local.get 6
                    i32.sub
                    i32.const 32
                    i32.lt_u
                    br_if 3 (;@5;)
                    local.get 5
                    i32.const 160
                    i32.add
                    local.get 3
                    local.get 4
                    i32.const 96
                    local.get 7
                    i32.sub
                    local.tee 8
                    call 52
                    local.get 5
                    i64.load32_u offset=160
                    i64.const 1
                    i64.add
                    local.set 12
                    br 4 (;@4;)
                  end
                  local.get 1
                  local.get 3
                  i64.lt_u
                  local.tee 6
                  local.get 2
                  local.get 4
                  i64.lt_u
                  local.get 2
                  local.get 4
                  i64.eq
                  select
                  i32.eqz
                  br_if 5 (;@2;)
                  br 6 (;@1;)
                end
                local.get 1
                local.get 1
                local.get 3
                i64.div_u
                local.tee 9
                local.get 3
                i64.mul
                i64.sub
                local.set 1
                i64.const 0
                local.set 2
                br 5 (;@1;)
              end
              local.get 1
              i64.const 32
              i64.shr_u
              local.tee 9
              local.get 2
              local.get 2
              local.get 3
              i64.const 4294967295
              i64.and
              local.tee 2
              i64.div_u
              local.tee 11
              local.get 3
              i64.mul
              i64.sub
              i64.const 32
              i64.shl
              i64.or
              local.get 2
              i64.div_u
              local.tee 4
              i64.const 32
              i64.shl
              local.get 1
              i64.const 4294967295
              i64.and
              local.get 9
              local.get 3
              local.get 4
              i64.mul
              i64.sub
              i64.const 32
              i64.shl
              i64.or
              local.tee 1
              local.get 2
              i64.div_u
              local.tee 3
              i64.or
              local.set 9
              local.get 1
              local.get 2
              local.get 3
              i64.mul
              i64.sub
              local.set 1
              local.get 4
              i64.const 32
              i64.shr_u
              local.get 11
              i64.or
              local.set 11
              i64.const 0
              local.set 2
              br 4 (;@1;)
            end
            local.get 5
            i32.const 48
            i32.add
            local.get 1
            local.get 2
            i32.const 64
            local.get 6
            i32.sub
            local.tee 6
            call 52
            local.get 5
            i32.const 32
            i32.add
            local.get 3
            local.get 4
            local.get 6
            call 52
            local.get 5
            local.get 3
            i64.const 0
            local.get 5
            i64.load offset=48
            local.get 5
            i64.load offset=32
            i64.div_u
            local.tee 9
            i64.const 0
            call 47
            local.get 5
            i32.const 16
            i32.add
            local.get 4
            i64.const 0
            local.get 9
            i64.const 0
            call 47
            local.get 5
            i64.load
            local.set 10
            local.get 5
            i64.load offset=24
            local.get 5
            i64.load offset=8
            local.tee 13
            local.get 5
            i64.load offset=16
            i64.add
            local.tee 12
            local.get 13
            i64.lt_u
            i64.extend_i32_u
            i64.add
            i64.eqz
            if  ;; label = @5
              local.get 1
              local.get 10
              i64.lt_u
              local.tee 6
              local.get 2
              local.get 12
              i64.lt_u
              local.get 2
              local.get 12
              i64.eq
              select
              i32.eqz
              br_if 2 (;@3;)
            end
            local.get 1
            local.get 3
            i64.add
            local.tee 1
            local.get 3
            i64.lt_u
            i64.extend_i32_u
            local.get 2
            local.get 4
            i64.add
            i64.add
            local.get 12
            i64.sub
            local.get 1
            local.get 10
            i64.lt_u
            i64.extend_i32_u
            i64.sub
            local.set 2
            local.get 9
            i64.const 1
            i64.sub
            local.set 9
            local.get 1
            local.get 10
            i64.sub
            local.set 1
            br 3 (;@1;)
          end
          block  ;; label = @4
            block  ;; label = @5
              loop  ;; label = @6
                local.get 5
                i32.const 144
                i32.add
                local.get 1
                local.get 2
                i32.const 64
                local.get 6
                i32.sub
                local.tee 6
                call 52
                local.get 5
                i64.load offset=144
                local.set 10
                local.get 6
                local.get 8
                i32.lt_u
                if  ;; label = @7
                  local.get 5
                  i32.const 80
                  i32.add
                  local.get 3
                  local.get 4
                  local.get 6
                  call 52
                  local.get 5
                  i32.const -64
                  i32.sub
                  local.get 3
                  local.get 4
                  local.get 10
                  local.get 5
                  i64.load offset=80
                  i64.div_u
                  local.tee 13
                  i64.const 0
                  call 47
                  local.get 1
                  local.get 5
                  i64.load offset=64
                  local.tee 10
                  i64.lt_u
                  local.tee 6
                  local.get 2
                  local.get 5
                  i64.load offset=72
                  local.tee 12
                  i64.lt_u
                  local.get 2
                  local.get 12
                  i64.eq
                  select
                  i32.eqz
                  if  ;; label = @8
                    local.get 2
                    local.get 12
                    i64.sub
                    local.get 6
                    i64.extend_i32_u
                    i64.sub
                    local.set 2
                    local.get 1
                    local.get 10
                    i64.sub
                    local.set 1
                    local.get 11
                    local.get 9
                    local.get 9
                    local.get 13
                    i64.add
                    local.tee 9
                    i64.gt_u
                    i64.extend_i32_u
                    i64.add
                    local.set 11
                    br 7 (;@1;)
                  end
                  local.get 1
                  local.get 1
                  local.get 3
                  i64.add
                  local.tee 3
                  i64.gt_u
                  i64.extend_i32_u
                  local.get 2
                  local.get 4
                  i64.add
                  i64.add
                  local.get 12
                  i64.sub
                  local.get 3
                  local.get 10
                  i64.lt_u
                  i64.extend_i32_u
                  i64.sub
                  local.set 2
                  local.get 3
                  local.get 10
                  i64.sub
                  local.set 1
                  local.get 11
                  local.get 9
                  local.get 9
                  local.get 13
                  i64.add
                  i64.const 1
                  i64.sub
                  local.tee 9
                  i64.gt_u
                  i64.extend_i32_u
                  i64.add
                  local.set 11
                  br 6 (;@1;)
                end
                local.get 5
                i32.const 128
                i32.add
                local.get 10
                local.get 12
                i64.div_u
                local.tee 10
                i64.const 0
                local.get 6
                local.get 8
                i32.sub
                local.tee 6
                call 50
                local.get 5
                i32.const 112
                i32.add
                local.get 3
                local.get 4
                local.get 10
                i64.const 0
                call 47
                local.get 5
                i32.const 96
                i32.add
                local.get 5
                i64.load offset=112
                local.get 5
                i64.load offset=120
                local.get 6
                call 50
                local.get 5
                i64.load offset=128
                local.tee 10
                local.get 9
                i64.add
                local.tee 9
                local.get 10
                i64.lt_u
                i64.extend_i32_u
                local.get 5
                i64.load offset=136
                local.get 11
                i64.add
                i64.add
                local.set 11
                local.get 2
                local.get 5
                i64.load offset=104
                i64.sub
                local.get 1
                local.get 5
                i64.load offset=96
                local.tee 10
                i64.lt_u
                i64.extend_i32_u
                i64.sub
                local.tee 2
                i64.clz
                local.get 1
                local.get 10
                i64.sub
                local.tee 1
                i64.clz
                i64.const -64
                i64.sub
                local.get 2
                i64.const 0
                i64.ne
                select
                i32.wrap_i64
                local.tee 6
                local.get 7
                i32.lt_u
                if  ;; label = @7
                  local.get 6
                  i32.const 63
                  i32.gt_u
                  br_if 2 (;@5;)
                  br 1 (;@6;)
                end
              end
              local.get 1
              local.get 3
              i64.lt_u
              local.tee 6
              local.get 2
              local.get 4
              i64.lt_u
              local.get 2
              local.get 4
              i64.eq
              select
              i32.eqz
              br_if 1 (;@4;)
              br 4 (;@1;)
            end
            local.get 1
            local.get 1
            local.get 3
            i64.div_u
            local.tee 2
            local.get 3
            i64.mul
            i64.sub
            local.set 1
            local.get 11
            local.get 9
            local.get 2
            local.get 9
            i64.add
            local.tee 9
            i64.gt_u
            i64.extend_i32_u
            i64.add
            local.set 11
            i64.const 0
            local.set 2
            br 3 (;@1;)
          end
          local.get 2
          local.get 4
          i64.sub
          local.get 6
          i64.extend_i32_u
          i64.sub
          local.set 2
          local.get 1
          local.get 3
          i64.sub
          local.set 1
          local.get 11
          local.get 9
          i64.const 1
          i64.add
          local.tee 9
          i64.eqz
          i64.extend_i32_u
          i64.add
          local.set 11
          br 2 (;@1;)
        end
        local.get 2
        local.get 12
        i64.sub
        local.get 6
        i64.extend_i32_u
        i64.sub
        local.set 2
        local.get 1
        local.get 10
        i64.sub
        local.set 1
        br 1 (;@1;)
      end
      local.get 2
      local.get 4
      i64.sub
      local.get 6
      i64.extend_i32_u
      i64.sub
      local.set 2
      local.get 1
      local.get 3
      i64.sub
      local.set 1
      i64.const 1
      local.set 9
    end
    local.get 0
    local.get 1
    i64.store offset=16
    local.get 0
    local.get 9
    i64.store
    local.get 0
    local.get 2
    i64.store offset=24
    local.get 0
    local.get 11
    i64.store offset=8
    local.get 5
    i32.const 176
    i32.add
    global.set 0)
  (func (;50;) (type 11) (param i32 i64 i64 i32)
    (local i64)
    block  ;; label = @1
      local.get 3
      i32.const 64
      i32.and
      i32.eqz
      if  ;; label = @2
        local.get 3
        i32.eqz
        br_if 1 (;@1;)
        local.get 2
        local.get 3
        i64.extend_i32_u
        local.tee 4
        i64.shl
        local.get 1
        i32.const 0
        local.get 3
        i32.sub
        i64.extend_i32_u
        i64.shr_u
        i64.or
        local.set 2
        local.get 1
        local.get 4
        i64.shl
        local.set 1
        br 1 (;@1;)
      end
      local.get 1
      local.get 3
      i64.extend_i32_u
      i64.shl
      local.set 2
      i64.const 0
      local.set 1
    end
    local.get 0
    local.get 1
    i64.store
    local.get 0
    local.get 2
    i64.store offset=8)
  (func (;51;) (type 7) (param i32 i64 i64 i64 i64)
    (local i32 i32)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 6
    global.set 0
    local.get 6
    i64.const 0
    local.get 1
    i64.sub
    local.get 1
    local.get 2
    i64.const 0
    i64.lt_s
    local.tee 5
    select
    i64.const 0
    local.get 2
    local.get 1
    i64.const 0
    i64.ne
    i64.extend_i32_u
    i64.add
    i64.sub
    local.get 2
    local.get 5
    select
    i64.const 0
    local.get 3
    i64.sub
    local.get 3
    local.get 4
    i64.const 0
    i64.lt_s
    local.tee 5
    select
    i64.const 0
    local.get 4
    local.get 3
    i64.const 0
    i64.ne
    i64.extend_i32_u
    i64.add
    i64.sub
    local.get 4
    local.get 5
    select
    call 49
    local.get 6
    i64.load offset=8
    local.set 1
    local.get 0
    i64.const 0
    local.get 6
    i64.load
    local.tee 3
    i64.sub
    local.get 3
    local.get 2
    local.get 4
    i64.xor
    i64.const 0
    i64.lt_s
    local.tee 5
    select
    i64.store
    local.get 0
    i64.const 0
    local.get 1
    local.get 3
    i64.const 0
    i64.ne
    i64.extend_i32_u
    i64.add
    i64.sub
    local.get 1
    local.get 5
    select
    i64.store offset=8
    local.get 6
    i32.const 32
    i32.add
    global.set 0)
  (func (;52;) (type 11) (param i32 i64 i64 i32)
    (local i64)
    block  ;; label = @1
      local.get 3
      i32.const 64
      i32.and
      i32.eqz
      if  ;; label = @2
        local.get 3
        i32.eqz
        br_if 1 (;@1;)
        local.get 2
        i32.const 0
        local.get 3
        i32.sub
        i64.extend_i32_u
        i64.shl
        local.get 1
        local.get 3
        i64.extend_i32_u
        local.tee 4
        i64.shr_u
        i64.or
        local.set 1
        local.get 2
        local.get 4
        i64.shr_u
        local.set 2
        br 1 (;@1;)
      end
      local.get 2
      local.get 3
      i64.extend_i32_u
      i64.shr_u
      local.set 1
      i64.const 0
      local.set 2
    end
    local.get 0
    local.get 1
    i64.store
    local.get 0
    local.get 2
    i64.store offset=8)
  (func (;53;) (type 1) (param i64) (result i64)
    (local i32)
    global.get 0
    i32.const 16
    i32.sub
    local.tee 1
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        local.get 1
        local.get 0
        i64.const 0
        call 12
        local.tee 0
        i64.const 2
        call 13
        if (result i64)  ;; label = @3
          local.get 0
          i64.const 2
          call 0
          local.tee 0
          i64.const 255
          i64.and
          i64.const 77
          i64.ne
          br_if 1 (;@2;)
          local.get 1
          local.get 0
          i64.store offset=8
          i64.const 1
        else
          i64.const 0
        end
        i64.store
        br 1 (;@1;)
      end
      unreachable
    end
    local.get 1
    i32.load
    i32.eqz
    if  ;; label = @1
      unreachable
    end
    local.get 1
    i64.load offset=8
    local.get 1
    i32.const 16
    i32.add
    global.set 0)
  (func (;54;) (type 3) (param i32 i64)
    (local i32 i32 i64)
    global.get 0
    i32.const 32
    i32.sub
    local.tee 2
    global.set 0
    global.get 0
    i32.const 32
    i32.sub
    local.tee 3
    global.set 0
    block  ;; label = @1
      block  ;; label = @2
        local.get 1
        i64.const 0
        call 12
        local.tee 1
        i64.const 2
        call 13
        if  ;; label = @3
          local.get 3
          local.get 1
          i64.const 2
          call 0
          call 14
          i64.const 1
          local.set 4
          local.get 3
          i64.load
          i64.const 1
          i64.eq
          br_if 1 (;@2;)
          local.get 3
          i64.load offset=16
          local.set 1
          local.get 2
          local.get 3
          i64.load offset=24
          i64.store offset=24
          local.get 2
          local.get 1
          i64.store offset=16
        end
        local.get 2
        i64.const 0
        i64.store offset=8
        local.get 2
        local.get 4
        i64.store
        local.get 3
        i32.const 32
        i32.add
        global.set 0
        br 1 (;@1;)
      end
      unreachable
    end
    local.get 2
    i32.load
    i32.const 1
    i32.and
    i32.eqz
    if  ;; label = @1
      unreachable
    end
    local.get 2
    i64.load offset=24
    local.set 1
    local.get 0
    local.get 2
    i64.load offset=16
    i64.store
    local.get 0
    local.get 1
    i64.store offset=8
    local.get 2
    i32.const 32
    i32.add
    global.set 0)
  (memory (;0;) 17)
  (global (;0;) (mut i32) (i32.const 1048576))
  (global (;1;) i32 (i32.const 1048621))
  (export "memory" (memory 0))
  (export "__constructor" (func 39))
  (export "balance_shares" (func 40))
  (export "deposit" (func 41))
  (export "get_rsrvs" (func 43))
  (export "swap" (func 44))
  (export "withdraw" (func 45))
  (export "_" (global 1))
  (data (;0;) (i32.const 1048576) "TokenATokenBTotalSharesReserveAReserveBShares")
  (@custom "contractmetav0" "\00\00\00\00\00\00\00\0bDescription\00\00\00\00(Constant product AMM with a .3% swap fee\00\00\00\00\00\00\00\05rsver\00\00\00\00\00\00\061.99.1\00\00\00\00\00\00\00\00\00\08rssdkver\00\00\00/28.0.0#48d506712f964094d14176e2f0b02afcd1054567\00\00\00\00\00\00\00\00\12rssdk_spec_shaking\00\00\00\00\00\012\00\00\00")
  (@custom "contractenvmetav0" "\00\00\00\00\00\00\00\1c\00\00\00\00")
  (@custom "contractmetav0" "\00\00\00\00\00\00\00\06cliver\00\00\00\00\00/28.0.0#300aaf69ab100536678bdb641428b06f06b318ea\00")
  (@custom "contractspecv0" "\00\00\00\00\00\00\00\00\00\00\00\04swap\00\00\00\04\00\00\00\00\00\00\00\02to\00\00\00\00\00\13\00\00\00\00\00\00\00\05buy_a\00\00\00\00\00\00\01\00\00\00\00\00\00\00\03out\00\00\00\00\0b\00\00\00\00\00\00\00\06in_max\00\00\00\00\00\0b\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\07deposit\00\00\00\00\05\00\00\00\00\00\00\00\02to\00\00\00\00\00\13\00\00\00\00\00\00\00\09desired_a\00\00\00\00\00\00\0b\00\00\00\00\00\00\00\05min_a\00\00\00\00\00\00\0b\00\00\00\00\00\00\00\09desired_b\00\00\00\00\00\00\0b\00\00\00\00\00\00\00\05min_b\00\00\00\00\00\00\0b\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\08withdraw\00\00\00\04\00\00\00\00\00\00\00\02to\00\00\00\00\00\13\00\00\00\00\00\00\00\0cshare_amount\00\00\00\0b\00\00\00\00\00\00\00\05min_a\00\00\00\00\00\00\0b\00\00\00\00\00\00\00\05min_b\00\00\00\00\00\00\0b\00\00\00\01\00\00\03\ed\00\00\00\02\00\00\00\0b\00\00\00\0b\00\00\00\00\00\00\00\00\00\00\00\09get_rsrvs\00\00\00\00\00\00\00\00\00\00\01\00\00\03\ed\00\00\00\02\00\00\00\0b\00\00\00\0b\00\00\00\00\00\00\00\00\00\00\00\0d__constructor\00\00\00\00\00\00\02\00\00\00\00\00\00\00\07token_a\00\00\00\00\13\00\00\00\00\00\00\00\07token_b\00\00\00\00\13\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0ebalance_shares\00\00\00\00\00\01\00\00\00\00\00\00\00\04user\00\00\00\13\00\00\00\01\00\00\00\0b"))
