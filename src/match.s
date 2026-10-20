// seek-asm: match.s — minúsculas y substring case-insensitive (WCHAR).
// Solo ASCII A-Z se pliega; el resto pasa intacto (pass-through).
// contains_ci: outer escalar por posición; inner en chunks de 8 WCHAR con
// SSE2 (movdqu/pcmpgtw/pandn/paddw/pcmpeqw/pmovmskb) + cola escalar.
// El plegado vectorial es el mismo (A-Z -> +0x20); semántica idéntica.
// Leaf: sin llamadas, solo registros volátiles + XMM0-XMM3.
// Constantes de 16B alineadas en .data (cA1/cZ/cAdd).

.intel_syntax noprefix
.text
.globl lowercase_query
.globl contains_ci
.globl contains_ci_a
.globl prefilter_firstbyte
.globl glob_match_ci
.globl glob_match_ci_a
.globl glob_has_wild

// lowercase_query: RCX = ptr WCHAR, RDX = len (WCHARs). In-place.
lowercase_query:
    test rdx, rdx
    jz lq_done
lq_loop:
    movzx eax, WORD PTR [rcx]
    cmp eax, 0x41
    jb lq_next
    cmp eax, 0x5A
    ja lq_next
    add eax, 0x20
    mov WORD PTR [rcx], ax
lq_next:
    add rcx, 2
    dec rdx
    jnz lq_loop
lq_done:
    ret

// contains_ci: RCX = hay ptr, RDX = haylen, R8 = needle ptr, R9 = needlelen.
// Retorna RAX = 1 si needle está contenido, 0 si no.
// El needle ya viene en minúsculas; el haystack se pliega al vuelo.
contains_ci:
    test r9, r9
    jz ci_hit
    cmp rdx, r9
    jb ci_miss
    // R10 = puntero fin (última posición inicial válida)
    mov r10, rdx
    sub r10, r9
    shl r10, 1
    add r10, rcx
    // RCX = posición actual
ci_outer:
    cmp rcx, r10
    ja ci_miss
    xor r11d, r11d
    // RAX = fin del tramo vectorial (nlen redondeado a múltiplo de 8)
    mov rax, r9
    and rax, -8
ci_inner:
    cmp r11, rax
    jae ci_tail
    // chunk de 8 WCHAR: pliega haystack y compara todo junto
    movdqu xmm0, XMMWORD PTR [rcx + r11*2]
    movdqu xmm1, XMMWORD PTR [r8 + r11*2]
    movdqa xmm2, xmm0
    pcmpgtw xmm2, XMMWORD PTR [rip + cA1]
    movdqa xmm3, xmm0
    pcmpgtw xmm3, XMMWORD PTR [rip + cZ]
    pandn xmm3, xmm2
    pand xmm3, XMMWORD PTR [rip + cAdd]
    paddw xmm0, xmm3
    pcmpeqw xmm0, xmm1
    pmovmskb edx, xmm0
    cmp edx, 0xFFFF
    jne ci_nextpos
    add r11, 8
    jmp ci_inner
ci_tail:
    cmp r11, r9
    jae ci_hit
    movzx eax, WORD PTR [rcx + r11*2]
    cmp eax, 0x41
    jb ci_nofold
    cmp eax, 0x5A
    ja ci_nofold
    add eax, 0x20
ci_nofold:
    // RDX (haylen) ya no se usa: lo reciclo como char del needle
    movzx edx, WORD PTR [r8 + r11*2]
    cmp eax, edx
    jne ci_nextpos
    inc r11
    jmp ci_tail
ci_nextpos:
    add rcx, 2
    jmp ci_outer
ci_hit:
    mov eax, 1
    ret
ci_miss:
    xor eax, eax
    ret

// contains_ci_a: RCX = hay ptr (bytes UTF-8), RDX = haylen, R8 = needle,
// R9 = needlelen. Retorna EAX = 1 si contenido, 0 si no.
// Misma semántica ASCII que contains_ci (A-Z se pliega; UTF-8 multibyte
// pasa intacto y la auto-sincronía preserva el matching). Escalar. Leaf.
contains_ci_a:
    test r9, r9
    jz cia_hit
    cmp rdx, r9
    jb cia_miss
    mov r10, rdx
    sub r10, r9
    add r10, rcx
cia_outer:
    cmp rcx, r10
    ja cia_miss
    xor r11d, r11d
cia_inner:
    cmp r11, r9
    jae cia_hit
    movzx eax, BYTE PTR [rcx + r11]
    cmp eax, 0x41
    jb cia_nofold
    cmp eax, 0x5A
    ja cia_nofold
    add eax, 0x20
cia_nofold:
    movzx edx, BYTE PTR [r8 + r11]
    cmp eax, edx
    jne cia_next
    inc r11
    jmp cia_inner
cia_next:
    inc rcx
    jmp cia_outer
cia_hit:
    mov eax, 1
    ret
cia_miss:
    xor eax, eax
    ret

// prefilter_firstbyte: RCX=hay bytes, RDX=haylen, R8D=byte lo, R9D=byte hi.
// EAX=1 si hay algun byte == lo o == hi. Para fold ASCII: el patron ya viene
// en minusculas (lo) y hi es su mayuscula (o igual si no es a-z).
// Descarta rapido nombres sin el primer byte del query antes del
// contains_ci/glob completo. Con comodin lider ('*'/'?') NO se usa (el primer
// byte no es literal). SSE2 16B/chunk (pcmpeqb+por+pmovmskb) + cola escalar.
// Leaf: preserva R10 (el llamante lo usa como name_ptr). Clobbera RAX/R11/XMM0-3.
prefilter_firstbyte:
    test rdx, rdx
    jz pf_no
    and r8d, 0xFF
    imul r8d, r8d, 0x01010101
    movd xmm2, r8d
    pshufd xmm2, xmm2, 0
    and r9d, 0xFF
    imul r9d, r9d, 0x01010101
    movd xmm3, r9d
    pshufd xmm3, xmm3, 0
    mov rax, rcx
    mov r11, rdx
pf_loop:
    cmp r11, 16
    jb pf_tail
    movdqu xmm0, XMMWORD PTR [rax]
    movdqa xmm1, xmm0
    pcmpeqb xmm0, xmm2
    pcmpeqb xmm1, xmm3
    por xmm0, xmm1
    pmovmskb ecx, xmm0
    test ecx, ecx
    jnz pf_yes
    add rax, 16
    sub r11, 16
    jmp pf_loop
pf_tail:
    test r11, r11
    jz pf_no
pf_tloop:
    movzx ecx, BYTE PTR [rax]
    cmp cl, r8b
    je pf_yes
    cmp cl, r9b
    je pf_yes
    inc rax
    dec r11
    jnz pf_tloop
pf_no:
    xor eax, eax
    ret
pf_yes:
    mov eax, 1
    ret

// glob_has_wild: RCX=ptr WCHAR, RDX=len -> EAX 1 si hay '*'/'?', 0 si no.
// Leaf: solo RAX/R10 (volatiles).
glob_has_wild:
    test rdx, rdx
    jz ghw_no
    xor r10d, r10d
ghw_loop:
    cmp r10, rdx
    jae ghw_no
    movzx eax, WORD PTR [rcx + r10*2]
    cmp eax, 0x2A
    je ghw_yes
    cmp eax, 0x3F
    je ghw_yes
    inc r10
    jmp ghw_loop
ghw_yes:
    mov eax, 1
    ret
ghw_no:
    xor eax, eax
    ret

// glob_match_ci: RCX=hay WCHAR*, RDX=haylen, R8=pat WCHAR*, R9=patlen.
// Full-match: '*'=cualquier secuencia (incl vacia), '?'=exactamente un WCHAR.
// Case-insensitive ASCII (pat ya minusculas, hay se pliega). Leaf.
// Frame 32: [rsp]=star_pi(-1), [rsp+8]=star_hi, [rsp+16]=haylen, [rsp+24]=patlen.
// R10=hi, R11=pi. RAX/RDX temps (lens recargados de pila cada vuelta).
glob_match_ci:
    test r9, r9
    jz gm_hit0
    sub rsp, 32
    mov QWORD PTR [rsp+16], rdx
    mov QWORD PTR [rsp+24], r9
    mov QWORD PTR [rsp], -1
    mov QWORD PTR [rsp+8], 0
    xor r10d, r10d
    xor r11d, r11d
gm_loop:
    mov rdx, QWORD PTR [rsp+16]
    cmp r10, rdx
    jae gm_tail
    mov rax, QWORD PTR [rsp+24]
    cmp r11, rax
    jae gm_bt
    movzx eax, WORD PTR [r8 + r11*2]
    cmp eax, 0x2A
    jne gm_q
    mov QWORD PTR [rsp], r11
    mov QWORD PTR [rsp+8], r10
    inc r11
    jmp gm_loop
gm_q:
    cmp eax, 0x3F
    je gm_cons
    movzx edx, WORD PTR [rcx + r10*2]
    cmp edx, 0x41
    jb gm_cmp
    cmp edx, 0x5A
    ja gm_cmp
    add edx, 0x20
gm_cmp:
    cmp edx, eax
    jne gm_bt
gm_cons:
    inc r10
    inc r11
    jmp gm_loop
gm_bt:
    mov rax, QWORD PTR [rsp]
    cmp rax, -1
    je gm_miss
    mov rdx, QWORD PTR [rsp+8]
    inc rdx
    mov QWORD PTR [rsp+8], rdx
    mov rax, QWORD PTR [rsp+16]
    cmp rdx, rax
    ja gm_miss
    mov r10, rdx
    mov rax, QWORD PTR [rsp]
    inc rax
    mov r11, rax
    jmp gm_loop
gm_tail:
    mov rax, QWORD PTR [rsp+24]
gm_tail_l:
    cmp r11, rax
    jae gm_hit
    movzx edx, WORD PTR [r8 + r11*2]
    cmp edx, 0x2A
    jne gm_miss
    inc r11
    jmp gm_tail_l
gm_hit:
    mov eax, 1
    add rsp, 32
    ret
gm_miss:
    xor eax, eax
    add rsp, 32
    ret
gm_hit0:
    mov eax, 1
    ret

// glob_match_ci_a: RCX=hay bytes*, RDX=haylen, R8=pat bytes*, R9=patlen.
// Igual que glob_match_ci pero en bytes UTF-8 ('?'=exactamente un byte;
// en ASCII equivale a un WCHAR). Leaf, mismo frame que la WCHAR.
glob_match_ci_a:
    test r9, r9
    jz gma_hit0
    sub rsp, 32
    mov QWORD PTR [rsp+16], rdx
    mov QWORD PTR [rsp+24], r9
    mov QWORD PTR [rsp], -1
    mov QWORD PTR [rsp+8], 0
    xor r10d, r10d
    xor r11d, r11d
gma_loop:
    mov rdx, QWORD PTR [rsp+16]
    cmp r10, rdx
    jae gma_tail
    mov rax, QWORD PTR [rsp+24]
    cmp r11, rax
    jae gma_bt
    movzx eax, BYTE PTR [r8 + r11]
    cmp eax, 0x2A
    jne gma_q
    mov QWORD PTR [rsp], r11
    mov QWORD PTR [rsp+8], r10
    inc r11
    jmp gma_loop
gma_q:
    cmp eax, 0x3F
    je gma_cons
    movzx edx, BYTE PTR [rcx + r10]
    cmp edx, 0x41
    jb gma_cmp
    cmp edx, 0x5A
    ja gma_cmp
    add edx, 0x20
gma_cmp:
    cmp edx, eax
    jne gma_bt
gma_cons:
    inc r10
    inc r11
    jmp gma_loop
gma_bt:
    mov rax, QWORD PTR [rsp]
    cmp rax, -1
    je gma_miss
    mov rdx, QWORD PTR [rsp+8]
    inc rdx
    mov QWORD PTR [rsp+8], rdx
    mov rax, QWORD PTR [rsp+16]
    cmp rdx, rax
    ja gma_miss
    mov r10, rdx
    mov rax, QWORD PTR [rsp]
    inc rax
    mov r11, rax
    jmp gma_loop
gma_tail:
    mov rax, QWORD PTR [rsp+24]
gma_tail_l:
    cmp r11, rax
    jae gma_hit
    movzx edx, BYTE PTR [r8 + r11]
    cmp edx, 0x2A
    jne gma_miss
    inc r11
    jmp gma_tail_l
gma_hit:
    mov eax, 1
    add rsp, 32
    ret
gma_miss:
    xor eax, eax
    add rsp, 32
    ret
gma_hit0:
    mov eax, 1
    ret

.data
.p2align 4
cA1: .short 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40
cZ: .short 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A, 0x5A
cAdd: .short 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20
