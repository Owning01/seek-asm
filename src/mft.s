// seek-asm: mft.s — enumeración MFT directa (NTFS, requiere admin).
// Solo drive-root (X:\ o \\?\X:\). Subrutas → fallback (0) para paridad.
// Activación: scan_opt_mft==1 (--mft, fuerza). 0 = off (default, Find).
// Auto desactivado por defecto (sin paridad admin verificada): ver README.
// mft_try_root(RCX=ws) → EAX 1 si enumeró, 0 si fallback/fallo.
// En éxito: records 12B, nombres UTF-8, mismos excludes/matching/emits,
//   mft_used=1. En fallo con force: mft_force_fail=1 (sin fallback).
// Tabla FRN→tmp (hash abierto 4M x 16B, commit total) + temp bump 512MB
// (commit progresivo) con cabecera 32B por entrada + nombre WCHAR.
// Resolución padres por recursión memoizada (mft_ensure): dirs siempre,
//   files solo si match/index; excludes por full path (path_is_excluded);
//   reparse/sistema/huérfanos se ignoran (sin contar, como Find invisible).
// Reusa de scan.s: build_path, path_is_excluded, contains_ci_a,
//   glob_match_ci_a, ws_alloc, ws_rec_ensure, emit_path. Solo kernel32.

.intel_syntax noprefix
.text
.globl mft_try_root
.globl scan_opt_mft
.globl mft_used
.globl mft_force_fail
.globl mft_explicit
.globl mft_lasterr
.globl mft_stage

// NOTA GAS: todo .equ numérico va ANTES del primer uso.
.equ MFT_SLOTS, 4194304
.equ MFT_MASK, 4194303
.equ MFT_HE, 16
.equ MFT_HSIZE, 0x4000000
.equ MFT_TRSV, 0x20000000
.equ MFT_TCHUNK, 0x10000
.equ MFT_USNBUF, 65536
.equ MFT_ENUM_IN, 28
.equ FSCTL_GET_VOL, 0x90064
.equ FSCTL_ENUM_USN, 0x9C0B0
.equ MFT_GEN_READ, 0x80000000
.equ MFT_SHARE, 3
.equ MFT_OPEN, 3
.equ MFT_ATTR_DIR, 0x10
.equ MFT_ATTR_REP, 0x400
.equ MFT_EOF, 38
.equ MFT_MEM_COMMIT, 0x1000
.equ MFT_MEM_RESERVE, 0x2000
.equ MFT_MEM_RELEASE, 0x8000
.equ MFT_PAGE_RW, 0x4
.equ MFT_PAGE_NA, 0x1
.equ MFT_WMSG_LEN, 34
.equ MFT_WS_R_BASE, 32
.equ MFT_WS_A_BASE, 0
.equ MFT_WS_A_BRK, 8
.equ MFT_WS_A_RSV, 16
.equ MFT_WS_A_CEND, 24
.equ MFT_WS_R_CEND, 40
.equ MFT_WS_R_END, 48
.equ MFT_WS_REC, 80
.equ MFT_WS_RECCNT, 88
.equ MFT_WS_MTIME_BASE, 96
.equ MFT_WS_FILES, 128
.equ MFT_WS_MATCH, 136
.equ MFT_WS_EXCL, 144
.equ MFT_WS_BPCIDX, 168
.equ MFT_WS_BPCLEN, 176
.equ MFT_WS_BPMISS, 184
.equ MFT_WS_WLEN, 192
.equ MFT_WS_QALEN, 200
.equ MFT_WS_QPTR, 216
.equ MFT_WS_QLEN, 224
.equ MFT_WS_TRUNC, 160
.equ MFT_WB_ROOT, 256
.equ MFT_WB_DIRPATH, 65792
.equ MFT_WB_DIRW, 196608
.equ MFT_WB_SEG, 327936
.equ MFT_WB_NTMP, 394112
.equ MFT_WB_EMITW, 395136
.equ MFT_WB_QA, 460672
.equ MFT_WB_OUTW, 468864
.equ MFT_WB_OUTA, 534400

// mft_tmp_alloc: RCX=bytes (ya incluye cabecera+nombre+pad) -> RAX=ptr, 0 fail.
// Bump en región temp con commit progresivo (patrón ws_alloc).
mft_tmp_alloc:
    sub rsp, 64
    mov QWORD PTR [rsp+32], rcx
    add rcx, 7
    and rcx, -8
    mov QWORD PTR [rsp+32], rcx
    test rcx, rcx
    jz mta_zero
    lea rax, [rip + mft_tmp_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz mta_fail
    lea rdx, [rip + mft_tmp_brk]
    mov rdx, QWORD PTR [rdx]
    add rdx, rcx
    mov QWORD PTR [rsp+40], rdx
    lea rax, [rip + mft_tmp_rsv]
    mov rax, QWORD PTR [rax]
    cmp rdx, rax
    ja mta_fail
mta_cloop:
    lea rax, [rip + mft_tmp_cend]
    mov rax, QWORD PTR [rax]
    cmp QWORD PTR [rsp+40], rax
    jbe mta_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, MFT_TCHUNK
    jae mta_hc
    mov rdx, MFT_TCHUNK
mta_hc:
    lea rcx, [rip + mft_tmp_rsv]
    mov rcx, QWORD PTR [rcx]
    sub rcx, rax
    cmp rdx, rcx
    jbe mta_cf
    mov rdx, rcx
mta_cf:
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], rdx
    mov rcx, rax
    mov r8d, MFT_MEM_COMMIT
    mov r9d, MFT_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz mta_fail
    lea rax, [rip + mft_tmp_cend]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rsp+56]
    mov QWORD PTR [rax], rdx
    jmp mta_cloop
mta_ok:
    lea rax, [rip + mft_tmp_brk]
    mov rax, QWORD PTR [rax]
    mov rdx, QWORD PTR [rsp+40]
    lea rcx, [rip + mft_tmp_brk]
    mov QWORD PTR [rcx], rdx
    jmp mta_done
mta_zero:
    lea rax, [rip + mft_tmp_brk]
    mov rax, QWORD PTR [rax]
    jmp mta_done
mta_fail:
    xor eax, eax
mta_done:
    add rsp, 64
    ret

// mft_hash_insert: RCX=FRN, RDX=temp_off (u32) -> EAX 1 ok, 0 llena.
// Lineal, h=FRN&MASK. FRN 0 = libre (nunca se inserta FRN<16 salvo 5,
// y el 5 (raíz) no se inserta: se resuelve directo a mft_root_idx).
mft_hash_insert:
    push rbx
    mov rbx, rcx
    lea rax, [rip + mft_hash_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz mhi_fail
    mov rcx, rbx
    and rcx, MFT_MASK
mhi_probe:
    mov r8, rcx
    shl r8, 4
    add r8, rax
    mov r9, QWORD PTR [r8]
    test r9, r9
    jz mhi_store
    cmp r9, rbx
    je mhi_dup
    inc rcx
    and rcx, MFT_MASK
    jmp mhi_probe
mhi_store:
    mov QWORD PTR [r8], rbx
    mov DWORD PTR [r8+8], edx
    mov DWORD PTR [r8+12], 0
    mov eax, 1
    pop rbx
    ret
mhi_dup:
    mov DWORD PTR [r8+8], edx
    mov eax, 1
    pop rbx
    ret
mhi_fail:
    xor eax, eax
    pop rbx
    ret

// mft_hash_find: RCX=FRN -> RAX=temp_off (u32, zero-ext) o -1 si miss. Leaf.
mft_hash_find:
    lea rax, [rip + mft_hash_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz mhf_miss
    mov rdx, rcx
    and rdx, MFT_MASK
mhf_probe:
    mov r8, rdx
    shl r8, 4
    add r8, rax
    mov r9, QWORD PTR [r8]
    test r9, r9
    jz mhf_miss
    cmp r9, rcx
    je mhf_hit
    inc rdx
    and rdx, MFT_MASK
    jmp mhf_probe
mhf_hit:
    mov eax, DWORD PTR [r8+8]
    ret
mhf_miss:
    mov rax, -1
    ret

// mft_ensure: RCX=temp_off (u32) -> RAX=final idx (>=0), -2 ignorado, -3 excluido.
// Recursivo (prof ≤30). Usa R15=ws (fijado por mft_try_root antes del loop).
// Frame 8 pushes + sub 176 (alineado como scan_root_ws).
mft_ensure:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    // alinear rsp a 16B: skc_* (Rust) exige 16B en sus llamadas
    and rsp, -16
    sub rsp, 176
    mov r15, QWORD PTR [rip + mft_ws]
    mov QWORD PTR [rsp+64], rcx
    lea rax, [rip + mft_tmp_base]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz men_ign
    mov rdx, QWORD PTR [rsp+64]
    add rax, rdx
    mov QWORD PTR [rsp+72], rax
    mov rax, QWORD PTR [rax+24]
    cmp rax, -1
    jne men_memo
    mov rbx, QWORD PTR [rsp+72]
    mov r12, QWORD PTR [rbx]
    mov r13, QWORD PTR [rbx+8]
    mov r14d, DWORD PTR [rbx+16]
    mov QWORD PTR [rsp+80], r12
    mov QWORD PTR [rsp+88], r13
    mov DWORD PTR [rsp+96], r14d
    mov eax, DWORD PTR [rbx+20]
    mov DWORD PTR [rsp+100], eax
    lea rsi, [rbx+32]
    mov QWORD PTR [rsp+104], rsi
    test r14d, MFT_ATTR_REP
    jnz men_ign
    cmp eax, 0
    je men_ign
    cmp eax, 520
    ja men_ign
    cmp eax, 2
    jne men_notdot
    cmp WORD PTR [rsi], 0x2E
    je men_ign
men_notdot:
    cmp eax, 4
    jne men_nodotdot
    cmp WORD PTR [rsi], 0x2E
    jne men_nodotdot
    cmp WORD PTR [rsi+2], 0x2E
    je men_ign
men_nodotdot:
    cmp r13, r12
    je men_ign
    cmp r13, 5
    je men_par_root
    cmp r13, 16
    jb men_ign
    mov rcx, r13
    call mft_hash_find
    cmp rax, -1
    je men_ign
    mov rcx, rax
    call mft_ensure
    cmp rax, -2
    je men_ign
    cmp rax, -3
    je men_excl_parent
    mov QWORD PTR [rsp+112], rax
    jmp men_havepar
men_par_root:
    mov rax, QWORD PTR [rip + mft_root_idx]
    mov QWORD PTR [rsp+112], rax
men_havepar:
    mov r11d, DWORD PTR [rsp+112]
    mov rcx, r15
    call build_path
    test eax, eax
    jz men_ign
    mov r9d, eax
    mov rax, QWORD PTR [r15 + MFT_WS_BPMISS]
    test rax, rax
    jz men_xb_wok
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + MFT_WB_DIRPATH]
    lea rax, [r15 + MFT_WB_DIRW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz men_ign
    mov DWORD PTR [rsp+116], eax
    movsxd rdx, eax
    mov QWORD PTR [r15 + MFT_WS_WLEN], rdx
    jmp men_xb_build
men_xb_wok:
    mov eax, DWORD PTR [r15 + MFT_WS_BPCLEN]
    mov DWORD PTR [rsp+116], eax
men_xb_build:
    lea rsi, [r15 + MFT_WB_DIRW]
    lea rdi, [r15 + MFT_WB_SEG]
    mov ecx, DWORD PTR [rsp+116]
    rep movsw
    mov eax, DWORD PTR [rsp+116]
    test eax, eax
    jz men_xb_name
    movzx edx, WORD PTR [rdi-2]
    cmp edx, 0x5C
    je men_xb_name
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
    inc eax
men_xb_name:
    mov ecx, DWORD PTR [rsp+100]
    shr ecx, 1
    add eax, ecx
    cmp eax, 32767
    ja men_ign
    mov DWORD PTR [rsp+120], eax
    mov rsi, QWORD PTR [rsp+104]
    rep movsw
    mov WORD PTR [rdi], 0
    lea rsi, [r15 + MFT_WB_SEG]
    mov ecx, DWORD PTR [rsp+120]
    call path_is_excluded
    test eax, eax
    jnz men_excl
    mov rcx, 65001
    xor edx, edx
    mov r8, QWORD PTR [rsp+104]
    mov r9d, DWORD PTR [rsp+100]
    shr r9d, 1
    lea rax, [r15 + MFT_WB_NTMP]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 1024
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz men_ign
    mov DWORD PTR [rsp+124], eax
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne men_store
    // query de ruta: match de ruta completo una vez; flag en [rsp+152]
    mov QWORD PTR [rsp+152], 0
    cmp QWORD PTR [rip + scan_is_pathq], 0
    je men_pq_nom
    lea rcx, [r15 + MFT_WB_SEG]
    mov eax, DWORD PTR [rsp+120]
    mov rdx, rax
    mov r8, QWORD PTR [r15 + MFT_WS_QPTR]
    mov r9, QWORD PTR [r15 + MFT_WS_QLEN]
    mov rax, QWORD PTR [rip + scan_is_glob]
    mov QWORD PTR [rsp+32], rax
    call skc_match_path
    movsxd rdx, eax
    mov QWORD PTR [rsp+152], rdx
men_pq_nom:
    mov eax, DWORD PTR [rsp+96]
    test eax, MFT_ATTR_DIR
    jnz men_store
    // FILE: en pathq el flag ya decide; sin pathq, match de nombre
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne men_pqf
    lea rcx, [r15 + MFT_WB_NTMP]
    mov edx, DWORD PTR [rsp+124]
    lea r8, [r15 + MFT_WB_QA]
    mov r9, QWORD PTR [r15 + MFT_WS_QALEN]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne men_gf
    call contains_ci_a
    jmp men_gd
men_gf:
    call glob_match_ci_a
men_gd:
    test eax, eax
    jz men_file_nomatch
    jmp men_store
men_pqf:
    cmp QWORD PTR [rsp+152], 0
    jne men_store
    jmp men_file_nomatch
men_store:
    mov ecx, DWORD PTR [rsp+124]
    add ecx, 3
    mov edx, ecx
    mov rcx, r15
    call ws_alloc
    test rax, rax
    jz men_trunc
    mov ecx, DWORD PTR [rsp+124]
    mov WORD PTR [rax], cx
    mov QWORD PTR [rsp+128], rax
    lea rdi, [rax+2]
    lea rsi, [r15 + MFT_WB_NTMP]
    rep movsb
    mov BYTE PTR [rdi], 0
    mov rax, QWORD PTR [rsp+128]
    add rax, 2
    mov QWORD PTR [rsp+136], rax
    mov rax, QWORD PTR [r15 + MFT_WS_RECCNT]
    mov QWORD PTR [rsp+144], rax
    mov rcx, r15
    mov rdx, rax
    call ws_rec_ensure
    test eax, eax
    jz men_trunc
    mov rax, QWORD PTR [r15 + MFT_WS_REC]
    mov rdx, QWORD PTR [rsp+144]
    imul rdx, rdx, 12
    add rax, rdx
    mov rdx, QWORD PTR [rsp+136]
    mov QWORD PTR [rax], rdx
    mov edx, DWORD PTR [rsp+112]
    mov ecx, DWORD PTR [rsp+96]
    test ecx, MFT_ATTR_DIR
    jz men_parfile
    or edx, 0x80000000
men_parfile:
    mov DWORD PTR [rax+8], edx
    // mtime: 0 (MFT no da FILETIME aqui; CLI no tickea)
    mov rcx, QWORD PTR [r15 + MFT_WS_MTIME_BASE]
    test rcx, rcx
    jz men_nomtime
    mov rdx, QWORD PTR [rsp+144]
    mov QWORD PTR [rcx+rdx*8], 0
men_nomtime:
    mov rax, QWORD PTR [r15 + MFT_WS_RECCNT]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_RECCNT], rax
    mov rax, QWORD PTR [r15 + MFT_WS_FILES]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_FILES], rax
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne men_memo_ok
    mov eax, DWORD PTR [rsp+96]
    test eax, MFT_ATTR_DIR
    jz men_fmatch
    // pathq: decide el flag [rsp+152]; sin pathq, match de nombre
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne men_pqd
    lea rcx, [r15 + MFT_WB_NTMP]
    mov edx, DWORD PTR [rsp+124]
    lea r8, [r15 + MFT_WB_QA]
    mov r9, QWORD PTR [r15 + MFT_WS_QALEN]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne men_gd2
    call contains_ci_a
    jmp men_gd3
men_gd2:
    call glob_match_ci_a
men_gd3:
    test eax, eax
    jz men_memo_ok
    jmp men_emit
men_pqd:
    cmp QWORD PTR [rsp+152], 0
    jne men_emit
    jmp men_memo_ok
men_fmatch:
    mov rax, QWORD PTR [r15 + MFT_WS_MATCH]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_MATCH], rax
    lea rax, [rip + scan_opt_countonly]
    cmp QWORD PTR [rax], 0
    jne men_memo_ok2
    jmp men_emit2
men_emit:
    mov rax, QWORD PTR [r15 + MFT_WS_MATCH]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_MATCH], rax
    lea rax, [rip + scan_opt_countonly]
    cmp QWORD PTR [rax], 0
    jne men_memo_ok2
men_emit2:
    mov r11d, DWORD PTR [rsp+144]
    mov rcx, r15
    call build_path
    test eax, eax
    jz men_memo_ok2
    mov r9d, eax
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + MFT_WB_DIRPATH]
    lea rax, [r15 + MFT_WB_EMITW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz men_memo_ok2
    lea rsi, [r15 + MFT_WB_EMITW]
    mov edx, eax
    mov rcx, r15
    call emit_path
    jmp men_memo_ok2
men_file_nomatch:
    mov rax, QWORD PTR [r15 + MFT_WS_FILES]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_FILES], rax
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], -2
    mov rax, -2
    jmp men_ret
men_memo_ok:
    mov rdx, QWORD PTR [rsp+144]
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], rdx
    mov rax, rdx
    jmp men_ret
men_memo_ok2:
    mov rdx, QWORD PTR [rsp+144]
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], rdx
    mov rax, rdx
    jmp men_ret
men_excl:
    mov rax, QWORD PTR [r15 + MFT_WS_EXCL]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_EXCL], rax
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], -3
    mov rax, -3
    jmp men_ret
men_excl_parent:
    mov rax, QWORD PTR [r15 + MFT_WS_EXCL]
    inc rax
    mov QWORD PTR [r15 + MFT_WS_EXCL], rax
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], -3
    mov rax, -3
    jmp men_ret
men_memo:
    mov rax, QWORD PTR [rsp+72]
    mov rax, QWORD PTR [rax+24]
    jmp men_ret
men_trunc:
    mov rax, QWORD PTR [r15 + MFT_WS_TRUNC]
    mov QWORD PTR [r15 + MFT_WS_TRUNC], 1
    mov rbx, QWORD PTR [rsp+72]
    mov QWORD PTR [rbx+24], -2
    mov rax, -2
    jmp men_ret
men_ign:
    mov rbx, QWORD PTR [rsp+72]
    test rbx, rbx
    jz men_ign_norecord
    mov QWORD PTR [rbx+24], -2
men_ign_norecord:
    mov rax, -2
men_ret:
    lea rsp, [rbp-56]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// mft_try_root: RCX=ws -> EAX 1 enumeró, 0 fallback/fallo.
// Solo si scan_opt_mft==1 y raíz es drive-root y volumen abre (admin).
// Frame 8 pushes + sub 256. Locales: +64 ws, +72 handle, +80 in_usn,
//   +112 out_bytes, +120 next_frn, +128 enum_in (28B en +128..155),
//   +160 volpath (7 WCHAR), +176 saved_reccnt/files/match/excl/brk.
mft_try_root:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256
    mov r15, rcx
    mov QWORD PTR [rsp+64], rcx
    mov QWORD PTR [rip + mft_lasterr], 0
    mov QWORD PTR [rip + mft_stage], 0
    mov QWORD PTR [rsp+72], -1
    mov QWORD PTR [rip + mft_ws], rcx
    lea rax, [rip + scan_opt_mft]
    cmp QWORD PTR [rax], 0
    je mft_fallback
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    jne mft_warn_fallback
    lea rax, [r15 + MFT_WB_ROOT]
    mov ecx, DWORD PTR [rax]
    cmp ecx, 0x005C005C
    jne mft_warn_fallback
    movzx ecx, WORD PTR [rax+4]
    cmp ecx, 0x3F
    jne mft_warn_fallback
    movzx ecx, WORD PTR [rax+6]
    cmp ecx, 0x5C
    jne mft_warn_fallback
    movzx ecx, WORD PTR [rax+8]
    cmp ecx, 0x41
    jb mft_checklc
    cmp ecx, 0x5A
    jbe mft_drvok
mft_checklc:
    cmp ecx, 0x61
    jb mft_warn_fallback
    cmp ecx, 0x7A
    ja mft_warn_fallback
mft_drvok:
    movzx edx, WORD PTR [rax+10]
    cmp edx, 0x3A
    jne mft_warn_fallback
    movzx edx, WORD PTR [rax+12]
    cmp edx, 0x5C
    jne mft_warn_fallback
    movzx edx, WORD PTR [rax+14]
    test edx, edx
    jnz mft_warn_fallback
    mov QWORD PTR [rip + mft_drive], rcx
    mov rax, QWORD PTR [r15 + MFT_WS_RECCNT]
    mov QWORD PTR [rsp+176], rax
    mov rax, QWORD PTR [r15 + MFT_WS_FILES]
    mov QWORD PTR [rsp+184], rax
    mov rax, QWORD PTR [r15 + MFT_WS_MATCH]
    mov QWORD PTR [rsp+192], rax
    mov rax, QWORD PTR [r15 + MFT_WS_EXCL]
    mov QWORD PTR [rsp+200], rax
    mov rax, QWORD PTR [r15 + MFT_WS_A_BRK]
    mov QWORD PTR [rsp+208], rax
    mov rax, QWORD PTR [r15 + MFT_WS_RECCNT]
    dec rax
    mov QWORD PTR [rip + mft_root_idx], rax
    mov WORD PTR [rsp+160], 0x5C
    mov WORD PTR [rsp+162], 0x5C
    mov WORD PTR [rsp+164], 0x2E
    mov WORD PTR [rsp+166], 0x5C
    mov rax, QWORD PTR [rip + mft_drive]
    mov WORD PTR [rsp+168], ax
    mov WORD PTR [rsp+170], 0x3A
    mov WORD PTR [rsp+172], 0
    lea rcx, [rsp+160]
    mov rdx, MFT_GEN_READ
    mov r8d, MFT_SHARE
    mov r9d, MFT_OPEN
    mov QWORD PTR [rsp+32], 0x80
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0
    call CreateFileW
    cmp rax, -1
    jne 1f
    call GetLastError
    movsxd rax, eax
    mov QWORD PTR [rip + mft_lasterr], rax
    jmp mft_openfail
1:
    mov QWORD PTR [rsp+72], rax
    mov rcx, rax
    mov edx, FSCTL_GET_VOL
    lea r8, [r15 + MFT_WB_NTMP]
    xor r9d, r9d
    mov QWORD PTR [rsp+32], r8
    mov QWORD PTR [rsp+40], 1024
    lea rax, [rsp+112]
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], 0
    call DeviceIoControl
    test eax, eax
    jnz mft_gv_ok
    call GetLastError
    movsxd rax, eax
    mov QWORD PTR [rip + mft_lasterr], rax
    mov QWORD PTR [rip + mft_stage], 2
    jmp mft_iofail
mft_gv_ok:
    mov rcx, 0
    mov rdx, MFT_TRSV
    mov r8d, MFT_MEM_RESERVE
    mov r9d, MFT_PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz mft_iofail
    lea rcx, [rip + mft_tmp_base]
    mov QWORD PTR [rcx], rax
    lea rcx, [rip + mft_tmp_brk]
    mov QWORD PTR [rcx], rax
    add rax, MFT_TRSV
    lea rcx, [rip + mft_tmp_rsv]
    mov QWORD PTR [rcx], rax
    lea rax, [rip + mft_tmp_base]
    mov rax, QWORD PTR [rax]
    lea rcx, [rip + mft_tmp_cend]
    mov QWORD PTR [rcx], rax
    mov rcx, 0
    mov rdx, MFT_HSIZE
    mov r8d, MFT_MEM_COMMIT
    or r8d, MFT_MEM_RESERVE
    mov r9d, MFT_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz mft_tmpfail
    lea rcx, [rip + mft_hash_base]
    mov QWORD PTR [rcx], rax
    mov rcx, 0
    mov rdx, MFT_USNBUF
    mov r8d, MFT_MEM_COMMIT
    or r8d, MFT_MEM_RESERVE
    mov r9d, MFT_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz mft_hashfail
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+120], 0
mft_enum:
    mov rax, 0x0000000200000002
    mov QWORD PTR [rsp+128], rax
    mov QWORD PTR [rsp+136], 0
    mov QWORD PTR [rsp+144], -1
    mov WORD PTR [rsp+152], 2
    mov WORD PTR [rsp+154], 2
    mov rcx, QWORD PTR [rsp+72]
    mov edx, FSCTL_ENUM_USN
    lea r8, [rsp+128]
    mov r9d, 8
    mov rax, QWORD PTR [rsp+80]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], MFT_USNBUF
    lea rax, [rsp+112]
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], 0
    call DeviceIoControl
    test eax, eax
    jz mft_enum_err
    mov r12, QWORD PTR [rsp+112]
    cmp r12, 8
    jbe mft_enum_done
    mov rax, QWORD PTR [rsp+80]
    mov rdx, QWORD PTR [rax]
    mov QWORD PTR [rsp+120], rdx
    mov r13, 8
mft_rec:
    cmp r13, r12
    jae mft_enum
    mov rax, QWORD PTR [rsp+80]
    add rax, r13
    mov edx, DWORD PTR [rax]
    test edx, edx
    jz mft_enum
    cmp edx, 60
    jb mft_rec_next
    mov rbx, rax
    movzx ecx, WORD PTR [rbx+4]
    cmp ecx, 2
    jne mft_rec_next
    mov r8, QWORD PTR [rbx+8]
    cmp r8, 5
    je mft_rec_next
    cmp r8, 16
    jb mft_rec_next
    mov r9, QWORD PTR [rbx+16]
    mov r10d, DWORD PTR [rbx+52]
    movzx r11d, WORD PTR [rbx+56]
    test r11d, r11d
    jz mft_rec_next
    cmp r11d, 520
    ja mft_rec_next
    movzx eax, WORD PTR [rbx+58]
    cmp eax, 60
    jb mft_rec_next
    mov rcx, rax
    add rcx, r11
    cmp rcx, rdx
    ja mft_rec_next
    lea rsi, [rbx+rax]
    mov rax, r11
    add rax, 32
    add rax, 7
    and rax, -8
    mov QWORD PTR [rsp+216], r8
    mov QWORD PTR [rsp+224], r9
    mov DWORD PTR [rsp+232], r10d
    mov DWORD PTR [rsp+236], r11d
    mov QWORD PTR [rsp+240], rsi
    mov rcx, rax
    call mft_tmp_alloc
    test rax, rax
    jz mft_tmpfull
    mov r8, QWORD PTR [rsp+216]
    mov QWORD PTR [rax], r8
    mov r8, QWORD PTR [rsp+224]
    mov QWORD PTR [rax+8], r8
    mov r8d, DWORD PTR [rsp+232]
    mov DWORD PTR [rax+16], r8d
    mov r8d, DWORD PTR [rsp+236]
    mov DWORD PTR [rax+20], r8d
    mov QWORD PTR [rax+24], -1
    lea rdi, [rax+32]
    mov rsi, QWORD PTR [rsp+240]
    mov ecx, DWORD PTR [rsp+236]
    rep movsb
    lea rdx, [rip + mft_tmp_base]
    mov rdx, QWORD PTR [rdx]
    sub rax, rdx
    mov edx, eax
    mov rcx, QWORD PTR [rsp+216]
    call mft_hash_insert
    test eax, eax
    jz mft_tmpfull
mft_rec_next:
    mov rax, QWORD PTR [rsp+80]
    add rax, r13
    mov edx, DWORD PTR [rax]
    add r13, rdx
    jmp mft_rec
mft_enum_err:
    call GetLastError
    movsxd r12d, eax
    mov QWORD PTR [rip + mft_lasterr], r12
    mov QWORD PTR [rip + mft_stage], 3
    cmp eax, MFT_EOF
    je mft_enum_done
    cmp eax, 259
    je mft_enum_done
    jmp mft_iofail
mft_enum_done:
    lea rax, [rip + mft_tmp_base]
    mov rax, QWORD PTR [rax]
    mov QWORD PTR [rsp+248], rax
    lea rax, [rip + mft_tmp_brk]
    mov rax, QWORD PTR [rax]
    mov QWORD PTR [rsp+240], rax
mft_eloop:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, QWORD PTR [rsp+240]
    jae mft_eok
    lea rdx, [rip + mft_tmp_base]
    mov rdx, QWORD PTR [rdx]
    sub rax, rdx
    mov rcx, rax
    call mft_ensure
    mov rax, QWORD PTR [rsp+248]
    movzx edx, WORD PTR [rax+20]
    mov rcx, rdx
    add rcx, 32
    add rcx, 7
    and rcx, -8
    add QWORD PTR [rsp+248], rcx
    jmp mft_eloop
mft_eok:
    lea rax, [rip + mft_used]
    mov QWORD PTR [rax], 1
    jmp mft_cleanup_ok
mft_tmpfull:
    jmp mft_iofail
mft_tmpfail:
    mov QWORD PTR [rip + mft_stage], 4
    jmp mft_iofail
mft_hashfail:
    mov QWORD PTR [rip + mft_stage], 4
    lea rax, [rip + mft_tmp_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz mft_openfail2
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    lea rax, [rip + mft_tmp_base]
    mov QWORD PTR [rax], 0
    jmp mft_openfail2
mft_openfail:
    mov QWORD PTR [rip + mft_stage], 1
    lea rax, [rip + mft_explicit]
    cmp QWORD PTR [rax], 0
    je mft_fallback
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 1
    jmp mft_fallback
mft_openfail2:
    lea rax, [rip + mft_explicit]
    cmp QWORD PTR [rax], 0
    je mft_fallback
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 1
    jmp mft_fallback
mft_iofail:
    call GetLastError
    movsxd rax, eax
    mov QWORD PTR [rip + mft_lasterr], rax
    cmp QWORD PTR [rip + mft_stage], 0
    jne 3f
    mov QWORD PTR [rip + mft_stage], 5
3:
    mov rcx, QWORD PTR [rsp+72]
    cmp rcx, -1
    je mft_restore
    call CloseHandle
    mov QWORD PTR [rsp+72], -1
    lea rax, [rip + mft_hash_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz mft_freetmp
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    lea rax, [rip + mft_hash_base]
    mov QWORD PTR [rax], 0
mft_freetmp:
    lea rax, [rip + mft_tmp_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz mft_freeusn
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    lea rax, [rip + mft_tmp_base]
    mov QWORD PTR [rax], 0
mft_freeusn:
    mov rcx, QWORD PTR [rsp+80]
    test rcx, rcx
    jz mft_restore
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    mov QWORD PTR [rsp+80], 0
mft_restore:
    mov rax, QWORD PTR [rsp+176]
    mov QWORD PTR [r15 + MFT_WS_RECCNT], rax
    mov rax, QWORD PTR [rsp+184]
    mov QWORD PTR [r15 + MFT_WS_FILES], rax
    mov rax, QWORD PTR [rsp+192]
    mov QWORD PTR [r15 + MFT_WS_MATCH], rax
    mov rax, QWORD PTR [rsp+200]
    mov QWORD PTR [r15 + MFT_WS_EXCL], rax
    mov rax, QWORD PTR [rsp+208]
    mov QWORD PTR [r15 + MFT_WS_A_BRK], rax
    mov QWORD PTR [r15 + MFT_WS_BPCIDX], -1
    lea rax, [rip + mft_explicit]
    cmp QWORD PTR [rax], 0
    je mft_fallback
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 1
mft_fallback:
    xor eax, eax
    jmp mft_ret
// Subruta o --topdirs con --mft: aviso explícito (no silencioso) + Find.
// Solo el fallo de apertura (admin/NTFS) es error fatal (force_fail).
mft_warn_fallback:
    // Aviso solo si --mft explícito; en auto, fallback silencioso
    lea rax, [rip + mft_explicit]
    cmp QWORD PTR [rax], 0
    je mft_fallback
    sub rsp, 80
    lea rax, [rip + scan_opt_errh]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rip + mft_wmsg]
    mov r8d, MFT_WMSG_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    add rsp, 80
    xor eax, eax
    jmp mft_ret
mft_force_fail_ret:
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 1
    xor eax, eax
    jmp mft_ret
mft_cleanup_ok:
    mov rcx, QWORD PTR [rsp+72]
    call CloseHandle
    lea rax, [rip + mft_hash_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz mft_ctmp
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    lea rax, [rip + mft_hash_base]
    mov QWORD PTR [rax], 0
mft_ctmp:
    lea rax, [rip + mft_tmp_base]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz mft_cusn
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
    lea rax, [rip + mft_tmp_base]
    mov QWORD PTR [rax], 0
mft_cusn:
    mov rcx, QWORD PTR [rsp+80]
    test rcx, rcx
    jz mft_ok1
    mov rdx, 0
    mov r8d, MFT_MEM_RELEASE
    call VirtualFree
mft_ok1:
    mov eax, 1
mft_ret:
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

.data
mft_drive: .quad 0
mft_wmsg: .ascii "seek: --mft solo unidad, uso Find\n"

.bss
scan_opt_mft: .space 8
mft_used: .space 8
mft_force_fail: .space 8
mft_explicit: .space 8
mft_ws: .space 8
mft_root_idx: .space 8
mft_tmp_base: .space 8
mft_tmp_brk: .space 8
mft_tmp_rsv: .space 8
mft_tmp_cend: .space 8
mft_hash_base: .space 8
mft_lasterr: .space 8
mft_stage: .space 8
