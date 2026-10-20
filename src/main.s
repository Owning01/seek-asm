// seek-asm: main.s — punto de entrada (global main, CRT de gcc).
// int main(int argc, char** argv). Convierte UTF-8/ACP a WCHAR,
// minúsculas una vez, mide con QPC, delega en scan_run/scan_run_all,
// stats a stderr. Sin ruta escanea todos los discos locales.
// Frame 544: args de pila en [rsp+0..63], locales en [rsp+64..543].
// Locales: +64 argc, +72 argv, +80 pat_utf8, +88 root_utf8, +96 countonly,
//   +104 pat_wptr, +112 pat_wlen, +120 root_wptr, +128 root_wlen,
//   +136 freq, +144 t0, +152 t1, +160 out_h, +168 err_h,
//   +176..207 tmp dígitos, +208 dashdash, +216..351 msg,
//   +352 excl_count, +360 excl_ptrs[16], +488 noexcl, +496 incwin, +504 incnm,
//   +512 incsys, +520 inccache, +528 inctemp, +536 topdirs.

.intel_syntax noprefix

// NOTA GAS: todo .equ numérico va ANTES del primer uso. Un .equ con
// referencia hacia adelante se ensambla como carga absoluta [addr].
.equ S_ARCH_LEN, 16
.equ S_MATCH_LEN, 15
.equ S_TIME_LEN, 8
.equ S_MS_LEN, 9
.equ S_KB_LEN, 2
.equ S_TRUNC_LEN, 18
.equ S_DISK_LEN, 8
.equ S_EXCL_LEN, 6
.equ S_MFT_LEN, 6
.equ S_MFTERR_LEN, 8
.equ S_MFTST_LEN, 7
.equ S_FILT_LEN, 8
.equ S_FILTMS_LEN, 2
.equ S_NL_LEN, 1
.equ U_LEN, 1002
.equ E_OPT_LEN, 38
.equ E_MANY_LEN, 41
.equ E_ARENA_LEN, 31
.equ E_CONV_LEN, 50
.equ E_LONG_LEN, 40
.equ E_ROOTLONG_LEN, 27
.equ E_CWD_LEN, 43
.equ E_EXCLVAL_LEN, 34
.equ E_MFT_LEN, 49
.equ E_EXCLMANY_LEN, 38
.equ E_EXCLLONG_LEN, 42

.text
.globl main

main:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 544
    mov DWORD PTR [rsp+64], ecx
    mov QWORD PTR [rsp+72], rdx
    mov QWORD PTR [rsp+80], 0
    mov QWORD PTR [rsp+88], 0
    mov QWORD PTR [rsp+96], 0
    // MFT auto DESACTIVADO: FSCTL_ENUM_USN_DATA/QUERY_USN_JOURNAL denegados
    // en Windows 11 26H2 (err=5/1) con admin+privilegios. --mft queda opt-in.
    mov QWORD PTR [rsp+208], 0
    mov QWORD PTR [rsp+352], 0
    mov QWORD PTR [rsp+488], 0
    mov QWORD PTR [rsp+496], 0
    mov QWORD PTR [rsp+504], 0
    mov QWORD PTR [rsp+512], 0
    mov QWORD PTR [rsp+520], 0
    mov QWORD PTR [rsp+528], 0
    mov QWORD PTR [rsp+536], 0
    mov ecx, -11
    call GetStdHandle
    mov QWORD PTR [rsp+160], rax
    mov ecx, -12
    call GetStdHandle
    mov QWORD PTR [rsp+168], rax
    mov rbx, 1
parse_loop:
    mov eax, DWORD PTR [rsp+64]
    cmp rbx, rax
    jae parse_done
    mov rax, QWORD PTR [rsp+72]
    mov rdi, QWORD PTR [rax+rbx*8]
    cmp QWORD PTR [rsp+208], 0
    jne positional
    movzx eax, BYTE PTR [rdi]
    cmp eax, 0x2D
    jne positional
    movzx eax, BYTE PTR [rdi+1]
    cmp eax, 0x2D
    jne shortflag
    cmp BYTE PTR [rdi+2], 0
    je set_dashdash
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_count]
    mov r8, 5
    call streq
    test eax, eax
    jz try_help
    mov QWORD PTR [rsp+96], 1
    jmp parse_next
try_help:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_help]
    mov r8, 4
    call streq
    test eax, eax
    jz try_exclude
    jmp do_help
try_exclude:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_exclude]
    mov r8, 7
    call streq
    test eax, eax
    jz try_noexcl
    mov rax, QWORD PTR [rsp+64]
    mov rcx, rbx
    inc rcx
    cmp rcx, rax
    jae err_exclval
    mov rax, QWORD PTR [rsp+352]
    cmp rax, 16
    jae err_exclmany
    mov rax, QWORD PTR [rsp+72]
    mov rdx, rbx
    inc rdx
    mov rdx, QWORD PTR [rax+rdx*8]
    mov rax, QWORD PTR [rsp+352]
    shl rax, 3
    lea rcx, [rsp+360]
    add rcx, rax
    mov QWORD PTR [rcx], rdx
    mov rax, QWORD PTR [rsp+352]
    inc rax
    mov QWORD PTR [rsp+352], rax
    inc rbx
    jmp parse_next
try_noexcl:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_noexcl]
    mov r8, 11
    call streq
    test eax, eax
    jz try_all
    mov QWORD PTR [rsp+488], 1
    jmp parse_next
try_all:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_all]
    mov r8, 3
    call streq
    test eax, eax
    jz try_incwin
    mov QWORD PTR [rsp+488], 1
    jmp parse_next
try_incwin:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_incwin]
    mov r8, 15
    call streq
    test eax, eax
    jz try_incnm
    mov QWORD PTR [rsp+496], 1
    jmp parse_next
try_incnm:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_incnm]
    mov r8, 18
    call streq
    test eax, eax
    jz try_incsys
    mov QWORD PTR [rsp+504], 1
    jmp parse_next
try_incsys:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_incsys]
    mov r8, 11
    call streq
    test eax, eax
    jz try_inccache
    mov QWORD PTR [rsp+512], 1
    jmp parse_next
try_inccache:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_inccache]
    mov r8, 13
    call streq
    test eax, eax
    jz try_inctemp
    mov QWORD PTR [rsp+520], 1
    jmp parse_next
try_inctemp:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_inctemp]
    mov r8, 12
    call streq
    test eax, eax
    jz try_topdirs
    mov QWORD PTR [rsp+528], 1
    jmp parse_next
try_topdirs:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_topdirs]
    mov r8, 7
    call streq
    test eax, eax
    jz try_nomft
    mov QWORD PTR [rsp+536], 1
    jmp parse_next
try_nomft:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_nomft]
    mov r8, 6
    call streq
    test eax, eax
    jz try_mft
    lea rax, [rip + scan_opt_mft]
    mov QWORD PTR [rax], 0
    jmp parse_next
try_mft:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_mft]
    mov r8, 3
    call streq
    test eax, eax
    jz try_idxdbg
    lea rax, [rip + scan_opt_mft]
    mov QWORD PTR [rax], 1
    lea rax, [rip + mft_explicit]
    mov QWORD PTR [rax], 1
    jmp parse_next
try_idxdbg:
    lea rcx, [rdi+2]
    lea rdx, [rip + lit_idxdbg]
    mov r8, 6
    call streq
    test eax, eax
    jz unknown_opt
    lea rax, [rip + scan_opt_idxdbg]
    mov QWORD PTR [rax], 1
    jmp parse_next
shortflag:
    cmp BYTE PTR [rdi+1], 0x68
    jne unknown_opt
    cmp BYTE PTR [rdi+2], 0
    jne unknown_opt
    jmp do_help
set_dashdash:
    mov QWORD PTR [rsp+208], 1
    jmp parse_next
positional:
    cmp QWORD PTR [rsp+80], 0
    jne have_pat
    mov QWORD PTR [rsp+80], rdi
    jmp parse_next
have_pat:
    cmp QWORD PTR [rsp+88], 0
    jne too_many
    mov QWORD PTR [rsp+88], rdi
parse_next:
    inc rbx
    jmp parse_loop
parse_done:
    cmp QWORD PTR [rsp+80], 0
    je no_pattern
    call arena_init
    test eax, eax
    jz err_arena
    // patrón -> WCHAR
    mov rcx, QWORD PTR [rsp+80]
    call utf8_to_wide
    test rax, rax
    jz err_conv
    mov QWORD PTR [rsp+104], rax
    mov QWORD PTR [rsp+112], rdx
    cmp rdx, 1024
    ja err_long
    // trim: recorta blancos (0x20/0x09) en ambos extremos ("  x  " -> "x")
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call cli_trim_query
    mov QWORD PTR [rsp+104], rax
    mov QWORD PTR [rsp+112], rdx
    // exclusiones custom -> WCHAR + registro
    mov rbx, 0
excl_loop:
    mov rax, QWORD PTR [rsp+352]
    cmp rbx, rax
    jae excl_done
    lea rax, [rsp+360]
    mov rcx, QWORD PTR [rax+rbx*8]
    call utf8_to_wide
    test rax, rax
    jz err_conv
    cmp rdx, 1
    jb err_excllong
    cmp rdx, 128
    ja err_excllong
    mov rcx, rax
    // RDX ya tiene len
    call scan_add_exclude
    test eax, eax
    jz err_exclmany
    inc rbx
    jmp excl_loop
excl_done:
    // raíz -> WCHAR (o todos los discos si no hay)
    cmp QWORD PTR [rsp+88], 0
    jne have_root
    // sin ruta: no convertir, se usa scan_run_all
    mov QWORD PTR [rsp+120], 0
    mov QWORD PTR [rsp+128], 0
    jmp root_done
have_root:
    mov rcx, QWORD PTR [rsp+88]
    call utf8_to_wide
    test rax, rax
    jz err_conv
    mov QWORD PTR [rsp+120], rax
    mov QWORD PTR [rsp+128], rdx
    cmp rdx, 32000
    jae err_rootlong
root_done:
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call lowercase_query
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call glob_has_wild
    lea rcx, [rip + scan_is_glob]
    mov QWORD PTR [rcx], rax
    // query de ruta: contiene '\' o '/' -> match sobre la ruta completa
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call skc_query_is_pathq
    lea rcx, [rip + scan_is_pathq]
    mov QWORD PTR [rcx], rax
    mov rcx, QWORD PTR [rsp+488]
    mov rdx, QWORD PTR [rsp+496]
    mov r8, QWORD PTR [rsp+504]
    call scan_set_opts
    mov rax, QWORD PTR [rsp+512]
    lea rcx, [rip + opt_incsys]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rsp+520]
    lea rcx, [rip + opt_inccache]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rsp+528]
    lea rcx, [rip + opt_inctemp]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rsp+536]
    lea rcx, [rip + scan_opt_topdirs]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rsp+168]
    lea rcx, [rip + scan_opt_errh]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rsp+96]
    lea rdx, [rip + scan_opt_countonly]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+160]
    lea rdx, [rip + scan_opt_handle]
    mov QWORD PTR [rdx], rax
    lea rcx, [rsp+136]
    call QueryPerformanceFrequency
    lea rcx, [rsp+144]
    call QueryPerformanceCounter
    cmp QWORD PTR [rsp+88], 0
    jne do_single
    lea rax, [rip + scan_opt_idxdbg]
    cmp QWORD PTR [rax], 0
    je do_all
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call scan_idxdbg
    jmp timed
do_all:
    mov rcx, QWORD PTR [rsp+104]
    mov rdx, QWORD PTR [rsp+112]
    call scan_run_all
    jmp timed
do_single:
    mov rcx, QWORD PTR [rsp+120]
    mov rdx, QWORD PTR [rsp+128]
    mov r8, QWORD PTR [rsp+104]
    mov r9, QWORD PTR [rsp+112]
    call scan_run
timed:
    lea rcx, [rsp+152]
    call QueryPerformanceCounter
    // ms = (t1-t0)*1000/freq
    mov rax, QWORD PTR [rsp+152]
    sub rax, QWORD PTR [rsp+144]
    mov r15, rax
    mov rax, QWORD PTR [rsp+136]
    test rax, rax
    jz ms_zero
    mov rcx, 1000
    mov rax, r15
    mul rcx
    div QWORD PTR [rsp+136]
    mov r15, rax
    jmp ms_done
ms_zero:
    xor r15d, r15d
ms_done:
    mov QWORD PTR [rsp+144], r15
    // --mft forzado sin MFT (sin admin / no NTFS / no drive-root): error exit 1
    lea rax, [rip + mft_force_fail]
    cmp QWORD PTR [rax], 0
    je mft_noerr
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_mft]
    mov r8, E_MFT_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    call arena_free
    mov eax, 1
    jmp main_epilogue0
mft_noerr:
    // --count: solo el número a stdout
    cmp QWORD PTR [rsp+96], 0
    je stats_now
    lea rax, [rip + g_matches]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rdi, [rsp+216]
    mov r15, rdi
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    mov BYTE PTR [rdi], 0x0A
    inc rdi
    mov rcx, QWORD PTR [rsp+160]
    mov rdx, r15
    mov r8, rdi
    sub r8, r15
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
stats_now:
    // "[seek] archivos=.. coincidencias=.. tiempo=..ms arena=..KB discos=.. excl=..[ trunc] \n"
    lea rdi, [rsp+216]
    mov r15, rdi
    lea rsi, [rip + s_arch]
    mov rcx, S_ARCH_LEN
    rep movsb
    lea rax, [rip + g_files]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_match]
    mov rcx, S_MATCH_LEN
    rep movsb
    lea rax, [rip + g_matches]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_time]
    mov rcx, S_TIME_LEN
    rep movsb
    mov rcx, QWORD PTR [rsp+144]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_ms]
    mov rcx, S_MS_LEN
    rep movsb
    call scan_arena_used
    shr rax, 10
    mov rcx, rax
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_kb]
    mov rcx, S_KB_LEN
    rep movsb
    lea rax, [rip + scan_truncated]
    cmp QWORD PTR [rax], 0
    je stats_disk
    lea rsi, [rip + s_trunc]
    mov rcx, S_TRUNC_LEN
    rep movsb
stats_disk:
    lea rsi, [rip + s_disk]
    mov rcx, S_DISK_LEN
    rep movsb
    lea rax, [rip + g_disks]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_excl]
    mov rcx, S_EXCL_LEN
    rep movsb
    lea rax, [rip + g_excluded]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rax, [rip + mft_used]
    cmp QWORD PTR [rax], 0
    jne stats_mfts
    lea rsi, [rip + s_mftf]
    mov rcx, S_MFT_LEN
    rep movsb
    jmp stats_filt
stats_mfts:
    lea rsi, [rip + s_mfts]
    mov rcx, S_MFT_LEN
    rep movsb
stats_filt:
    lea rax, [rip + mft_lasterr]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz stats_filt2
    push rcx
    lea rsi, [rip + s_mfterr]
    mov rcx, S_MFTERR_LEN
    rep movsb
    pop rcx
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
stats_filt2:
    lea rax, [rip + mft_stage]
    mov rcx, QWORD PTR [rax]
    test rcx, rcx
    jz stats_filt3
    push rcx
    lea rsi, [rip + s_mftst]
    mov rcx, S_MFTST_LEN
    rep movsb
    pop rcx
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
stats_filt3:
    lea rsi, [rip + s_filtro]
    mov rcx, S_FILT_LEN
    rep movsb
    lea rax, [rip + scan_filter_ms]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rsp+208]
    call u64dec
    mov rsi, rax
    lea rcx, [rsp+208]
    sub rcx, rsi
    rep movsb
    lea rsi, [rip + s_filtms]
    mov rcx, S_FILTMS_LEN
    rep movsb
stats_nl:
    lea rsi, [rip + s_nl]
    mov rcx, S_NL_LEN
    rep movsb
    mov rcx, QWORD PTR [rsp+168]
    mov rdx, r15
    mov r8, rdi
    sub r8, r15
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    call arena_free
    xor eax, eax
main_epilogue0:
    add rsp, 544
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// streq: RCX=str, RDX=lit, R8=len -> EAX 1 si iguales (y str termina ahí).
streq:
    mov r9, rcx
    mov r10, rdx
    mov r11, r8
streq_loop:
    test r11, r11
    jz streq_tail
    movzx eax, BYTE PTR [r9]
    movzx edx, BYTE PTR [r10]
    cmp eax, edx
    jne streq_no
    inc r9
    inc r10
    dec r11
    jmp streq_loop
streq_tail:
    cmp BYTE PTR [r9], 0
    jne streq_no
    mov eax, 1
    ret
streq_no:
    xor eax, eax
    ret

// u64dec: RCX=valor, RDX=fin(buf 32B) -> RAX=inicio de dígitos.
u64dec:
    mov r8, rdx
    mov rax, rcx
    mov r9, r8
    mov r10, 10
    test rax, rax
    jnz u64_loop
    dec r9
    mov BYTE PTR [r9], 0x30
    mov rax, r9
    ret
u64_loop:
    xor edx, edx
    div r10
    add edx, 0x30
    dec r9
    mov BYTE PTR [r9], dl
    test rax, rax
    jnz u64_loop
    mov rax, r9
    ret

// utf8_to_wide: RCX=cstr -> RAX=ptr WCHAR, RDX=len (sin NUL). 0 si falla.
// Intenta UTF-8 estricto, reintenta con ACP.
utf8_to_wide:
    sub rsp, 72
    mov QWORD PTR [rsp+48], rcx
    mov ecx, 65001
    mov edx, 8
    mov r8, QWORD PTR [rsp+48]
    mov r9d, -1
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call MultiByteToWideChar
    test eax, eax
    jnz wide_have_len
    mov ecx, 0
    xor edx, edx
    mov r8, QWORD PTR [rsp+48]
    mov r9d, -1
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call MultiByteToWideChar
    test eax, eax
    jz wide_fail
wide_have_len:
    mov QWORD PTR [rsp+64], rax
    mov ecx, eax
    add ecx, ecx
    call arena_alloc
    test rax, rax
    jz wide_fail
    mov QWORD PTR [rsp+56], rax
    mov ecx, 65001
    mov edx, 8
    mov r8, QWORD PTR [rsp+48]
    mov r9d, -1
    mov r10, QWORD PTR [rsp+56]
    mov QWORD PTR [rsp+32], r10
    mov rax, QWORD PTR [rsp+64]
    mov QWORD PTR [rsp+40], rax
    call MultiByteToWideChar
    test eax, eax
    jnz wide_ok
    mov ecx, 0
    xor edx, edx
    mov r8, QWORD PTR [rsp+48]
    mov r9d, -1
    mov r10, QWORD PTR [rsp+56]
    mov QWORD PTR [rsp+32], r10
    mov rax, QWORD PTR [rsp+64]
    mov QWORD PTR [rsp+40], rax
    call MultiByteToWideChar
    test eax, eax
    jz wide_fail
wide_ok:
    mov rax, QWORD PTR [rsp+56]
    mov rdx, QWORD PTR [rsp+64]
    dec rdx
    add rsp, 72
    ret
wide_fail:
    xor eax, eax
    add rsp, 72
    ret

// cli_trim_query(RCX=ptr WCHAR, RDX=len) -> RAX=ptr, RDX=len sin blancos
// (0x20, 0x09) en extremos. Leaf sin stack.
cli_trim_query:
    test rdx, rdx
    jz ctq_ret
ctq_lead:
    test rdx, rdx
    jz ctq_ret
    movzx eax, WORD PTR [rcx]
    cmp eax, 0x20
    je ctq_adv
    cmp eax, 0x09
    jne ctq_trail
ctq_adv:
    add rcx, 2
    dec rdx
    jmp ctq_lead
ctq_trail:
    test rdx, rdx
    jz ctq_ret
    mov rax, rdx
    dec rax
    movzx eax, WORD PTR [rcx+rax*2]
    cmp eax, 0x20
    je ctq_unw
    cmp eax, 0x09
    jne ctq_ret
ctq_unw:
    dec rdx
    jmp ctq_trail
ctq_ret:
    mov rax, rcx
    ret

do_help:
    mov rcx, QWORD PTR [rsp+160]
    lea rdx, [rip + u_text]
    mov r8, U_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    xor eax, eax
    jmp main_epilogue0
no_pattern:
    mov rcx, QWORD PTR [rsp+160]
    lea rdx, [rip + u_text]
    mov r8, U_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
unknown_opt:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_opt]
    mov r8, E_OPT_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
too_many:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_many]
    mov r8, E_MANY_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_arena:
err_arena2:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_arena]
    mov r8, E_ARENA_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_conv:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_conv]
    mov r8, E_CONV_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_long:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_long]
    mov r8, E_LONG_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_rootlong:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_rootlong]
    mov r8, E_ROOTLONG_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_cwd:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_cwd]
    mov r8, E_CWD_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_exclval:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_exclval]
    mov r8, E_EXCLVAL_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_exclmany:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_exclmany]
    mov r8, E_EXCLMANY_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0
err_excllong:
    mov rcx, QWORD PTR [rsp+168]
    lea rdx, [rip + e_excllong]
    mov r8, E_EXCLLONG_LEN
    lea r9, [rsp+64]
    mov QWORD PTR [rsp+32], 0
    call WriteFile
    mov eax, 1
    jmp main_epilogue0

.data
lit_count: .ascii "count"
lit_help: .ascii "help"
lit_exclude: .ascii "exclude"
lit_noexcl: .ascii "no-excludes"
lit_all: .ascii "all"
lit_incwin: .ascii "include-windows"
lit_incnm: .ascii "include-nodemodules"
lit_incsys: .ascii "include-sys"
lit_inccache: .ascii "include-cache"
lit_inctemp: .ascii "include-temp"
lit_topdirs: .ascii "topdirs"
lit_mft: .ascii "mft"
lit_nomft: .ascii "no-mft"
lit_idxdbg: .ascii "idxdbg"
s_arch: .ascii "[seek] archivos="
s_arch_end:
s_match: .ascii " coincidencias="
s_match_end:
s_time: .ascii " tiempo="
s_time_end:
s_ms: .ascii "ms arena="
s_ms_end:
s_kb: .ascii "KB"
s_kb_end:
s_trunc: .ascii " trunc=arena-llena"
s_trunc_end:
s_disk: .ascii " discos="
s_disk_end:
s_excl: .ascii " excl="
s_excl_end:
s_mfts: .ascii " mft=S"
s_mfts_end:
s_mftf: .ascii " mft=F"
s_mftf_end:
s_mfterr: .ascii " mfterr="
s_mfterr_end:
s_mftst: .ascii " mftst="
s_mftst_end:
s_filtro: .ascii " filtro="
s_filtro_end:
s_filtms: .ascii "ms"
s_filtms_end:
s_nl: .ascii "\n"
s_nl_end:
u_text: .ascii "uso: seek <patron> [ruta] [--count] [--exclude <txt>]... [--no-excludes] [--include-windows] [--include-nodemodules] [--include-sys] [--include-cache] [--include-temp] [--topdirs] [--mft]\nBusca por subcadena (sin distinguir mayusculas) en nombres de archivo. * =cualquier secuencia, ? =un caracter.\n  --count   solo imprime el conteo\n  sin ruta  escanea todos los discos locales\n  --exclude <txt>  excluye rutas con txt (repetible, max 16)\n  --no-excludes  desactiva exclusiones por defecto\n  --include-windows  no excluye Windows\n  --include-nodemodules  no excluye node_modules\n  --include-sys  no excluye sistema (pagefile, Recovery, etc.)\n  --include-cache  no excluye caches (Cache, Code Cache, etc.)\n  --include-temp  no excluye Temp (Windows Temp, AppData Local Temp)\n  --topdirs  lista los 20 dirs con mas entradas (a stderr)\n  MFT directo: activo por defecto (busca en el indice NTFS; pide admin)\n  --mft  fuerza MFT: error si no abre (solo raiz de unidad NTFS)\n  --no-mft  usa Find (sin MFT)\n"
u_text_end:
e_opt: .ascii "seek: opcion desconocida (usa --help)\n"
e_opt_end:
e_many: .ascii "seek: demasiados argumentos (usa --help)\n"
e_many_end:
e_arena: .ascii "seek: sin memoria (arena 64MB)\n"
e_arena_end:
e_conv: .ascii "seek: no se pudo convertir el argumento a Unicode\n"
e_conv_end:
e_long: .ascii "seek: patron demasiado largo (max 1024)\n"
e_long_end:
e_rootlong: .ascii "seek: ruta demasiado larga\n"
e_rootlong_end:
e_cwd: .ascii "seek: no se pudo leer el directorio actual\n"
e_cwd_end:
e_exclval: .ascii "seek: --exclude necesita un valor\n"
e_exclval_end:
e_exclmany: .ascii "seek: demasiadas exclusiones (max 16)\n"
e_exclmany_end:
e_excllong: .ascii "seek: exclusion demasiado larga (max 128)\n"
e_excllong_end:
e_mft: .ascii "seek: --mft requiere admin y raiz de unidad NTFS\n"
e_mft_end:
