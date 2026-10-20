// seek-asm: arena.s — bump allocator sobre VirtualAlloc (optimizado lossless).
// Nombres: reserva 256MB (0x10000000), commit inicial 64KB, crecimiento en
// múltiplos de 64KB (mín 64KB). Tablas (records/pila) en región aparte con
// commit progresivo sin copia-abandono: REC 32MB (2M x 16B) + STK 4MB (1M x 4B).
// Alineación 8. Sin HeapAlloc ni malloc.

.intel_syntax noprefix
.text
.globl arena_init
.globl arena_alloc
.globl arena_used
.globl arena_free
.globl table_rec_base
.globl table_stk_base
.globl table_ensure_rec
.globl table_ensure_stk

// NOTA GAS: .equ antes del primer uso.
.equ ARENA_RSV, 0x10000000
.equ ARENA_CHUNK, 0x10000
.equ REC_RSV, 0x2000000
.equ STK_RSV, 0x400000
.equ TABLE_CHUNK, 0x10000
.equ MEM_COMMIT, 0x1000
.equ MEM_RESERVE, 0x2000
.equ MEM_RELEASE, 0x8000
.equ PAGE_RW, 0x4
.equ PAGE_NA, 0x1

// arena_init: reserva nombres + tablas, commit inicial 64KB c/u.
// Retorna EAX = 1 si ok, 0 si falla.
arena_init:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    lea rax, [rip + arena_base]
    cmp QWORD PTR [rax], 0
    jne init_already
    // --- nombres: reserva 256MB ---
    mov rcx, 0
    mov rdx, ARENA_RSV
    mov r8d, MEM_RESERVE
    mov r9d, PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz init_fail
    lea rcx, [rip + arena_base]
    mov QWORD PTR [rcx], rax
    lea rcx, [rip + arena_brk]
    mov QWORD PTR [rcx], rax
    add rax, ARENA_RSV
    lea rcx, [rip + arena_rsv_end]
    mov QWORD PTR [rcx], rax
    // commit inicial 64KB
    lea rcx, [rip + arena_base]
    mov rcx, QWORD PTR [rcx]
    mov rdx, ARENA_CHUNK
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz init_commit_fail
    lea rcx, [rip + arena_base]
    mov rax, QWORD PTR [rcx]
    add rax, ARENA_CHUNK
    lea rcx, [rip + arena_commit_end]
    mov QWORD PTR [rcx], rax
    // --- tablas REC: reserva 32MB ---
    mov rcx, 0
    mov rdx, REC_RSV
    mov r8d, MEM_RESERVE
    mov r9d, PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz init_commit_fail
    lea rcx, [rip + rec_rsv_base]
    mov QWORD PTR [rcx], rax
    mov QWORD PTR [rsp+32], rax
    add rax, REC_RSV
    lea rcx, [rip + rec_rsv_end]
    mov QWORD PTR [rcx], rax
    mov rcx, QWORD PTR [rsp+32]
    mov rdx, TABLE_CHUNK
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz init_commit_fail
    mov rax, QWORD PTR [rsp+32]
    add rax, TABLE_CHUNK
    lea rcx, [rip + rec_commit_end]
    mov QWORD PTR [rcx], rax
    // --- pila STK: reserva 4MB ---
    mov rcx, 0
    mov rdx, STK_RSV
    mov r8d, MEM_RESERVE
    mov r9d, PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz init_commit_fail
    lea rcx, [rip + stk_rsv_base]
    mov QWORD PTR [rcx], rax
    mov QWORD PTR [rsp+32], rax
    add rax, STK_RSV
    lea rcx, [rip + stk_rsv_end]
    mov QWORD PTR [rcx], rax
    mov rcx, QWORD PTR [rsp+32]
    mov rdx, TABLE_CHUNK
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz init_commit_fail
    mov rax, QWORD PTR [rsp+32]
    add rax, TABLE_CHUNK
    lea rcx, [rip + stk_commit_end]
    mov QWORD PTR [rcx], rax
    mov eax, 1
    jmp init_done
init_already:
    mov eax, 1
    jmp init_done
init_commit_fail:
    // liberar lo reservado y ceros
    lea rax, [rip + arena_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz init_free_rec
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + arena_base]
    mov QWORD PTR [rcx], 0
init_free_rec:
    lea rax, [rip + rec_rsv_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz init_free_stk
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + rec_rsv_base]
    mov QWORD PTR [rcx], 0
init_free_stk:
    lea rax, [rip + stk_rsv_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz init_fail
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + stk_rsv_base]
    mov QWORD PTR [rcx], 0
init_fail:
    xor eax, eax
init_done:
    add rsp, 48
    pop rbp
    ret

// arena_alloc: RCX = bytes. Retorna RAX = ptr, o 0 si no hay lugar.
arena_alloc:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    add rcx, 7
    mov rax, rcx
    shr rax, 3
    shl rax, 3
    cmp rax, rcx
    je alloc_aligned
    add rax, 8
alloc_aligned:
    mov QWORD PTR [rsp+32], rax
    test rax, rax
    jz alloc_zero
    lea rax, [rip + arena_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz alloc_fail
    lea rax, [rip + arena_brk]
    mov rax, QWORD PTR [rax]
    add rax, QWORD PTR [rsp+32]
    mov QWORD PTR [rsp+40], rax
    lea rax, [rip + arena_rsv_end]
    mov rax, QWORD PTR [rax]
    cmp QWORD PTR [rsp+40], rax
    ja alloc_fail
alloc_commit_loop:
    lea rax, [rip + arena_commit_end]
    mov rax, QWORD PTR [rax]
    cmp QWORD PTR [rsp+40], rax
    jbe alloc_commit_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, ARENA_CHUNK
    jae alloc_have_chunk
    mov rdx, ARENA_CHUNK
alloc_have_chunk:
    lea rcx, [rip + arena_rsv_end]
    mov rcx, QWORD PTR [rcx]
    sub rcx, rax
    cmp rdx, rcx
    jbe alloc_chunk_fit
    mov rdx, rcx
alloc_chunk_fit:
    mov QWORD PTR [rsp+32], rdx
    mov rcx, rax
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz alloc_fail
    lea rax, [rip + arena_commit_end]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rsp+32]
    mov QWORD PTR [rax], rdx
    jmp alloc_commit_loop
alloc_commit_ok:
    lea rax, [rip + arena_brk]
    mov rax, QWORD PTR [rax]
    mov rdx, QWORD PTR [rsp+40]
    lea rcx, [rip + arena_brk]
    mov QWORD PTR [rcx], rdx
    jmp alloc_done
alloc_zero:
    lea rax, [rip + arena_brk]
    mov rax, QWORD PTR [rax]
    jmp alloc_done
alloc_fail:
    xor eax, eax
alloc_done:
    add rsp, 48
    pop rbp
    ret

// arena_used: retorna RAX = bytes usados (nombres) desde la base.
arena_used:
    lea rax, [rip + arena_base]
    mov rax, QWORD PTR [rax]
    lea rdx, [rip + arena_brk]
    mov rdx, QWORD PTR [rdx]
    sub rdx, rax
    mov rax, rdx
    ret

// table_rec_base: RAX = base región records.
table_rec_base:
    lea rax, [rip + rec_rsv_base]
    mov rax, QWORD PTR [rax]
    ret

// table_stk_base: RAX = base región pila.
table_stk_base:
    lea rax, [rip + stk_rsv_base]
    mov rax, QWORD PTR [rax]
    ret

// table_ensure_rec: RCX = idx (0-based). Asegura commit para (idx+1)*12B.
// Retorna EAX 1 ok, 0 sin lugar/fallo.
table_ensure_rec:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov QWORD PTR [rsp+32], rcx
    lea rax, [rip + rec_rsv_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz tens_fail
    mov rdx, QWORD PTR [rsp+32]
    inc rdx
    imul rdx, rdx, 12
    add rdx, rax
    mov QWORD PTR [rsp+40], rdx
    lea rax, [rip + rec_rsv_end]
    mov rax, QWORD PTR [rax]
    cmp rdx, rax
    ja tens_fail
    lea rax, [rip + rec_commit_end]
    mov rax, QWORD PTR [rax]
    cmp rdx, rax
    jbe tens_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, TABLE_CHUNK
    jae tens_have
    mov rdx, TABLE_CHUNK
tens_have:
    lea rcx, [rip + rec_rsv_end]
    mov rcx, QWORD PTR [rcx]
    sub rcx, rax
    cmp rdx, rcx
    jbe tens_fit
    mov rdx, rcx
tens_fit:
    mov QWORD PTR [rsp+32], rdx
    mov rcx, rax
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz tens_fail
    lea rax, [rip + rec_commit_end]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rsp+32]
    mov QWORD PTR [rax], rdx
tens_ok:
    mov eax, 1
    add rsp, 48
    pop rbp
    ret
tens_fail:
    xor eax, eax
    add rsp, 48
    pop rbp
    ret

// table_ensure_stk: RCX = idx (0-based). Asegura commit para (idx+1)*4B.
table_ensure_stk:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    mov QWORD PTR [rsp+32], rcx
    lea rax, [rip + stk_rsv_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz stens_fail
    mov rdx, QWORD PTR [rsp+32]
    inc rdx
    shl rdx, 2
    add rdx, rax
    mov QWORD PTR [rsp+40], rdx
    lea rax, [rip + stk_rsv_end]
    mov rax, QWORD PTR [rax]
    cmp rdx, rax
    ja stens_fail
    lea rax, [rip + stk_commit_end]
    mov rax, QWORD PTR [rax]
    cmp rdx, rax
    jbe stens_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, TABLE_CHUNK
    jae stens_have
    mov rdx, TABLE_CHUNK
stens_have:
    lea rcx, [rip + stk_rsv_end]
    mov rcx, QWORD PTR [rcx]
    sub rcx, rax
    cmp rdx, rcx
    jbe stens_fit
    mov rdx, rcx
stens_fit:
    mov QWORD PTR [rsp+32], rdx
    mov rcx, rax
    mov r8d, MEM_COMMIT
    mov r9d, PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz stens_fail
    lea rax, [rip + stk_commit_end]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rsp+32]
    mov QWORD PTR [rax], rdx
stens_ok:
    mov eax, 1
    add rsp, 48
    pop rbp
    ret
stens_fail:
    xor eax, eax
    add rsp, 48
    pop rbp
    ret

// arena_free: libera nombres + tablas. Retorna EAX de VirtualFree.
arena_free:
    push rbp
    mov rbp, rsp
    sub rsp, 48
    lea rax, [rip + arena_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz free_rec
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + arena_base]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + arena_brk]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + arena_rsv_end]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + arena_commit_end]
    mov QWORD PTR [rcx], 0
free_rec:
    lea rax, [rip + rec_rsv_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz free_stk
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + rec_rsv_base]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + rec_commit_end]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + rec_rsv_end]
    mov QWORD PTR [rcx], 0
free_stk:
    lea rax, [rip + stk_rsv_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz free_done
    mov rdx, 0
    mov r8d, MEM_RELEASE
    call VirtualFree
    lea rcx, [rip + stk_rsv_base]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + stk_commit_end]
    mov QWORD PTR [rcx], 0
    lea rcx, [rip + stk_rsv_end]
    mov QWORD PTR [rcx], 0
free_done:
    add rsp, 48
    pop rbp
    ret

.bss
arena_base: .space 8
arena_brk: .space 8
arena_rsv_end: .space 8
arena_commit_end: .space 8
rec_rsv_base: .space 8
rec_commit_end: .space 8
rec_rsv_end: .space 8
stk_rsv_base: .space 8
stk_commit_end: .space 8
stk_rsv_end: .space 8
