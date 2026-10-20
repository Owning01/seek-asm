// seek-asm: scan.s — DFS iterativo con pila explícita (sin recursión).
// Un hilo por disco: cada scan vive en un WORKSPACE privado (bloque 640KB +
// regiones VirtualAlloc propias: nombres 256MB, records 32MB, pila 4MB).
// Nada writable se comparte entre hilos: cero locks, cero interlocked.
// Solo lectura compartida: excludes, opts, query WCHAR original.
// Registro fijo de 12 bytes: name_ptr:8, parent_idx:4 (bit31 = is_dir).
// La raíz de cada scan lleva parent 0xFFFFFFFF (termina build_path);
// su índice es root_start (0 en workspaces frescos, acumula multi-raíz).
// Nombres UTF-8 en la arena con prefijo de largo en BYTES (1 WORD) + NUL.
// Conversión WCHAR->UTF-8 una vez al guardar (WideCharToMultiByte); match
// directo sobre bytes con contains_ci_a; vuelta a WCHAR solo para FindFirst
// (pat) y emit_path (emitw). dirpath guarda BYTES; dirpath_w cachea el padre
// en WCHAR; build_path tiene cache de un nivel (mismo índice, sin rebuild).
// scan_run_all: 1 CreateThread por unidad FIXED/REMOVABLE; el main suma y
// flushea en orden de unidad (salida determinista). scan_run: 1 raíz inline.
// R15 = workspace (callee-saved, sobrevive calls); RBX = dir idx en DFS.

.intel_syntax noprefix
.text
.globl scan_run
.globl scan_one_root
.globl scan_run_all
.globl scan_add_exclude
.globl scan_set_opts
.globl path_is_excluded
.globl scan_arena_used
.globl g_files
.globl g_matches
.globl g_excluded
.globl g_disks
.globl scan_opt_countonly
.globl scan_opt_handle
.globl scan_truncated
.globl scan_opt_index
.globl scan_bloom
.globl scan_big_rec
.globl ws_create
.globl ws_free
.globl ws_used
.globl ws_alloc
.globl ws_rec_ensure
.globl emit_path
.globl scan_root_ws
.globl build_path
.globl scan_ws_recbase
.globl scan_ws_reccnt
.globl scan_ws_path
.globl scan_ws_parent
.globl scan_ws_files
.globl scan_idxdbg
.globl scan_opt_idxdbg
.globl scan_is_glob
.globl opt_incsys
.globl opt_inccache
.globl opt_inctemp
.globl scan_opt_topdirs
.globl scan_opt_errh
.globl scan_filter_ms
.globl scan_is_pathq

// NOTA GAS: todo .equ numérico va ANTES del primer uso.
.equ OUT_CAP, 32768
.equ SEG_MAX, 4096
.equ EXCL_MAX, 16
.equ EXCL_SLOT_W, 260
.equ EXCL_SLOT_B, 520
.equ WIN_MID_LEN, 9
.equ WIN_END_LEN, 8
.equ NM_MID_LEN, 14
.equ NM_END_LEN, 13
.equ REC_LEN, 12
.equ SYS_LEN, 25
.equ PF_LEN, 12
.equ HIB_LEN, 12
.equ SWP_LEN, 12
.equ WINRE_LEN, 11
.equ RECOV_LEN, 8
.equ CFGMSI_LEN, 10
.equ MSO_LEN, 8
.equ WBT_LEN, 12
.equ WWS_LEN, 12
.equ WINOLD_LEN, 11
.equ PERF_LEN, 8
.equ PREF_LEN, 8
.equ SOFT_LEN, 20
.equ WTEMP_LEN, 12
.equ ATEMP_LEN, 18
.equ INET_LEN, 9
.equ BCACHE_LEN, 6
.equ CODEC_LEN, 10
.equ SVCW_LEN, 14
.equ PYC_LEN, 11
.equ FINDEX_BASIC, 1
.equ FINDEX_NAMEMATCH, 0
.equ FIND_EX_LARGE_FETCH, 2
// Workspace: cabecera de estado (offset WS_*) + buffers (offset WB_*).
.equ WS_A_BASE, 0
.equ WS_A_BRK, 8
.equ WS_A_RSV, 16
.equ WS_A_CEND, 24
.equ WS_R_BASE, 32
.equ WS_R_CEND, 40
.equ WS_R_END, 48
.equ WS_S_BASE, 56
.equ WS_S_CEND, 64
.equ WS_S_END, 72
.equ WS_REC, 80
.equ WS_RECCNT, 88
.equ WS_STK, 104
.equ WS_STKTOP, 112
.equ WS_FILES, 128
.equ WS_MATCH, 136
.equ WS_EXCL, 144
.equ WS_OUTPOS, 152
.equ WS_TRUNC, 160
.equ WS_BPCIDX, 168
.equ WS_BPCLEN, 176
.equ WS_BPMISS, 184
.equ WS_WLEN, 192
.equ WS_QALEN, 200
.equ WS_DRIVE, 208
.equ WS_QPTR, 216
.equ WS_QLEN, 224
.equ WS_BPTMP, 232
.equ WS_MTIME_BASE, 96
.equ WS_MTIME_END, 240
.equ WS_MTIME_CEND, 120
.equ WS_HDRSZ, 256
.equ WB_ROOT, 256
.equ WB_DIRPATH, 65792
.equ WB_DIRW, 196608
.equ WB_PAT, 262400
.equ WB_SEG, 327936
.equ WB_FIND, 393472
.equ WB_NTMP, 394112
.equ WB_EMITW, 395136
.equ WB_QA, 460672
.equ WB_OUTW, 468864
.equ WB_OUTA, 534400
.equ WB_ALLOC, 0xA0000
.equ WS_NAMES_RSV, 0x10000000
.equ WS_NAMES_CHUNK, 0x10000
.equ WS_REC_RSV, 0x2000000
.equ WS_STK_RSV, 0x400000
.equ WS_TABLE_CHUNK, 0x10000
.equ WS_MEM_COMMIT, 0x1000
.equ WS_MEM_RESERVE, 0x2000
.equ WS_MEM_RELEASE, 0x8000
.equ WS_PAGE_RW, 0x4
.equ WS_PAGE_NA, 0x1
.equ WS_REC_MAX, 2097152
.equ WS_STK_MAX, 1048576
.equ WS_REC_BIG, 0x8000000

// scan_set_opts: RCX=noexcl, RDX=incwin, R8=incnm. Leaf.
scan_set_opts:
    lea rax, [rip + opt_noexcl]
    mov QWORD PTR [rax], rcx
    lea rax, [rip + opt_incwin]
    mov QWORD PTR [rax], rdx
    lea rax, [rip + opt_incnm]
    mov QWORD PTR [rax], r8
    ret

// scan_add_exclude: RCX=ptr WCHAR, RDX=len -> EAX 1 ok, 0 fail.
// Copia con lowercase (A-Z). Valida len 1..128 y count<16.
// Si el patron tiene '*' o '?' setea su bit en excl_glob (match via Rust).
scan_add_exclude:
    push rbx
    push rsi
    push rdi
    push r11
    push r12
    test rdx, rdx
    jz sae_fail
    cmp rdx, 128
    ja sae_fail
    lea rax, [rip + excl_count]
    mov rax, QWORD PTR [rax]
    cmp rax, 16
    jae sae_fail
    mov rbx, rax
    mov r11, rdx
    mov r10, rdx
    mov rsi, rcx
    xor r12d, r12d
    mov rax, rbx
    shl rax, 9
    mov rdx, rbx
    shl rdx, 3
    add rax, rdx
    lea rdx, [rip + excl_data]
    add rax, rdx
    mov rdi, rax
sae_loop:
    test r10, r10
    jz sae_done
    movzx eax, WORD PTR [rsi]
    cmp eax, 0x2A
    je sae_wild
    cmp eax, 0x3F
    je sae_wild
    cmp eax, 0x41
    jb sae_nofold
    cmp eax, 0x5A
    ja sae_nofold
    add eax, 0x20
sae_nofold:
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    dec r10
    jmp sae_loop
sae_wild:
    mov r12d, 1
    jmp sae_nofold
sae_done:
    lea rax, [rip + excl_lens]
    mov QWORD PTR [rax + rbx*8], r11
    test r12d, r12d
    jz sae_noglob
    mov rcx, rbx
    mov rax, 1
    shl rax, cl
    lea rdx, [rip + excl_glob]
    or QWORD PTR [rdx], rax
sae_noglob:
    lea rax, [rip + excl_count]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov eax, 1
    pop r12
    pop r11
    pop rdi
    pop rsi
    pop rbx
    ret
sae_fail:
    xor eax, eax
    pop r12
    pop r11
    pop rdi
    pop rsi
    pop rbx
    ret

// has_char_ci: RCX=ptr WCHAR, EDX=len, R8D=char (ya minúscula).
// EAX=1 si algún WCHAR del path plegado A-Z == char. Solo volátiles.
// Prefiltro barato de path_is_excluded: condición necesaria -> lossless.
has_char_ci:
    test edx, edx
    jz hcc_no
hcc_loop:
    movzx eax, WORD PTR [rcx]
    cmp eax, 0x41
    jb hcc_cmp
    cmp eax, 0x5A
    ja hcc_cmp
    add eax, 0x20
hcc_cmp:
    cmp eax, r8d
    je hcc_yes
    add rcx, 2
    dec edx
    jnz hcc_loop
hcc_no:
    xor eax, eax
    ret
hcc_yes:
    mov eax, 1
    ret

// path_is_excluded: RSI=ptr WCHAR, ECX=len -> EAX 1 excluido, 0 no.
// Revisa defaults (salvo flags) + customs con contains_ci.
// Solo lee globales read-only: seguro entre hilos.
// Preserva RBX,RSI,RDI,R12-R15 (callee-saved).
path_is_excluded:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64
    mov QWORD PTR [rsp+32], rsi
    mov DWORD PTR [rsp+40], ecx
    lea rax, [rip + opt_noexcl]
    cmp QWORD PTR [rax], 0
    jne pie_customs
    lea rax, [rip + opt_incwin]
    cmp QWORD PTR [rax], 0
    jne pie_skip_win
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x77
    call has_char_ci
    test eax, eax
    jz pie_skip_win
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_win_mid]
    mov r9, WIN_MID_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
    mov eax, DWORD PTR [rsp+40]
    cmp eax, WIN_END_LEN
    jb pie_skip_win_end
    mov rcx, QWORD PTR [rsp+32]
    mov edx, eax
    sub edx, WIN_END_LEN
    lea r10, [rcx + rdx*2]
    lea r11, [rip + def_win_end]
    xor r8d, r8d
pie_win_loop:
    cmp r8d, WIN_END_LEN
    jae pie_hit
    movzx eax, WORD PTR [r10 + r8*2]
    cmp eax, 0x41
    jb pie_win_nof
    cmp eax, 0x5A
    ja pie_win_nof
    add eax, 0x20
pie_win_nof:
    movzx edx, WORD PTR [r11 + r8*2]
    cmp eax, edx
    jne pie_skip_win_end
    inc r8d
    jmp pie_win_loop
pie_skip_win_end:
pie_skip_win:
    lea rax, [rip + opt_incnm]
    cmp QWORD PTR [rax], 0
    jne pie_skip_nm
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x6E
    call has_char_ci
    test eax, eax
    jz pie_skip_nm
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_nm_mid]
    mov r9, NM_MID_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
    mov eax, DWORD PTR [rsp+40]
    cmp eax, NM_END_LEN
    jb pie_skip_nm_end
    mov rcx, QWORD PTR [rsp+32]
    mov edx, eax
    sub edx, NM_END_LEN
    lea r10, [rcx + rdx*2]
    lea r11, [rip + def_nm_end]
    xor r8d, r8d
pie_nm_loop:
    cmp r8d, NM_END_LEN
    jae pie_hit
    movzx eax, WORD PTR [r10 + r8*2]
    cmp eax, 0x41
    jb pie_nm_nof
    cmp eax, 0x5A
    ja pie_nm_nof
    add eax, 0x20
pie_nm_nof:
    movzx edx, WORD PTR [r11 + r8*2]
    cmp eax, edx
    jne pie_skip_nm_end
    inc r8d
    jmp pie_nm_loop
pie_skip_nm_end:
pie_skip_nm:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x24
    call has_char_ci
    test eax, eax
    jz pie_sys
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_rec]
    mov r9, REC_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
pie_sys:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x73
    call has_char_ci
    test eax, eax
    jz pie_customs
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_sys]
    mov r9, SYS_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
    // --- grupo SYS (archivos pagefile/hiberfil/swapfile + dirs sistema) ---
    // salvo --include-sys. Cada check: prefiltro has_char + contains_ci.
    lea rax, [rip + opt_incsys]
    cmp QWORD PTR [rax], 0
    jne pie_temp
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x70
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_pf]
    mov r9, PF_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x68
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_hib]
    mov r9, HIB_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x73
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_swp]
    mov r9, SWP_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x24
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_winre]
    mov r9, WINRE_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x72
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_recov]
    mov r9, RECOV_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x63
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_cfgmsi]
    mov r9, CFGMSI_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x6D
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_mso]
    mov r9, MSO_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x24
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_wbt]
    mov r9, WBT_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x24
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_wws]
    mov r9, WWS_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x77
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_winold]
    mov r9, WINOLD_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x70
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_perfl]
    mov r9, PERF_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x70
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_pref]
    mov r9, PREF_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x73
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_soft]
    mov r9, SOFT_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
pie_temp:
    // --- grupo TEMP (Windows\Temp + AppData\Local\Temp), salvo --include-temp ---
    lea rax, [rip + opt_inctemp]
    cmp QWORD PTR [rax], 0
    jne pie_cache
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x77
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_wtemp]
    mov r9, WTEMP_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x61
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_atemp]
    mov r9, ATEMP_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
pie_cache:
    // --- grupo CACHE (INetCache, \Cache, Code Cache, Service Worker, __pycache__) ---
    // salvo --include-cache. '\cache' cubre Chrome (*Chrome*\*Cache*) y todo \Cache.
    lea rax, [rip + opt_inccache]
    cmp QWORD PTR [rax], 0
    jne pie_customs
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x69
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_inet]
    mov r9, INET_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x63
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_bcache]
    mov r9, BCACHE_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x63
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_codec]
    mov r9, CODEC_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x73
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_svcw]
    mov r9, SVCW_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8d, 0x5F
    call has_char_ci
    test eax, eax
    jz 1f
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    lea r8, [rip + def_pyc]
    mov r9, PYC_LEN
    call contains_ci
    test eax, eax
    jnz pie_hit
1:
pie_customs:
    lea rax, [rip + excl_count]
    mov r14, QWORD PTR [rax]
    test r14, r14
    jz pie_miss
    xor ebx, ebx
pie_cust_loop:
    cmp rbx, r14
    jae pie_miss
    mov rax, rbx
    shl rax, 9
    mov rdx, rbx
    shl rdx, 3
    add rax, rdx
    lea rdx, [rip + excl_data]
    add rax, rdx
    mov r10, rax
    // patron con wildcards -> full-match glob via Rust (sin prefilter)
    mov rcx, rbx
    mov rax, 1
    shl rax, cl
    lea rdx, [rip + excl_glob]
    test rax, QWORD PTR [rdx]
    jnz pie_cust_glob
    movzx r8d, WORD PTR [r10]
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    call has_char_ci
    test eax, eax
    jz pie_cust_next
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8, r10
    lea rax, [rip + excl_lens]
    mov r9, QWORD PTR [rax + rbx*8]
    call contains_ci
    test eax, eax
    jnz pie_hit
    jmp pie_cust_next
pie_cust_glob:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, DWORD PTR [rsp+40]
    mov r8, r10
    lea rax, [rip + excl_lens]
    mov r9, QWORD PTR [rax + rbx*8]
    call skc_excl_glob
    test eax, eax
    jnz pie_hit
pie_cust_next:
    inc rbx
    jmp pie_cust_loop
pie_hit:
    mov eax, 1
    jmp pie_done
pie_miss:
    xor eax, eax
pie_done:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

// ws_create: crea workspace (bloque + 3 regiones). -> RAX=ws, 0 si falla.
// Frame 72: [rsp+32]=ws temp.
ws_create:
    push rbx
    sub rsp, 72
    mov rcx, 0
    mov rdx, WB_ALLOC
    mov r8d, WS_MEM_COMMIT
    or r8d, WS_MEM_RESERVE
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wsc_fail
    mov rbx, rax
    mov rcx, rbx
    call ws_init_regions
    test eax, eax
    jz wsc_free_blk
    mov rax, rbx
    jmp wsc_ret
wsc_free_blk:
    mov rcx, rbx
    call ws_free
wsc_fail:
    xor eax, eax
wsc_ret:
    add rsp, 72
    pop rbx
    ret

// ws_init_regions: RCX=ws. Reserva nombres+rec+stk, commit inicial.
// Deja contadores en 0 y bp_cache_idx=-1. EAX 1 ok, 0 fail.
ws_init_regions:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 64
    mov rbx, rcx
    mov QWORD PTR [rbx + WS_RECCNT], 0
    mov QWORD PTR [rbx + WS_STKTOP], 0
    mov QWORD PTR [rbx + WS_FILES], 0
    mov QWORD PTR [rbx + WS_MATCH], 0
    mov QWORD PTR [rbx + WS_EXCL], 0
    mov QWORD PTR [rbx + WS_OUTPOS], 0
    mov QWORD PTR [rbx + WS_TRUNC], 0
    mov QWORD PTR [rbx + WS_BPCIDX], -1
    mov QWORD PTR [rbx + WS_BPCLEN], 0
    mov QWORD PTR [rbx + WS_BPMISS], 0
    mov QWORD PTR [rbx + WS_WLEN], 0
    mov QWORD PTR [rbx + WS_QALEN], 0
    mov QWORD PTR [rbx + WS_QPTR], 0
    mov QWORD PTR [rbx + WS_QLEN], 0
    mov QWORD PTR [rbx + WS_DRIVE], 0
    mov QWORD PTR [rbx + WS_MTIME_BASE], 0
    mov QWORD PTR [rbx + WS_MTIME_END], 0
    mov QWORD PTR [rbx + WS_MTIME_CEND], 0
    // nombres: reserva 256MB
    mov rcx, 0
    mov rdx, WS_NAMES_RSV
    mov r8d, WS_MEM_RESERVE
    mov r9d, WS_PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov QWORD PTR [rbx + WS_A_BASE], rax
    mov QWORD PTR [rbx + WS_A_BRK], rax
    add rax, WS_NAMES_RSV
    mov QWORD PTR [rbx + WS_A_RSV], rax
    mov rcx, QWORD PTR [rbx + WS_A_BASE]
    mov rdx, WS_NAMES_CHUNK
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov rax, QWORD PTR [rbx + WS_A_BASE]
    add rax, WS_NAMES_CHUNK
    mov QWORD PTR [rbx + WS_A_CEND], rax
    // records: reserva 32MB (64MB si scan_big_rec: índice GUI multi-raíz)
    mov rcx, 0
    mov rdx, WS_REC_RSV
    lea rax, [rip + scan_big_rec]
    cmp QWORD PTR [rax], 0
    je wir_rec32
    mov rdx, WS_REC_BIG
wir_rec32:
    // + mtimes (u64 por record): total = rsv + rsv/12*8, carved al final
    mov r10, rdx
    mov rax, rdx
    xor edx, edx
    mov ecx, 12
    div rcx
    shl rax, 3
    add rax, r10
    mov QWORD PTR [rsp+40], r10
    mov QWORD PTR [rsp+48], rax
    mov rdx, rax
    xor ecx, ecx
    mov r8d, WS_MEM_RESERVE
    mov r9d, WS_PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov QWORD PTR [rbx + WS_R_BASE], rax
    mov QWORD PTR [rbx + WS_REC], rax
    mov r10, QWORD PTR [rsp+40]
    mov rdx, rax
    add rdx, r10
    mov QWORD PTR [rbx + WS_R_END], rdx
    mov QWORD PTR [rbx + WS_MTIME_BASE], rdx
    mov rcx, rax
    add rcx, QWORD PTR [rsp+48]
    mov QWORD PTR [rbx + WS_MTIME_END], rcx
    mov QWORD PTR [rbx + WS_MTIME_CEND], rdx
    lea rcx, [rip + scan_big_rec]
    cmp QWORD PTR [rcx], 0
    jne wir_rend_big
    add rax, WS_REC_RSV
    mov QWORD PTR [rbx + WS_R_END], rax
    jmp wir_rend_done
wir_rend_big:
    add rax, WS_REC_BIG
    mov QWORD PTR [rbx + WS_R_END], rax
wir_rend_done:
    mov rcx, QWORD PTR [rbx + WS_R_BASE]
    mov rdx, WS_TABLE_CHUNK
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov rax, QWORD PTR [rbx + WS_R_BASE]
    add rax, WS_TABLE_CHUNK
    mov QWORD PTR [rbx + WS_R_CEND], rax
    // pila: reserva 4MB
    mov rcx, 0
    mov rdx, WS_STK_RSV
    mov r8d, WS_MEM_RESERVE
    mov r9d, WS_PAGE_NA
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov QWORD PTR [rbx + WS_S_BASE], rax
    mov QWORD PTR [rbx + WS_STK], rax
    add rax, WS_STK_RSV
    mov QWORD PTR [rbx + WS_S_END], rax
    mov rcx, QWORD PTR [rbx + WS_S_BASE]
    mov rdx, WS_TABLE_CHUNK
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wsi_fail
    mov rax, QWORD PTR [rbx + WS_S_BASE]
    add rax, WS_TABLE_CHUNK
    mov QWORD PTR [rbx + WS_S_CEND], rax
    mov eax, 1
    jmp wsi_ret
wsi_fail:
    xor eax, eax
wsi_ret:
    add rsp, 64
    pop rbx
    pop rbp
    ret

// ws_free: RCX=ws. Libera bloque + regiones (tolera ceros).
ws_free:
    push rbp
    mov rbp, rsp
    sub rsp, 56
    mov QWORD PTR [rsp+32], rcx
    mov rcx, QWORD PTR [rcx + WS_A_BASE]
    test rcx, rcx
    jz wsf_rec
    mov rdx, 0
    mov r8d, WS_MEM_RELEASE
    call VirtualFree
wsf_rec:
    mov rax, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rax + WS_R_BASE]
    test rcx, rcx
    jz wsf_stk
    mov rdx, 0
    mov r8d, WS_MEM_RELEASE
    call VirtualFree
wsf_stk:
    mov rax, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rax + WS_S_BASE]
    test rcx, rcx
    jz wsf_blk
    mov rdx, 0
    mov r8d, WS_MEM_RELEASE
    call VirtualFree
wsf_blk:
    mov rcx, QWORD PTR [rsp+32]
    mov rdx, 0
    mov r8d, WS_MEM_RELEASE
    call VirtualFree
    add rsp, 56
    pop rbp
    ret

// ws_alloc: RCX=ws, RDX=bytes. -> RAX=ptr, 0 si no hay lugar.
// Bump privado (sin locks: el ws es de un solo hilo). Alineado a 8.
// Frame 64: +32 ws, +40 newbrk, +48 addr, +56 chunk.
ws_alloc:
    sub rsp, 64
    mov QWORD PTR [rsp+32], rcx
    add rdx, 7
    and rdx, -8
    test rdx, rdx
    jz wsa_zero
    mov rax, QWORD PTR [rcx + WS_A_BASE]
    test rax, rax
    jz wsa_fail
    mov rax, QWORD PTR [rcx + WS_A_BRK]
    add rax, rdx
    cmp rax, QWORD PTR [rcx + WS_A_RSV]
    ja wsa_fail
    mov QWORD PTR [rsp+40], rax
wsa_commit_loop:
    mov rcx, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rcx + WS_A_CEND]
    cmp QWORD PTR [rsp+40], rax
    jbe wsa_commit_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, WS_NAMES_CHUNK
    jae wsa_have_chunk
    mov rdx, WS_NAMES_CHUNK
wsa_have_chunk:
    mov rcx, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rcx + WS_A_RSV]
    sub rcx, rax
    cmp rdx, rcx
    jbe wsa_chunk_fit
    mov rdx, rcx
wsa_chunk_fit:
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], rdx
    mov rcx, rax
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wsa_fail
    mov rcx, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rcx + WS_A_CEND]
    add rax, QWORD PTR [rsp+56]
    mov QWORD PTR [rcx + WS_A_CEND], rax
    jmp wsa_commit_loop
wsa_commit_ok:
    mov rcx, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rcx + WS_A_BRK]
    mov rdx, QWORD PTR [rsp+40]
    mov QWORD PTR [rcx + WS_A_BRK], rdx
    jmp wsa_done
wsa_zero:
    mov rcx, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rcx + WS_A_BRK]
    jmp wsa_done
wsa_fail:
    xor eax, eax
wsa_done:
    add rsp, 64
    ret

// ws_used: RCX=ws -> RAX=bytes usados en nombres. Leaf.
ws_used:
    mov rax, QWORD PTR [rcx + WS_A_BRK]
    sub rax, QWORD PTR [rcx + WS_A_BASE]
    ret

// ws_rec_ensure: RCX=ws, RDX=idx. Commit para (idx+1)*12B. EAX 1/0.
// Frame 64: +32 ws, +40 need, +48 addr, +56 chunk.
ws_rec_ensure:
    push rbp
    mov rbp, rsp
    sub rsp, 72
    mov QWORD PTR [rsp+32], rcx
    mov QWORD PTR [rsp+64], rdx
    mov rax, QWORD PTR [rcx + WS_R_BASE]
    test rax, rax
    jz wre_fail
    mov rcx, rdx
    inc rcx
    imul rcx, rcx, 12
    add rcx, rax
    mov QWORD PTR [rsp+40], rcx
    mov rax, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rax + WS_R_END]
    cmp rcx, rax
    ja wre_fail
    mov rax, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rax + WS_R_CEND]
    cmp rcx, rax
    jbe wre_mtime
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, WS_TABLE_CHUNK
    jae wre_have
    mov rdx, WS_TABLE_CHUNK
wre_have:
    mov rcx, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rcx + WS_R_END]
    sub rcx, rax
    cmp rdx, rcx
    jbe wre_fit
    mov rdx, rcx
wre_fit:
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], rdx
    mov rcx, rax
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wre_fail
    mov rax, QWORD PTR [rsp+32]
    mov rdx, QWORD PTR [rax + WS_R_CEND]
    add rdx, QWORD PTR [rsp+56]
    mov QWORD PTR [rax + WS_R_CEND], rdx
wre_mtime:
    // mtimes: commit par (idx+1)*8 (region ausente -> skipea, sin trunc)
    mov rax, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rax + WS_MTIME_BASE]
    test rax, rax
    jz wre_ok
    mov rdx, QWORD PTR [rsp+64]
    inc rdx
    shl rdx, 3
    add rdx, rax
    mov QWORD PTR [rsp+40], rdx
    mov rcx, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rcx + WS_MTIME_END]
    cmp rdx, rcx
    ja wre_fail
    mov rcx, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rcx + WS_MTIME_CEND]
    cmp rdx, rcx
    jbe wre_mok
    mov rax, rdx
    sub rax, rcx
    add rax, 0xFFF
    and eax, 0xFFFFF000
    mov QWORD PTR [rsp+56], rax
    mov QWORD PTR [rsp+48], rcx
    mov rdx, rax
    mov rcx, QWORD PTR [rsp+48]
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wre_fail
    mov rax, QWORD PTR [rsp+32]
    mov rdx, QWORD PTR [rax + WS_MTIME_CEND]
    add rdx, QWORD PTR [rsp+56]
    mov QWORD PTR [rax + WS_MTIME_CEND], rdx
wre_mok:
    jmp wre_ok
wre_ok:
    mov eax, 1
    add rsp, 72
    pop rbp
    ret
wre_fail:
    xor eax, eax
    add rsp, 72
    pop rbp
    ret

// ws_stk_ensure: RCX=ws, RDX=idx. Commit para (idx+1)*4B. EAX 1/0.
// Frame 64: +32 ws, +40 need, +48 addr, +56 chunk.
ws_stk_ensure:
    push rbp
    mov rbp, rsp
    sub rsp, 72
    mov QWORD PTR [rsp+32], rcx
    mov rax, QWORD PTR [rcx + WS_S_BASE]
    test rax, rax
    jz wse_fail
    mov rcx, rdx
    inc rcx
    shl rcx, 2
    add rcx, rax
    mov QWORD PTR [rsp+40], rcx
    mov rax, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rax + WS_S_END]
    cmp rcx, rax
    ja wse_fail
    mov rax, QWORD PTR [rsp+32]
    mov rax, QWORD PTR [rax + WS_S_CEND]
    cmp rcx, rax
    jbe wse_ok
    mov rdx, QWORD PTR [rsp+40]
    sub rdx, rax
    add rdx, 0xFFFF
    shr rdx, 16
    shl rdx, 16
    cmp rdx, WS_TABLE_CHUNK
    jae wse_have
    mov rdx, WS_TABLE_CHUNK
wse_have:
    mov rcx, QWORD PTR [rsp+32]
    mov rcx, QWORD PTR [rcx + WS_S_END]
    sub rcx, rax
    cmp rdx, rcx
    jbe wse_fit
    mov rdx, rcx
wse_fit:
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], rdx
    mov rcx, rax
    mov r8d, WS_MEM_COMMIT
    mov r9d, WS_PAGE_RW
    call VirtualAlloc
    test rax, rax
    jz wse_fail
    mov rax, QWORD PTR [rsp+32]
    mov rdx, QWORD PTR [rax + WS_S_CEND]
    add rdx, QWORD PTR [rsp+56]
    mov QWORD PTR [rax + WS_S_CEND], rdx
wse_ok:
    mov eax, 1
    add rsp, 72
    pop rbp
    ret
wse_fail:
    xor eax, eax
    add rsp, 72
    pop rbp
    ret

// scan_root_ws: RCX=ws, RDX=root WCHAR*, R8=root_len.
// Query en WS_QPTR/WS_QLEN. Corre el DFS en ese workspace.
// Frame 192: args en [rsp+0..63], locales en [rsp+64..191].
// Locales: +64 root_ptr, +72 root_len, +96 entry_bytelen,
//   +100 dirlen_w, +104 entry_len, +108 entry_isdir,
//   +112 entry_name, +120 newidx, +128 scratch, +136 scratch2,
//   +144 rlen, +152 root_start_idx, +160 files_start.
// No-volátiles: RBX=dir idx, R12=qptr, R13=qlen, R14=hFind/rlen,
//   R15=ws block. R14D es rlen en el prólogo, hFind en el DFS.
scan_root_ws:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    // alinear rsp a 16B: skc_* (Rust) hace movdqa de xmm6-8 en el prologo
    // y faultea si la entrada viene con paridad rara (frames del caller).
    and rsp, -16
    sub rsp, 192
    mov r15, rcx
    mov QWORD PTR [rsp+64], rdx
    mov QWORD PTR [rsp+72], r8
    mov r12, QWORD PTR [r15 + WS_QPTR]
    mov r13, QWORD PTR [r15 + WS_QLEN]
    // NOTA: WS_RECCNT no se resetea (acumula multi-raíz: índice GUI).
    // ws_init_regions lo deja en 0 para workspaces frescos.
    mov QWORD PTR [r15 + WS_STKTOP], 0
    mov QWORD PTR [r15 + WS_BPCIDX], -1
    mov rax, QWORD PTR [r15 + WS_RECCNT]
    mov QWORD PTR [rsp+152], rax
    mov rax, QWORD PTR [r15 + WS_FILES]
    mov QWORD PTR [rsp+160], rax
    // 1) ruta absoluta
    mov rcx, QWORD PTR [rsp+64]
    mov edx, 32768
    lea r8, [r15 + WB_ROOT]
    xor r9d, r9d
    call GetFullPathNameW
    test eax, eax
    jz sor_fail
    cmp eax, 32760
    jae sor_fail
    mov r14d, eax
    // quitar backslash final (salvo "X:\")
    cmp r14d, 3
    jbe sor_nostrip
    lea rax, [r15 + WB_ROOT]
    movzx edx, WORD PTR [rax + r14*2 - 2]
    cmp edx, 0x5C
    jne sor_nostrip
    cmp r14d, 3
    jne sor_dostrip
    movzx edx, WORD PTR [rax+2]
    cmp edx, 0x3A
    je sor_nostrip
sor_dostrip:
    dec r14d
    mov WORD PTR [rax + r14*2], 0
sor_nostrip:
    // prefijo \\?\ (o \\?\UNC\ si es UNC)
    lea rax, [r15 + WB_ROOT]
    movzx ecx, WORD PTR [rax]
    cmp ecx, 0x5C
    jne sor_devpfx
    movzx ecx, WORD PTR [rax+2]
    cmp ecx, 0x5C
    jne sor_devpfx
    movzx ecx, WORD PTR [rax+4]
    cmp ecx, 0x3F
    je sor_prefixed
    // UNC: insertar "?UNC\" (6 WCHAR) en pos 2
    mov ecx, r14d
    sub ecx, 2
    add ecx, 1
    lea rsi, [rax + r14*2]
    lea rdi, [rsi + 12]
    std
    rep movsw
    cld
    mov WORD PTR [rax+4], 0x3F
    mov WORD PTR [rax+6], 0x5C
    mov WORD PTR [rax+8], 0x55
    mov WORD PTR [rax+10], 0x4E
    mov WORD PTR [rax+12], 0x43
    mov WORD PTR [rax+14], 0x5C
    add r14d, 6
    jmp sor_storelen
sor_devpfx:
    mov ecx, r14d
    add ecx, 1
    lea rsi, [rax + r14*2]
    lea rdi, [rsi + 8]
    std
    rep movsw
    cld
    mov WORD PTR [rax], 0x5C
    mov WORD PTR [rax+2], 0x5C
    mov WORD PTR [rax+4], 0x3F
    mov WORD PTR [rax+6], 0x5C
    add r14d, 4
    jmp sor_storelen
sor_prefixed:
sor_storelen:
    mov DWORD PTR [rsp+144], r14d
    // raíz excluida? contar y volver sin escanear
    lea rsi, [r15 + WB_ROOT]
    mov ecx, r14d
    call path_is_excluded
    test eax, eax
    jz sor_root_ok
    mov rax, QWORD PTR [r15 + WS_EXCL]
    inc rax
    mov QWORD PTR [r15 + WS_EXCL], rax
    jmp sor_epilogue_ok
sor_root_ok:
    // 2) tablas del ws: ensure inicial (cap máxima, commit progresivo)
    // La raíz vive en root_start (acumula multi-raíz); la pila arranca en 0.
    mov rcx, r15
    mov rdx, QWORD PTR [rsp+152]
    call ws_rec_ensure
    test eax, eax
    jz sor_fail
    mov rcx, r15
    xor edx, edx
    call ws_stk_ensure
    test eax, eax
    jz sor_fail
    mov QWORD PTR [r15 + WS_BPCIDX], -1
    // 2b) query WCHAR -> UTF-8 una vez (match sobre bytes)
    mov QWORD PTR [r15 + WS_QALEN], 0
    cmp r13, 0
    je sor_qa_done
    mov rcx, 65001
    xor edx, edx
    mov r8, r12
    mov r9, r13
    lea rax, [r15 + WB_QA]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 8192
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz sor_qa_done
    movsxd rdx, eax
    mov QWORD PTR [r15 + WS_QALEN], rdx
sor_qa_done:
    // 3) record raíz: ruta absoluta WCHAR -> UTF-8 en el ws
    mov ecx, r14d
    imul ecx, ecx, 3
    add ecx, 3
    mov rdx, rcx
    mov rcx, r15
    call ws_alloc
    test rax, rax
    jz sor_fail
    mov QWORD PTR [rsp+128], rax
    add rax, 2
    mov QWORD PTR [rsp+32], rax
    mov ecx, r14d
    imul ecx, ecx, 3
    add ecx, 1
    mov QWORD PTR [rsp+40], rcx
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_ROOT]
    mov r9d, r14d
    call WideCharToMultiByte
    test eax, eax
    jz sor_fail
    cmp eax, 60000
    ja sor_fail
    mov rcx, QWORD PTR [rsp+128]
    mov WORD PTR [rcx], ax
    movsxd rdx, eax
    add rcx, 2
    add rcx, rdx
    mov BYTE PTR [rcx], 0
    mov rax, QWORD PTR [rsp+128]
    add rax, 2
    mov rcx, QWORD PTR [rsp+152]
    mov QWORD PTR [rsp+120], rcx
    imul rcx, rcx, 12
    add rcx, QWORD PTR [r15 + WS_REC]
    mov QWORD PTR [rcx], rax
    mov DWORD PTR [rcx+8], 0xFFFFFFFF
    mov rax, QWORD PTR [rsp+152]
    inc rax
    mov QWORD PTR [r15 + WS_RECCNT], rax
    mov rcx, QWORD PTR [r15 + WS_STK]
    mov eax, DWORD PTR [rsp+120]
    mov DWORD PTR [rcx], eax
    mov QWORD PTR [r15 + WS_STKTOP], 1
    // 3b) MFT directo (--mft, solo drive-root; si falla con force, sin DFS)
    lea rax, [rip + scan_opt_mft]
    cmp QWORD PTR [rax], 0
    je mft_skip_hook
    mov rcx, r15
    call mft_try_root
    test eax, eax
    jnz sor_done
    lea rax, [rip + mft_force_fail]
    cmp QWORD PTR [rax], 0
    jne sor_done
mft_skip_hook:
    // 4) DFS
sor_dfs:
    mov rax, QWORD PTR [r15 + WS_STKTOP]
    test rax, rax
    jz sor_done
    dec rax
    mov QWORD PTR [r15 + WS_STKTOP], rax
    mov rdx, QWORD PTR [r15 + WS_STK]
    mov ebx, DWORD PTR [rdx+rax*4]
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    je 1f
    mov QWORD PTR [rsp+168], 0
1:
    mov r11d, ebx
    mov rcx, r15
    call build_path
    test eax, eax
    jz sor_dfs
    mov r9d, eax
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_DIRPATH]
    lea rax, [r15 + WB_DIRW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz sor_dfs
    mov DWORD PTR [rsp+100], eax
    movsxd rdx, eax
    mov QWORD PTR [r15 + WS_WLEN], rdx
    mov ecx, DWORD PTR [rsp+100]
    lea rsi, [r15 + WB_DIRW]
    lea rdi, [r15 + WB_PAT]
    rep movsw
    cmp DWORD PTR [rsp+100], 0
    je sor_star
    cmp WORD PTR [rdi-2], 0x5C
    je sor_star
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
sor_star:
    mov WORD PTR [rdi], 0x2A
    mov WORD PTR [rdi+2], 0
    // FindFirstFileExW(path, FindExInfoBasic, datos, NameMatch, 0, LARGE_FETCH)
    lea rcx, [r15 + WB_PAT]
    mov edx, FINDEX_BASIC
    lea r8, [r15 + WB_FIND]
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], FIND_EX_LARGE_FETCH
    call FindFirstFileExW
    cmp rax, -1
    jne sor_ex_ok
    lea rcx, [r15 + WB_PAT]
    lea rdx, [r15 + WB_FIND]
    call FindFirstFileW
    cmp rax, -1
    je sor_first_failed
sor_ex_ok:
    mov r14, rax
    jmp sor_entry
sor_first_failed:
    // si es el primer dir y no hay nada: la raíz puede ser un archivo.
    // Relativo a esta raíz (snapshots); en modo índice nunca (raíces X:\).
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_dfs
    mov rax, QWORD PTR [rsp+160]
    cmp QWORD PTR [r15 + WS_FILES], rax
    jne sor_dfs
    cmp QWORD PTR [r15 + WS_STKTOP], 0
    jne sor_dfs
    mov rax, QWORD PTR [rsp+152]
    inc rax
    cmp QWORD PTR [r15 + WS_RECCNT], rax
    jne sor_dfs
    jmp sor_as_file
sor_entry:
    mov DWORD PTR [rsp+184], 0
    lea rax, [r15 + WB_FIND]
    mov r11d, DWORD PTR [rax]
    lea rsi, [rax+44]
    xor ecx, ecx
sor_flen:
    cmp ecx, 260
    jae sor_flen_cap
    movzx edx, WORD PTR [rsi+rcx*2]
    test edx, edx
    jz sor_flen_done
    inc ecx
    jmp sor_flen
sor_flen_cap:
    mov ecx, 260
sor_flen_done:
    mov DWORD PTR [rsp+104], ecx
    cmp ecx, 1
    jne sor_not1
    cmp WORD PTR [rsi], 0x2E
    je sor_next
sor_not1:
    cmp ecx, 2
    jne sor_not2
    cmp WORD PTR [rsi], 0x2E
    jne sor_not2
    cmp WORD PTR [rsi+2], 0x2E
    je sor_next
sor_not2:
    test r11d, 0x400
    jnz sor_next
    mov eax, 0
    test r11d, 0x10
    jz sor_filed
    mov eax, 1
sor_filed:
    mov DWORD PTR [rsp+108], eax
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    je 1f
    mov rax, QWORD PTR [rsp+168]
    inc rax
    mov QWORD PTR [rsp+168], rax
1:
    // --- fast path archivos en streaming: match WCHAR antes de convertir ---
    // Sin match no hay W2M ni candidato completo: solo tail-exclude p/conteo.
    mov eax, DWORD PTR [rsp+108]
    test eax, eax
    jnz sor_xb_refresh
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_xb_refresh
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_xb_refresh
    // query de ruta (pathq): el match se hace despues, sobre el WCHAR completo
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne sor_xb_refresh
    mov rcx, rsi
    mov edx, DWORD PTR [rsp+104]
    mov r8, QWORD PTR [r15 + WS_QPTR]
    mov r9, QWORD PTR [r15 + WS_QLEN]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne sor_ff_glob
    call contains_ci
    jmp sor_ff_test
sor_ff_glob:
    call glob_match_ci
sor_ff_test:
    test eax, eax
    jz sor_f_nomatch
    mov DWORD PTR [rsp+184], 1
    jmp sor_xb_refresh
    // --- archivo sin match: tail-exclude exacto (padre limpio por invariante) ---
sor_f_nomatch:
    mov r11d, ebx
    mov rcx, r15
    call build_path
    test eax, eax
    jz sor_xb_refresh
    mov rax, QWORD PTR [r15 + WS_BPMISS]
    test rax, rax
    jz sor_fn_havew
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_DIRPATH]
    lea rax, [r15 + WB_DIRW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz sor_xb_refresh
    movsxd rdx, eax
    mov QWORD PTR [r15 + WS_WLEN], rdx
sor_fn_havew:
    mov rcx, QWORD PTR [r15 + WS_WLEN]
    mov eax, ecx
    sub eax, 160
    jns sor_fn_tsk
    xor eax, eax
sor_fn_tsk:
    lea rsi, [r15 + WB_DIRW]
    lea rsi, [rsi + rax*2]
    sub ecx, eax
    lea rdi, [r15 + WB_SEG]
    rep movsw
    test ecx, ecx
    jz sor_fn_copyname
    movzx edx, WORD PTR [rdi-2]
    cmp edx, 0x5C
    je sor_fn_copyname
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
sor_fn_copyname:
    mov ecx, DWORD PTR [rsp+104]
    lea rsi, [r15 + WB_FIND]
    add rsi, 44
    rep movsw
    mov WORD PTR [rdi], 0
    lea rax, [r15 + WB_SEG]
    sub rdi, rax
    shr rdi, 1
    dec rdi
    mov ecx, edi
    lea rsi, [r15 + WB_SEG]
    call path_is_excluded
    test eax, eax
    jz sor_fn_clean
    mov rax, QWORD PTR [r15 + WS_EXCL]
    inc rax
    mov QWORD PTR [r15 + WS_EXCL], rax
    jmp sor_next
sor_fn_clean:
    mov rax, QWORD PTR [r15 + WS_FILES]
    inc rax
    mov QWORD PTR [r15 + WS_FILES], rax
    jmp sor_next
sor_xb_refresh:
    // --- refrescar path del padre (bytes, cacheado) ---
    mov DWORD PTR [rsp+128], 0
    mov r11d, ebx
    mov rcx, r15
    call build_path
    test eax, eax
    jz sor_noexcl_stream
    mov r9d, eax
    mov rax, QWORD PTR [r15 + WS_BPMISS]
    test rax, rax
    jz sor_xb_havew
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_DIRPATH]
    lea rax, [r15 + WB_DIRW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz sor_noexcl_stream
    mov DWORD PTR [rsp+100], eax
    movsxd rdx, eax
    mov QWORD PTR [r15 + WS_WLEN], rdx
sor_xb_havew:
    // --- exclude-before-alloc: candidato WCHAR = dirpath_w + sep + nombre ---
    lea rsi, [r15 + WB_DIRW]
    lea rdi, [r15 + WB_SEG]
    mov ecx, DWORD PTR [rsp+100]
    rep movsw
    mov eax, DWORD PTR [rsp+100]
    test eax, eax
    jz sor_xb_copyname
    movzx edx, WORD PTR [rdi-2]
    cmp edx, 0x5C
    je sor_xb_copyname
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
    inc eax
sor_xb_copyname:
    mov ecx, DWORD PTR [rsp+104]
    add eax, ecx
    cmp eax, 32767
    ja sor_noexcl_stream
    mov DWORD PTR [rsp+128], eax
    lea rsi, [r15 + WB_FIND]
    add rsi, 44
    rep movsw
    mov WORD PTR [rdi], 0
    lea rsi, [r15 + WB_SEG]
    mov ecx, DWORD PTR [rsp+128]
    call path_is_excluded
    test eax, eax
    jz sor_noexcl_stream
    mov rax, QWORD PTR [r15 + WS_EXCL]
    inc rax
    mov QWORD PTR [r15 + WS_EXCL], rax
    jmp sor_next
sor_noexcl_stream:
    // query de ruta (pathq): match sobre el WCHAR completo ya construido.
    // Gate por modo indice primero: en indice se guarda todo, sin matchear.
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_nq_ok
    cmp QWORD PTR [rip + scan_is_pathq], 0
    je sor_nq_ok
    mov DWORD PTR [rsp+184], 0
    mov eax, DWORD PTR [rsp+128]
    test eax, eax
    jz sor_pq_nomatch
    lea rcx, [r15 + WB_SEG]
    mov rdx, rax
    mov r8, QWORD PTR [r15 + WS_QPTR]
    mov r9, QWORD PTR [r15 + WS_QLEN]
    mov rax, QWORD PTR [rip + scan_is_glob]
    mov QWORD PTR [rsp+32], rax
    call skc_match_path
    test eax, eax
    jz sor_pq_nomatch
    mov DWORD PTR [rsp+184], 1
    jmp sor_nq_ok
sor_pq_nomatch:
    // dir: guardar igual (hace falta para descender) y no emitir;
    // archivo: solo contarlo como escaneado
    mov eax, DWORD PTR [rsp+108]
    test eax, eax
    jnz sor_nq_ok
    inc QWORD PTR [r15 + WS_FILES]
    jmp sor_next
sor_nq_ok:
    // nombre WCHAR -> UTF-8 una vez (match y guardado sobre bytes)
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_FIND]
    add r8, 44
    mov r9d, DWORD PTR [rsp+104]
    lea rax, [r15 + WB_NTMP]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 1024
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz sor_next
    mov DWORD PTR [rsp+96], eax
    mov eax, DWORD PTR [rsp+108]
    test eax, eax
    jz sor_file_stream
    // ===== DIR no-excluido: guardar UTF-8 (necesario para descender) =====
    mov ecx, DWORD PTR [rsp+96]
    add ecx, 3
    mov edx, ecx
    mov rcx, r15
    call ws_alloc
    test rax, rax
    jz sor_noarena
    mov ecx, DWORD PTR [rsp+96]
    mov WORD PTR [rax], cx
    mov QWORD PTR [rsp+136], rax
    lea rdi, [rax+2]
    lea rsi, [r15 + WB_NTMP]
    rep movsb
    mov BYTE PTR [rdi], 0
    mov rax, QWORD PTR [rsp+136]
    add rax, 2
    mov QWORD PTR [rsp+112], rax
    mov rax, QWORD PTR [r15 + WS_RECCNT]
    mov QWORD PTR [rsp+120], rax
    mov rcx, r15
    mov rdx, rax
    call ws_rec_ensure
    test eax, eax
    jz sor_noarena
    mov rax, QWORD PTR [r15 + WS_REC]
    mov rdx, QWORD PTR [rsp+120]
    imul rdx, rdx, 12
    add rax, rdx
    mov rdx, QWORD PTR [rsp+112]
    mov QWORD PTR [rax], rdx
    mov edx, ebx
    mov ecx, DWORD PTR [rsp+108]
    shl ecx, 31
    or edx, ecx
    mov DWORD PTR [rax+8], edx
    // mtime FindData -> array (tick incremental)
    mov rcx, QWORD PTR [r15 + WS_MTIME_BASE]
    test rcx, rcx
    jz sor_dir_nomtime
    mov rdx, QWORD PTR [rsp+120]
    mov rax, QWORD PTR [r15 + WB_FIND + 20]
    mov QWORD PTR [rcx+rdx*8], rax
sor_dir_nomtime:
    // firma de 64 bits del nombre (pre-filtro del filtro: descarta records
    // sin leer el nombre de la arena)
    mov rax, QWORD PTR [rip + scan_bloom]
    test rax, rax
    jz sor_dir_nobloom
    // nombre UTF-8 en la arena + largo en BYTES (no el puntero de arena)
    mov rcx, QWORD PTR [rsp+112]
    mov edx, DWORD PTR [rsp+96]
    mov r9, QWORD PTR [rsp+120]
    // guardas: el indice del record debe caber en la firma (12M) y el largo
    // del nombre es <= 4096 bytes (un nombre de archivo no pasa de ~1020)
    cmp r9, 12000000
    jae sor_dir_nobloom
    cmp edx, 4096
    ja sor_dir_nobloom
    shl r9, 3
    add rax, r9
    mov r8, rax
    call skc_bloom_build
sor_dir_nobloom:
    mov rax, QWORD PTR [r15 + WS_RECCNT]
    inc rax
    mov QWORD PTR [r15 + WS_RECCNT], rax
    mov rax, QWORD PTR [r15 + WS_FILES]
    inc rax
    mov QWORD PTR [r15 + WS_FILES], rax
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_dir_push
    // pathq: el flag [rsp+184] (match de ruta en sor_noexcl_stream) manda
    cmp QWORD PTR [rip + scan_is_pathq], 0
    je 3f
    cmp DWORD PTR [rsp+184], 0
    jne 4f
    jmp sor_dir_push
 3:
    mov rcx, QWORD PTR [rsp+112]
    mov edx, DWORD PTR [rsp+96]
    lea r8, [r15 + WB_QA]
    mov r9, QWORD PTR [r15 + WS_QALEN]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne 1f
    call contains_ci_a
    jmp 2f
1:
    call glob_match_ci_a
2:
    test eax, eax
    jz sor_dir_push
 4:
    mov rax, QWORD PTR [r15 + WS_MATCH]
    inc rax
    mov QWORD PTR [r15 + WS_MATCH], rax
    lea rax, [rip + scan_opt_countonly]
    cmp QWORD PTR [rax], 0
    jne sor_dir_push
    mov r11d, DWORD PTR [rsp+120]
    mov rcx, r15
    call build_path
    test eax, eax
    jz sor_dir_push
    mov r9d, eax
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_DIRPATH]
    lea rax, [r15 + WB_EMITW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz sor_dir_push
    lea rsi, [r15 + WB_EMITW]
    mov edx, eax
    mov rcx, r15
    call emit_path
sor_dir_push:
    mov rax, QWORD PTR [r15 + WS_STKTOP]
    mov QWORD PTR [rsp+128], rax
    mov rcx, r15
    mov rdx, rax
    call ws_stk_ensure
    test eax, eax
    jz sor_stackfull
    mov rax, QWORD PTR [r15 + WS_STK]
    mov rdx, QWORD PTR [rsp+128]
    mov ecx, DWORD PTR [rsp+120]
    mov DWORD PTR [rax+rdx*4], ecx
    mov rax, QWORD PTR [r15 + WS_STKTOP]
    inc rax
    mov QWORD PTR [r15 + WS_STKTOP], rax
    jmp sor_next
sor_file_stream:
    // ===== FILE no-excluido: match sobre bytes UTF-8, descartar si no-match =====
    mov rax, QWORD PTR [r15 + WS_FILES]
    inc rax
    mov QWORD PTR [r15 + WS_FILES], rax
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_file_istore
    cmp DWORD PTR [rsp+184], 0
    jne sor_file_prematched
    lea rcx, [r15 + WB_NTMP]
    mov edx, DWORD PTR [rsp+96]
    lea r8, [r15 + WB_QA]
    mov r9, QWORD PTR [r15 + WS_QALEN]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne 1f
    call contains_ci_a
    jmp 2f
1:
    call glob_match_ci_a
2:
    test eax, eax
    jz sor_next
sor_file_prematched:
    mov rax, QWORD PTR [r15 + WS_MATCH]
    inc rax
    mov QWORD PTR [r15 + WS_MATCH], rax
    lea rax, [rip + scan_opt_countonly]
    cmp QWORD PTR [rax], 0
    jne sor_next
    // match + con salida: guardar UTF-8 y emitir
    // (sor_file_istore: en modo índice guarda todo sin matchear ni emitir)
sor_file_istore:
    mov ecx, DWORD PTR [rsp+96]
    add ecx, 3
    mov edx, ecx
    mov rcx, r15
    call ws_alloc
    test rax, rax
    jz sor_noarena
    mov ecx, DWORD PTR [rsp+96]
    mov WORD PTR [rax], cx
    mov QWORD PTR [rsp+136], rax
    lea rdi, [rax+2]
    lea rsi, [r15 + WB_NTMP]
    rep movsb
    mov BYTE PTR [rdi], 0
    mov rax, QWORD PTR [rsp+136]
    add rax, 2
    mov QWORD PTR [rsp+112], rax
    mov rax, QWORD PTR [r15 + WS_RECCNT]
    mov QWORD PTR [rsp+120], rax
    mov rcx, r15
    mov rdx, rax
    call ws_rec_ensure
    test eax, eax
    jz sor_noarena
    mov rax, QWORD PTR [r15 + WS_REC]
    mov rdx, QWORD PTR [rsp+120]
    imul rdx, rdx, 12
    add rax, rdx
    mov rdx, QWORD PTR [rsp+112]
    mov QWORD PTR [rax], rdx
    mov DWORD PTR [rax+8], ebx
    // mtime FindData -> array (tick incremental; tambien archivos)
    mov rcx, QWORD PTR [r15 + WS_MTIME_BASE]
    test rcx, rcx
    jz sor_file_nomtime
    mov rdx, QWORD PTR [rsp+120]
    mov rax, QWORD PTR [r15 + WB_FIND + 20]
    mov QWORD PTR [rcx+rdx*8], rax
sor_file_nomtime:
    // firma de 64 bits del nombre (pre-filtro del filtro)
    mov rax, QWORD PTR [rip + scan_bloom]
    test rax, rax
    jz sor_file_nobloom
    // nombre UTF-8 en la arena + largo en BYTES (no el puntero de arena)
    mov rcx, QWORD PTR [rsp+112]
    mov edx, DWORD PTR [rsp+96]
    // guardas: el indice del record debe caber en la firma (12M) y el largo
    // del nombre es <= 4096 bytes (un nombre de archivo no pasa de ~1020)
    mov r9, QWORD PTR [rsp+120]
    cmp r9, 12000000
    jae sor_file_nobloom
    cmp edx, 4096
    ja sor_file_nobloom
    shl r9, 3
    add rax, r9
    mov r8, rax
    call skc_bloom_build
sor_file_nobloom:
    mov rax, QWORD PTR [r15 + WS_RECCNT]
    inc rax
    mov QWORD PTR [r15 + WS_RECCNT], rax
    lea rax, [rip + scan_opt_index]
    cmp QWORD PTR [rax], 0
    jne sor_next
    mov r11d, DWORD PTR [rsp+120]
    mov rcx, r15
    call build_path
    test eax, eax
    jz sor_next
    mov r9d, eax
    mov rcx, 65001
    xor edx, edx
    lea r8, [r15 + WB_DIRPATH]
    lea rax, [r15 + WB_EMITW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz sor_next
    lea rsi, [r15 + WB_EMITW]
    mov edx, eax
    mov rcx, r15
    call emit_path
    jmp sor_next
sor_noarena:
    mov QWORD PTR [r15 + WS_TRUNC], 1
    jmp sor_next
sor_stackfull:
    mov QWORD PTR [r15 + WS_TRUNC], 1
sor_next:
    mov rcx, r14
    lea rdx, [r15 + WB_FIND]
    call FindNextFileW
    test eax, eax
    jnz sor_entry
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    je 1f
    mov rax, QWORD PTR [rsp+168]
    test rax, rax
    jz 1f
    mov rcx, r15
    mov rdx, rax
    lea r8, [r15 + WB_DIRPATH]
    mov r9, QWORD PTR [r15 + WS_BPCLEN]
    call top_insert
1:
    mov rcx, r14
    call FindClose
    jmp sor_dfs
sor_as_file:
    // solo si la ruta existe (si no, fue Access Denied o no existe: 0/0)
    lea rcx, [r15 + WB_ROOT]
    call GetFileAttributesW
    cmp eax, -1
    je sor_dfs
    lea rax, [r15 + WB_ROOT]
    mov edx, DWORD PTR [rsp+144]
    lea rsi, [rax + rdx*2]
    mov rdi, rsi
sor_fb:
    cmp rsi, rax
    jbe sor_fb_have
    sub rsi, 2
    cmp WORD PTR [rsi], 0x5C
    je sor_fb_found
    jmp sor_fb
sor_fb_found:
    add rsi, 2
sor_fb_have:
    mov rcx, rdi
    sub rcx, rsi
    shr rcx, 1
    test ecx, ecx
    jz sor_dfs
    mov rdx, rcx
    mov r8, r12
    mov r9, r13
    mov rcx, rsi
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne 1f
    call contains_ci
    jmp 2f
1:
    call glob_match_ci
2:
    test eax, eax
    jz sor_dfs
    mov QWORD PTR [r15 + WS_FILES], 1
    mov QWORD PTR [r15 + WS_MATCH], 1
    lea rax, [rip + scan_opt_countonly]
    cmp QWORD PTR [rax], 0
    jne sor_dfs
    lea rsi, [r15 + WB_ROOT]
    mov ecx, DWORD PTR [rsp+144]
    mov edx, ecx
    mov rcx, r15
    call emit_path
    jmp sor_dfs
sor_done:
    // sin flush: lo hace el wrapper (acumula)
    jmp sor_epilogue_ok
sor_fail:
    // fallo de normalización/memoria: volver sin abortar todo
    jmp sor_epilogue_ok
sor_epilogue_ok:
    xor eax, eax
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

// scan_worker: RCX=ws (hilo por disco). Arma "X:\" y corre scan_root_ws.
scan_worker:
    push rbx
    sub rsp, 56
    mov rbx, rcx
    mov rax, QWORD PTR [rbx + WS_DRIVE]
    add eax, 0x41
    mov WORD PTR [rsp+40], ax
    mov WORD PTR [rsp+42], 0x3A
    mov WORD PTR [rsp+44], 0x5C
    mov WORD PTR [rsp+46], 0
    mov rcx, rbx
    lea rdx, [rsp+40]
    mov r8d, 3
    call scan_root_ws
    xor eax, eax
    add rsp, 56
    pop rbx
    ret

// scan_run: RCX=root, RDX=root_len, R8=query, R9=qlen -> RAX=matches.
// Resetea globales + 1 raíz inline + flush + free.
scan_run:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128
    mov QWORD PTR [rsp+64], rcx
    mov QWORD PTR [rsp+72], rdx
    mov QWORD PTR [rsp+80], r8
    mov QWORD PTR [rsp+88], r9
    lea rax, [rip + g_files]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_matches]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_excluded]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_disks]
    mov QWORD PTR [rax], 1
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 0
    lea rax, [rip + mft_used]
    mov QWORD PTR [rax], 0
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 0
    mov QWORD PTR [rsp+96], 0
    call ws_create
    test rax, rax
    jz srun_fail
    mov r15, rax
    mov QWORD PTR [rsp+96], rax
    lea rcx, [rip + scan_ws_last]
    mov QWORD PTR [rcx], rax
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    je 1f
    lea rdi, [rip + top_cnt]
    xor eax, eax
    mov ecx, 60
    rep stosq
1:
    mov rcx, QWORD PTR [rsp+80]
    mov QWORD PTR [r15 + WS_QPTR], rcx
    mov rcx, QWORD PTR [rsp+88]
    mov QWORD PTR [r15 + WS_QLEN], rcx
    mov rcx, r15
    mov rdx, QWORD PTR [rsp+64]
    mov r8, QWORD PTR [rsp+72]
    call scan_root_ws
    mov rcx, r15
    call ws_used
    lea rdx, [rip + scan_arena_total]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+96]
    mov r15, rcx
    call ws_totals_to_globals
    mov rcx, r15
    call flush_out
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    je 1f
    mov rcx, r15
    call scan_print_tops
1:
    mov rcx, r15
    call ws_free
    lea rax, [rip + g_matches]
    mov rax, QWORD PTR [rax]
    jmp srun_ret
srun_fail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
    xor eax, eax
srun_ret:
    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret


// ws_totals_to_globals: RCX=ws. Suma contadores y trunc a globales.
ws_totals_to_globals:
    lea rax, [rip + g_files]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rcx + WS_FILES]
    mov QWORD PTR [rax], rdx
    lea rax, [rip + g_matches]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rcx + WS_MATCH]
    mov QWORD PTR [rax], rdx
    lea rax, [rip + g_excluded]
    mov rdx, QWORD PTR [rax]
    add rdx, QWORD PTR [rcx + WS_EXCL]
    mov QWORD PTR [rax], rdx
    cmp QWORD PTR [rcx + WS_TRUNC], 0
    je wtt_ret
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
wtt_ret:
    ret

// scan_one_root: RCX=root, RDX=root_len, R8=query, R9=qlen.
// Compat: ACUMULA en globales (no resetea), flushea y libera.
scan_one_root:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128
    mov QWORD PTR [rsp+64], rcx
    mov QWORD PTR [rsp+72], rdx
    mov QWORD PTR [rsp+80], r8
    mov QWORD PTR [rsp+88], r9
    call ws_create
    test rax, rax
    jz soro_fail
    mov r15, rax
    mov QWORD PTR [rsp+96], rax
    lea rcx, [rip + scan_ws_last]
    mov QWORD PTR [rcx], rax
    mov rcx, QWORD PTR [rsp+80]
    mov QWORD PTR [r15 + WS_QPTR], rcx
    mov rcx, QWORD PTR [rsp+88]
    mov QWORD PTR [r15 + WS_QLEN], rcx
    mov rcx, r15
    mov rdx, QWORD PTR [rsp+64]
    mov r8, QWORD PTR [rsp+72]
    call scan_root_ws
    mov rcx, QWORD PTR [rsp+96]
    call ws_totals_to_globals
    mov rcx, QWORD PTR [rsp+96]
    call flush_out
    mov rcx, QWORD PTR [rsp+96]
    call ws_free
    xor eax, eax
    jmp soro_ret
soro_fail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
    xor eax, eax
soro_ret:
    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// scan_run_all: RCX=qptr, RDX=qlen -> RAX=matches.
// 1 hilo por unidad FIXED(3)/REMOVABLE(2). Suma y flush en orden.
// Frame 528: [rsp+0..63] args, [rsp+64..271] handles,
//   [rsp+272..479] ws, [rsp+480..527] locales (qptr,qlen,ndrives).
scan_run_all:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 528
    mov QWORD PTR [rsp+480], rcx
    mov QWORD PTR [rsp+488], rdx
    lea rax, [rip + g_files]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_matches]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_excluded]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_disks]
    mov QWORD PTR [rax], 0
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 0
    lea rax, [rip + mft_used]
    mov QWORD PTR [rax], 0
    lea rax, [rip + mft_force_fail]
    mov QWORD PTR [rax], 0
    lea rax, [rip + scan_arena_total]
    mov QWORD PTR [rax], 0
    mov QWORD PTR [rsp+496], 0
    mov r12, QWORD PTR [rsp+480]
    mov r13, QWORD PTR [rsp+488]
    lea rax, [rip + scan_opt_mft]
    cmp QWORD PTR [rax], 0
    jne sra_mft_seq
    lea rax, [rip + scan_opt_topdirs]
    cmp QWORD PTR [rax], 0
    jne sra_top_seq
    call GetLogicalDrives
    mov ebx, eax
    xor r14d, r14d
sra_loop:
    cmp r14d, 26
    jae sra_join
    mov eax, 1
    mov ecx, r14d
    shl eax, cl
    test ebx, eax
    jz sra_next
    mov eax, r14d
    add eax, 0x41
    lea rcx, [rip + drive_buf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + drive_buf]
    call GetDriveTypeW
    cmp eax, 2
    je sra_valid
    cmp eax, 3
    jne sra_next
sra_valid:
    lea rax, [rip + g_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov rax, QWORD PTR [rsp+496]
    cmp rax, 26
    jae sra_next
    mov QWORD PTR [rsp+504], rax
    call ws_create
    test rax, rax
    jz sra_wsfail
    mov rdx, QWORD PTR [rsp+504]
    mov QWORD PTR [rsp+272+rdx*8], rax
    mov QWORD PTR [rax + WS_DRIVE], r14
    mov QWORD PTR [rax + WS_QPTR], r12
    mov QWORD PTR [rax + WS_QLEN], r13
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + scan_worker]
    mov r9, rax
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    test rax, rax
    jz sra_thfail
    mov rdx, QWORD PTR [rsp+504]
    mov QWORD PTR [rsp+64+rdx*8], rax
    mov rax, QWORD PTR [rsp+496]
    inc rax
    mov QWORD PTR [rsp+496], rax
    jmp sra_next
sra_thfail:
    mov rdx, QWORD PTR [rsp+504]
    mov rcx, QWORD PTR [rsp+272+rdx*8]
    call ws_free
    mov rdx, QWORD PTR [rsp+504]
    mov QWORD PTR [rsp+272+rdx*8], 0
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
    jmp sra_next
sra_wsfail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
sra_next:
    inc r14d
    jmp sra_loop
sra_join:
    mov rax, QWORD PTR [rsp+496]
    test rax, rax
    jz sra_done
    mov ecx, eax
    lea rdx, [rsp+64]
    mov r8d, 1
    mov r9, -1
    call WaitForMultipleObjects
    xor r14d, r14d
sra_collect:
    mov rax, QWORD PTR [rsp+496]
    cmp r14, rax
    jae sra_done
    mov rcx, QWORD PTR [rsp+272+r14*8]
    test rcx, rcx
    jz sra_cnext
    mov QWORD PTR [rsp+504], rcx
    call ws_totals_to_globals
    mov rcx, QWORD PTR [rsp+504]
    call ws_used
    lea rdx, [rip + scan_arena_total]
    add QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+504]
    call flush_out
    mov rcx, QWORD PTR [rsp+64+r14*8]
    call CloseHandle
    mov rcx, QWORD PTR [rsp+504]
    call ws_free
sra_cnext:
    inc r14
    jmp sra_collect
sra_done:
    lea rax, [rip + g_matches]
    mov rax, QWORD PTR [rax]
    add rsp, 528
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// sra_mft_seq: variante --mft de scan_run_all: 1 ws por unidad, secuencial
// (MFT usa estado global temp/hash: no hilos). R12=qptr, R13=qlen.
// Acumula + flushea en orden; aborta al primer force_fail (el main avisa).
sra_mft_seq:
    call GetLogicalDrives
    mov ebx, eax
    xor r14d, r14d
sms_loop:
    cmp r14d, 26
    jae sms_done
    lea rax, [rip + mft_force_fail]
    cmp QWORD PTR [rax], 0
    jne sms_done
    mov eax, 1
    mov ecx, r14d
    shl eax, cl
    test ebx, eax
    jz sms_next
    mov eax, r14d
    add eax, 0x41
    lea rcx, [rip + drive_buf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + drive_buf]
    call GetDriveTypeW
    cmp eax, 2
    je sms_valid
    cmp eax, 3
    jne sms_next
sms_valid:
    lea rax, [rip + g_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    call ws_create
    test rax, rax
    jz sms_wsfail
    mov r15, rax
    mov QWORD PTR [rsp+504], rax
    mov QWORD PTR [rax + WS_QPTR], r12
    mov QWORD PTR [rax + WS_QLEN], r13
    mov eax, r14d
    add eax, 0x41
    mov WORD PTR [rsp+512], ax
    mov WORD PTR [rsp+514], 0x3A
    mov WORD PTR [rsp+516], 0x5C
    mov WORD PTR [rsp+518], 0
    mov rcx, r15
    lea rdx, [rsp+512]
    mov r8d, 3
    call scan_root_ws
    mov rcx, QWORD PTR [rsp+504]
    mov r15, rcx
    call ws_used
    lea rdx, [rip + scan_arena_total]
    add QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+504]
    call ws_totals_to_globals
    mov rcx, QWORD PTR [rsp+504]
    call flush_out
    mov rcx, QWORD PTR [rsp+504]
    call ws_free
    jmp sms_next
sms_wsfail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
sms_next:
    inc r14d
    jmp sms_loop
sms_done:
    lea rax, [rip + g_matches]
    mov rax, QWORD PTR [rax]
    add rsp, 528
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// sra_top_seq: variante --topdirs de scan_run_all: un ws, raices secuenciales
// (monohilo, tabla top global sin locks). R12=qptr WCHAR, R13=qlen.
sra_top_seq:
    lea rdi, [rip + top_cnt]
    xor eax, eax
    mov ecx, 60
    rep stosq
    call ws_create
    test rax, rax
    jz sra_top_fail
    mov r15, rax
    mov QWORD PTR [rsp+504], rax
    mov rcx, r12
    mov QWORD PTR [rax + WS_QPTR], rcx
    mov rcx, r13
    mov QWORD PTR [rax + WS_QLEN], rcx
    call GetLogicalDrives
    mov ebx, eax
    xor r14d, r14d
sra_top_loop:
    cmp r14d, 26
    jae sra_top_finish
    mov eax, 1
    mov ecx, r14d
    shl eax, cl
    test ebx, eax
    jz sra_top_next
    mov eax, r14d
    add eax, 0x41
    lea rcx, [rip + drive_buf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + drive_buf]
    call GetDriveTypeW
    cmp eax, 2
    je sra_top_valid
    cmp eax, 3
    jne sra_top_next
sra_top_valid:
    lea rax, [rip + g_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov eax, r14d
    add eax, 0x41
    mov WORD PTR [rsp+512], ax
    mov WORD PTR [rsp+514], 0x3A
    mov WORD PTR [rsp+516], 0x5C
    mov WORD PTR [rsp+518], 0
    mov rcx, QWORD PTR [rsp+504]
    mov r15, rcx
    lea rdx, [rsp+512]
    mov r8d, 3
    call scan_root_ws
sra_top_next:
    inc r14d
    jmp sra_top_loop
sra_top_finish:
    mov rcx, QWORD PTR [rsp+504]
    mov r15, rcx
    call ws_used
    lea rdx, [rip + scan_arena_total]
    add QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+504]
    call ws_totals_to_globals
    mov rcx, QWORD PTR [rsp+504]
    call flush_out
    mov rcx, QWORD PTR [rsp+504]
    call scan_print_tops
    mov rcx, QWORD PTR [rsp+504]
    call ws_free
    lea rax, [rip + g_matches]
    mov rax, QWORD PTR [rax]
    add rsp, 528
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret
sra_top_fail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
    xor eax, eax
    add rsp, 528
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// scan_arena_used: bytes usados por el último scan (suma de workspaces).
scan_arena_used:
    lea rax, [rip + scan_arena_total]
    mov rax, QWORD PTR [rax]
    ret

// top_insert: RCX=ws, RDX=count, R8=src bytes ptr, R9=len bytes.
// Solo inserta si count supera al menor del top20 (orden desc). Copia el
// path al ws (arena privada, sin locks: topdirs es monohilo secuencial).
top_insert:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64
    mov r15, rcx
    mov r12, rdx
    mov QWORD PTR [rsp+32], r8
    mov QWORD PTR [rsp+40], r9
    xor r13d, r13d
ti_find:
    cmp r13, 20
    jae ti_ret
    lea rax, [rip + top_cnt]
    mov rax, QWORD PTR [rax+r13*8]
    cmp r12, rax
    ja ti_doalloc
    inc r13
    jmp ti_find
ti_doalloc:
    mov rcx, r15
    mov rdx, QWORD PTR [rsp+40]
    inc rdx
    call ws_alloc
    test rax, rax
    jz ti_ret
    mov rbx, rax
    mov rsi, QWORD PTR [rsp+32]
    mov rdi, rbx
    mov rcx, QWORD PTR [rsp+40]
    rep movsb
    mov BYTE PTR [rdi], 0
    mov r14, 19
ti_shift:
    cmp r14, r13
    jbe ti_store
    lea rax, [rip + top_cnt]
    mov rdx, QWORD PTR [rax+r14*8-8]
    mov QWORD PTR [rax+r14*8], rdx
    lea rax, [rip + top_ptr]
    mov rdx, QWORD PTR [rax+r14*8-8]
    mov QWORD PTR [rax+r14*8], rdx
    lea rax, [rip + top_len]
    mov rdx, QWORD PTR [rax+r14*8-8]
    mov QWORD PTR [rax+r14*8], rdx
    dec r14
    jmp ti_shift
ti_store:
    lea rax, [rip + top_cnt]
    mov QWORD PTR [rax+r13*8], r12
    lea rax, [rip + top_ptr]
    mov QWORD PTR [rax+r13*8], rbx
    mov rdx, QWORD PTR [rsp+40]
    lea rax, [rip + top_len]
    mov QWORD PTR [rax+r13*8], rdx
ti_ret:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// scan_print_tops: RCX=ws. Imprime top20 (count>0) a stderr (scan_opt_errh).
// Linea WCHAR: "<count> <path-sin-\\?\\>\r\n". Usa WB_EMITW (path) y WB_OUTW
// (linea); fallback UTF-8 via WB_OUTA si WriteConsoleW falla (redirect).
// Frame 8 pushes + sub 136 (alineado). Locales: +64 ws, +72 i, +80 count,
//   +88 src, +96 slen, +104 wlen, +112 linelen, +120 escrito.
scan_print_tops:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 136
    mov QWORD PTR [rsp+64], rcx
    mov QWORD PTR [rsp+72], 0
spt_loop:
    mov rax, QWORD PTR [rsp+72]
    cmp rax, 20
    jae spt_ret
    lea rdx, [rip + top_cnt]
    mov rax, QWORD PTR [rdx+rax*8]
    test rax, rax
    jz spt_ret
    mov QWORD PTR [rsp+80], rax
    mov rdx, QWORD PTR [rsp+72]
    lea rax, [rip + top_ptr]
    mov rax, QWORD PTR [rax+rdx*8]
    mov QWORD PTR [rsp+88], rax
    lea rax, [rip + top_len]
    mov rax, QWORD PTR [rax+rdx*8]
    mov QWORD PTR [rsp+96], rax
    // path bytes -> WCHAR en WB_EMITW (cap 32768)
    mov rcx, 65001
    xor edx, edx
    mov r8, QWORD PTR [rsp+88]
    mov r9, QWORD PTR [rsp+96]
    mov rax, QWORD PTR [rsp+64]
    lea rax, [rax + WB_EMITW]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 32768
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call MultiByteToWideChar
    test eax, eax
    jz spt_next
    movsxd rdx, eax
    mov QWORD PTR [rsp+104], rdx
    mov rbx, QWORD PTR [rsp+64]
    lea rsi, [rbx + WB_EMITW]
    // strip \\?\ (o \\?\UNC\ -> \\) solo en pantalla
    cmp rdx, 4
    jb spt_build
    mov eax, DWORD PTR [rsi]
    cmp eax, 0x005C005C
    jne spt_build
    movzx eax, WORD PTR [rsi+4]
    cmp eax, 0x3F
    jne spt_build
    movzx eax, WORD PTR [rsi+6]
    cmp eax, 0x5C
    jne spt_build
    cmp rdx, 8
    jb spt_skip4
    movzx eax, WORD PTR [rsi+8]
    cmp eax, 0x55
    jne spt_skip4
    movzx eax, WORD PTR [rsi+10]
    cmp eax, 0x4E
    jne spt_skip4
    movzx eax, WORD PTR [rsi+12]
    cmp eax, 0x43
    jne spt_skip4
    movzx eax, WORD PTR [rsi+14]
    cmp eax, 0x5C
    jne spt_skip4
    add rsi, 12
    sub rdx, 6
    jmp spt_build
spt_skip4:
    add rsi, 8
    sub rdx, 4
spt_build:
    mov QWORD PTR [rsp+104], rdx
    // linea en WB_OUTW: count decimal + ' ' + path + CRLF
    mov rax, QWORD PTR [rsp+64]
    lea rdi, [rax + WB_OUTW]
    mov QWORD PTR [rsp+112], rdi
    // count -> digitos (pila [rsp+120..]): div 10, guarda reverso
    mov rax, QWORD PTR [rsp+80]
    lea rbx, [rsp+120]
    mov r14, rbx
    mov r15, 10
    test rax, rax
    jnz spt_dloop
    mov WORD PTR [rbx], 0x30
    add rbx, 2
    jmp spt_ddone
spt_dloop:
    xor edx, edx
    div r15
    add edx, 0x30
    mov WORD PTR [rbx], dx
    add rbx, 2
    test rax, rax
    jnz spt_dloop
spt_ddone:
    // copia digitos en orden (de rbx-2 hacia atras hasta r14)
    mov rax, rbx
spt_dcopy:
    sub rbx, 2
    cmp rbx, r14
    jb spt_dcopied
    movzx edx, WORD PTR [rbx]
    mov WORD PTR [rdi], dx
    add rdi, 2
    jmp spt_dcopy
spt_dcopied:
    mov WORD PTR [rdi], 0x20
    add rdi, 2
    // path (rdx=wlen en spt_build? recargar: wlen en [rsp+104], src en rsi)
    mov rdx, QWORD PTR [rsp+104]
    // trunc si excede OUT_CAP(32768): linelen actual = (rdi-base)/2
    mov rax, QWORD PTR [rsp+64]
    lea rax, [rax + WB_OUTW]
    mov rcx, rdi
    sub rcx, rax
    shr rcx, 1
    // resto = 32768 - rcx - 2 (CRLF); si wlen > resto, wlen = resto
    mov rax, 32768
    sub rax, rcx
    sub rax, 2
    cmp rdx, rax
    jbe spt_pcopy
    mov rdx, rax
spt_pcopy:
    mov rcx, rdx
    test rcx, rcx
    jz spt_crlf
    rep movsw
spt_crlf:
    mov WORD PTR [rdi], 0x0D
    mov WORD PTR [rdi+2], 0x0A
    add rdi, 4
    mov rax, QWORD PTR [rsp+64]
    lea rax, [rax + WB_OUTW]
    mov rcx, rdi
    sub rcx, rax
    shr rcx, 1
    mov QWORD PTR [rsp+112], rcx
    // write a stderr
    lea rax, [rip + scan_opt_errh]
    mov rcx, QWORD PTR [rax]
    mov rax, QWORD PTR [rsp+64]
    lea rdx, [rax + WB_OUTW]
    mov r8, QWORD PTR [rsp+112]
    lea r9, [rsp+120]
    mov QWORD PTR [rsp+32], 0
    call WriteConsoleW
    test eax, eax
    jnz spt_next
    // fallback UTF-8
    mov ecx, 65001
    xor edx, edx
    mov rax, QWORD PTR [rsp+64]
    lea r8, [rax + WB_OUTW]
    mov r9, QWORD PTR [rsp+112]
    mov rax, QWORD PTR [rsp+64]
    lea rax, [rax + WB_OUTA]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 98304
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz spt_next
    mov r8d, eax
    lea rax, [rip + scan_opt_errh]
    mov rcx, QWORD PTR [rax]
    mov rax, QWORD PTR [rsp+64]
    lea rdx, [rax + WB_OUTA]
    lea r9, [rsp+120]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
spt_next:
    mov rax, QWORD PTR [rsp+72]
    inc rax
    mov QWORD PTR [rsp+72], rax
    jmp spt_loop
spt_ret:
    add rsp, 136
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// scan_idxdbg: RCX=qptr WCHAR, RDX=qlen. Diagnóstico --idxdbg: reproduce el
// path del indexador GUI en el CLI (big+index, UN ws, raíces secuenciales,
// filtro lineal). Vuelca: g_files=visitados, g_matches=matches del filtro,
// g_excluded, g_disks, scan_truncated (+1 si inconsistencia o/w trunc),
// scan_arena_total. Libera el ws. -> RAX=matches.
// Chequeo de integridad por record: prefijo blen<=780 y ptr dentro de
// [arena_base, arena_brk); más reccnt≈files+4 (tolerancia 64).
// Frame 256: +64 qptr,+72 qlen,+80 ws,+88 freq,+96 t0,+104 t1,+112 i,
//   +116 drive, +120 mask, +128 f_freq, +136 f_t0, +144 f_t1 (fase filtro),
//   +152 flo, +160 fhi, +168 fskip, +192 SYSTEM_INFO(48), +240 T, +248 i.
//   RBX=ws, R12=fqa, R13=fqlen, R14=base, R15=n, RDI=total.
//   filtro_ms mide SOLO el loop de filtro (QPC); el scan total lo mide main.s.
//   Filtro paralelo: si n>200K, T hilos (cores, tope 8) sobre particiones
//   contiguas (suma de conteos; mismo total exacto que el loop single).
scan_idxdbg:
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
    mov QWORD PTR [rsp+64], rcx
    mov QWORD PTR [rsp+72], rdx
    lea rax, [rip + scan_big_rec]
    mov QWORD PTR [rax], 1
    lea rax, [rip + scan_opt_index]
    mov QWORD PTR [rax], 1
    lea rax, [rip + g_files]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_matches]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_excluded]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_disks]
    mov QWORD PTR [rax], 0
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 0
    lea rax, [rip + scan_arena_total]
    mov QWORD PTR [rax], 0
    call ws_create
    test rax, rax
    jz idxd_fail
    mov rbx, rax
    mov QWORD PTR [rsp+80], rax
    // query -> UTF-8 a WB_QA (el índice usa query vacía; el filtro no)
    mov rcx, 65001
    xor edx, edx
    mov r8, QWORD PTR [rsp+64]
    mov r9, QWORD PTR [rsp+72]
    lea rax, [rbx + WB_QA]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 8192
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    movsxd r13, eax
    lea r12, [rbx + WB_QA]
    // prefiltro primer byte: lo=fqa[0] (minusculas), hi=mayuscula si a-z.
    // Con '*'/'?' lider no aplica (primer byte no literal): fskip=1.
    mov QWORD PTR [rsp+168], 0
    test r13, r13
    jz idxd_nopre
    movzx eax, BYTE PTR [r12]
    cmp QWORD PTR [rip + scan_is_glob], 0
    je idxd_precomm
    cmp eax, 0x2A
    je idxd_nopre
    cmp eax, 0x3F
    je idxd_nopre
idxd_precomm:
    mov QWORD PTR [rsp+152], rax
    cmp eax, 0x61
    jb idxd_prehave
    cmp eax, 0x7A
    ja idxd_prehave
    sub eax, 0x20
idxd_prehave:
    mov QWORD PTR [rsp+160], rax
    jmp idxd_doloop
idxd_nopre:
    mov QWORD PTR [rsp+168], 1
idxd_doloop:
    call GetLogicalDrives
    mov DWORD PTR [rsp+120], eax
    mov DWORD PTR [rsp+124], 0
idxd_loop:
    mov eax, DWORD PTR [rsp+124]
    cmp eax, 26
    jae idxd_scanned
    mov ecx, eax
    mov eax, 1
    shl eax, cl
    test eax, DWORD PTR [rsp+120]
    jz idxd_next
    mov eax, DWORD PTR [rsp+124]
    add eax, 0x41
    lea rcx, [rip + drive_buf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + drive_buf]
    call GetDriveTypeW
    cmp eax, 2
    je idxd_valid
    cmp eax, 3
    jne idxd_next
idxd_valid:
    lea rax, [rip + g_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov rcx, rbx
    lea rdx, [rip + drive_buf]
    mov r8d, 3
    call scan_root_ws
idxd_next:
    mov eax, DWORD PTR [rsp+124]
    inc eax
    mov DWORD PTR [rsp+124], eax
    jmp idxd_loop
idxd_scanned:
    // filtro lineal idéntico al GUI + integridad
    mov rcx, rbx
    call ws_used
    lea rdx, [rip + scan_arena_total]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rbx + WS_FILES]
    lea rdx, [rip + g_files]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rbx + WS_EXCL]
    lea rdx, [rip + g_excluded]
    mov QWORD PTR [rdx], rax
    cmp QWORD PTR [rbx + WS_TRUNC], 0
    je idxd_notr
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
idxd_notr:
    mov rcx, rbx
    call scan_ws_recbase
    mov r14, rax
    mov rcx, rbx
    call scan_ws_reccnt
    mov r15, rax
    xor edi, edi
    xor esi, esi
    mov QWORD PTR [rsp+112], 0
    mov rax, QWORD PTR [rbx + WS_A_BASE]
    mov QWORD PTR [rsp+88], rax
    mov rax, QWORD PTR [rbx + WS_A_BRK]
    mov QWORD PTR [rsp+96], rax
    lea rcx, [rsp+128]
    call QueryPerformanceFrequency
    lea rcx, [rsp+136]
    call QueryPerformanceCounter
    cmp r15, 200000
    ja idxd_parfilter
idxd_floop:
    mov rax, QWORD PTR [rsp+112]
    cmp rax, r15
    jae idxd_fdone
    mov rdx, rax
    imul rdx, rdx, 12
    mov r10, QWORD PTR [r14+rdx]
    // integridad: ptr en [base, brk) y blen<=780
    cmp r10, QWORD PTR [rsp+88]
    jb idxd_bad
    cmp r10, QWORD PTR [rsp+96]
    jae idxd_bad
    movzx edx, WORD PTR [r10-2]
    cmp edx, 780
    ja idxd_bad
    cmp QWORD PTR [rsp+168], 0
    jne idxd_domatch
    mov rcx, r10
    mov r8, QWORD PTR [rsp+152]
    mov r9, QWORD PTR [rsp+160]
    call prefilter_firstbyte
    test eax, eax
    jz idxd_fnext
    movzx edx, WORD PTR [r10-2]
idxd_domatch:
    mov rcx, r10
    mov r8, r12
    mov r9, r13
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne 1f
    call contains_ci_a
    jmp 2f
1:
    call glob_match_ci_a
2:
    test eax, eax
    jz idxd_fnext
    inc rdi
    jmp idxd_fnext
idxd_bad:
    inc rsi
idxd_fnext:
    inc QWORD PTR [rsp+112]
    jmp idxd_floop
// Filtro paralelo (n>200K): T hilos sobre particiones contiguas.
// T = min(cores, 8). Join uno-por-uno (robusto si un CreateThread falla:
// ese tramo corre inline en este hilo). Suma totales+bad (= single exacto).
idxd_parfilter:
    lea rcx, [rsp+192]
    call GetSystemInfo
    mov eax, DWORD PTR [rsp+192+32]
    test eax, eax
    jz idxd_floop
    cmp eax, 8
    jbe idxd_coresok
    mov eax, 8
idxd_coresok:
    mov QWORD PTR [rsp+240], rax
    lea rax, [rip + idx_th_base]
    mov QWORD PTR [rax], r14
    lea rax, [rip + idx_th_qa]
    mov QWORD PTR [rax], r12
    lea rax, [rip + idx_th_qlen]
    mov QWORD PTR [rax], r13
    mov rax, QWORD PTR [rsp+152]
    lea rdx, [rip + idx_th_flo]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+160]
    lea rdx, [rip + idx_th_fhi]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+168]
    lea rdx, [rip + idx_th_fskip]
    mov QWORD PTR [rdx], rax
    lea rax, [rip + idx_th_n]
    mov QWORD PTR [rax], r15
    mov rax, QWORD PTR [rbx]
    lea rdx, [rip + idx_th_abeg]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+96]
    lea rdx, [rip + idx_th_brk]
    mov QWORD PTR [rdx], rax
    mov QWORD PTR [rsp+248], 0
idxd_zero:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, 8
    jae idxd_zeroed
    lea rdx, [rip + idx_th_tot]
    mov QWORD PTR [rdx+rax*8], 0
    lea rdx, [rip + idx_th_bad]
    mov QWORD PTR [rdx+rax*8], 0
    inc QWORD PTR [rsp+248]
    jmp idxd_zero
idxd_zeroed:
    mov QWORD PTR [rsp+248], 0
    mov rax, r15
    xor edx, edx
    div QWORD PTR [rsp+240]
    mov rdi, rax
    mov rsi, rdx
    mov QWORD PTR [rsp+248], 0
idxd_mkth:
    mov rcx, QWORD PTR [rsp+248]
    cmp rcx, QWORD PTR [rsp+240]
    jae idxd_join
    mov rax, rcx
    mul rdi
    mov rdx, rcx
    cmp rcx, rsi
    jae idxd_nomin1
    mov rdx, rsi
idxd_nomin1:
    add rax, rdx
    lea rdx, [rip + idx_th_start]
    mov QWORD PTR [rdx+rcx*8], rax
    mov rdx, rdi
    cmp rcx, rsi
    jae idxd_nomin2
    inc rdx
idxd_nomin2:
    add rax, rdx
    lea rdx, [rip + idx_th_end]
    mov QWORD PTR [rdx+rcx*8], rax
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + idxdbg_worker]
    mov r9, QWORD PTR [rsp+248]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    lea rdx, [rip + idx_th_h]
    mov rcx, QWORD PTR [rsp+248]
    mov QWORD PTR [rdx+rcx*8], rax
    test rax, rax
    jnz idxd_mknext
    mov rcx, QWORD PTR [rsp+248]
    call idxdbg_worker
idxd_mknext:
    inc QWORD PTR [rsp+248]
    jmp idxd_mkth
idxd_join:
    xor edi, edi
    xor esi, esi
    mov QWORD PTR [rsp+248], 0
idxd_wait:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, QWORD PTR [rsp+240]
    jae idxd_sumdone
    lea rdx, [rip + idx_th_h]
    mov rcx, QWORD PTR [rdx+rax*8]
    test rcx, rcx
    jz idxd_waitsum
    mov edx, -1
    call WaitForSingleObject
    lea rdx, [rip + idx_th_h]
    mov rax, QWORD PTR [rsp+248]
    mov rcx, QWORD PTR [rdx+rax*8]
    call CloseHandle
idxd_waitsum:
    lea rdx, [rip + idx_th_tot]
    mov rax, QWORD PTR [rsp+248]
    mov rcx, QWORD PTR [rdx+rax*8]
    add rdi, rcx
    lea rdx, [rip + idx_th_bad]
    mov rcx, QWORD PTR [rdx+rax*8]
    add rsi, rcx
    inc QWORD PTR [rsp+248]
    jmp idxd_wait
idxd_sumdone:
    jmp idxd_fdone
idxd_fdone:
    lea rcx, [rsp+144]
    call QueryPerformanceCounter
    mov rax, QWORD PTR [rsp+144]
    sub rax, QWORD PTR [rsp+136]
    mov r11, rax
    mov rax, QWORD PTR [rsp+128]
    test rax, rax
    jz idxd_fmszero
    mov rcx, 1000
    mov rax, r11
    mul rcx
    div QWORD PTR [rsp+128]
    mov r11, rax
    jmp idxd_fmsok
idxd_fmszero:
    xor r11d, r11d
idxd_fmsok:
    lea rax, [rip + scan_filter_ms]
    mov QWORD PTR [rax], r11
    lea rax, [rip + g_matches]
    mov QWORD PTR [rax], rdi
    // sanidad: reccnt≈files+4 (tolerancia 64) y 0 corruptos
    test rsi, rsi
    jnz idxd_sanity_fail
    mov rax, QWORD PTR [rbx + WS_FILES]
    add rax, 4
    mov rdx, QWORD PTR [rbx + WS_RECCNT]
    sub rdx, rax
    cmp rdx, 64
    jg idxd_sanity_fail
    cmp rdx, -64
    jl idxd_sanity_fail
    jmp idxd_cleanup
idxd_sanity_fail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
idxd_cleanup:
    mov rcx, rbx
    call ws_free
    lea rax, [rip + scan_opt_index]
    mov QWORD PTR [rax], 0
    lea rax, [rip + g_matches]
    mov rax, QWORD PTR [rax]
    jmp idxd_ret
idxd_fail:
    lea rax, [rip + scan_truncated]
    mov QWORD PTR [rax], 1
    xor eax, eax
idxd_ret:
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

// idxdbg_worker(RCX=slot). Cuenta matches en [start,end) con el mismo
// prefilter+match que el loop single. Tot->idx_th_tot[slot],
// bad->idx_th_bad[slot]. Frame push rbx + sub 64 (alineado).
idxdbg_worker:
    push rbx
    sub rsp, 64
    mov rbx, rcx
    mov rax, QWORD PTR [rip + idx_th_base]
    mov QWORD PTR [rsp+56], rax
    lea rax, [rip + idx_th_start]
    mov rax, QWORD PTR [rax+rbx*8]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rip + idx_th_end]
    mov rax, QWORD PTR [rax+rbx*8]
    mov rdx, QWORD PTR [rip + idx_th_n]
    cmp rax, rdx
    jbe idxw_endok
    mov rax, rdx
idxw_endok:
    mov QWORD PTR [rsp+40], rax
    mov QWORD PTR [rsp+48], 0
idxw_loop:
    mov rax, QWORD PTR [rsp+32]
    cmp rax, QWORD PTR [rsp+40]
    jae idxw_done
    mov rdx, rax
    imul rdx, rdx, 12
    add rdx, QWORD PTR [rsp+56]
    mov r10, QWORD PTR [rdx]
    cmp r10, QWORD PTR [rip + idx_th_abeg]
    jb idxw_bad
    cmp r10, QWORD PTR [rip + idx_th_brk]
    jae idxw_bad
    movzx edx, WORD PTR [r10-2]
    cmp edx, 780
    ja idxw_bad
    cmp QWORD PTR [rip + idx_th_fskip], 0
    jne idxw_domatch
    mov rcx, r10
    mov r8, QWORD PTR [rip + idx_th_flo]
    mov r9, QWORD PTR [rip + idx_th_fhi]
    call prefilter_firstbyte
    test eax, eax
    jz idxw_next
    movzx edx, WORD PTR [r10-2]
idxw_domatch:
    mov rcx, r10
    mov r8, QWORD PTR [rip + idx_th_qa]
    mov r9, QWORD PTR [rip + idx_th_qlen]
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne idxw_glob
    call contains_ci_a
    jmp idxw_test
idxw_glob:
    call glob_match_ci_a
idxw_test:
    test eax, eax
    jz idxw_next
    inc QWORD PTR [rsp+48]
    jmp idxw_next
idxw_bad:
    lea rax, [rip + idx_th_bad]
    inc QWORD PTR [rax+rbx*8]
idxw_next:
    inc QWORD PTR [rsp+32]
    jmp idxw_loop
idxw_done:
    lea rax, [rip + idx_th_tot]
    mov rdx, QWORD PTR [rsp+48]
    mov QWORD PTR [rax+rbx*8], rdx
    xor eax, eax
    add rsp, 64
    pop rbx
    ret

// scan_ws_recbase: RCX=ws -> RAX=base de records. Leaf (para GUI).
scan_ws_recbase:
    mov rax, QWORD PTR [rcx + WS_REC]
    ret

// scan_ws_reccnt: RCX=ws -> RAX=records usados. Leaf (para GUI).
scan_ws_reccnt:
    mov rax, QWORD PTR [rcx + WS_RECCNT]
    ret

// scan_ws_path: RCX=ws -> RAX=dir del path en bytes (WB_DIRPATH). Leaf.
scan_ws_path:
    lea rax, [rcx + WB_DIRPATH]
    ret

// scan_ws_parent: RCX=ws, RDX=idx -> EAX=parent idx (bit31 fuera). Leaf.
scan_ws_parent:
    mov rax, QWORD PTR [rcx + WS_REC]
    imul rdx, rdx, 12
    mov eax, DWORD PTR [rax + rdx + 8]
    and eax, 0x7FFFFFFF
    ret

// scan_ws_files: RCX=ws -> RAX=archivos visitados. Leaf (progreso GUI).
scan_ws_files:
    mov rax, QWORD PTR [rcx + WS_FILES]
    ret

// build_path: RCX=ws, R11D=índice -> EAX=largo en BYTES (sin NUL).
// Ruta UTF-8 en WB_DIRPATH con NUL. 0 = error (>100000 B o profundidad).
// Cache de un nivel en el ws. Solo registros volátiles.
build_path:
    sub rsp, 16
    mov QWORD PTR [rsp+8], rcx
    mov eax, r11d
    cmp rax, QWORD PTR [rcx + WS_BPCIDX]
    jne bp_build
    mov QWORD PTR [rcx + WS_BPMISS], 0
    mov eax, DWORD PTR [rcx + WS_BPCLEN]
    add rsp, 16
    ret
bp_build:
    mov DWORD PTR [rcx + WS_BPTMP], r11d
    mov r10d, r11d
    xor r9d, r9d
bp_collect:
    cmp r9, SEG_MAX
    jae bp_fail
    mov rax, QWORD PTR [rcx + WS_REC]
    mov rdx, r10
    imul rdx, rdx, 12
    add rdx, rax
    mov rax, QWORD PTR [rdx]
    // tombstone (delta): nombre nulo -> path invalido, sin AV
    test rax, rax
    jz bp_fail
    movzx esi, WORD PTR [rax-2]
    mov r8, r9
    shl r8, 4
    lea r11, [rcx + WB_SEG]
    mov QWORD PTR [r11+r8], rax
    mov QWORD PTR [r11+r8+8], rsi
    inc r9
    mov eax, DWORD PTR [rdx+8]
    cmp eax, 0xFFFFFFFF
    je bp_have_all
    and eax, 0x7FFFFFFF
    mov r10d, eax
    movsxd r10, r10d
    jmp bp_collect
bp_have_all:
    dec r9
    js bp_fail
    mov rdx, r9
    shl rdx, 4
    lea rax, [rcx + WB_SEG]
    mov rsi, QWORD PTR [rax+rdx]
    mov r8, QWORD PTR [rax+rdx+8]
    cmp r8d, 100000
    ja bp_fail
    lea rdi, [rcx + WB_DIRPATH]
    mov ecx, r8d
    rep movsb
    mov rcx, QWORD PTR [rsp+8]
    mov r10d, r8d
bp_seg:
    sub r9, 1
    js bp_built
    lea rax, [rcx + WB_SEG]
    mov rdx, r9
    shl rdx, 4
    mov rsi, QWORD PTR [rax+rdx]
    mov edx, DWORD PTR [rax+rdx+8]
    mov r11d, edx
    cmp r10d, 0
    je bp_dosep
    cmp BYTE PTR [rdi-1], 0x5C
    je bp_nosep
bp_dosep:
    mov BYTE PTR [rdi], 0x5C
    inc rdi
    inc r10d
bp_nosep:
    mov ecx, edx
    rep movsb
    mov rcx, QWORD PTR [rsp+8]
    add r10d, r11d
    cmp r10d, 100000
    ja bp_fail
    jmp bp_seg
bp_built:
    mov BYTE PTR [rdi], 0
    mov eax, r10d
    mov DWORD PTR [rcx + WS_BPCLEN], eax
    mov edx, DWORD PTR [rcx + WS_BPTMP]
    mov QWORD PTR [rcx + WS_BPCIDX], rdx
    mov QWORD PTR [rcx + WS_BPMISS], 1
    add rsp, 16
    ret
bp_fail:
    mov rcx, QWORD PTR [rsp+8]
    mov QWORD PTR [rcx + WS_BPCIDX], -1
    xor eax, eax
    add rsp, 16
    ret

// emit_path: RCX=ws, RSI=ptr WCHAR, EDX=largo. Agrega CRLF, flushea si falta.
// Quita el prefijo \\?\ (o \\?\UNC\ -> \\) solo en pantalla.
emit_path:
    sub rsp, 96
    mov QWORD PTR [rsp+64], rcx
    cmp edx, 4
    jb emit_noprefix
    mov eax, DWORD PTR [rsi]
    cmp eax, 0x005C005C
    jne emit_noprefix
    movzx eax, WORD PTR [rsi+4]
    cmp eax, 0x3F
    jne emit_noprefix
    movzx eax, WORD PTR [rsi+6]
    cmp eax, 0x5C
    jne emit_noprefix
    cmp edx, 8
    jb emit_skip4
    movzx eax, WORD PTR [rsi+8]
    cmp eax, 0x55
    jne emit_skip4
    movzx eax, WORD PTR [rsi+10]
    cmp eax, 0x4E
    jne emit_skip4
    movzx eax, WORD PTR [rsi+12]
    cmp eax, 0x43
    jne emit_skip4
    movzx eax, WORD PTR [rsi+14]
    cmp eax, 0x5C
    jne emit_skip4
    add rsi, 12
    sub edx, 6
    jmp emit_noprefix
emit_skip4:
    add rsi, 8
    sub edx, 4
emit_noprefix:
    mov QWORD PTR [rsp+72], rsi
    mov DWORD PTR [rsp+80], edx
    mov eax, edx
    add eax, 2
    cmp eax, OUT_CAP
    ja emit_direct
    mov rcx, QWORD PTR [rsp+64]
    mov edx, DWORD PTR [rcx + WS_OUTPOS]
    add edx, eax
    cmp edx, OUT_CAP
    jbe emit_copy
    mov rcx, QWORD PTR [rsp+64]
    call flush_out
    mov rcx, QWORD PTR [rsp+64]
emit_copy:
    lea rax, [rcx + WB_OUTW]
    mov edx, DWORD PTR [rcx + WS_OUTPOS]
    lea rdi, [rax + rdx*2]
    mov rsi, QWORD PTR [rsp+72]
    mov ecx, DWORD PTR [rsp+80]
    rep movsw
    mov DWORD PTR [rdi], 0x000A000D
    mov rax, QWORD PTR [rsp+64]
    mov edx, DWORD PTR [rax + WS_OUTPOS]
    add edx, DWORD PTR [rsp+80]
    add edx, 2
    mov DWORD PTR [rax + WS_OUTPOS], edx
    add rsp, 96
    ret
emit_direct:
    mov rcx, QWORD PTR [rsp+64]
    call flush_out
    mov rcx, QWORD PTR [rsp+64]
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    mov rdx, QWORD PTR [rsp+72]
    mov r8d, DWORD PTR [rsp+80]
    lea r9, [rsp+88]
    mov QWORD PTR [rsp+32], 0
    call WriteConsoleW
    test eax, eax
    jnz emit_direct_crlf
    mov ecx, 65001
    xor edx, edx
    mov r8, QWORD PTR [rsp+72]
    mov r9d, DWORD PTR [rsp+80]
    mov rax, QWORD PTR [rsp+64]
    lea rax, [rax + WB_OUTA]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 98304
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz emit_direct_crlf
    mov r8d, eax
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    mov rax, QWORD PTR [rsp+64]
    lea rdx, [rax + WB_OUTA]
    lea r9, [rsp+88]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
emit_direct_crlf:
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rip + crlf_w]
    mov r8d, 2
    lea r9, [rsp+88]
    mov QWORD PTR [rsp+32], 0
    call WriteConsoleW
    test eax, eax
    jnz emit_direct_done
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rip + crlf_a]
    mov r8d, 2
    lea r9, [rsp+88]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
emit_direct_done:
    add rsp, 96
    ret

// flush_out: RCX=ws. Escribe el buffer pendiente (WriteConsoleW, fallback UTF-8).
flush_out:
    sub rsp, 80
    mov QWORD PTR [rsp+72], rcx
    cmp DWORD PTR [rcx + WS_OUTPOS], 0
    je flush_ret
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    mov rax, QWORD PTR [rsp+72]
    lea rdx, [rax + WB_OUTW]
    mov r8d, DWORD PTR [rax + WS_OUTPOS]
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteConsoleW
    test eax, eax
    jnz flush_ok
    mov ecx, 65001
    xor edx, edx
    mov rax, QWORD PTR [rsp+72]
    lea r8, [rax + WB_OUTW]
    mov r9d, DWORD PTR [rax + WS_OUTPOS]
    mov rax, QWORD PTR [rsp+72]
    lea rax, [rax + WB_OUTA]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 98304
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz flush_ok
    mov r8d, eax
    lea rax, [rip + scan_opt_handle]
    mov rcx, QWORD PTR [rax]
    mov rax, QWORD PTR [rsp+72]
    lea rdx, [rax + WB_OUTA]
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
flush_ok:
    mov rax, QWORD PTR [rsp+72]
    mov DWORD PTR [rax + WS_OUTPOS], 0
flush_ret:
    add rsp, 80
    ret

.data
crlf_w: .short 0x0D, 0x0A
crlf_a: .byte 0x0D, 0x0A
def_win_mid: .short 0x5C, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x5C
def_win_end: .short 0x5C, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73
def_nm_mid: .short 0x5C, 0x6E, 0x6F, 0x64, 0x65, 0x5F, 0x6D, 0x6F, 0x64, 0x75, 0x6C, 0x65, 0x73, 0x5C
def_nm_end: .short 0x5C, 0x6E, 0x6F, 0x64, 0x65, 0x5F, 0x6D, 0x6F, 0x64, 0x75, 0x6C, 0x65, 0x73
def_rec: .short 0x24, 0x72, 0x65, 0x63, 0x79, 0x63, 0x6C, 0x65, 0x2E, 0x62, 0x69, 0x6E
def_sys: .short 0x73, 0x79, 0x73, 0x74, 0x65, 0x6D, 0x20, 0x76, 0x6F, 0x6C, 0x75, 0x6D, 0x65, 0x20, 0x69, 0x6E, 0x66, 0x6F, 0x72, 0x6D, 0x61, 0x74, 0x69, 0x6F, 0x6E
def_pf: .short 0x70, 0x61, 0x67, 0x65, 0x66, 0x69, 0x6C, 0x65, 0x2E, 0x73, 0x79, 0x73
def_hib: .short 0x68, 0x69, 0x62, 0x65, 0x72, 0x66, 0x69, 0x6C, 0x2E, 0x73, 0x79, 0x73
def_swp: .short 0x73, 0x77, 0x61, 0x70, 0x66, 0x69, 0x6C, 0x65, 0x2E, 0x73, 0x79, 0x73
def_winre: .short 0x24, 0x77, 0x69, 0x6E, 0x72, 0x65, 0x61, 0x67, 0x65, 0x6E, 0x74
def_recov: .short 0x72, 0x65, 0x63, 0x6F, 0x76, 0x65, 0x72, 0x79
def_cfgmsi: .short 0x63, 0x6F, 0x6E, 0x66, 0x69, 0x67, 0x2E, 0x6D, 0x73, 0x69
def_mso: .short 0x6D, 0x73, 0x6F, 0x63, 0x61, 0x63, 0x68, 0x65
def_wbt: .short 0x24, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x2E, 0x7E, 0x62, 0x74
def_wws: .short 0x24, 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x2E, 0x7E, 0x77, 0x73
def_winold: .short 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x2E, 0x6F, 0x6C, 0x64
def_perfl: .short 0x70, 0x65, 0x72, 0x66, 0x6C, 0x6F, 0x67, 0x73
def_pref: .short 0x70, 0x72, 0x65, 0x66, 0x65, 0x74, 0x63, 0x68
def_soft: .short 0x73, 0x6F, 0x66, 0x74, 0x77, 0x61, 0x72, 0x65, 0x64, 0x69, 0x73, 0x74, 0x72, 0x69, 0x62, 0x75, 0x74, 0x69, 0x6F, 0x6E
def_wtemp: .short 0x77, 0x69, 0x6E, 0x64, 0x6F, 0x77, 0x73, 0x5C, 0x74, 0x65, 0x6D, 0x70
def_atemp: .short 0x61, 0x70, 0x70, 0x64, 0x61, 0x74, 0x61, 0x5C, 0x6C, 0x6F, 0x63, 0x61, 0x6C, 0x5C, 0x74, 0x65, 0x6D, 0x70
def_inet: .short 0x69, 0x6E, 0x65, 0x74, 0x63, 0x61, 0x63, 0x68, 0x65
def_bcache: .short 0x5C, 0x63, 0x61, 0x63, 0x68, 0x65
def_codec: .short 0x63, 0x6F, 0x64, 0x65, 0x20, 0x63, 0x61, 0x63, 0x68, 0x65
def_svcw: .short 0x73, 0x65, 0x72, 0x76, 0x69, 0x63, 0x65, 0x20, 0x77, 0x6F, 0x72, 0x6B, 0x65, 0x72
def_pyc: .short 0x5F, 0x5F, 0x70, 0x79, 0x63, 0x61, 0x63, 0x68, 0x65, 0x5F, 0x5F

.bss
g_files: .space 8
g_matches: .space 8
g_excluded: .space 8
g_disks: .space 8
scan_truncated: .space 8
scan_opt_countonly: .space 8
scan_opt_handle: .space 8
scan_arena_total: .space 8
scan_ws_last: .space 8
scan_opt_index: .space 8
scan_bloom: .space 8
scan_big_rec: .space 8
scan_opt_idxdbg: .space 8
opt_noexcl: .space 8
opt_incwin: .space 8
opt_incnm: .space 8
opt_incsys: .space 8
opt_inccache: .space 8
opt_inctemp: .space 8
scan_is_glob: .space 8
scan_opt_topdirs: .space 8
scan_opt_errh: .space 8
scan_filter_ms: .space 8
idx_th_base: .space 8
idx_th_abeg: .space 8
idx_th_brk: .space 8
idx_th_n: .space 8
idx_th_qa: .space 8
idx_th_qlen: .space 8
idx_th_flo: .space 8
idx_th_fhi: .space 8
idx_th_fskip: .space 8
idx_th_start: .space 64
idx_th_end: .space 64
idx_th_tot: .space 64
idx_th_bad: .space 64
idx_th_h: .space 64
top_cnt: .space 160
top_ptr: .space 160
top_len: .space 160
excl_data: .space 8320
excl_lens: .space 128
excl_count: .space 8
// excl_glob: bitmask, bit i = el patron custom i tiene '*' o '?' (Rust glob).
// scan_is_pathq: 1 = la query contiene '\' o '/' (match sobre ruta completa).
excl_glob: .space 8
scan_is_pathq: .space 8
drive_buf: .space 8
