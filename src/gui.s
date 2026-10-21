// seek-gui: GUI Win32 100% ASM (GAS x86-64, .intel_syntax noprefix).
// Ventana: Edit busqueda + ListView report VIRTUAL (LVS_OWNERDATA|LVS_REPORT)
// + StatusBar (archivos/coincidencias/ms/arena/discos). Thread worker con motor
// propio (duplicado minimo): mismo matching (contains_ci sobre el nombre,
// case-insensitive ASCII, Unicode intacto) y mismas exclusiones
// (path_is_excluded de scan.s). Streaming: no-match no se guarda.
// Display cap 100K items, motor completo, total aparte. Sin debounce: busca en
// cada tecla (índice parcial si aún indexa; gw_done refiltra al terminar) y
// cancela scan previo (gen + WaitForSingleObject al worker anterior).
// Click derecho: menu EXACTO del Shell via COM:
//   SHParseDisplayName(path sin \\?\) -> SHBindToParent ->
//   IShellFolder::GetUIObjectOf(IID_IContextMenu) ->
//   IContextMenu::QueryContextMenu + TrackPopupMenuEx(TPM_RETURNCMD) ->
//   IContextMenu::InvokeCommand.
// WM_INITMENUPOPUP/WM_DRAWITEM/WM_MEASUREITEM se reenvian a IContextMenu2/3.
// Multi-seleccion: un solo GetUIObjectOf si mismo padre (comparacion ordinal
// del dir; los paths vienen de la misma enumeracion). Padres mixtos:
// menu del primer item (documentado). Doble-click/Enter: LVN_ITEMACTIVATE
// -> ShellExecuteW(open).
// GUIDs: IContextMenu {000214e4-...}, IContextMenu2 {000214f4-...},
// IContextMenu3 {000214f5-...}, IShellFolder {000214e6-...}.
// CoInitializeEx(COINIT_APARTMENTTHREADED) en UI thread.
// NOTA GAS: todo .equ numerico va ANTES del primer uso.

.intel_syntax noprefix
.text
.globl WinMain

.equ WS_OVERLAPPEDWINDOW, 0xCF0000
.equ WS_CLIPCHILDREN, 0x2000000
.equ WS_CHILD, 0x40000000
.equ WS_VISIBLE, 0x10000000
.equ WS_BORDER, 0x800000
.equ WS_CLIPSIBLINGS, 0x4000000
.equ WS_EX_CLIENTEDGE, 0x200
.equ ES_AUTOHSCROLL, 0x80
.equ LVS_REPORT, 0x1
.equ LVS_OWNERDATA, 0x1000
.equ LVS_SHOWSELALWAYS, 0x8
.equ LVS_EX_FULLROWSELECT, 0x20
.equ LVS_EX_DOUBLEBUFFER, 0x10000
.equ IDC_SEARCH, 101
.equ IDC_LIST, 102
.equ IDC_STATUS, 103
.equ TIMER_SEARCH, 1
.equ TIMER_HIDE, 2
.equ HIDE_MS, 500
.equ WM_CREATE, 1
.equ WM_DESTROY, 2
.equ WM_SIZE, 5
.equ WM_COMMAND, 0x111
.equ WM_NOTIFY, 0x4E
.equ WM_TIMER, 0x113
.equ WM_CONTEXTMENU, 0x7B
.equ WM_DRAWITEM, 0x2B
.equ WM_MEASUREITEM, 0x2C
.equ WM_INITMENUPOPUP, 0x117
.equ WM_APP, 0x8000
.equ EN_CHANGE, 0x300
.equ LVM_SETITEMCOUNT, 0x102F
.equ LVM_GETNEXTITEM, 0x100C
.equ LVM_INSERTCOLUMNW, 0x1061
.equ LVM_SETEXTENDEDLISTVIEWSTYLE, 0x1036
.equ LVNI_SELECTED, 0x2
.equ LVCF_ALL, 0xF
.equ SB_SETPARTS, 0x404
.equ SB_SETTEXTW, 0x40B
.equ EM_SETCUEBANNER, 0x1501
.equ TPM_RETURNCMD, 0x100
.equ TPM_RIGHTBUTTON, 0x2
.equ SW_SHOWNORMAL, 1
.equ COINIT_APT, 0x2
.equ GUI_MAXDISPLAY, 100000
.equ GUI_STACKMAX, 65536
.equ GUI_SELCAP, 256
.equ GUI_QUERYMAX, 1024
.equ GUI_APP_DONE, 0x8001
.equ GUI_APP_PROG, 0x8002
.equ LVN_GETDISPINFO, -177
.equ LVN_COLUMNCLICK, -108
.equ LVN_ITEMACTIVATE, -114
// PILDORA flotante 700x35 centrada arriba (y=8), movible, bordes redondeados.
// BAR_ALPHA fijo
// 184/255 (~0.72, mismo fondo rgba(20,24,38,0.72) de la maqueta).
// Futuro flag: --alpha N (0-255) para ajustar sin recompilar.
.equ BAR_ALPHA, 184
.equ BAR_W, 700
.equ BAR_H, 40
.equ BAR_Y, 8
// BAR_R = elipse 36x36 = radio 18 (CreateRoundRectRgn usa diametros, no radio)
.equ BAR_R, 36
.equ BAR_PANEL_H, 320
.equ WS_POPUP, 0x80000000
.equ WS_EX_TOPMOST, 0x8
.equ WS_EX_LAYERED, 0x80000
.equ WS_EX_TOOLWINDOW, 0x80
.equ WS_EX_BAR, 0x80080
.equ LWA_ALPHA, 2
.equ SM_CXSCREEN, 0
.equ SM_CYSCREEN, 1
.equ WM_MOVE, 3
.equ WM_NCHITTEST, 0x84
.equ HTCAPTION, 2
.equ WM_EXITSIZEMOVE, 0x232
.equ SW_HIDE, 0
.equ SW_SHOW, 5
.equ SW_SHOWNA, 4
.equ MOD_ALT, 0x1
.equ VK_SPACE, 0x20
.equ VK_ESCAPE, 0x1B
.equ WM_HOTKEY, 0x312
.equ WM_ACTIVATE, 0x6
.equ WA_INACTIVE, 0
.equ WM_KEYDOWN, 0x100
.equ WM_CTLCOLOREDIT, 0x133
.equ WM_CTLCOLORSTATIC, 0x138
.equ BN_CLICKED, 0
.equ EN_SETFOCUS, 0x100
.equ EN_KILLFOCUS, 0x200
.equ IDC_LOGO, 104
.equ IDC_HINT, 105
.equ IDC_PIN, 106
.equ IDC_MODE, 107
.equ IDC_EMPTY, 108
// tick incremental: u64 mtime por record + trigger cada REPAIR_MS
.equ WS_MTIME_BASE, 96
.equ WS_REC, 80
.equ WS_R_BASE, 32
.equ WS_R_END, 48
// intervalo minimo entre ticks incrementales (30 s): lo dispara el timer
// de 500 ms (automatico) y el summon del hotkey
.equ REPAIR_MS, 30000
// Barrido por franjas: el tick completo de ~300K dirs cuesta ~6 s de CPU.
// En vez de un pico de 6 s cada 30 s, se hace una franja por vez (presupuesto
// TICK_BUDGET_MS=500 ms, en el codigo Rust de skc_dir_tick) y se sigue
// desde el cursor. Consecuencia: archivo nuevo visible en ~1-2 min.
.equ REPAIR_SLICE_MS, 10000
.equ TICK_NCH, 1024
.equ HOTKEY_ID, 1
.equ LVM_SETBKCOLOR, 0x1001
.equ LVM_SETTEXTCOLOR, 0x1024
.equ LVM_SETTEXTBKCOLOR, 0x1026
.equ EM_SETSEL, 0xB1
.equ SWP_NOMOVE, 0x2
.equ SWP_NOSIZE, 0x1
.equ SWP_NOZORDER, 0x4
.equ SWP_NOACTIVATE, 0x10
.equ VK_F5, 0x75
.equ IDI_ICON1, 101
.equ HKEY_CURRENT_USER, 0xFFFFFFFF80000001
.equ REG_SZ, 1
.equ REG_DWORD, 4
.equ KEY_WRITE, 0x20006
.equ KEY_READ, 0x20019
.equ KEY_SETVAL, 0x2
.equ MB_ICONINFO, 0x40
.equ MB_ICONERR, 0x10
.equ ERR_FILENOTFOUND, 2
// BUG1 nav teclado (flechas en Edit + WM_KEYDOWN barra)
.equ VK_UP, 0x26
.equ VK_DOWN, 0x28
.equ VK_RETURN, 0x0D
.equ VK_PRIOR, 0x21
.equ VK_NEXT, 0x22
.equ VK_HOME, 0x24
.equ VK_END, 0x23
.equ GWLP_WNDPROC, -4
.equ LVM_GETITEMCOUNT, 0x1004
.equ LVM_GETCOUNTPERPAGE, 0x1028
.equ LVM_GETSELECTIONMARK, 0x1042
.equ LVM_SETSELECTIONMARK, 0x1043
.equ LVM_SETITEMSTATE, 0x102B
.equ LVM_GETITEMSTATE, 0x102C
.equ LVM_ENSUREVISIBLE, 0x1013
.equ LVIS_FOCUSED, 0x1
.equ LVIS_SELECTED, 0x2
.equ LVIF_STATE, 0x8
.equ LVIF_IMAGE, 0x2
// BUG2 iconos sistema (ImageList + iImage por extension)
.equ LVM_SETIMAGELIST, 0x1003
.equ LVM_GETIMAGELIST, 0x1002
.equ LVSIL_SMALL, 0x1
.equ SHGFI_SMALLICON, 0x1
.equ SHGFI_USEFILEATTRIBUTES, 0x10
.equ SHGFI_SYSICONINDEX, 0x4000
.equ FILE_ATTR_NORM, 0x80
.equ FILE_ATTR_DIR, 0x10
.equ WS_A_BASE, 0
.equ WS_A_BRK, 8
// Estetica moderna (solo GUI, sin tocar el motor).
.equ NM_CUSTOMDRAW, -12
.equ CDDS_PREPAINT, 1
.equ CDDS_ITEMPREPAINT, 0x10001
.equ CDRF_NOTIFYITEMDRAW, 0x20
.equ CDRF_NEWFONT, 2
.equ CDIS_SELECTED, 1
.equ CDIS_HOT, 0x40
.equ EM_SETMARGINS, 0xD3
.equ EC_LEFTMARGIN, 1
.equ EC_RIGHTMARGIN, 2
.equ WM_CTLCOLORBTN, 0x135
.equ BS_FLAT, 0x8000
.equ WM_SETFONT, 0x30
.equ SB_SETBKCOLOR, 0x401
.equ WCA_ACCENT_POLICY, 19
.equ ACCENT_ACRYLIC, 4
.equ LOGPIXELSY, 88
.equ GWL_EXSTYLE, -20
.equ SWP_FRAMECHANGED, 0x20
// instancia unica (mutex con nombre)
.equ WM_CLOSE, 0x10
.equ ERROR_ALREADY_EXISTS, 183
.equ WAIT_ABANDONED, 0x80

// WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR cmd, int show).
// cmd (R8, ANSI) admite: --window (ventana vieja), --bar (explicito = default),
// --focus (robar foco al arrancar; por defecto NO). Default = bar fina.
// --install-startup / --uninstall-startup: autoarranque HKCU Run (valor seek
// = ruta entrecomillada del exe); muestran MessageBoxW y salen sin ventana.
WinMain:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264
    mov r15d, r9d
    mov QWORD PTR [rsp+248], r8
    lea rax, [rip + gui_hinst]
    mov QWORD PTR [rax], rcx
    // flags -> gui_mode (0=bar,1=window), gui_focus_req, gui_pinned=0, panel=0
    // (pin se restaura de HKCU\Software\seek en gui_load_barpos).
    mov rcx, QWORD PTR [rsp+248]
    call gui_parse_flags
    // autoarranque: atiende --install/--uninstall-startup y sale (sin ventana)
    mov rax, QWORD PTR [rip + gui_install_req]
    test rax, rax
    jnz gwmain_doinstall
    mov rax, QWORD PTR [rip + gui_uninstall_req]
    test rax, rax
    jnz gwmain_douninstall
    jmp gwmain_afterstartup
gwmain_doinstall:
    call gui_startup_install
    jmp gwmain_epilogue
gwmain_douninstall:
    call gui_startup_uninstall
    jmp gwmain_epilogue
gwmain_afterstartup:
    // instancia unica: mutex con nombre. La primera instancia lo crea con
    // ownership; si ya existe, esta instancia nueva le manda WM_CLOSE a la
    // vieja (EnumWindows + GetClassNameW: FindWindowW no ve clases privadas
    // cross-process) y espera a que muera (libera el mutex) antes de seguir.
    // CreateMutexW: rcx=lpAttr, edx=bInitialOwner, r8=lpName
    xor ecx, ecx
    mov edx, 1
    lea r8, [rip + gui_mtxname]
    call CreateMutexW
    // sin mutex seguimos igual (no bloquear el arranque)
    test rax, rax
    jz gwmain_afterinstance
    mov rbx, rax
    lea rax, [rip + gui_hmutex]
    mov QWORD PTR [rax], rbx
    call GetLastError
    cmp eax, ERROR_ALREADY_EXISTS
    // primera instancia: seguimos ya
    jne gwmain_afterinstance
    // reintentos (tope ~4s: la vieja tarda hasta ~2s en salir por el
    // join del indexer)
    xor esi, esi
gwmain_killloop:
    lea rax, [rip + gui_enum_found]
    mov QWORD PTR [rax], 0
    // EnumWindows(lpEnumFunc=rcx, lParam=rdx)
    lea rcx, [rip + gui_enum_close]
    xor edx, edx
    call EnumWindows
    // si las ventanas viejas ya desaparecieron, seguimos ya: A esta en su
    // salida (hotkey y ventana ya liberados); no hace falta esperar a que
    // el proceso termine de unir sus threads
    lea rax, [rip + gui_enum_found]
    cmp QWORD PTR [rax], 0
    je gwmain_afterinstance
    // la vieja libera el mutex al morir (WM_CLOSE -> destroy -> quit)
    mov rcx, QWORD PTR [rip + gui_hmutex]
    mov edx, 500
    call WaitForSingleObject
    // WAIT_OBJECT_0: adquirida, ya somos la unica
    test eax, eax
    je gwmain_afterinstance
    // murio sin liberar (WAIT_ABANDONED): tambien adquirida
    cmp eax, WAIT_ABANDONED
    je gwmain_afterinstance
    inc esi
    cmp esi, 8
    jb gwmain_killloop
    // si no murio (patologico): seguimos igual; mejor dos que ninguna
gwmain_afterinstance:
    // arena (nombres resultados + dirs pila)
    call arena_init
    test eax, eax
    jz gwmain_noarena
    // COM STA en UI thread
    xor ecx, ecx
    mov edx, COINIT_APT
    call CoInitializeEx
    test eax, eax
    js gwmain_noarena
    // common controls: listview + statusbar
    lea rax, [rip + gui_icc]
    mov DWORD PTR [rax], 8
    mov DWORD PTR [rax+4], 5
    lea rcx, [rip + gui_icc]
    call InitCommonControlsEx
    // clase ventana
    xor ecx, ecx
    call GetModuleHandleW
    test rax, rax
    jz gwmain_fail
    mov rbx, rax
    xor ecx, ecx
    mov edx, 32512
    call LoadCursorW
    mov r12, rax
    // icono propio IDI_ICON1 (resource.res) para clase/titulo/taskbar
    mov rcx, rbx
    mov edx, IDI_ICON1
    call LoadIconW
    mov QWORD PTR [rsp+240], rax
    // brush oscuro de la maqueta RGB(20,24,38) para fondo bar
    mov ecx, 0x1E1E1E
    call CreateSolidBrush
    lea rcx, [rip + gui_brush]
    mov QWORD PTR [rcx], rax
    lea rcx, [rip + gui_wcx]
    mov DWORD PTR [rcx], 80
    // CS_DROPSHADOW|CS_VREDRAW|CS_HREDRAW: sombra nativa que sigue la region
    // de la pildora (solo funciona con la ventana sin WS_EX_LAYERED).
    mov DWORD PTR [rcx+4], 0x20003
    lea rdx, [rip + gui_wndproc]
    mov QWORD PTR [rcx+8], rdx
    mov DWORD PTR [rcx+16], 0
    mov DWORD PTR [rcx+20], 0
    mov QWORD PTR [rcx+24], rbx
    mov rax, QWORD PTR [rsp+240]
    mov QWORD PTR [rcx+32], rax
    mov QWORD PTR [rcx+40], r12
    mov rax, QWORD PTR [rip + gui_brush]
    test rax, rax
    jz gwmain_classdef
    mov QWORD PTR [rcx+48], rax
    jmp gwmain_classreg
gwmain_classdef:
    mov QWORD PTR [rcx+48], 6
gwmain_classreg:
    mov QWORD PTR [rcx+56], 0
    lea rdx, [rip + gui_cls_main]
    mov QWORD PTR [rcx+64], rdx
    mov rax, QWORD PTR [rsp+240]
    mov QWORD PTR [rcx+72], rax
    call RegisterClassExW
    test eax, eax
    jz gwmain_fail
    // rama bar vs window
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gwmain_mkwindow
    // PILDORA: 700x35, x=(SM_CXSCREEN-700)/2, y=8, ex=TOPMOST|LAYERED|TOOLWINDOW
    // posicion restaurada de HKCU\Software\seek si existe (clamp a primario)
    xor ecx, ecx
    call GetSystemMetrics
    test eax, eax
    jz gwmain_fail
    lea rcx, [rip + gui_screenw]
    mov QWORD PTR [rcx], rax
    mov ecx, SM_CYSCREEN
    call GetSystemMetrics
    lea rcx, [rip + gui_screenh]
    mov QWORD PTR [rcx], rax
    call gui_load_barpos
    mov ecx, WS_EX_TOOLWINDOW
    lea rdx, [rip + gui_cls_main]
    lea r8, [rip + gui_title_bar]
    mov r9d, 0x86000000
    mov rax, QWORD PTR [rip + gui_barx]
    mov QWORD PTR [rsp+32], rax
    mov rax, QWORD PTR [rip + gui_bary]
    mov QWORD PTR [rsp+40], rax
    mov QWORD PTR [rsp+48], BAR_W
    mov QWORD PTR [rsp+56], BAR_H
    mov QWORD PTR [rsp+64], 0
    mov QWORD PTR [rsp+72], 0
    mov QWORD PTR [rsp+80], rbx
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    test rax, rax
    jz gwmain_fail
    lea rcx, [rip + gui_hwnd]
    mov QWORD PTR [rcx], rax
    // region redondeada 700x40, elipse 36x36 = radio 18 (CreateRoundRectRgn
    // toma ancho/alto de elipse, no radio; convive con LAYERED)
    mov rcx, rax
    call gui_apply_rgn
    // acrilico: desactivado por AV historico (ver README). Reactivar = descomentar.
    // mov rcx, QWORD PTR [rip + gui_hwnd]
    // call gui_enable_acrylic
    // Pildora OPAKA (sin WS_EX_LAYERED): fondo maqueta + hijos con tema se
    // pintan al 100% y el texto es legible sobre cualquier escritorio. El
    // alfa BAR_ALPHA=184 componia toda la ventana al 71% encima del
    // escritorio: la lista salia ilegible (feedback 2026-10-09).
    // Acrilico fuera (B11): AV determinista ~4s en KERNELBASE con composicion
    // activa. gui_enable_acrylic quedo con el struct SWCA corregido (Data +8,
    // SizeOfData +16) para reactivarlo solo despues de aislar ese AV.
    // hotkey global Alt+Espacio
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, HOTKEY_ID
    mov r8d, MOD_ALT
    mov r9d, VK_SPACE
    call RegisterHotKey
    // si fallo (otra instancia tenia Alt+Space), el watchdog reintenta
    test eax, eax
    setnz al
    movzx eax, al
    mov QWORD PTR [rip + gui_hotkey_ok], rax
    // pin restaurado (opt-in TOPMOST): si pin==1, poner TOPMOST post-creacion
    mov rax, QWORD PTR [rip + gui_pinned]
    test rax, rax
    jz 1f
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov rdx, -1
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x13
    call SetWindowPos
1:
    // timer 500ms de auto-hide (solo bar; window lo ignora en el handler)
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, TIMER_HIDE
    mov r8d, HIDE_MS
    xor r9d, r9d
    call SetTimer
    // show sin robar foco salvo --focus
    mov rax, QWORD PTR [rip + gui_focus_req]
    test rax, rax
    jnz gwmain_barfocus
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, SW_SHOWNA
    call ShowWindow
    jmp gwmain_updated
gwmain_barfocus:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, SW_SHOWNORMAL
    call ShowWindow
    jmp gwmain_updated
gwmain_mkwindow:
    // ventana vieja (--window): ex=0, 920x620, titulo seek-gui
    xor ecx, ecx
    lea rdx, [rip + gui_cls_main]
    lea r8, [rip + gui_title]
    mov r9d, 0x2CF0000
    mov DWORD PTR [rsp+32], 0x80000000
    mov DWORD PTR [rsp+40], 0x80000000
    mov QWORD PTR [rsp+48], 920
    mov QWORD PTR [rsp+56], 620
    mov QWORD PTR [rsp+64], 0
    mov QWORD PTR [rsp+72], 0
    mov QWORD PTR [rsp+80], rbx
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    test rax, rax
    jz gwmain_fail
    lea rcx, [rip + gui_hwnd]
    mov QWORD PTR [rcx], rax
    mov rcx, rax
    mov edx, r15d
    call ShowWindow
gwmain_updated:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call UpdateWindow
    call gui_start_index
gwmain_loop:
    lea rcx, [rip + gui_msg]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call GetMessageW
    test eax, eax
    jz gwmain_exit
    // Esc global (caza teclas del Edit sin subclass): oculta panel + limpia
    lea rax, [rip + gui_msg]
    cmp DWORD PTR [rax+8], WM_KEYDOWN
    jne gwmain_dispatch
    cmp QWORD PTR [rax+16], VK_ESCAPE
    je gwmain_esc
    cmp QWORD PTR [rax+16], VK_F5
    jne gwmain_dispatch
    call gui_reindex
    jmp gwmain_loop
gwmain_esc:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_on_escape
    jmp gwmain_loop
gwmain_dispatch:
    lea rcx, [rip + gui_msg]
    call TranslateMessage
    lea rcx, [rip + gui_msg]
    call DispatchMessageW
    jmp gwmain_loop
gwmain_exit:
    // hotkey fuera + thread join
    mov rcx, QWORD PTR [rip + gui_hwnd]
    test rcx, rcx
    jz gwmain_nounreg
    mov edx, HOTKEY_ID
    call UnregisterHotKey
gwmain_nounreg:
    mov rcx, QWORD PTR [rip + gui_hthread]
    test rcx, rcx
    jz gwmain_nothread
    lea rax, [rip + gui_gen]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov edx, 2000
    call WaitForSingleObject
    mov rcx, QWORD PTR [rip + gui_hthread]
    call CloseHandle
gwmain_nothread:
    call gui_save_recents
    call CoUninitialize
    call arena_free
    xor eax, eax
    jmp gwmain_epilogue
gwmain_fail:
    mov eax, 1
    jmp gwmain_epilogue
gwmain_noarena:
    mov eax, 1
gwmain_epilogue:
    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_wndproc(HWND,UINT,WPARAM,LPARAM). Frame 8 pushes + sub 128.
gui_wndproc:
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
    mov DWORD PTR [rsp+72], edx
    mov QWORD PTR [rsp+80], r8
    mov QWORD PTR [rsp+88], r9
    mov eax, edx
    cmp eax, WM_CREATE
    je gw_create
    cmp eax, WM_SIZE
    je gw_size
    cmp eax, WM_COMMAND
    je gw_command
    cmp eax, WM_TIMER
    je gw_timer
    cmp eax, WM_NOTIFY
    je gw_notify
    cmp eax, WM_CONTEXTMENU
    je gw_ctxmenu
    cmp eax, WM_INITMENUPOPUP
    je gw_initmenu
    cmp eax, WM_DRAWITEM
    je gw_drawitem
    cmp eax, WM_MEASUREITEM
    je gw_measureitem
    cmp eax, GUI_APP_DONE
    je gw_done
    cmp eax, GUI_APP_PROG
    je gw_prog
    cmp eax, WM_HOTKEY
    je gw_hotkey
    cmp eax, WM_ACTIVATE
    je gw_activate
    cmp eax, WM_KEYDOWN
    je gw_keydown
    cmp eax, WM_CTLCOLOREDIT
    je gw_ctlcolor
    cmp eax, WM_CTLCOLORSTATIC
    je gw_ctlcolor
    cmp eax, WM_CTLCOLORBTN
    je gw_ctlcolor
    cmp eax, WM_NCHITTEST
    je gw_nchittest
    cmp eax, WM_EXITSIZEMOVE
    je gw_exitsize
    cmp eax, WM_DESTROY
    je gw_destroy
    jmp gw_def
gw_nchittest:
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gw_def
    mov eax, HTCAPTION
    jmp gw_ret
gw_exitsize:
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gw_zero
    mov rcx, QWORD PTR [rsp+64]
    call gui_save_barpos
    xor eax, eax
    jmp gw_ret
gw_create:
    mov rcx, QWORD PTR [rsp+64]
    call gui_build_children
    mov rcx, QWORD PTR [rsp+64]
    call gui_load_recents
    xor eax, eax
    jmp gw_ret
gw_size:
    mov rcx, QWORD PTR [rsp+64]
    call gui_layout
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gw_size_done
    mov rcx, QWORD PTR [rsp+64]
    call gui_apply_rgn
gw_size_done:
    xor eax, eax
    jmp gw_ret
gw_command:
    mov rax, QWORD PTR [rsp+80]
    movzx r10d, ax
    shr rax, 16
    and eax, 0xFFFF
    cmp r10d, IDC_PIN
    jne gw_cmd_mode
    cmp eax, BN_CLICKED
    jne gw_def
    mov rcx, QWORD PTR [rsp+64]
    call gui_toggle_pin
    xor eax, eax
    jmp gw_ret
gw_cmd_mode:
    // boton modo: cicla Todos->Archivos->Carpetas, guarda y refiltra
    cmp r10d, IDC_MODE
    jne gw_cmd_search
    cmp eax, BN_CLICKED
    jne gw_def
    mov eax, DWORD PTR [rip + gui_fmode]
    inc eax
    cmp eax, 2
    jbe gw_cm_ok
    xor eax, eax
gw_cm_ok:
    lea rdx, [rip + gui_fmode]
    mov DWORD PTR [rdx], eax
    call gui_mode_setglyph
    mov rcx, QWORD PTR [rsp+64]
    call gui_save_barpos
    mov rcx, QWORD PTR [rsp+64]
    call gui_start_search
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_panel
    xor eax, eax
    jmp gw_ret
gw_cmd_search:
    cmp r10d, IDC_SEARCH
    jne gw_def
    cmp eax, EN_CHANGE
    je gw_cmd_change
    cmp eax, EN_SETFOCUS
    je gw_cmd_focus
    jmp gw_def
gw_cmd_change:
    // debounce opcional: si gui_debounce>0, programa timer en vez de filtrar ya
    mov rax, QWORD PTR [rip + gui_debounce]
    test rax, rax
    jz gw_cc_now
    mov rcx, QWORD PTR [rsp+64]
    mov rdx, TIMER_SEARCH
    call KillTimer
    mov rcx, QWORD PTR [rsp+64]
    mov rdx, TIMER_SEARCH
    mov r8, QWORD PTR [rip + gui_debounce]
    xor r9d, r9d
    call SetTimer
    jmp gw_cc_refresh
gw_cc_now:
    mov rcx, QWORD PTR [rsp+64]
    call gui_start_search
gw_cc_refresh:
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_panel
    xor eax, eax
    jmp gw_ret
gw_cmd_focus:
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_panel
    xor eax, eax
    jmp gw_ret
gw_timer:
    mov rax, QWORD PTR [rsp+80]
    cmp rax, TIMER_HIDE
    je gw_timer_hide
    cmp rax, TIMER_SEARCH
    jne gw_def
    mov rcx, QWORD PTR [rsp+64]
    mov rdx, TIMER_SEARCH
    call KillTimer
    mov rcx, QWORD PTR [rsp+64]
    call gui_start_search
    xor eax, eax
    jmp gw_ret
gw_timer_hide:
    mov rcx, QWORD PTR [rsp+64]
    call gui_check_autohide
    // watchdog de instancia unica (500ms): cierra duplicados tardios
    call gui_single_watch
    // tick incremental automatico: cada 500 ms chequea si toca reparar
    call gui_maybe_repair
    xor eax, eax
    jmp gw_ret
gw_notify:
    mov rcx, QWORD PTR [rsp+88]
    call gui_on_notify
    jmp gw_ret
gw_ctxmenu:
    mov rcx, QWORD PTR [rsp+64]
    mov rdx, QWORD PTR [rsp+80]
    mov r8, QWORD PTR [rsp+88]
    call gui_on_contextmenu
    jmp gw_ret
gw_initmenu:
    mov ecx, WM_INITMENUPOPUP
    mov rdx, QWORD PTR [rsp+80]
    mov r8, QWORD PTR [rsp+88]
    call gui_menu_forward
    test eax, eax
    jz gw_def
    xor eax, eax
    jmp gw_ret
gw_drawitem:
    mov rax, QWORD PTR [rsp+80]
    cmp eax, IDC_MODE
    je gw_di_mode
    cmp eax, IDC_EMPTY
    je gw_di_empty
    mov ecx, WM_DRAWITEM
    mov rdx, QWORD PTR [rsp+80]
    mov r8, QWORD PTR [rsp+88]
    call gui_menu_forward
    test eax, eax
    jz gw_def
    mov eax, 1
    jmp gw_ret
gw_di_mode:
    mov rcx, QWORD PTR [rsp+88]
    call gui_mode_draw
    mov eax, 1
    jmp gw_ret
gw_di_empty:
    mov rcx, QWORD PTR [rsp+88]
    call gui_empty_draw
    mov eax, 1
    jmp gw_ret
gw_measureitem:
    mov ecx, WM_MEASUREITEM
    mov rdx, QWORD PTR [rsp+80]
    mov r8, QWORD PTR [rsp+88]
    call gui_menu_forward
    test eax, eax
    jz gw_def
    mov eax, 1
    jmp gw_ret
gw_done:
    mov rax, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_gen]
    cmp rax, QWORD PTR [rdx]
    jne gw_zero
    // indice completo: calibrar el tick incremental
    call GetTickCount64
    lea rdx, [rip + gui_lasttick]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_final
    call gui_edit_len
    test rax, rax
    jz gw_zero
    mov rcx, QWORD PTR [rsp+64]
    call gui_start_search
    xor eax, eax
    jmp gw_ret
gw_prog:
    mov rax, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_gen]
    cmp rax, QWORD PTR [rdx]
    jne gw_zero
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gw_prog_nofiles
    call scan_ws_files
    lea rdx, [rip + gui_files]
    mov QWORD PTR [rdx], rax
gw_prog_nofiles:
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_prog
    xor eax, eax
    jmp gw_ret
gw_zero:
    xor eax, eax
    jmp gw_ret
gw_destroy:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    test rcx, rcx
    jz gw_destroy_noreg
    push rcx
    mov edx, HOTKEY_ID
    call UnregisterHotKey
    pop rcx
    mov rcx, QWORD PTR [rsp+64]
    call gui_save_barpos
gw_destroy_noreg:
    mov rcx, QWORD PTR [rip + gui_hthread]
    test rcx, rcx
    jz gw_nothr
    lea rax, [rip + gui_gen]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov edx, 1000
    call WaitForSingleObject
gw_nothr:
    xor ecx, ecx
    call PostQuitMessage
    xor eax, eax
    jmp gw_ret
gw_hotkey:
    mov rcx, QWORD PTR [rsp+64]
    call gui_on_hotkey
    xor eax, eax
    jmp gw_ret
gw_activate:
    mov rax, QWORD PTR [rsp+80]
    and eax, 0xFFFF
    cmp eax, WA_INACTIVE
    jne gw_zero
    mov rcx, QWORD PTR [rsp+64]
    call gui_check_autohide
    xor eax, eax
    jmp gw_ret
gw_keydown:
    mov rax, QWORD PTR [rsp+80]
    // Ctrl+Q: salir de la app
    cmp rax, 0x51
    jne gw_kd_o
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_o
    xor ecx, ecx
    call PostQuitMessage
    xor eax, eax
    jmp gw_ret
gw_kd_o:
    // Ctrl+O: abrir carpeta contenedora del seleccionado
    cmp rax, 0x4F
    jne gw_kd_copy
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_copy
    mov rcx, QWORD PTR [rsp+64]
    call gui_open_folder
    xor eax, eax
    jmp gw_ret
gw_kd_copy:
    // Ctrl+Shift+C: copiar ruta del seleccionado
    cmp rax, 0x43
    jne gw_kd_hist
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_hist
    mov ecx, 0x10
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_hist
    mov rcx, QWORD PTR [rsp+64]
    call gui_copy_path
    xor eax, eax
    jmp gw_ret
gw_kd_hist:
    // Ctrl+Up/Ctrl+Down: historial de busquedas
    cmp rax, VK_UP
    je gw_kd_histupchk
    cmp rax, VK_DOWN
    je gw_kd_histdownchk
    jmp gw_kd_esc2
gw_kd_histupchk:
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_esc2
    mov rcx, QWORD PTR [rsp+64]
    call gui_hist_up
    xor eax, eax
    jmp gw_ret
gw_kd_histdownchk:
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz gw_kd_esc2
    mov rcx, QWORD PTR [rsp+64]
    call gui_hist_down
    xor eax, eax
    jmp gw_ret
gw_kd_esc2:
    cmp rax, VK_ESCAPE
    je gw_keyesc
    cmp rax, VK_F5
    je gw_keyf5
    // BUG1: flechas/Enter en la barra mueven seleccion del ListView.
    // (El Edit las come: el subclass gui_edit_proc cubre ese foco.
    // Aqui se cubre foco en lista/barra + PostMessage de test.)
    cmp rax, VK_DOWN
    je gw_keynav
    cmp rax, VK_UP
    je gw_keynav
    cmp rax, VK_NEXT
    je gw_keynav
    cmp rax, VK_PRIOR
    je gw_keynav
    cmp rax, VK_HOME
    je gw_keynav
    cmp rax, VK_END
    je gw_keynav
    cmp rax, VK_RETURN
    je gw_keynav
    jmp gw_def
gw_keyf5:
    call gui_reindex
    xor eax, eax
    jmp gw_ret
gw_keynav:
    mov ecx, eax
    call gui_handle_nav
    xor eax, eax
    jmp gw_ret
gw_keyesc:
    mov rcx, QWORD PTR [rsp+64]
    call gui_on_escape
    xor eax, eax
    jmp gw_ret
gw_ctlcolor:
    mov rcx, QWORD PTR [rsp+80]
    mov rdx, QWORD PTR [rsp+88]
    call gui_on_ctlcolor
    jmp gw_ret
gw_def:
    mov rcx, QWORD PTR [rsp+64]
    mov edx, DWORD PTR [rsp+72]
    mov r8, QWORD PTR [rsp+80]
    mov r9, QWORD PTR [rsp+88]
    call DefWindowProcW
gw_ret:
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

// gui_build_children(RCX=hwnd padre). Crea edit+list+status (+logo/hint/pin en bar).
gui_build_children:
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
    mov QWORD PTR [rsp+96], rcx
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_hinst]
    mov QWORD PTR [rsp+104], rax
    // edit (plano: sin CLIENTEDGE hundido; la pildora ya recorta el borde)
    xor ecx, ecx
    lea rdx, [rip + gui_cls_edit]
    xor r8d, r8d
    mov r9d, 0x50810080
    mov QWORD PTR [rsp+32], 8
    mov QWORD PTR [rsp+40], 8
    mov QWORD PTR [rsp+48], 860
    mov QWORD PTR [rsp+56], 26
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_SEARCH
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_edit]
    mov QWORD PTR [rcx], rax
    // cue banner (bar: texto maqueta; window: viejo)
    mov rcx, rax
    mov edx, EM_SETCUEBANNER
    mov r8d, 1
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gbc_cueold
    lea r9, [rip + gui_cue_bar]
    jmp gbc_cuego
gbc_cueold:
    lea r9, [rip + gui_cue]
gbc_cuego:
    call SendMessageW
    mov rbx, QWORD PTR [rsp+96]
    // listview (0x40=LVS_SHAREIMAGELISTS: no destruye el ImageList del sistema;
    // 0x4000=LVS_NOCOLUMNHEADER: sin cabecera blanca, look moderno)
    xor ecx, ecx
    lea rdx, [rip + gui_cls_list]
    xor r8d, r8d
    mov r9d, 0x50811049
    mov QWORD PTR [rsp+32], 8
    mov QWORD PTR [rsp+40], 40
    mov QWORD PTR [rsp+48], 860
    mov QWORD PTR [rsp+56], 480
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_LIST
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_list]
    mov QWORD PTR [rcx], rax
    mov r12, rax
    // scrollbar oscura (uxtheme): tema DarkMode_Explorer en el ListView
    mov rcx, r12
    lea rdx, [rip + gui_theme_dark]
    xor r8d, r8d
    call SetWindowTheme
    mov rcx, r12
    mov edx, LVM_SETEXTENDEDLISTVIEWSTYLE
    mov r8d, LVS_EX_FULLROWSELECT
    mov r9d, 0x10020
    call SendMessageW
    // fondo oscuro lista (contraste maqueta): bk + textbk + text
    mov rcx, r12
    mov edx, LVM_SETBKCOLOR
    xor r8d, r8d
    mov r9d, 0x1E1E1E
    call SendMessageW
    mov rcx, r12
    mov edx, LVM_SETTEXTBKCOLOR
    xor r8d, r8d
    mov r9d, 0x1E1E1E
    call SendMessageW
    mov rcx, r12
    mov edx, LVM_SETTEXTCOLOR
    xor r8d, r8d
    mov r9d, 0xF2F2F2
    call SendMessageW
    // columna 0 Nombre
    lea rax, [rip + gui_lvc]
    mov DWORD PTR [rax], LVCF_ALL
    mov DWORD PTR [rax+4], 0
    mov DWORD PTR [rax+8], 210
    lea rdx, [rip + gui_col0]
    mov QWORD PTR [rax+16], rdx
    mov DWORD PTR [rax+24], 0
    mov DWORD PTR [rax+28], 0
    mov DWORD PTR [rax+32], 0
    mov DWORD PTR [rax+36], 0
    mov rcx, r12
    mov edx, LVM_INSERTCOLUMNW
    xor r8d, r8d
    lea r9, [rip + gui_lvc]
    call SendMessageW
    // columna 1 Carpeta
    lea rax, [rip + gui_lvc]
    mov DWORD PTR [rax], LVCF_ALL
    mov DWORD PTR [rax+4], 0
    mov DWORD PTR [rax+8], 440
    lea rdx, [rip + gui_col1]
    mov QWORD PTR [rax+16], rdx
    mov DWORD PTR [rax+24], 0
    mov DWORD PTR [rax+28], 1
    mov DWORD PTR [rax+32], 0
    mov DWORD PTR [rax+36], 1
    mov rcx, r12
    mov edx, LVM_INSERTCOLUMNW
    mov r8d, 1
    lea r9, [rip + gui_lvc]
    call SendMessageW
    // columna 2 Modificado (fecha)
    lea rax, [rip + gui_lvc]
    mov DWORD PTR [rax], LVCF_ALL
    mov DWORD PTR [rax+4], 0
    mov DWORD PTR [rax+8], 130
    lea rdx, [rip + gui_col2]
    mov QWORD PTR [rax+16], rdx
    mov DWORD PTR [rax+24], 0
    mov DWORD PTR [rax+28], 2
    mov DWORD PTR [rax+32], 0
    mov DWORD PTR [rax+36], 2
    mov rcx, r12
    mov edx, LVM_INSERTCOLUMNW
    mov r8d, 2
    lea r9, [rip + gui_lvc]
    call SendMessageW
    // BUG2: ImageList del sistema (iconos por extension)
    call gui_init_imagelist
    // BUG1: subclass del Edit para flechas/Enter/Esc sin robar dialogo
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz gbc_noedit
    mov edx, GWLP_WNDPROC
    lea r8, [rip + gui_edit_proc]
    call SetWindowLongPtrW
    lea rcx, [rip + gui_edit_old]
    mov QWORD PTR [rcx], rax
gbc_noedit:
    mov rbx, QWORD PTR [rsp+96]
    // status: STATIC oscuro de una linea (el StatusBar con SB_SETBKCOLOR
    // rompia idle a los ~4s: B12. El STATIC usa CTLCOLORSTATIC oscuro +
    // fuente Segoe + SS_CENTERIMAGE para centrado vertical).
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    xor r8d, r8d
    mov r9d, 0x50000280
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 100
    mov QWORD PTR [rsp+56], 24
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_STATUS
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_status]
    mov QWORD PTR [rcx], rax
    // modo Todos/Archivos/Carpetas: STATIC owner-draw (SS_OWNERDRAW+SS_NOTIFY)
    // con iconos reales del sistema. Nada de texto con surrogates: un
    // SetWindowTextW con emoji en este STATIC tumbaba el proceso (AV en
    // DrawTextW de comctl). El paint lo hace gui_mode_draw via WM_DRAWITEM.
    mov rbx, QWORD PTR [rsp+96]
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    lea r8, [rip + gui_empty]
    mov r9d, 0x5000010D
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 24
    mov QWORD PTR [rsp+56], 23
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_MODE
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_hmode]
    mov QWORD PTR [rcx], rax
    call gui_init_modeicons
    call gui_mode_setglyph
    // vacio: STATIC owner-draw "Sin resultados" sobre la lista (oculto;
    // lo muestra gui_update_empty). Owner-draw porque el STATIC con texto
    // jamas pinto (texto/fuente/colores/z verificados OK). Ultimo hijo.
    mov rbx, QWORD PTR [rsp+96]
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    lea r8, [rip + gui_empty_txt]
    mov r9d, 0x5000010D
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 100
    mov QWORD PTR [rsp+56], 24
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_EMPTY
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_hempty]
    mov QWORD PTR [rcx], rax
    // arriba de la lista (los hijos se apilan raro: la lista queda encima)
    mov rdx, 0
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x13
    call SetWindowPos
    // bar: logo + hint + pin
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gbc_layout
    mov rbx, QWORD PTR [rsp+96]
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    lea r8, [rip + gui_logo_txt]
    mov r9d, 0x50000001
    mov QWORD PTR [rsp+32], 8
    mov QWORD PTR [rsp+40], 9
    mov QWORD PTR [rsp+48], 34
    mov QWORD PTR [rsp+56], 17
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_LOGO
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_hlogo]
    mov QWORD PTR [rcx], rax
    mov rbx, QWORD PTR [rsp+96]
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    lea r8, [rip + gui_hint_txt]
    mov r9d, 0x50000000
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 80
    mov QWORD PTR [rsp+56], 16
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_HINT
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_hhint]
    mov QWORD PTR [rcx], rax
    // pin: STATIC clicable (SS_NOTIFY) en vez de BUTTON: el BUTTON con tema
    // pinta cara blanca sobre la pildora oscura; el STATIC usa CTLCOLORSTATIC
    // oscuro. STN_CLICKED=0=BN_CLICKED: gw_command no cambia.
    mov rbx, QWORD PTR [rsp+96]
    xor ecx, ecx
    lea rdx, [rip + gui_cls_static]
    lea r8, [rip + gui_pin_txt]
    mov r9d, 0x50000381
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 24
    mov QWORD PTR [rsp+56], 23
    mov QWORD PTR [rsp+64], rbx
    mov QWORD PTR [rsp+72], IDC_PIN
    mov rax, QWORD PTR [rsp+104]
    mov QWORD PTR [rsp+80], rax
    mov QWORD PTR [rsp+88], 0
    call CreateWindowExW
    lea rcx, [rip + gui_hpin]
    mov QWORD PTR [rcx], rax
    // bar arranca con panel oculto (solo pildora 40px)
    mov rcx, QWORD PTR [rip + gui_list]
    xor edx, edx
    call ShowWindow
    mov rcx, QWORD PTR [rip + gui_status]
    xor edx, edx
    call ShowWindow
    mov rcx, QWORD PTR [rip + gui_hempty]
    xor edx, edx
    call ShowWindow
    // B12: status 100% stock (sin SB_SETBKCOLOR ni SetWindowTheme). El status
    // oscuro (bk + untheme) tumbaba la pildora idle a los ~4s (AV en
    // KERNELBASE con SB_SETTEXTW a alta frecuencia sobre el control oculto
    // sin tema). Por eso el status ahora es STATIC de una linea (ver
    // creacion): CTLCOLORSTATIC oscuro + SetWindowTextW, sin SB_*.
    // Fuente/margenes/pin-flat/custom-draw quedan (verificados).
    // (Bloque oscuro removido; ver BENCH.)
gbc_nosttheme:
    // fuente Segoe UI 11pt en todos los controles + padding interno del Edit.
    // La altura de fila del ListView crece con la fuente (aire sin owner-draw).
    call gui_init_font
    mov rax, QWORD PTR [rip + gui_hfont]
    test rax, rax
    jz gbc_nofont
    mov rcx, QWORD PTR [rip + gui_edit]
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_status]
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_hlogo]
    test rcx, rcx
    jz gbc_fonthint
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
gbc_fonthint:
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_hhint]
    test rcx, rcx
    jz gbc_fontpin
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
gbc_fontpin:
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_hpin]
    test rcx, rcx
    jz gbc_fontmode
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
gbc_fontmode:
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_hmode]
    test rcx, rcx
    jz gbc_fontempty
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
gbc_fontempty:
    mov rax, QWORD PTR [rip + gui_hfont]
    mov rcx, QWORD PTR [rip + gui_hempty]
    test rcx, rcx
    jz gbc_fontdone
    mov edx, WM_SETFONT
    mov r8, rax
    mov r9d, 1
    call SendMessageW
gbc_fontdone:
    mov rcx, QWORD PTR [rip + gui_edit]
    mov edx, EM_SETMARGINS
    mov r8d, 3
    mov r9d, 0x00060006
    call SendMessageW
gbc_nofont:
gbc_layout:
    mov rcx, QWORD PTR [rsp+96]
    call gui_layout
    // foco inicial solo si window o --focus (no robar foco en bar default)
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gbc_focus
    mov rax, QWORD PTR [rip + gui_focus_req]
    test rax, rax
    jz gbc_ret
gbc_focus:
    mov rcx, QWORD PTR [rip + gui_edit]
    call SetFocus
gbc_ret:
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

// gui_layout(RCX=hwnd). Posiciona hijos (rama bar vs window).
gui_layout:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gui_layout_win
    // PILDORA 700x40: logo(8,11,34,17) edit(50,9,W-206,23) hint(W-148,12,80,16)
    // modo(W-60,8,24,23) pin(W-32,8,24,23) list(8,45,W-16,H-73) status(8,H-24,W-8,24)
    lea rdx, [rsp+48]
    call GetClientRect
    mov eax, DWORD PTR [rsp+56]
    mov DWORD PTR [rsp+40], eax
    mov rbx, QWORD PTR [rip + gui_edit]
    test rbx, rbx
    jz gui_lay_ret
    mov eax, DWORD PTR [rsp+56]
    sub eax, 206
    mov rcx, rbx
    mov edx, 50
    mov r8d, 9
    mov r9d, eax
    mov DWORD PTR [rsp+32], 23
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    mov rcx, QWORD PTR [rip + gui_hlogo]
    test rcx, rcx
    jz gui_lay_barskip1
    mov edx, 8
    mov r8d, 11
    mov r9d, 34
    mov DWORD PTR [rsp+32], 17
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_barskip1:
    mov eax, DWORD PTR [rsp+56]
    sub eax, 148
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_hhint]
    test rcx, rcx
    jz gui_lay_barskip2
    mov edx, r12d
    mov r8d, 12
    mov r9d, 80
    mov DWORD PTR [rsp+32], 16
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    // modo (W-60,8,24,23)
    mov eax, DWORD PTR [rsp+56]
    sub eax, 60
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_hmode]
    test rcx, rcx
    jz gui_lay_barskip2
    mov edx, r12d
    mov r8d, 8
    mov r9d, 24
    mov DWORD PTR [rsp+32], 23
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_barskip2:
    mov eax, DWORD PTR [rsp+56]
    sub eax, 32
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_hpin]
    test rcx, rcx
    jz gui_lay_barlist
    mov edx, r12d
    mov r8d, 8
    mov r9d, 24
    mov DWORD PTR [rsp+32], 23
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_barlist:
    mov eax, DWORD PTR [rsp+56]
    sub eax, 16
    mov ebx, eax
    mov eax, DWORD PTR [rsp+60]
    sub eax, 73
    mov r12d, eax
    cmp r12d, 0
    jle gui_lay_barstatus
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, 8
    mov r8d, 45
    mov r9d, ebx
    mov DWORD PTR [rsp+32], r12d
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    // vacio cubre la lista (texto centrado por estilo)
    mov rcx, QWORD PTR [rip + gui_hempty]
    test rcx, rcx
    jz gui_lay_barstatus
    mov edx, 8
    mov r8d, 45
    mov r9d, ebx
    mov DWORD PTR [rsp+32], r12d
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_barstatus:
    mov eax, DWORD PTR [rsp+60]
    sub eax, 24
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_status]
    mov edx, 8
    mov r8d, r12d
    mov r9d, DWORD PTR [rsp+56]
    sub r9d, 8
    mov DWORD PTR [rsp+32], 24
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    jmp gui_lay_ret
gui_layout_win:
    lea rdx, [rsp+48]
    mov rcx, QWORD PTR [rsp+40]
    call GetClientRect
    mov rbx, QWORD PTR [rip + gui_edit]
    test rbx, rbx
    jz gui_lay_ret
    // edit: (8,8,w-48,26) + modo (w-32,8,24,26)
    mov eax, DWORD PTR [rsp+56]
    sub eax, 48
    mov rcx, rbx
    mov edx, 8
    mov r8d, 8
    mov r9d, eax
    mov DWORD PTR [rsp+32], 26
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    mov eax, DWORD PTR [rsp+56]
    sub eax, 32
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_hmode]
    test rcx, rcx
    jz gui_lay_winlist
    mov edx, r12d
    mov r8d, 8
    mov r9d, 24
    mov DWORD PTR [rsp+32], 26
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_winlist:
    mov eax, DWORD PTR [rsp+56]
    sub eax, 16
    mov ebx, eax
    mov eax, DWORD PTR [rsp+60]
    sub eax, 66
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, 8
    mov r8d, 40
    mov r9d, ebx
    mov DWORD PTR [rsp+32], r12d
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
    mov rcx, QWORD PTR [rip + gui_hempty]
    test rcx, rcx
    jz gui_lay_winempty
    mov edx, 8
    mov r8d, 40
    mov r9d, ebx
    mov DWORD PTR [rsp+32], r12d
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_winempty:
    mov eax, DWORD PTR [rsp+60]
    sub eax, 24
    mov r12d, eax
    mov rcx, QWORD PTR [rip + gui_status]
    mov edx, 8
    mov r8d, r12d
    mov r9d, DWORD PTR [rsp+56]
    sub r9d, 8
    mov DWORD PTR [rsp+32], 24
    mov QWORD PTR [rsp+40], 1
    call MoveWindow
gui_lay_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_start_search(RCX=hwnd). Filtra el índice persistente en memoria
// (sin re-escanear): query del Edit -> UTF-8 -> contains_ci_a por record.
// Total en gui_total + primeros GUI_MAXDISPLAY índices en gui_items.
// Filtro incremental: si la query nueva extiende la anterior (sin globs en
// ambas, anterior prefijo de la nueva, total previo <= cap) se filtran SOLO
// los resultados previos (mismo resultado exacto; si no, filtrado completo).
// Prefiltro SSE2 por primer byte (match.s) salvo comodin lider.
// Frame 264: [rsp+64]=hwnd, [rsp+72]=base, [rsp+80]=n, [rsp+88]=freq,
//   [rsp+96]=t0, [rsp+104]=t1, [rsp+112]=i, [rsp+120]=fskip,
//   [rsp+128]=flo, [rsp+136]=fhi, [rsp+144]=incflag, [rsp+152]=prevtotal,
//   [rsp+160]=prevcount, [rsp+192]=SYSTEM_INFO(48), [rsp+240]=T, [rsp+248]=i.
//   8 pushes + sub 264 = 328 = 8 mod 16: pila 16B antes de call (ABI x64;
//   COMCTL32 usa movaps en prologos y falla con +8 de skew).
//   R12=fqa, R13=fqlen, R14=base,
//   R15=n, RDI=total, RSI=mostrados, RBX=recidx (loop incremental).
//   Filtro paralelo: si via completa y n>200K, T hilos (cores, tope 8) sobre
//   particiones contiguas + merge ordenado por indice (mismo orden que el
//   single, cap 100K exacto: cada hilo guarda sus primeros 100K).
gui_start_search:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264
    mov QWORD PTR [rsp+64], rcx
    // marca ocupado mientras se filtra (el repair en fondo aborta si busy)
    lea rax, [rip + gui_busy]
    mov QWORD PTR [rax], 1
    // (records contados siempre completos: name, parent y count en orden).
    // gw_done refiltra con el índice completo al terminar el indexado.
    mov rax, QWORD PTR [rip + gui_idx_ws]
    test rax, rax
    jz gui_ss_empty
    // leer edit (cap 1024)
    mov rcx, QWORD PTR [rip + gui_edit]
    lea rdx, [rip + gui_query]
    mov r8d, 1025
    call GetWindowTextW
    lea rdx, [rip + gui_qlen]
    mov QWORD PTR [rdx], rax
    cmp rax, GUI_QUERYMAX
    jbe gui_ss_qok
    mov QWORD PTR [rdx], GUI_QUERYMAX
gui_ss_qok:
    lea rcx, [rip + gui_query]
    mov rdx, QWORD PTR [rip + gui_qlen]
    call lowercase_query
    lea rcx, [rip + gui_query]
    mov rdx, QWORD PTR [rip + gui_qlen]
    call glob_has_wild
    lea rcx, [rip + scan_is_glob]
    mov QWORD PTR [rcx], rax
    // query de ruta: contiene '\' o '/' -> match sobre la ruta completa
    lea rcx, [rip + gui_query]
    mov rdx, QWORD PTR [rip + gui_qlen]
    call skc_query_is_pathq
    lea rcx, [rip + scan_is_pathq]
    mov QWORD PTR [rcx], rax
    mov rax, QWORD PTR [rip + gui_total]
    mov QWORD PTR [rsp+152], rax
    mov rax, QWORD PTR [rip + gui_count]
    mov QWORD PTR [rsp+160], rax
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], 0
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_SETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    cmp QWORD PTR [rip + gui_qlen], 0
    je gui_ss_empty
    // query -> UTF-8 una vez
    mov rcx, 65001
    xor edx, edx
    lea r8, [rip + gui_query]
    mov r9, QWORD PTR [rip + gui_qlen]
    lea rax, [rip + gui_fqa]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 8192
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    call WideCharToMultiByte
    test eax, eax
    jz gui_ss_empty
    movsxd rdx, eax
    lea rax, [rip + gui_fqalen]
    mov QWORD PTR [rax], rdx
    // query NORMALIZADA (fold, '/', trim, './', '\' final): una vez por
    // filtrado. Antes se normalizaba por record (memset de 1KB x 3M records).
    // OJO: para pasar la DIRECCION del buffer va `lea`: un `mov rcx, [rip+X]`
    // carga el CONTENIDO del buffer y el Rust leeria desde un puntero basura.
    lea rcx, [rip + gui_fqa]
    mov rdx, QWORD PTR [rip + gui_fqalen]
    lea r8, [rip + gui_fqn]
    mov r9d, 1024
    call skc_qnorm8
    mov QWORD PTR [rip + gui_fqnlen], rax
    lea rcx, [rip + gui_query]
    mov rdx, QWORD PTR [rip + gui_qlen]
    lea r8, [rip + gui_qn]
    mov r9d, 1024
    call skc_qnorm
    mov QWORD PTR [rip + gui_qnlen], rax
    // gui_globval: 0 = normal, 1 = glob, 2 = ANCLADO (la query arranca con
    // la unidad "X:\" => el match es un prefijo de la ruta y se corta al
    // divergir, sin armarla entera), 3 = glob anclado.
    mov QWORD PTR [rip + gui_globval], 0
    mov rax, QWORD PTR [rip + gui_qnlen]
    cmp rax, 3
    jb ggl_done
    lea rcx, [rip + gui_qn]
    movzx edx, WORD PTR [rcx]
    cmp dl, 0x61
    jb ggl_done
    cmp dl, 0x7A
    ja ggl_done
    movzx edx, WORD PTR [rcx+2]
    cmp dl, 0x3A
    jne ggl_done
    movzx edx, WORD PTR [rcx+4]
    cmp dl, 0x5C
    jne ggl_done
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne ggl_glob
    mov QWORD PTR [rip + gui_globval], 2
    jmp ggl_done
ggl_glob:
    mov QWORD PTR [rip + gui_globval], 3
ggl_done:
    // mascara de condiciones de la query (pre-filtro por la firma de 64 bits)
    lea rcx, [rip + gui_qn]
    mov rdx, QWORD PTR [rip + gui_qnlen]
    call skc_bloom_mask
    mov QWORD PTR [rip + gui_qmask], rax
    lea rcx, [rsp+88]
    call QueryPerformanceFrequency
    lea rcx, [rsp+96]
    call QueryPerformanceCounter
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    call scan_ws_recbase
    mov r14, rax
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    mov rax, QWORD PTR [rcx+WS_A_BASE]
    lea rdx, [rip + gui_th_abeg]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rcx+WS_A_BRK]
    lea rdx, [rip + gui_th_abrk]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    call scan_ws_reccnt
    mov r15, rax
    lea r12, [rip + gui_fqn]
    mov r13, QWORD PTR [rip + gui_fqnlen]
    mov QWORD PTR [rsp+120], 0
    mov QWORD PTR [rsp+144], 0
    test r13, r13
    jz gui_ss_decided
    // primer byte normalizado + fskip tri-estado (Rust): el prefilter
    // crudo perderia blancos/"./" iniciales; 2 = segunda chance 0xC3
    mov rcx, r12
    mov rdx, r13
    call skc_qpre
    mov r8d, eax
    movzx eax, r8b
    mov edx, r8d
    shr edx, 8
    and edx, 0xFF
    mov QWORD PTR [rsp+120], rdx
    // query de ruta: el prefilter de primer byte del nombre no aplica
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne gui_ss_nopre
    cmp QWORD PTR [rip + scan_is_glob], 0
    je gui_ss_precomm
    cmp eax, 0x2A
    je gui_ss_nopre
    cmp eax, 0x3F
    je gui_ss_nopre
gui_ss_precomm:
    mov QWORD PTR [rsp+128], rax
    cmp eax, 0x61
    jb gui_ss_prehave
    cmp eax, 0x7A
    ja gui_ss_prehave
    sub eax, 0x20
gui_ss_prehave:
    mov QWORD PTR [rsp+136], rax
    jmp gui_ss_incchk
gui_ss_nopre:
    mov QWORD PTR [rsp+120], 1
gui_ss_incchk:
    // query de ruta: ahora o antes, sin incremental (no es prefijo-cerrado)
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne gui_ss_decided
    cmp QWORD PTR [rip + gui_prevpathq], 0
    jne gui_ss_decided
    cmp QWORD PTR [rip + scan_is_glob], 0
    jne gui_ss_decided
    cmp QWORD PTR [rip + gui_prevwild], 0
    jne gui_ss_decided
    mov rax, QWORD PTR [rip + gui_prevlen]
    test rax, rax
    jz gui_ss_decided
    cmp rax, r13
    jae gui_ss_decided
    lea rsi, [rip + gui_fqa]
    lea rdi, [rip + gui_prevqa]
    mov rcx, rax
    repe cmpsb
    jne gui_ss_decided
    mov rax, QWORD PTR [rsp+152]
    test rax, rax
    jz gui_ss_decided
    cmp rax, GUI_MAXDISPLAY
    ja gui_ss_decided
    cmp rax, QWORD PTR [rsp+160]
    jne gui_ss_decided
    mov QWORD PTR [rsp+144], 1
gui_ss_decided:
    xor edi, edi
    xor esi, esi
    mov QWORD PTR [rsp+112], 0
    // reset del cache de rutas (skc_score_rec usa gui_pathbuf como cache:
    // [0..2) = profundidad de la pila de ancestros). Una pasada por el indice.
    mov DWORD PTR [rip + gui_pathbuf], 0
    cmp QWORD PTR [rsp+144], 0
    jne gui_ss_incloop
    cmp r15, 200000
    ja gui_ss_par
gui_ss_loop:
    mov rax, QWORD PTR [rsp+112]
    cmp rax, r15
    jae gui_ss_sort
    mov rdx, rax
    imul rdx, rdx, 12
    mov r10, QWORD PTR [r14+rdx]
    cmp r10, QWORD PTR [rip + gui_th_abeg]
    jb gui_ss_next
    cmp r10, QWORD PTR [rip + gui_th_abrk]
    jae gui_ss_next
    movzx edx, WORD PTR [r10-2]
    cmp QWORD PTR [rsp+120], 0
    jne gui_ss_domatch
    // Pre-filtro por la firma de 64 bits del record: si a la query le falta
    // un bit, este record NO puede matchear -> se descarta sin leer el
    // nombre (que esta disperso en la arena). Sustituye al prefilter por byte.
    mov rax, QWORD PTR [rip + gui_bloom]
    test rax, rax
    jz gui_ss_preok
    mov rcx, QWORD PTR [rsp+112]
    imul rcx, rcx, 8
    add rax, rcx
    mov rax, QWORD PTR [rax]
    and rax, QWORD PTR [rip + gui_qmask]
    cmp rax, QWORD PTR [rip + gui_qmask]
    jne gui_ss_next
gui_ss_preok:
    movzx edx, WORD PTR [r10-2]
gui_ss_domatch:
    // query de ruta: match sobre la ruta completa del record (Rust)
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne gui_ss_pathq
    // score por relevancia (Rust): tier exacta/prefijo/subcadena+glob,
    // boost de modo archivo/carpeta, bonus por nombre corto.
    mov rcx, r10
    mov r8, r12
    mov r9, r13
    mov rax, QWORD PTR [rip + scan_is_glob]
    mov QWORD PTR [rsp+32], rax
    mov rax, QWORD PTR [rsp+112]
    imul rax, rax, 12
    mov eax, DWORD PTR [r14+rax+8]
    shr eax, 31
    mov QWORD PTR [rsp+40], rax
    mov eax, DWORD PTR [rip + gui_fmode]
    mov QWORD PTR [rsp+48], rax
    call skc_score_name
    test eax, eax
    jz gui_ss_next
    // empaqueta (score<<32 | ~idx) en [rsp+56] para gui_ss_hit
    mov edx, DWORD PTR [rsp+112]
    not edx
    shl rax, 32
    or rax, rdx
    mov QWORD PTR [rsp+56], rax
    jmp gui_ss_hit
gui_ss_pathq:
    // skc_score_rec(rec, idx, q, qlen, is_glob, mode, buf, buflen):
    // 4 args en registros (rcx,rdx,r8,r9) + 4 en pila (+32,+40,+48,+56).
    mov rcx, r14
    mov rdx, QWORD PTR [rsp+112]
    lea r8, [rip + gui_qn]
    mov r9, QWORD PTR [rip + gui_qnlen]
    mov rax, QWORD PTR [rip + gui_globval]
    mov QWORD PTR [rsp+32], rax
    mov eax, DWORD PTR [rip + gui_fmode]
    mov QWORD PTR [rsp+40], rax
    lea rax, [rip + gui_pathbuf]
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], 32768
    call skc_score_rec
    test eax, eax
    jz gui_ss_next
    mov edx, DWORD PTR [rsp+112]
    not edx
    shl rax, 32
    or rax, rdx
    mov QWORD PTR [rsp+56], rax
    jmp gui_ss_hit
gui_ss_hit:
    inc rdi
    cmp rsi, GUI_MAXDISPLAY
    jae gui_ss_next
    mov rax, QWORD PTR [rsp+56]
    lea rdx, [rip + gui_items]
    mov QWORD PTR [rdx+rsi*8], rax
    inc rsi
gui_ss_next:
    inc QWORD PTR [rsp+112]
    jmp gui_ss_loop
// Loop incremental: filtra solo los indices previos (gui_items[0..prevtotal),
// compactando in-place (escritura <= lectura). Solo sin globs (el total nuevo
// es subconjunto del previo por prefijo). Sin prefiltro: todos contienen el
// primer byte por construccion.
gui_ss_incloop:
    mov rax, QWORD PTR [rsp+112]
    cmp rax, QWORD PTR [rsp+152]
    jae gui_ss_sort
    lea rdx, [rip + gui_items]
    mov rax, QWORD PTR [rdx+rax*8]
    mov rbx, rax
    mov rdx, rax
    imul rdx, rdx, 12
    mov r10, QWORD PTR [r14+rdx]
    cmp r10, QWORD PTR [rip + gui_th_abeg]
    jb gui_ss_incnext
    cmp r10, QWORD PTR [rip + gui_th_abrk]
    jae gui_ss_incnext
    movzx edx, WORD PTR [r10-2]
    mov rcx, r10
    mov r8, r12
    mov r9, r13
    // incremental nunca es glob: is_glob=0; score + empaqueta igual
    xor eax, eax
    mov QWORD PTR [rsp+32], rax
    mov rax, rbx
    imul rax, rax, 12
    mov eax, DWORD PTR [r14+rax+8]
    shr eax, 31
    mov QWORD PTR [rsp+40], rax
    mov eax, DWORD PTR [rip + gui_fmode]
    mov QWORD PTR [rsp+48], rax
    call skc_score_name
    test eax, eax
    jz gui_ss_incnext
    inc rdi
    cmp rsi, GUI_MAXDISPLAY
    jae gui_ss_incnext
    mov edx, ebx
    not edx
    shl rax, 32
    or rax, rdx
    lea rdx, [rip + gui_items]
    mov QWORD PTR [rdx+rsi*8], rax
    inc rsi
gui_ss_incnext:
    inc QWORD PTR [rsp+112]
    jmp gui_ss_incloop
// Ordena gui_items[0..rsi) por score desc (Rust) y desempaqueta a recidx.
// gui_items guarda (score<<32 | ~idx) durante la coleccion; el siguiente
// filtrado incremental ya lo ve desempaquetado.
gui_ss_sort:
    lea rcx, [rip + gui_items]
    mov rdx, rsi
    call skc_rank_sort
    lea rdx, [rip + gui_items]
    xor ecx, ecx
gui_ss_unpack:
    cmp rcx, rsi
    jae gui_ss_timed
    mov eax, DWORD PTR [rdx+rcx*8]
    not eax
    mov QWORD PTR [rdx+rcx*8], rax
    inc rcx
    jmp gui_ss_unpack
// Filtro paralelo (via completa, n>200K): T hilos (cores, tope 8) sobre
// particiones contiguas + merge ordenado por indice en gui_items (cap 100K
// exacto: cada hilo guarda sus primeros 100K y el merge concatena en orden).
gui_ss_par:
    lea rcx, [rsp+192]
    call GetSystemInfo
    mov eax, DWORD PTR [rsp+192+32]
    test eax, eax
    jz gui_ss_loop
    cmp eax, 8
    jbe gui_ss_coresok
    mov eax, 8
gui_ss_coresok:
    mov QWORD PTR [rsp+240], rax
    lea rax, [rip + gui_th_base]
    mov QWORD PTR [rax], r14
    mov rax, QWORD PTR [rsp+128]
    lea rdx, [rip + gui_th_flo]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+136]
    lea rdx, [rip + gui_th_fhi]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rsp+120]
    lea rdx, [rip + gui_th_fskip]
    mov QWORD PTR [rdx], rax
    mov QWORD PTR [rsp+248], 0
gui_ss_zero:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, 8
    jae gui_ss_zeroed
    lea rdx, [rip + gui_th_tot]
    mov QWORD PTR [rdx+rax*8], 0
    lea rdx, [rip + gui_th_got]
    mov QWORD PTR [rdx+rax*8], 0
    inc QWORD PTR [rsp+248]
    jmp gui_ss_zero
gui_ss_zeroed:
    mov QWORD PTR [rsp+248], 0
    mov rax, r15
    xor edx, edx
    div QWORD PTR [rsp+240]
    mov rdi, rax
    mov rsi, rdx
    mov QWORD PTR [rsp+248], 0
gui_ss_mkth:
    mov rcx, QWORD PTR [rsp+248]
    cmp rcx, QWORD PTR [rsp+240]
    jae gui_ss_join
    mov rax, rcx
    mul rdi
    mov rdx, rcx
    cmp rcx, rsi
    jae gui_ss_nomin1
    mov rdx, rsi
gui_ss_nomin1:
    add rax, rdx
    lea rdx, [rip + gui_th_start]
    mov QWORD PTR [rdx+rcx*8], rax
    mov rdx, rdi
    cmp rcx, rsi
    jae gui_ss_nomin2
    inc rdx
gui_ss_nomin2:
    add rax, rdx
    lea rdx, [rip + gui_th_end]
    mov QWORD PTR [rdx+rcx*8], rax
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + gui_filter_worker]
    mov r9, QWORD PTR [rsp+248]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    lea rdx, [rip + gui_th_h]
    mov rcx, QWORD PTR [rsp+248]
    mov QWORD PTR [rdx+rcx*8], rax
    test rax, rax
    jnz gui_ss_mknext
    mov rcx, QWORD PTR [rsp+248]
    call gui_filter_worker
gui_ss_mknext:
    inc QWORD PTR [rsp+248]
    jmp gui_ss_mkth
gui_ss_join:
    mov QWORD PTR [rsp+248], 0
gui_ss_wait:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, QWORD PTR [rsp+240]
    jae gui_ss_merge
    lea rdx, [rip + gui_th_h]
    mov rcx, QWORD PTR [rdx+rax*8]
    test rcx, rcx
    jz gui_ss_waitnext
    mov edx, -1
    call WaitForSingleObject
    lea rdx, [rip + gui_th_h]
    mov rax, QWORD PTR [rsp+248]
    mov rcx, QWORD PTR [rdx+rax*8]
    call CloseHandle
gui_ss_waitnext:
    inc QWORD PTR [rsp+248]
    jmp gui_ss_wait
gui_ss_merge:
    // Los slots guardan (score<<32 | ~idx): compactar todo al inicio de
    // gui_th_bufs (contiguo 8x800KB), ordenar por score desc (Rust) y
    // copiar el top GUI_MAXDISPLAY desempaquetado a gui_items.
    xor r10d, r10d
    lea rdi, [rip + gui_th_bufs]
    mov QWORD PTR [rsp+248], 0
gui_ss_mslot:
    mov rax, QWORD PTR [rsp+248]
    cmp rax, QWORD PTR [rsp+240]
    jae gui_ss_msort
    lea rdx, [rip + gui_th_tot]
    add r10, QWORD PTR [rdx+rax*8]
    lea rdx, [rip + gui_th_got]
    mov rcx, QWORD PTR [rdx+rax*8]
    test rcx, rcx
    jz gui_ss_mslotnext
    mov rax, QWORD PTR [rsp+248]
    imul rax, rax, 800000
    lea rsi, [rip + gui_th_bufs]
    add rsi, rax
    rep movsq
gui_ss_mslotnext:
    inc QWORD PTR [rsp+248]
    jmp gui_ss_mslot
gui_ss_msort:
    lea rax, [rip + gui_th_bufs]
    mov rcx, rdi
    sub rcx, rax
    shr rcx, 3
    mov QWORD PTR [rsp+56], r10
    mov QWORD PTR [rsp+248], rcx
    lea rcx, [rip + gui_th_bufs]
    mov rdx, QWORD PTR [rsp+248]
    call skc_rank_sort
    mov r10, QWORD PTR [rsp+56]
    mov rcx, QWORD PTR [rsp+248]
    cmp rcx, GUI_MAXDISPLAY
    jbe gui_ss_mcopy
    mov rcx, GUI_MAXDISPLAY
gui_ss_mcopy:
    lea rsi, [rip + gui_th_bufs]
    lea rdx, [rip + gui_items]
    xor r8d, r8d
gui_ss_mcpy:
    cmp r8, rcx
    jae gui_ss_mdone
    mov eax, DWORD PTR [rsi+r8*8]
    not eax
    mov QWORD PTR [rdx+r8*8], rax
    inc r8
    jmp gui_ss_mcpy
gui_ss_mdone:
    mov rsi, rcx
    mov rdi, r10
    jmp gui_ss_timed
gui_ss_timed:
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], rdi
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], rsi
    lea rcx, [rsp+104]
    call QueryPerformanceCounter
    mov rax, QWORD PTR [rsp+104]
    sub rax, QWORD PTR [rsp+96]
    mov r15, rax
    mov rax, QWORD PTR [rsp+88]
    test rax, rax
    jz gui_ss_mszero
    mov rcx, 1000
    mov rax, r15
    mul rcx
    div QWORD PTR [rsp+88]
    mov r15, rax
    jmp gui_ss_msok
gui_ss_mszero:
    xor r15d, r15d
gui_ss_msok:
    lea rax, [rip + gui_ms]
    mov QWORD PTR [rax], r15
    lea rsi, [rip + gui_fqa]
    lea rdi, [rip + gui_prevqa]
    mov rcx, QWORD PTR [rip + gui_fqalen]
    rep movsb
    mov rax, QWORD PTR [rip + gui_fqalen]
    lea rdx, [rip + gui_prevlen]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rip + scan_is_glob]
    lea rdx, [rip + gui_prevwild]
    mov QWORD PTR [rdx], rax
    mov rax, QWORD PTR [rip + scan_is_pathq]
    lea rdx, [rip + gui_prevpathq]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rsp+64]
    call gui_refresh_final
    jmp gui_ss_ret
gui_ss_empty:
    mov rcx, QWORD PTR [rsp+64]
    call gui_update_status
    mov rcx, QWORD PTR [rsp+64]
    call gui_update_title
gui_ss_ret:
    // filtro terminado: liberar ocupado
    lea rax, [rip + gui_busy]
    mov QWORD PTR [rax], 0
    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_filter_worker(RCX=slot). Filtra [start,end) con el mismo
// prefilter+match que el loop single (query de ruta: skc_match_rec con
// buffer propio en el frame). Guarda los primeros 100K recidx en su tramo
// de gui_th_bufs; total->gui_th_tot[slot], guardados->gui_th_got.
// Regs: RSI=i, RDI=end, R12=total, R13=got (los args de pila de la llamada
// Rust machacan [rsp+32..55]: los contadores no viven en la pila).
// Frame: 5 pushes + sub 65600 (buffer ruta 32768 WCHAR en [rsp+64]).
gui_filter_worker:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    // Windows expande el stack solo al tocar la guard page actual; un sub de 64KB
    // la salta y la primera escritura AVa. Sondear pagina por pagina hacia abajo
    // (como __chkstk) antes de reservar el frame grande.
    mov rax, rsp
    and rax, -4096
    lea rdx, [rsp - 65648]
gtw_probe:
    sub rax, 4096
    mov BYTE PTR [rax], 0
    cmp rax, rdx
    ja gtw_probe
    sub rsp, 65600
    mov rbx, rcx
    // reset del cache de rutas (skc_score_rec lo usa como cache por hilo:
    // [0..2)=profundidad de la pila de ancestros). El stack puede venir sucio.
    mov DWORD PTR [rsp+64], 0
    lea rax, [rip + gui_th_start]
    mov rsi, QWORD PTR [rax+rbx*8]
    lea rax, [rip + gui_th_end]
    mov rdi, QWORD PTR [rax+rbx*8]
    xor r12, r12
    xor r13, r13
gtw_loop:
    cmp rsi, rdi
    jae gtw_done
    mov rdx, rsi
    imul rdx, rdx, 12
    add rdx, QWORD PTR [rip + gui_th_base]
    mov r10, QWORD PTR [rdx]
    cmp r10, QWORD PTR [rip + gui_th_abeg]
    jb gtw_next
    cmp r10, QWORD PTR [rip + gui_th_abrk]
    jae gtw_next
    movzx edx, WORD PTR [r10-2]
    cmp QWORD PTR [rip + gui_th_fskip], 0
    jne gtw_domatch
    // Pre-filtro por la firma de 64 bits (ver gui_ss_loop)
    mov rax, QWORD PTR [rip + gui_bloom]
    test rax, rax
    jz gtw_preok
    mov rcx, rsi
    shl rcx, 3
    add rax, rcx
    mov rax, QWORD PTR [rax]
    and rax, QWORD PTR [rip + gui_qmask]
    cmp rax, QWORD PTR [rip + gui_qmask]
    jne gtw_next
gtw_preok:
    movzx edx, WORD PTR [r10-2]
gtw_domatch:
    // query de ruta: match sobre la ruta completa del record (Rust)
    cmp QWORD PTR [rip + scan_is_pathq], 0
    jne gtw_pathq
    // score por relevancia igual que el loop single
    mov rax, QWORD PTR [rip + scan_is_glob]
    mov QWORD PTR [rsp+32], rax
    mov rax, QWORD PTR [rip + gui_th_base]
    mov rcx, rsi
    imul rcx, rcx, 12
    mov eax, DWORD PTR [rax+rcx+8]
    shr eax, 31
    mov QWORD PTR [rsp+40], rax
    mov eax, DWORD PTR [rip + gui_fmode]
    mov QWORD PTR [rsp+48], rax
    mov rcx, r10
    movzx edx, WORD PTR [r10-2]
    lea r8, [rip + gui_fqn]
    mov r9, QWORD PTR [rip + gui_fqnlen]
    call skc_score_name
    jmp gtw_test
gtw_pathq:
    // skc_score_rec(rec, idx, q, qlen, is_glob, mode, buf, buflen)
    mov rcx, QWORD PTR [rip + gui_th_base]
    mov rdx, rsi
    lea r8, [rip + gui_qn]
    mov r9, QWORD PTR [rip + gui_qnlen]
    mov rax, QWORD PTR [rip + gui_globval]
    mov QWORD PTR [rsp+32], rax
    mov eax, DWORD PTR [rip + gui_fmode]
    mov QWORD PTR [rsp+40], rax
    lea rax, [rsp+64]
    mov QWORD PTR [rsp+48], rax
    mov QWORD PTR [rsp+56], 32768
    call skc_score_rec
gtw_test:
    test eax, eax
    jz gtw_next
    inc r12
    cmp r13, 100000
    jae gtw_next
    mov edx, esi
    not edx
    shl rax, 32
    or rax, rdx
    mov rcx, rbx
    imul rcx, rcx, 800000
    lea rdx, [rip + gui_th_bufs]
    add rcx, rdx
    mov QWORD PTR [rcx+r13*8], rax
    inc r13
gtw_next:
    inc rsi
    jmp gtw_loop
gtw_done:
    lea rax, [rip + gui_th_tot]
    mov QWORD PTR [rax+rbx*8], r12
    lea rax, [rip + gui_th_got]
    mov QWORD PTR [rax+rbx*8], r13
    xor eax, eax
    add rsp, 65600
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

// gui_start_index: una indexación al abrir (hilo indexer, índice persistente).
// Tablas grandes (64MB records) + modo índice (guarda todo, no emite).
gui_start_index:
    push rbx
    sub rsp, 80
    // indice nuevo -> el cursor del barrido vuelve a 0
    lea rax, [rip + gui_sweep_cursor]
    mov QWORD PTR [rax], 0
    // firma de 64 bits por record: 12M registros x 8 bytes = 96MB (RESERVE;
    // las paginas se commitean al escribirse). Se reutiliza entre reindexes.
    lea rax, [rip + gui_bloom]
    cmp QWORD PTR [rax], 0
    jne gsi_bloom_ok
    // VirtualAlloc(lpAddress=NULL, dwSize=96MB, MEM_RESERVE, PAGE_READWRITE)
    xor ecx, ecx
    mov edx, 0x6000000
    mov r8d, 0x3000
    mov r9d, 4
    xor r10d, r10d
    call VirtualAlloc
    test rax, rax
    jz gsi_bloom_ok
    lea rdx, [rip + gui_bloom]
    mov QWORD PTR [rdx], rax
gsi_bloom_ok:
    lea rax, [rip + scan_bloom]
    mov rcx, QWORD PTR [rip + gui_bloom]
    mov QWORD PTR [rax], rcx
    lea rax, [rip + scan_big_rec]
    mov QWORD PTR [rax], 1
    lea rax, [rip + scan_opt_index]
    mov QWORD PTR [rax], 1
    call ws_create
    test rax, rax
    jz gsi_ret
    lea rcx, [rip + gui_idx_ws]
    mov QWORD PTR [rcx], rax
    lea rax, [rip + gui_gen]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov r9, rdx
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + gui_indexer]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    test rax, rax
    jz gsi_thfail
    lea rcx, [rip + gui_hthread]
    mov QWORD PTR [rcx], rax
    jmp gsi_ret
gsi_thfail:
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    call ws_free
    lea rax, [rip + gui_idx_ws]
    mov QWORD PTR [rax], 0
gsi_ret:
    add rsp, 80
    pop rbx
    ret

// gui_reindex: F5 manual. Join total al indexer, ws nuevo, re-indexa.
// Frame 72. Espera INFINITE (corrección antes que latencia en F5).
gui_reindex:
    push rbx
    sub rsp, 72
    lea rax, [rip + gui_gen]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    mov QWORD PTR [rsp+48], rdx
    mov rcx, QWORD PTR [rip + gui_hthread]
    test rcx, rcx
    jz gri_nothr
    mov edx, -1
    call WaitForSingleObject
    mov rcx, QWORD PTR [rip + gui_hthread]
    call CloseHandle
    lea rax, [rip + gui_hthread]
    mov QWORD PTR [rax], 0
    // join al repair (si corre): el gen nuevo lo aborta; el join acota
    mov rcx, QWORD PTR [rip + gui_hrepair]
    test rcx, rcx
    jz gri_nothr
    mov edx, -1
    call WaitForSingleObject
gri_nothr:
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gri_nofree
    call ws_free
gri_nofree:
    lea rax, [rip + gui_idx_ws]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_idx_ready]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_prevlen]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_files]
    mov QWORD PTR [rax], 0
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz gri_nolist
    mov edx, LVM_SETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
gri_nolist:
    call ws_create
    test rax, rax
    jz gri_ret
    lea rcx, [rip + gui_idx_ws]
    mov QWORD PTR [rcx], rax
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + gui_indexer]
    mov r9, QWORD PTR [rsp+48]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    test rax, rax
    jz gri_thfail
    lea rcx, [rip + gui_hthread]
    mov QWORD PTR [rcx], rax
    jmp gri_ret
gri_thfail:
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    call ws_free
    lea rax, [rip + gui_idx_ws]
    mov QWORD PTR [rax], 0
gri_ret:
    add rsp, 72
    pop rbx
    ret

// gui_indexer: RCX=mygen. Indexa todos los discos FIXED/REMOVABLE en el ws
// persistente (un scan_root_ws por unidad, records acumulados).
// Progreso por disco vía GUI_APP_PROG; fin vía GUI_APP_DONE.
// Frame 168: +64 mygen, +72 drive, +112 drives, +136 freq, +144 t0, +152 t1.
gui_indexer:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 168
    mov QWORD PTR [rsp+64], rcx
    mov rbx, QWORD PTR [rip + gui_idx_ws]
    test rbx, rbx
    jz gix_abort
    lea rcx, [rsp+136]
    call QueryPerformanceFrequency
    lea rcx, [rsp+144]
    call QueryPerformanceCounter
    lea rax, [rip + gui_disks]
    mov QWORD PTR [rax], 0
    call GetLogicalDrives
    mov DWORD PTR [rsp+112], eax
    mov DWORD PTR [rsp+72], 0
gix_drive:
    mov eax, DWORD PTR [rsp+72]
    cmp eax, 26
    jae gix_finish
    mov ecx, eax
    mov eax, 1
    shl eax, cl
    test eax, DWORD PTR [rsp+112]
    jz gix_dnext
    mov eax, DWORD PTR [rsp+72]
    add eax, 0x41
    lea rcx, [rip + gui_drivebuf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + gui_drivebuf]
    call GetDriveTypeW
    cmp eax, 2
    je gix_dvalid
    cmp eax, 3
    jne gix_dnext
gix_dvalid:
    lea rax, [rip + gui_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    lea rax, [rip + gui_gen]
    mov rax, QWORD PTR [rax]
    cmp rax, QWORD PTR [rsp+64]
    jne gix_abort
    mov eax, DWORD PTR [rsp+72]
    add eax, 0x41
    mov WORD PTR [rsp+120], ax
    mov WORD PTR [rsp+122], 0x3A
    mov WORD PTR [rsp+124], 0x5C
    mov WORD PTR [rsp+126], 0
    mov rcx, rbx
    lea rdx, [rsp+120]
    mov r8d, 3
    call scan_root_ws
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, GUI_APP_PROG
    mov r8, QWORD PTR [rsp+64]
    xor r9d, r9d
    call PostMessageW
gix_dnext:
    mov eax, DWORD PTR [rsp+72]
    inc eax
    mov DWORD PTR [rsp+72], eax
    jmp gix_drive
gix_finish:
    lea rcx, [rsp+152]
    call QueryPerformanceCounter
    mov rax, QWORD PTR [rsp+152]
    sub rax, QWORD PTR [rsp+144]
    mov r15, rax
    mov rax, QWORD PTR [rsp+136]
    test rax, rax
    jz gix_mszero
    mov rcx, 1000
    mov rax, r15
    mul rcx
    div QWORD PTR [rsp+136]
    mov r15, rax
    jmp gix_msok
gix_mszero:
    xor r15d, r15d
gix_msok:
    lea rax, [rip + gui_ms]
    mov QWORD PTR [rax], r15
    mov rcx, rbx
    call scan_ws_files
    lea rdx, [rip + gui_files]
    mov QWORD PTR [rdx], rax
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_idx_ready]
    mov QWORD PTR [rax], 1
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, GUI_APP_DONE
    mov r8, QWORD PTR [rsp+64]
    xor r9d, r9d
    call PostMessageW
    xor eax, eax
    jmp gix_ret
gix_abort:
    mov eax, 1
gix_ret:
    add rsp, 168
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_idx_path: ECX=recidx -> RAX=path WCHAR sin \\?\ (gui_strip), 0 si falla.
// build_path + MBTWC + strip. Solo hilo UI (indexer quieto o listo).
gui_idx_path:
    push rbx
    // 128 segmentos x 16B desde rsp+128 = rsp+2176: frame 2224 (16-aligned)
    sub rsp, 2224
    mov r11d, ecx
    // Race fix: build_path usa cache+buffers (BPCIDX/DIRPATH/SEG) del ws que
    // el indexer escribe en su DFS. Solo con idx_ready el ws está quieto.
    lea rax, [rip + gui_idx_ready]
    cmp QWORD PTR [rax], 0
    je gip_indexing
    mov rbx, QWORD PTR [rip + gui_idx_ws]
    test rbx, rbx
    jz gip_no
    // tombstone (delta): nombre nulo -> sin ruta (r11d intacto p/build_path)
    mov rax, QWORD PTR [rbx + WS_REC]
    mov edx, r11d
    imul rdx, rdx, 12
    mov rax, QWORD PTR [rax+rdx]
    test rax, rax
    jz gip_no
    // skc_path_for(rec, idx, buf, buflen) -> largo en WCHAR sin NUL (0 = fallo).
    // Arma la ruta SOLO leyendo el array de records (sin cache ni buffers del
    // ws): la reparacion puede estar reescribiendo WB_SEG/WB_DIRPATH en otro
    // hilo sin corromper este path.
    mov rcx, QWORD PTR [rbx + WS_REC]
    mov edx, r11d
    lea r8, [rip + gui_pathw]
    mov r9d, 32768
    call skc_path_for
    test rax, rax
    jz gip_no
    mov ecx, eax
    lea rsi, [rip + gui_pathw]
    lea rdi, [rip + gui_strip]
    call gui_strip_prefix
    lea rax, [rip + gui_strip]
    jmp gip_ret
gip_indexing:
    cld
    mov rbx, QWORD PTR [rip + gui_idx_ws]
    test rbx, rbx
    jz gip_no
    // tombstone del record pedido: nombre nulo -> sin ruta
    mov rax, QWORD PTR [rbx + WS_REC]
    mov edx, r11d
    imul rdx, rdx, 12
    mov rax, QWORD PTR [rax + rdx]
    test rax, rax
    jz gip_no
    // recolectar segmentos (hoja -> raiz) en rsp+128 (max 128 niveles)
    xor r12d, r12d
    mov r13d, r11d
gip_idx_collect:
    cmp r12d, 128
    jae gip_no
    mov rax, QWORD PTR [rbx + WS_REC]
    mov edx, r13d
    imul rdx, rdx, 12
    mov rax, QWORD PTR [rax + rdx]
    test rax, rax
    jz gip_no
    mov r8, r12
    shl r8, 4
    lea r9, [rsp + 128]
    mov QWORD PTR [r9 + r8], rax
    movzx eax, WORD PTR [rax - 2]
    mov QWORD PTR [r9 + r8 + 8], rax
    inc r12d
    mov rax, QWORD PTR [rbx + WS_REC]
    mov edx, r13d
    imul rdx, rdx, 12
    mov eax, DWORD PTR [rax + rdx + 8]
    cmp eax, 0xFFFFFFFF
    je gip_idx_have_all
    and eax, 0x7FFFFFFF
    mov r13d, eax
    jmp gip_idx_collect
gip_idx_have_all:
    // longitud total (raiz -> hoja), con separadores
    xor r10d, r10d
    mov r8d, r12d
    dec r8d
gip_idx_totloop:
    cmp r8d, 0
    jl gip_idx_totdone
    mov eax, r12d
    dec eax
    cmp r8d, eax
    je gip_idx_totnosep
    inc r10d
gip_idx_totnosep:
    mov r9, r8
    shl r9, 4
    lea rax, [rsp + 128]
    mov rax, QWORD PTR [rax + r9 + 8]
    add r10d, eax
    cmp r10d, 100000
    ja gip_no
    dec r8d
    jmp gip_idx_totloop
gip_idx_totdone:
    // construir en gui_pathbuf (UTF-8)
    xor r10d, r10d
    mov r8d, r12d
    dec r8d
gip_idx_buildloop:
    cmp r8d, 0
    jl gip_idx_builtdone
    mov eax, r12d
    dec eax
    cmp r8d, eax
    je gip_idx_buildnosep
    test r10d, r10d
    jz gip_idx_buildnosep
    lea rax, [rip + gui_pathbuf]
    cmp BYTE PTR [rax + r10 - 1], 0x5C
    je gip_idx_buildnosep
    lea rax, [rip + gui_pathbuf]
    mov BYTE PTR [rax + r10], 0x5C
    inc r10d
gip_idx_buildnosep:
    mov r9, r8
    shl r9, 4
    lea rax, [rsp + 128]
    mov rsi, QWORD PTR [rax + r9]
    mov ecx, DWORD PTR [rax + r9 + 8]
    test ecx, ecx
    jz gip_idx_buildnext
    lea rdi, [rip + gui_pathbuf]
    add rdi, r10
    rep movsb
    mov r9, r8
    shl r9, 4
    lea rax, [rsp + 128]
    mov eax, DWORD PTR [rax + r9 + 8]
    add r10d, eax
gip_idx_buildnext:
    dec r8d
    jmp gip_idx_buildloop
gip_idx_builtdone:
    lea rax, [rip + gui_pathbuf]
    mov BYTE PTR [rax + r10], 0
    // MultiByteToWideChar -> gui_convpath, luego strip -> gui_strip
    mov r9d, r10d
    mov rcx, 65001
    xor edx, edx
    lea r8, [rip + gui_pathbuf]
    lea rax, [rip + gui_convpath]
    mov QWORD PTR [rsp + 32], rax
    mov QWORD PTR [rsp + 40], 32768
    call MultiByteToWideChar
    test eax, eax
    jz gip_no
    lea rsi, [rip + gui_convpath]
    mov ecx, eax
    lea rdi, [rip + gui_strip]
    call gui_strip_prefix
    lea rax, [rip + gui_strip]
    jmp gip_ret
gip_no:
    xor eax, eax
gip_ret:
    add rsp, 2224
    pop rbx
    ret

// gui_worker(RCX=gen). Escanea todos los discos fijos+extraibles.
// Locales: +64 mygen, +72 drive, +80 qlen, +96 prog, +100 dirlen,
//   +104 flen, +108 isdir, +112 stash, +120 stash2, +128 scratch,
//   +136 freq, +144 t0, +152 t1.
// No-volatiles: RBX=sp temp/dir, R12=qptr, R13=qlen, R14=hFind, R15=attrs.
gui_worker:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 168
    mov QWORD PTR [rsp+64], rcx
    lea rax, [rip + gui_query]
    mov r12, rax
    mov rax, QWORD PTR [rip + gui_qlen]
    mov r13, rax
    mov QWORD PTR [rsp+80], rax
    lea rcx, [rsp+136]
    call QueryPerformanceFrequency
    lea rcx, [rsp+144]
    call QueryPerformanceCounter
    lea rax, [rip + gui_files]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_disks]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_trunc]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_sp]
    mov QWORD PTR [rax], 0
    test r13, r13
    jz gw_finish
    call GetLogicalDrives
    mov DWORD PTR [rsp+112], eax
    mov DWORD PTR [rsp+72], 0
gw_drive:
    mov eax, DWORD PTR [rsp+72]
    cmp eax, 26
    jae gw_pop0
    mov ecx, eax
    mov eax, 1
    shl eax, cl
    test eax, DWORD PTR [rsp+112]
    jz gw_dnext
    mov eax, DWORD PTR [rsp+72]
    add eax, 0x41
    lea rcx, [rip + gui_drivebuf]
    mov WORD PTR [rcx], ax
    mov WORD PTR [rcx+2], 0x3A
    mov WORD PTR [rcx+4], 0x5C
    mov WORD PTR [rcx+6], 0
    lea rcx, [rip + gui_drivebuf]
    call GetDriveTypeW
    cmp eax, 2
    je gw_dvalid
    cmp eax, 3
    jne gw_dnext
gw_dvalid:
    lea rax, [rip + gui_disks]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    // root "\\?\X:\" (8 WCHAR con NUL = 16B) via arena
    mov ecx, 16
    call arena_alloc
    test rax, rax
    jz gw_dnext
    mov WORD PTR [rax], 0x5C
    mov WORD PTR [rax+2], 0x5C
    mov WORD PTR [rax+4], 0x3F
    mov WORD PTR [rax+6], 0x5C
    mov edx, DWORD PTR [rsp+72]
    add edx, 0x41
    mov WORD PTR [rax+8], dx
    mov WORD PTR [rax+10], 0x3A
    mov WORD PTR [rax+12], 0x5C
    mov WORD PTR [rax+14], 0
    lea rcx, [rip + gui_sp]
    mov rcx, QWORD PTR [rcx]
    cmp rcx, GUI_STACKMAX
    jae gw_dnext
    lea rdx, [rip + gui_stack]
    mov QWORD PTR [rdx+rcx*8], rax
    lea rdx, [rip + gui_sp]
    inc rcx
    mov QWORD PTR [rdx], rcx
gw_dnext:
    mov eax, DWORD PTR [rsp+72]
    inc eax
    mov DWORD PTR [rsp+72], eax
    jmp gw_drive
gw_pop0:
    lea rax, [rip + gui_sp]
    mov rax, QWORD PTR [rax]
    test rax, rax
    jz gw_finish
    dec rax
    lea rdx, [rip + gui_sp]
    mov QWORD PTR [rdx], rax
    lea rdx, [rip + gui_stack]
    mov rbx, QWORD PTR [rdx+rax*8]
    // gen?
    lea rax, [rip + gui_gen]
    mov rax, QWORD PTR [rax]
    cmp rax, QWORD PTR [rsp+64]
    jne gw_abort
    // dirlen = wcslen(dir)
    mov rcx, rbx
    call gui_wcslen
    cmp rax, 32760
    jae gw_pop0
    mov DWORD PTR [rsp+100], eax
    // patron = dir + (sep?) + "*" en gui_pat
    lea rsi, [rip + gui_stack]
    mov rsi, rbx
    lea rdi, [rip + gui_pat]
    mov ecx, DWORD PTR [rsp+100]
    rep movsw
    cmp WORD PTR [rdi-2], 0x5C
    je gw_star
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
gw_star:
    mov WORD PTR [rdi], 0x2A
    mov WORD PTR [rdi+2], 0
    lea rcx, [rip + gui_pat]
    lea rdx, [rip + gui_find]
    call FindFirstFileW
    cmp rax, -1
    je gw_pop0
    mov r14, rax
    jmp gw_entry
gw_entry:
    lea rax, [rip + gui_find]
    mov r15d, DWORD PTR [rax]
    lea rsi, [rax+44]
    xor ecx, ecx
gw_flen:
    cmp ecx, 260
    jae gw_flencap
    movzx edx, WORD PTR [rsi+rcx*2]
    test edx, edx
    jz gw_flendone
    inc ecx
    jmp gw_flen
gw_flencap:
    mov ecx, 260
gw_flendone:
    mov DWORD PTR [rsp+104], ecx
    cmp ecx, 1
    jne gw_not1
    cmp WORD PTR [rsi], 0x2E
    je gw_next
gw_not1:
    cmp ecx, 2
    jne gw_not2
    cmp WORD PTR [rsi], 0x2E
    jne gw_not2
    cmp WORD PTR [rsi+2], 0x2E
    je gw_next
gw_not2:
    test r15d, 0x400
    jnz gw_next
    mov eax, 0
    test r15d, 0x10
    jz gw_filed
    mov eax, 1
gw_filed:
    mov DWORD PTR [rsp+108], eax
    // gen cada entry (cancelacion rapida)
    lea rax, [rip + gui_gen]
    mov rax, QWORD PTR [rax]
    cmp rax, QWORD PTR [rsp+64]
    jne gw_close_abort
    // hijo = padre + sep + nombre en gui_child
    lea rsi, [rip + gui_pat]
    mov rsi, rbx
    lea rdi, [rip + gui_child]
    mov ecx, DWORD PTR [rsp+100]
    rep movsw
    movzx edx, WORD PTR [rdi-2]
    cmp edx, 0x5C
    je gw_copyn
    mov WORD PTR [rdi], 0x5C
    add rdi, 2
    mov eax, DWORD PTR [rsp+100]
    inc eax
    jmp gw_copyn2
gw_copyn:
    mov eax, DWORD PTR [rsp+100]
gw_copyn2:
    mov ecx, DWORD PTR [rsp+104]
    add eax, ecx
    cmp eax, 32760
    jae gw_next
    mov DWORD PTR [rsp+128], eax
    lea rsi, [rip + gui_find]
    add rsi, 44
    rep movsw
    mov WORD PTR [rdi], 0
    lea rsi, [rip + gui_child]
    mov ecx, DWORD PTR [rsp+128]
    call path_is_excluded
    test eax, eax
    jnz gw_next
    lea rax, [rip + gui_files]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    // progreso cada 2048
    test rdx, 2047
    jnz gw_match
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, GUI_APP_PROG
    mov r8, QWORD PTR [rsp+64]
    xor r9d, r9d
    push rax
    push rdx
    call PostMessageW
    pop rdx
    pop rax
gw_match:
    lea rcx, [rip + gui_find]
    add rcx, 44
    mov edx, DWORD PTR [rsp+104]
    mov r8, r12
    mov r9, r13
    call contains_ci
    test eax, eax
    jz gw_nomatch
    // HIT: total++ y guardar (cap 100K)
    lea rax, [rip + gui_total]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    lea rax, [rip + gui_count]
    mov rax, QWORD PTR [rax]
    cmp rax, GUI_MAXDISPLAY
    jae gw_isdir_push
    mov QWORD PTR [rsp+112], rax
    // strip \\?\ -> display+shel
    lea rsi, [rip + gui_child]
    mov ecx, DWORD PTR [rsp+128]
    lea rdi, [rip + gui_strip]
    call gui_strip_prefix
    // arena copy (len+1)*2
    mov ecx, eax
    inc ecx
    add ecx, ecx
    call arena_alloc
    test rax, rax
    jz gw_trunc
    mov QWORD PTR [rsp+120], rax
    mov ecx, DWORD PTR [rsp+128]
    lea rsi, [rip + gui_strip]
    // ojo: gui_strip len puede diferir (UNC); recalcular
    mov rcx, rsi
    call gui_wcslen
    mov ecx, eax
    inc ecx
    lea rdi, [rip + gui_strip]
    mov rdi, QWORD PTR [rsp+120]
    rep movsw
    lea rax, [rip + gui_items]
    mov rdx, QWORD PTR [rsp+112]
    mov rcx, QWORD PTR [rsp+120]
    mov QWORD PTR [rax+rdx*8], rcx
    lea rax, [rip + gui_count]
    mov rdx, QWORD PTR [rax]
    inc rdx
    mov QWORD PTR [rax], rdx
    jmp gw_isdir_push
gw_nomatch:
    mov eax, DWORD PTR [rsp+108]
    test eax, eax
    jz gw_next
    // dir no-match: push (copia arena del hijo con prefijo)
    mov ecx, DWORD PTR [rsp+128]
    inc ecx
    add ecx, ecx
    call arena_alloc
    test rax, rax
    jz gw_trunc
    mov QWORD PTR [rsp+120], rax
    lea rsi, [rip + gui_child]
    mov rdi, rax
    mov ecx, DWORD PTR [rsp+128]
    inc ecx
    rep movsw
    lea rax, [rip + gui_sp]
    mov rax, QWORD PTR [rax]
    cmp rax, GUI_STACKMAX
    jae gw_next
    lea rdx, [rip + gui_stack]
    mov rcx, QWORD PTR [rsp+120]
    mov QWORD PTR [rdx+rax*8], rcx
    lea rdx, [rip + gui_sp]
    inc rax
    mov QWORD PTR [rdx], rax
    jmp gw_next
gw_isdir_push:
    mov eax, DWORD PTR [rsp+108]
    test eax, eax
    jz gw_next
    mov ecx, DWORD PTR [rsp+128]
    inc ecx
    add ecx, ecx
    call arena_alloc
    test rax, rax
    jz gw_trunc
    mov QWORD PTR [rsp+120], rax
    lea rsi, [rip + gui_child]
    mov rdi, rax
    mov ecx, DWORD PTR [rsp+128]
    inc ecx
    rep movsw
    lea rax, [rip + gui_sp]
    mov rax, QWORD PTR [rax]
    cmp rax, GUI_STACKMAX
    jae gw_next
    lea rdx, [rip + gui_stack]
    mov rcx, QWORD PTR [rsp+120]
    mov QWORD PTR [rdx+rax*8], rcx
    lea rdx, [rip + gui_sp]
    inc rax
    mov QWORD PTR [rdx], rax
    jmp gw_next
gw_trunc:
    lea rax, [rip + gui_trunc]
    mov QWORD PTR [rax], 1
gw_next:
    mov rcx, r14
    lea rdx, [rip + gui_find]
    call FindNextFileW
    test eax, eax
    jnz gw_entry
    mov rcx, r14
    call FindClose
    jmp gw_pop0
gw_close_abort:
    mov rcx, r14
    call FindClose
gw_abort:
    mov eax, 1
    jmp gw_epilogue
gw_finish:
    lea rcx, [rsp+152]
    call QueryPerformanceCounter
    mov rax, QWORD PTR [rsp+152]
    sub rax, QWORD PTR [rsp+144]
    mov r15, rax
    mov rax, QWORD PTR [rsp+136]
    test rax, rax
    jz gw_mszero
    mov rcx, 1000
    mov rax, r15
    mul rcx
    div QWORD PTR [rsp+136]
    mov r15, rax
    jmp gw_msok
gw_mszero:
    xor r15d, r15d
gw_msok:
    lea rax, [rip + gui_ms]
    mov QWORD PTR [rax], r15
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, GUI_APP_DONE
    mov r8, QWORD PTR [rsp+64]
    xor r9d, r9d
    call PostMessageW
    xor eax, eax
gw_epilogue:
    add rsp, 168
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_wcslen(RCX=ptr) -> RAX=len cap 32768. Leaf.
gui_wcslen:
    xor eax, eax
gui_wl:
    cmp rax, 32768
    jae gui_wlret
    cmp WORD PTR [rcx+rax*2], 0
    je gui_wlret
    inc rax
    jmp gui_wl
gui_wlret:
    ret

// gui_strip_prefix(RSI=src con \\?\, ECX=len, RDI=dst) -> EAX=len dst.
// \\?\UNC\srv\sh -> \\srv\sh ; \\?\X:\.. -> X:\.. ; sin prefijo -> copia.
gui_strip_prefix:
    cmp ecx, 8
    jb gui_sp_copy
    mov eax, DWORD PTR [rsi]
    cmp eax, 0x005C005C
    jne gui_sp_copy
    movzx eax, WORD PTR [rsi+4]
    cmp eax, 0x3F
    jne gui_sp_copy
    movzx eax, WORD PTR [rsi+6]
    cmp eax, 0x5C
    jne gui_sp_copy
    movzx eax, WORD PTR [rsi+8]
    cmp eax, 0x55
    jne gui_sp_skip4
    movzx eax, WORD PTR [rsi+10]
    cmp eax, 0x4E
    jne gui_sp_skip4
    movzx eax, WORD PTR [rsi+12]
    cmp eax, 0x43
    jne gui_sp_skip4
    movzx eax, WORD PTR [rsi+14]
    cmp eax, 0x5C
    jne gui_sp_skip4
    // UNC: "\\" + resto (salta 8)
    mov WORD PTR [rdi], 0x5C
    mov WORD PTR [rdi+2], 0x5C
    add rdi, 4
    add rsi, 16
    sub ecx, 8
    jmp gui_sp_rest
gui_sp_skip4:
    add rsi, 8
    sub ecx, 4
    jmp gui_sp_rest
gui_sp_copy:
gui_sp_rest:
    mov eax, ecx
    rep movsw
    mov WORD PTR [rdi], 0
    ret

// gui_refresh_final(RCX=hwnd): SetItemCount + status + titulo.
gui_refresh_final:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_SETITEMCOUNT
    mov r8, QWORD PTR [rip + gui_count]
    xor r9d, r9d
    call SendMessageW
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_status
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_title
    call gui_update_empty
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_refresh_prog(RCX=hwnd): igual pero sin titulo final (titulo tambien).
gui_refresh_prog:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_SETITEMCOUNT
    mov r8, QWORD PTR [rip + gui_count]
    mov r9d, 1
    call SendMessageW
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_status
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_title
    call gui_update_empty
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_update_title(RCX=hwnd): bar -> "seek" fijo; window -> "seek-gui - T resultados (F arch)".
gui_update_title:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gut_win
    mov rcx, QWORD PTR [rsp+40]
    lea rdx, [rip + gui_title_bar]
    call SetWindowTextW
    jmp gut_ret
gut_win:
    lea rdi, [rip + gui_titlebuf]
    lea rsi, [rip + gui_titlepre]
    mov ecx, 11
    rep movsw
    mov rcx, QWORD PTR [rip + gui_total]
    lea rdx, [rsp+72]
    call gui_wdec
    mov rsi, rax
    lea rcx, [rsp+72]
    sub rcx, rsi
    shr rcx, 1
    rep movsw
    lea rsi, [rip + gui_titlemid]
    mov ecx, 14
    rep movsw
    mov rcx, QWORD PTR [rip + gui_files]
    lea rdx, [rsp+72]
    call gui_wdec
    mov rsi, rax
    lea rcx, [rsp+72]
    sub rcx, rsi
    shr rcx, 1
    rep movsw
    lea rsi, [rip + gui_titlesuf]
    mov ecx, 7
    rep movsw
    mov WORD PTR [rdi], 0
    mov rcx, QWORD PTR [rsp+40]
    lea rdx, [rip + gui_titlebuf]
    call SetWindowTextW
gut_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_wdec(RCX=valor, RDX=fin buf 64B WCHAR) -> RAX=inicio digitos.
gui_wdec:
    mov r8, rdx
    mov rax, rcx
    mov r9, r8
    mov r10, 10
    test rax, rax
    jnz gui_wd_loop
    sub r9, 2
    mov WORD PTR [r9], 0x30
    mov rax, r9
    ret
gui_wd_loop:
    xor edx, edx
    div r10
    add edx, 0x30
    sub r9, 2
    mov WORD PTR [r9], dx
    test rax, rax
    jnz gui_wd_loop
    mov rax, r9
    ret

// gui_update_status(RCX=hwnd): 5 partes en statusbar.
gui_update_status:
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
    // parte 0 idx=
    lea rcx, [rip + gui_sb0]
    lea rdx, [rip + gui_p_idx]
    mov r8d, 4
    mov r9, QWORD PTR [rip + gui_files]
    call gui_fmt_part
    // parte 1 coincidencias=
    lea rcx, [rip + gui_sb1]
    lea rdx, [rip + gui_p_match]
    mov r8d, 14
    mov r9, QWORD PTR [rip + gui_total]
    call gui_fmt_part
    // parte 2 filtro=Nms (QPC alrededor del filtrado incremental/paralelo)
    lea rcx, [rip + gui_sb2]
    lea rdx, [rip + gui_p_time]
    mov r8d, 7
    mov r9, QWORD PTR [rip + gui_ms]
    call gui_fmt_part_ms
    // parte 3 arena=NKB (del índice; 0 si aún no hay)
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gus_noarena
    call ws_used
    jmp gus_havearena
gus_noarena:
    xor eax, eax
gus_havearena:
    shr rax, 10
    mov QWORD PTR [rsp+72], rax
    lea rcx, [rip + gui_sb3]
    lea rdx, [rip + gui_p_arena]
    mov r8d, 6
    mov r9, QWORD PTR [rsp+72]
    call gui_fmt_part_kb
    // parte 4 discos=N
    lea rcx, [rip + gui_sb4]
    lea rdx, [rip + gui_p_disk]
    mov r8d, 7
    mov r9, QWORD PTR [rip + gui_disks]
    call gui_fmt_part
    // linea unica "sb0 · sb1 · sb2 · sb3 · sb4" en gui_sbline (partes
    // contiguas de 192 bytes). RBX=base parte, RDI=dst, R12=restantes.
    lea rbx, [rip + gui_sb0]
    lea rdi, [rip + gui_sbline]
    mov r12d, 5
gui_sb_part:
    mov rsi, rbx
gui_sb_ch:
    mov ax, WORD PTR [rsi]
    test ax, ax
    jz gui_sb_sep
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    jmp gui_sb_ch
gui_sb_sep:
    dec r12d
    jz gui_sb_end
    mov WORD PTR [rdi], 0x20
    mov WORD PTR [rdi+2], 0xB7
    mov WORD PTR [rdi+4], 0x20
    add rdi, 6
    add rbx, 192
    jmp gui_sb_part
gui_sb_end:
    mov WORD PTR [rdi], 0
    mov rcx, QWORD PTR [rip + gui_status]
    lea rdx, [rip + gui_sbline]
    call SetWindowTextW
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

// gui_fmt_part(RCX=dst, RDX=prefijo, R8=prelen, R9=valor) -> "pre+NUL".
gui_fmt_part:
    push rbx
    mov rbx, rcx
    mov rsi, rdx
    mov rdi, rcx
    mov ecx, r8d
    rep movsw
    mov rcx, r9
    sub rsp, 80
    lea rdx, [rsp+64]
    call gui_wdec
    mov rsi, rax
    lea rcx, [rsp+64]
    sub rcx, rsi
    shr rcx, 1
    rep movsw
    mov WORD PTR [rdi], 0
    add rsp, 80
    mov rax, rbx
    pop rbx
    ret

// gui_fmt_part_ms: "tiempo=Nms".
gui_fmt_part_ms:
    push rbx
    mov rbx, rcx
    mov rsi, rdx
    mov rdi, rcx
    mov ecx, r8d
    rep movsw
    mov rcx, r9
    sub rsp, 80
    lea rdx, [rsp+64]
    call gui_wdec
    mov rsi, rax
    lea rcx, [rsp+64]
    sub rcx, rsi
    shr rcx, 1
    rep movsw
    mov WORD PTR [rdi], 0x6D
    mov WORD PTR [rdi+2], 0x73
    mov WORD PTR [rdi+4], 0
    add rsp, 80
    mov rax, rbx
    pop rbx
    ret

// gui_fmt_part_kb: "arena=NKB".
gui_fmt_part_kb:
    push rbx
    mov rbx, rcx
    mov rsi, rdx
    mov rdi, rcx
    mov ecx, r8d
    rep movsw
    mov rcx, r9
    sub rsp, 80
    lea rdx, [rsp+64]
    call gui_wdec
    mov rsi, rax
    lea rcx, [rsp+64]
    sub rcx, rsi
    shr rcx, 1
    rep movsw
    mov WORD PTR [rdi], 0x4B
    mov WORD PTR [rdi+2], 0x42
    mov WORD PTR [rdi+4], 0
    add rsp, 80
    mov rax, rbx
    pop rbx
    ret

// gui_update_empty(): muestra "Sin resultados" si hay query sin matches,
// lo oculta en cualquier otro caso. Leaf con frame para el call.
gui_update_empty:
    push rbx
    sub rsp, 64
    mov rax, QWORD PTR [rip + gui_count]
    test rax, rax
    jnz gue_hide
    call gui_edit_len
    test rax, rax
    jz gue_hide
    mov rcx, QWORD PTR [rip + gui_hempty]
    test rcx, rcx
    jz gue_ret
    mov edx, SW_SHOWNA
    call ShowWindow
    mov rcx, QWORD PTR [rip + gui_hempty]
    mov rdx, 0
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x13
    call SetWindowPos
    mov rcx, QWORD PTR [rip + gui_hempty]
    xor edx, edx
    mov r8d, 1
    call InvalidateRect
    jmp gue_ret
gue_hide:
    mov rcx, QWORD PTR [rip + gui_hempty]
    test rcx, rcx
    jz gue_ret
    xor edx, edx
    call ShowWindow
gue_ret:
    add rsp, 64
    pop rbx
    ret

// gui_custom_draw(RCX=NMHDR*) -> EAX=CDRF. Solo el ListView propio:
// PREPAINT->NOTIFYITEMDRAW; ITEMPREPAINT->texto #F2F2F2 sobre #1E1E1E,
// seleccion #DC783A (texto blanco), hot-track sutil + NEWFONT. Leaf sin
// calls (sin requisitos de pila). El status ahora es STATIC (una linea via
// SetWindowTextW): su oscuro va por CTLCOLORSTATIC, sin SB_*.
gui_custom_draw:
    mov rax, QWORD PTR [rip + gui_list]
    cmp QWORD PTR [rcx], rax
    jne gcd_def
    mov eax, DWORD PTR [rcx+16]
    cmp eax, NM_CUSTOMDRAW
    jne gcd_def
    mov eax, DWORD PTR [rcx+24]
    cmp eax, CDDS_PREPAINT
    je gcd_pre
    cmp eax, CDDS_ITEMPREPAINT
    je gcd_item
gcd_def:
    xor eax, eax
    ret
gcd_pre:
    mov eax, CDRF_NOTIFYITEMDRAW
    ret
gcd_item:
    // Seleccion VERIFICADA en vivo (LVM_GETITEMSTATE): el uItemState del
    // paint llega con SELECTED stale para todas las filas en lluvias de
    // SetItemCount (medido: ST=0x201 con selected=0). La verdad en vivo
    // coincide siempre con la seleccion real (flechas/click).
    sub rsp, 48
    mov QWORD PTR [rsp+32], rcx
    mov rax, QWORD PTR [rcx+56]
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETITEMSTATE
    mov r8, rax
    mov r9d, LVIS_SELECTED
    call SendMessageW
    mov rcx, QWORD PTR [rsp+32]
    add rsp, 48
    test eax, eax
    jnz gcd_sel
    mov eax, DWORD PTR [rcx+64]
    test eax, CDIS_HOT
    jnz gcd_hot
    test eax, CDIS_HOT
    jnz gcd_hot
    mov DWORD PTR [rcx+80], 0xF2F2F2
    mov DWORD PTR [rcx+84], 0x1E1E1E
    jmp gcd_new
gcd_sel:
    mov DWORD PTR [rcx+80], 0xFFFFFF
    mov DWORD PTR [rcx+84], 0xF07800
    jmp gcd_new
gcd_hot:
    mov DWORD PTR [rcx+80], 0xF2F2F2
    mov DWORD PTR [rcx+84], 0x2D2D2D
gcd_new:
    mov eax, CDRF_NEWFONT
    ret

// gui_on_notify(RCX=NMHDR*). LVN_GETDISPINFO + ITEMACTIVATE.
gui_on_notify:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov eax, DWORD PTR [rcx+16]
    cmp eax, NM_CUSTOMDRAW
    je gui_noti_cd
    cmp eax, LVN_GETDISPINFO
    je gui_noti_disp
    cmp eax, LVN_COLUMNCLICK
    je gui_noti_colclick
    cmp eax, LVN_ITEMACTIVATE
    je gui_noti_act
    xor eax, eax
    jmp gui_noti_ret
gui_noti_cd:
    mov rcx, QWORD PTR [rsp+40]
    call gui_custom_draw
    jmp gui_noti_ret
gui_noti_disp:
    mov rcx, QWORD PTR [rsp+40]
    call gui_fill_item
    xor eax, eax
    jmp gui_noti_ret
gui_noti_colclick:
    mov rcx, QWORD PTR [rsp+40]
    call gui_sort_column
    xor eax, eax
    jmp gui_noti_ret
gui_noti_act:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_hist_push
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_open_focused
    xor eax, eax
gui_noti_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_fill_item(RCX=NMLVDISPINFO*). Sub 0=Nombre, 1=Carpeta.
gui_fill_item:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov eax, DWORD PTR [rcx+28]
    mov DWORD PTR [rsp+48], eax
    mov eax, DWORD PTR [rcx+32]
    mov DWORD PTR [rsp+52], eax
    mov rax, QWORD PTR [rcx+48]
    mov QWORD PTR [rsp+56], rax
    test rax, rax
    jz gui_fi_ret
    mov eax, DWORD PTR [rcx+56]
    test eax, eax
    jz gui_fi_ret
    lea rax, [rip + gui_count]
    mov edx, DWORD PTR [rsp+48]
    cmp rdx, QWORD PTR [rax]
    jae gui_fi_empty
    lea rax, [rip + gui_items]
    mov rax, QWORD PTR [rax+rdx*8]
    mov QWORD PTR [rsp+64], rax
    // Indexer activo: sin ruta (build_path es compartido). Col0 muestra el
    // nombre directo del record (seguro: recidx < rec_count contado); col1 vacía.
    lea rax, [rip + gui_idx_ready]
    cmp QWORD PTR [rax], 0
    jne gui_fi_ready
    cmp DWORD PTR [rsp+52], 0
    jne gui_fi_empty
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gui_fi_empty
    call scan_ws_recbase
    mov rdx, QWORD PTR [rsp+64]
    imul rdx, rdx, 12
    add rax, rdx
    mov rsi, QWORD PTR [rax]
    test rsi, rsi
    jz gui_fi_empty
    // El nombre vive en la arena como UTF-8 con prefijo WORD de bytes.
    // Convertir a WCHAR con CP_UTF8 (igual que gui_idx_path): antes rep movsw
    // copiaba bytes UTF-8 como WCHAR y cada par ASCII salia como CJK (mojibake).
    movzx r9d, WORD PTR [rsi-2]
    mov r10, QWORD PTR [rsp+40]
    mov eax, DWORD PTR [r10+56]
    test eax, eax
    jz gui_fi_ret
    dec eax
    mov rbx, QWORD PTR [rsp+40]
    mov rdi, QWORD PTR [rsp+56]
    mov rcx, 65001
    xor edx, edx
    mov r8, rsi
    mov QWORD PTR [rsp+32], rdi
    mov QWORD PTR [rsp+40], rax
    call MultiByteToWideChar
    mov QWORD PTR [rsp+40], rbx
    test eax, eax
    jz gui_fi_empty
    mov WORD PTR [rdi+rax*2], 0
    jmp gui_fi_ret
gui_fi_ready:
    // subitem 2 = fecha (mtime -> YYYY-MM-DD)
    cmp DWORD PTR [rsp+52], 2
    jne gui_fi_ready_path
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gui_fi_empty
    mov rax, QWORD PTR [rcx + WS_MTIME_BASE]
    test rax, rax
    jz gui_fi_empty
    mov rdx, QWORD PTR [rsp+64]
    shl rdx, 3
    mov rax, QWORD PTR [rax + rdx]
    test rax, rax
    jz gui_fi_empty
    mov QWORD PTR [rsp+32], rax
    lea rcx, [rsp+32]
    lea rdx, [rsp+16]
    call FileTimeToSystemTime
    test eax, eax
    jz gui_fi_empty
    mov rcx, QWORD PTR [rsp+56]
    lea rdx, [rip + gui_fmt_date]
    movzx r8d, WORD PTR [rsp+16]
    movzx r9d, WORD PTR [rsp+18]
    movzx eax, WORD PTR [rsp+22]
    mov QWORD PTR [rsp+32], rax
    call wsprintfW
    jmp gui_fi_ret
gui_fi_ready_path:
    mov rcx, QWORD PTR [rsp+64]
    call gui_idx_path
    test rax, rax
    jz gui_fi_empty
    mov QWORD PTR [rsp+32], rax
    mov rcx, rax
    call gui_wcslen
    mov QWORD PTR [rsp+24], rax
    mov eax, DWORD PTR [rsp+52]
    test eax, eax
    jz gui_fi_name
    // subitem 1 = carpeta: [0, lastsep)
    mov rcx, QWORD PTR [rsp+32]
    call gui_parent_len
    // rax = dirlen
    mov rdx, QWORD PTR [rsp+56]
    // cch = [dispinfo+56]
    mov r10, QWORD PTR [rsp+40]
    mov ecx, DWORD PTR [r10+56]
    dec ecx
    cmp eax, ecx
    jbe gui_fi_dok
    mov eax, ecx
gui_fi_dok:
    mov ecx, eax
    mov rdi, rdx
    test ecx, ecx
    jz gui_fi_dnull
    mov rsi, QWORD PTR [rsp+32]
    rep movsw
gui_fi_dnull:
    mov WORD PTR [rdi], 0
    jmp gui_fi_ret
gui_fi_name:
    // subitem 0 = nombre: desde lastsep+1
    mov rcx, QWORD PTR [rsp+32]
    call gui_parent_len
    // rax = lastsep pos (0 si no hay)
    mov rdx, QWORD PTR [rsp+32]
    cmp WORD PTR [rdx], 0
    je gui_fi_nfull
    mov rcx, QWORD PTR [rsp+24]
    test rax, rax
    jnz gui_fi_nsep
    // parent_len 0 pero hay texto: si empieza con sep? nombre completo
gui_fi_nfull:
    xor eax, eax
    jmp gui_fi_nhave
gui_fi_nsep:
    // si el path tiene sep en rax, nombre = rax+1 (salvo que len==pathlen?)
    inc rax
gui_fi_nhave:
    mov QWORD PTR [rsp+16], rax
    mov rdx, QWORD PTR [rsp+24]
    sub rdx, rax
    // rdx = namelen
    mov r10, QWORD PTR [rsp+40]
    mov ecx, DWORD PTR [r10+56]
    dec ecx
    cmp edx, ecx
    jbe gui_fi_nok
    mov edx, ecx
gui_fi_nok:
    mov ecx, edx
    test ecx, ecx
    jz gui_fi_nnull
    mov rdi, QWORD PTR [rsp+56]
    mov rsi, QWORD PTR [rsp+32]
    add rsi, QWORD PTR [rsp+16]
    add rsi, QWORD PTR [rsp+16]
    rep movsw
    mov WORD PTR [rdi], 0
    jmp gui_fi_icon
gui_fi_nnull:
    mov rdi, QWORD PTR [rsp+56]
    mov WORD PTR [rdi], 0
    jmp gui_fi_icon
gui_fi_empty:
    mov rax, QWORD PTR [rsp+56]
    mov WORD PTR [rax], 0
    // sin path: iImage=0 si lo piden
    mov rax, QWORD PTR [rsp+40]
    mov eax, DWORD PTR [rax+24]
    test eax, LVIF_IMAGE
    jz gui_fi_ret
    mov rax, QWORD PTR [rsp+40]
    mov DWORD PTR [rax+60], 0
    jmp gui_fi_ret
// BUG2: iImage por extension (solo subitem 0, solo si LVIF_IMAGE).
gui_fi_icon:
    mov rax, QWORD PTR [rsp+40]
    mov eax, DWORD PTR [rax+24]
    test eax, LVIF_IMAGE
    jz gui_fi_ret
    mov rax, QWORD PTR [rsp+40]
    mov eax, DWORD PTR [rax+32]
    test eax, eax
    jnz gui_fi_ret
    mov rax, QWORD PTR [rip + gui_himagelist]
    test rax, rax
    jz gui_fi_ret
    // is_dir desde el record (bit31 del parent)
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gui_fi_iconfile
    mov rax, QWORD PTR [rcx+80]
    test rax, rax
    jz gui_fi_iconfile
    mov rdx, QWORD PTR [rsp+64]
    imul rdx, rdx, 12
    mov eax, DWORD PTR [rax+rdx+8]
    test eax, 0x80000000
    jnz gui_fi_icondir
gui_fi_iconfile:
    mov rcx, QWORD PTR [rsp+32]
    xor edx, edx
    call gui_icon_for_path
    jmp gui_fi_iconstore
gui_fi_icondir:
    mov rcx, QWORD PTR [rsp+32]
    mov edx, 1
    call gui_icon_for_path
gui_fi_iconstore:
    mov rdx, QWORD PTR [rsp+40]
    mov DWORD PTR [rdx+60], eax
gui_fi_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_open_focused(RCX=hwnd): ShellExecuteW(open, primer seleccionado).
gui_open_focused:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETNEXTITEM
    mov r8d, -1
    mov r9d, LVNI_SELECTED
    call SendMessageW
    cmp rax, 0
    jl gui_of_ret
    lea rdx, [rip + gui_count]
    cmp rax, QWORD PTR [rdx]
    jae gui_of_ret
    lea rdx, [rip + gui_items]
    mov rax, QWORD PTR [rdx+rax*8]
    mov rcx, rax
    call gui_idx_path
    test rax, rax
    jz gui_of_ret
    mov QWORD PTR [rsp+48], rax
    mov rcx, QWORD PTR [rsp+40]
    lea rdx, [rip + gui_verb_open]
    mov r8, QWORD PTR [rsp+48]
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], SW_SHOWNORMAL
    call ShellExecuteW
gui_of_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_open_folder(RCX=hwnd): abre la carpeta contenedora del item seleccionado.
gui_open_folder:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    sub rsp, 72
    mov rbx, rcx
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETNEXTITEM
    mov r8d, -1
    mov r9d, LVNI_SELECTED
    call SendMessageW
    cmp rax, 0
    jl gof_ret
    lea rdx, [rip + gui_count]
    cmp rax, QWORD PTR [rdx]
    jae gof_ret
    lea rdx, [rip + gui_items]
    mov rax, QWORD PTR [rdx+rax*8]
    mov rcx, rax
    call gui_idx_path
    test rax, rax
    jz gof_ret
    mov QWORD PTR [rsp+48], rax
    // args = /select,"path" en gui_cmpbuf
    lea rdi, [rip + gui_cmpbuf]
    lea rsi, [rip + gui_select_prefix]
gof_pfx:
    movzx eax, WORD PTR [rsi]
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    test ax, ax
    jnz gof_pfx
    sub rdi, 2
    mov rsi, QWORD PTR [rsp+48]
gof_path:
    movzx eax, WORD PTR [rsi]
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    test ax, ax
    jnz gof_path
    sub rdi, 2
    mov WORD PTR [rdi], 0x22
    add rdi, 2
    mov WORD PTR [rdi], 0
    mov rcx, rbx
    xor edx, edx
    lea r8, [rip + gui_explorer_name]
    lea r9, [rip + gui_cmpbuf]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], SW_SHOWNORMAL
    call ShellExecuteW
gof_ret:
    add rsp, 72
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_copy_path(RCX=hwnd): copia la ruta del item seleccionado al portapapeles.
gui_copy_path:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    sub rsp, 72
    mov rbx, rcx
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETNEXTITEM
    mov r8d, -1
    mov r9d, LVNI_SELECTED
    call SendMessageW
    cmp rax, 0
    jl gcp_ret
    lea rdx, [rip + gui_count]
    cmp rax, QWORD PTR [rdx]
    jae gcp_ret
    lea rdx, [rip + gui_items]
    mov rax, QWORD PTR [rdx+rax*8]
    mov rcx, rax
    call gui_idx_path
    test rax, rax
    jz gcp_ret
    mov QWORD PTR [rsp+48], rax
    mov rcx, rbx
    call OpenClipboard
    test eax, eax
    jz gcp_ret
    call EmptyClipboard
    mov rsi, QWORD PTR [rsp+48]
    mov rcx, rsi
    call gui_wcslen
    inc rax
    shl rax, 1
    mov QWORD PTR [rsp+56], rax
    mov rcx, rax
    mov edx, 0x0002
    call GlobalAlloc
    test rax, rax
    jz gcp_close
    mov QWORD PTR [rsp+64], rax
    mov rcx, rax
    call GlobalLock
    test rax, rax
    jz gcp_close
    mov rdi, rax
    mov rsi, QWORD PTR [rsp+48]
    mov rcx, QWORD PTR [rsp+56]
    shr rcx, 1
    rep movsw
    mov rcx, QWORD PTR [rsp+64]
    call GlobalUnlock
    mov rcx, QWORD PTR [rsp+64]
    mov edx, 13
    call SetClipboardData
gcp_close:
    call CloseClipboard
gcp_ret:
    add rsp, 72
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_hist_push(): guarda el texto actual del Edit en el historial (si no vacio
// ni duplicado del ultimo). Llamar al confirmar una busqueda (Enter/click).
gui_hist_push:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    sub rsp, 72
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz gpush_ret
    lea rdx, [rip + gui_query]
    mov r8d, 1025
    call GetWindowTextW
    test rax, rax
    jz gpush_ret
    // duplicado del ultimo? -> skip
    mov rcx, QWORD PTR [rip + gui_hist_n]
    test rcx, rcx
    jz ghp_store
    mov rax, rcx
    dec rax
    shl rax, 11
    lea rsi, [rip + gui_hist]
    add rsi, rax
    lea rdi, [rip + gui_query]
ghp_cmp:
    movzx eax, WORD PTR [rsi]
    movzx edx, WORD PTR [rdi]
    cmp eax, edx
    jne ghp_store
    test eax, eax
    jz gpush_ret
    add rsi, 2
    add rdi, 2
    jmp ghp_cmp
ghp_store:
    mov rcx, QWORD PTR [rip + gui_hist_n]
    cmp rcx, 16
    jb ghp_append
    // buffer lleno: desplazar una ranura (descarta el mas viejo)
    lea rsi, [rip + gui_hist]
    add rsi, 2048
    lea rdi, [rip + gui_hist]
    mov rcx, 15*1024
    rep movsw
    mov rcx, 15
ghp_append:
    mov rax, rcx
    shl rax, 11
    lea rdi, [rip + gui_hist]
    add rdi, rax
    lea rsi, [rip + gui_query]
ghp_copy:
    movzx eax, WORD PTR [rsi]
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    test ax, ax
    jnz ghp_copy
    mov rax, QWORD PTR [rip + gui_hist_n]
    cmp rax, 16
    jae ghp_nokeep
    inc rax
    lea rcx, [rip + gui_hist_n]
    mov QWORD PTR [rcx], rax
ghp_nokeep:
    lea rax, [rip + gui_hist_pos]
    mov QWORD PTR [rax], -1
gpush_ret:
    add rsp, 72
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_hist_up(RCX=hwnd): recuerda la entrada anterior del historial.
gui_hist_up:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 72
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_hist_n]
    test rax, rax
    jz ghu_ret
    mov rcx, QWORD PTR [rip + gui_hist_pos]
    cmp rcx, -1
    jne ghu_dec
    mov rcx, rax
    dec rcx
    jmp ghu_set
ghu_dec:
    test rcx, rcx
    jz ghu_wrap
    dec rcx
    jmp ghu_set
ghu_wrap:
    mov rcx, rax
    dec rcx
ghu_set:
    lea rdx, [rip + gui_hist_pos]
    mov QWORD PTR [rdx], rcx
    shl rcx, 11
    lea rsi, [rip + gui_hist]
    add rsi, rcx
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz ghu_ret
    mov rdx, rsi
    call SetWindowTextW
    // cursor al final
    mov rcx, QWORD PTR [rip + gui_edit]
    mov edx, EM_SETSEL
    mov r8, -1
    mov r9, -1
    call SendMessageW
ghu_ret:
    add rsp, 72
    pop rbx
    pop rbp
    ret

// gui_hist_down(RCX=hwnd): recuerda la entrada siguiente (o limpia).
gui_hist_down:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 72
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_hist_n]
    test rax, rax
    jz ghd_ret
    mov rcx, QWORD PTR [rip + gui_hist_pos]
    cmp rcx, -1
    je ghd_ret
    inc rcx
    cmp rcx, rax
    jb ghd_set
    // fin del historial -> limpiar edit
    lea rdx, [rip + gui_hist_pos]
    mov QWORD PTR [rdx], -1
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz ghd_ret
    lea rdx, [rip + gui_empty]
    call SetWindowTextW
    jmp ghd_ret
ghd_set:
    lea rdx, [rip + gui_hist_pos]
    mov QWORD PTR [rdx], rcx
    shl rcx, 11
    lea rsi, [rip + gui_hist]
    add rsi, rcx
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz ghd_ret
    mov rdx, rsi
    call SetWindowTextW
    mov rcx, QWORD PTR [rip + gui_edit]
    mov edx, EM_SETSEL
    mov r8, -1
    mov r9, -1
    call SendMessageW
ghd_ret:
    add rsp, 72
    pop rbx
    pop rbp
    ret

// gui_save_recents(): persiste el historial en HKCU\Software\seek "recents" (REG_MULTI_SZ).
gui_save_recents:
    push rbx
    sub rsp, 368
    // construir multi-string en gui_cmpbuf
    lea rdi, [rip + gui_cmpbuf]
    mov rbx, 0
gsr_loop:
    cmp rbx, QWORD PTR [rip + gui_hist_n]
    jae gsr_term
    mov rax, rbx
    shl rax, 11
    lea rsi, [rip + gui_hist]
    add rsi, rax
gsr_copy:
    movzx eax, WORD PTR [rsi]
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    test ax, ax
    jnz gsr_copy
    inc rbx
    jmp gsr_loop
gsr_term:
    // doble null final
    mov WORD PTR [rdi], 0
    add rdi, 2
    mov WORD PTR [rdi], 0
    // guardar en registro
    mov QWORD PTR [rsp+80], 0
    lea rsi, [rip + gui_seekkey]
    lea rdi, [rsp+128]
    mov ecx, 14
    rep movsw
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+128]
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], KEY_WRITE
    mov QWORD PTR [rsp+48], 0
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+56], rax
    mov QWORD PTR [rsp+64], 0
    call RegCreateKeyExW
    test eax, eax
    jnz gsr_ret
    // calcular tamaño: (rdi - cmpbuf) * 2? rdi ya avanzo; usar puntero final
    lea rax, [rip + gui_cmpbuf]
    mov r10, rdi
    sub r10, rax
    add r10, 2
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_val_recents]
    xor r8d, r8d
    mov r9d, 7
    lea rax, [rip + gui_cmpbuf]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], r10
    call RegSetValueExW
    mov rcx, QWORD PTR [rsp+80]
    call RegCloseKey
gsr_ret:
    add rsp, 368
    pop rbx
    ret

// gui_load_recents(): carga el historial desde HKCU\Software\seek "recents".
gui_load_recents:
    push rbx
    sub rsp, 368
    mov QWORD PTR [rsp+80], 0
    lea rsi, [rip + gui_seekkey]
    lea rdi, [rsp+128]
    mov ecx, 14
    rep movsw
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+128]
    xor r8d, r8d
    mov r9d, KEY_READ
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+32], rax
    call RegOpenKeyExW
    test eax, eax
    jnz glr_ret
    // consultar tamaño
    mov DWORD PTR [rsp+176], 0
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_val_recents]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+168]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+176]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glr_close
    mov r10d, DWORD PTR [rsp+176]
    test r10d, r10d
    jz glr_close
    cmp r10d, 65536
    ja glr_close
    // leer datos en gui_cmpbuf
    lea rax, [rsp+176]
    mov QWORD PTR [rsp+40], rax
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_val_recents]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+168]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rip + gui_cmpbuf]
    mov QWORD PTR [rsp+48], rax
    // RegQueryValueExW signature: (hKey, name, reserved, type, data, size)
    // data is 5th (rsp+32), size is 6th (rsp+40). But I put type in rsp+32 above.
    // Redo: lpData in rsp+48? No—ABI: 5th at rsp+32, 6th at rsp+40. Only 6 args total? 
    // RegQueryValueExW has 6 params: hKey(rcx), name(rdx), reserved(r8), type*(r9), data(rsp+32), size*(rsp+40).
    // So data must be rsp+32, size rsp+40. Fix below by reloading.
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rip + gui_val_recents]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rip + gui_cmpbuf]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+176]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glr_close
    // parse multi-string into gui_hist
    lea rsi, [rip + gui_cmpbuf]
    lea rdi, [rip + gui_hist]
    mov rbx, 0
glr_parse:
    cmp rbx, 16
    jae glr_done
    movzx eax, WORD PTR [rsi]
    test eax, eax
    // doble null o vacio -> fin
    jz glr_done
    // copiar hasta null
    mov rax, rbx
    shl rax, 11
    lea rdi, [rip + gui_hist]
    add rdi, rax
glr_copy:
    movzx eax, WORD PTR [rsi]
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    test ax, ax
    jnz glr_copy
    inc rbx
    jmp glr_parse
glr_done:
    lea rax, [rip + gui_hist_n]
    mov QWORD PTR [rax], rbx
    lea rax, [rip + gui_hist_pos]
    mov QWORD PTR [rax], -1
glr_close:
    mov rcx, QWORD PTR [rsp+80]
    test rcx, rcx
    jz glr_ret
    call RegCloseKey
glr_ret:
    add rsp, 368
    pop rbx
    ret

// gui_sort_column(RCX=NMLISTVIEW*): ordena gui_items por la columna clickeada.
gui_sort_column:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    sub rsp, 72
    mov rbx, rcx
    mov eax, DWORD PTR [rbx+28]
    cmp eax, 0
    jl gsc_ret
    cmp eax, 2
    ja gsc_ret
    // toggle col/dir
    lea rdx, [rip + gui_sort_col]
    mov ecx, DWORD PTR [rdx]
    cmp eax, ecx
    jne gsc_newcol
    lea rdx, [rip + gui_sort_dir]
    mov ecx, DWORD PTR [rdx]
    xor ecx, 1
    mov DWORD PTR [rdx], ecx
    jmp gsc_dosort
gsc_newcol:
    lea rdx, [rip + gui_sort_col]
    mov DWORD PTR [rdx], eax
    lea rdx, [rip + gui_sort_dir]
    mov DWORD PTR [rdx], 0
gsc_dosort:
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    test rcx, rcx
    jz gsc_ret
    mov r12, rcx
    call scan_ws_recbase
    mov r13, rax
    mov rax, QWORD PTR [r12 + WS_MTIME_BASE]
    // r13=recbase, rax=mtbase
    mov r8, r13
    mov r9, rax
    lea rcx, [rip + gui_items]
    mov rdx, QWORD PTR [rip + gui_count]
    mov r10d, DWORD PTR [rip + gui_sort_col]
    mov QWORD PTR [rsp+32], r10
    mov r10d, DWORD PTR [rip + gui_sort_dir]
    mov QWORD PTR [rsp+40], r10
    // args: rcx=items, rdx=count, r8=recbase, r9=mtbase, [rsp+32]=mode, [rsp+40]=asc
    // but r8/r9 already set; need rcx/rdx before call. reorder:
    lea rcx, [rip + gui_items]
    mov rdx, QWORD PTR [rip + gui_count]
    mov r8, r13
    mov r9, rax
    call skc_sort_items
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_refresh_final
gsc_ret:
    add rsp, 72
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_on_contextmenu(RCX=hwnd, RDX=wparamHWND, R8=lparamXY).
gui_on_contextmenu:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rax, r8
    mov DWORD PTR [rsp+48], eax
    shr rax, 16
    and eax, 0xFFFF
    // extender signo de 16 bits para x/y (pantalla)
    movsx edx, WORD PTR [rsp+48]
    movsx eax, ax
    mov DWORD PTR [rsp+48], edx
    mov DWORD PTR [rsp+52], eax
    cmp edx, -1
    jne gui_cm_havexy
    cmp eax, -1
    jne gui_cm_havexy
    lea rcx, [rsp+56]
    call GetCursorPos
    mov edx, DWORD PTR [rsp+56]
    mov eax, DWORD PTR [rsp+60]
    mov DWORD PTR [rsp+48], edx
    mov DWORD PTR [rsp+52], eax
gui_cm_havexy:
    mov rcx, QWORD PTR [rsp+40]
    mov edx, DWORD PTR [rsp+48]
    mov r8d, DWORD PTR [rsp+52]
    call gui_show_menu
    xor eax, eax
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_show_menu(RCX=hwnd, EDX=x, R8D=y). Menu Shell exacto.
// Locales: +64 hwnd, +72 nsel, +80 nok, +88 folder, +96 ctx,
//   +104 hmenu, +112 cmd, +120 samepar, +128 child0tmp.
gui_show_menu:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 200
    mov QWORD PTR [rsp+64], rcx
    mov DWORD PTR [rsp+72+0], edx
    mov DWORD PTR [rsp+72+4], r8d
    mov QWORD PTR [rsp+88], 0
    mov QWORD PTR [rsp+96], 0
    mov QWORD PTR [rsp+104], 0
    // 1) seleccionados -> gui_selidx
    xor ebx, ebx
    mov r14d, -1
gui_sm_collect:
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETNEXTITEM
    mov r8d, r14d
    mov r9d, LVNI_SELECTED
    call SendMessageW
    cmp rax, 0
    jl gui_sm_have
    cmp ebx, GUI_SELCAP
    jae gui_sm_have
    lea rdx, [rip + gui_selidx]
    mov DWORD PTR [rdx+rbx*4], eax
    inc rbx
    mov r14d, eax
    jmp gui_sm_collect
gui_sm_have:
    test ebx, ebx
    jz gui_sm_ret
    // 2) SHParseDisplayName por item -> gui_fullpidl
    xor r12d, r12d
    xor r13d, r13d
gui_sm_parse:
    cmp r13d, ebx
    jae gui_sm_parsed
    lea rax, [rip + gui_selidx]
    mov eax, DWORD PTR [rax+r13*4]
    lea rdx, [rip + gui_count]
    cmp rax, QWORD PTR [rdx]
    jae gui_sm_pskip
    lea rdx, [rip + gui_items]
    mov rcx, QWORD PTR [rdx+rax*8]
    call gui_idx_path
    test rax, rax
    jz gui_sm_pskip
    mov rcx, rax
    xor edx, edx
    lea r8, [rsp+128]
    mov QWORD PTR [rsp+128], 0
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    call SHParseDisplayName
    test eax, eax
    js gui_sm_pskip
    mov rax, QWORD PTR [rsp+128]
    test rax, rax
    jz gui_sm_pskip
    lea rdx, [rip + gui_fullpidl]
    mov QWORD PTR [rdx+r12*8], rax
    lea rdx, [rip + gui_selok]
    lea rax, [rip + gui_selidx]
    mov eax, DWORD PTR [rax+r13*4]
    mov DWORD PTR [rdx+r12*4], eax
    inc r12
gui_sm_pskip:
    inc r13d
    jmp gui_sm_parse
gui_sm_parsed:
    test r12, r12
    jz gui_sm_ret
    mov QWORD PTR [rsp+80], r12
    mov r15, r12
    // 3) mismo padre? (índice de record padre exacto, sin strings)
    mov QWORD PTR [rsp+120], 1
    cmp r12, 1
    jbe gui_sm_bind
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    lea rax, [rip + gui_selok]
    mov eax, DWORD PTR [rax]
    lea rdx, [rip + gui_items]
    mov rdx, QWORD PTR [rdx+rax*8]
    call scan_ws_parent
    mov r14, rax
    mov r15, r12
    mov ebx, 1
gui_sm_pl:
    cmp rbx, r12
    jae gui_sm_bind
    lea rax, [rip + gui_selok]
    mov eax, DWORD PTR [rax+rbx*4]
    lea rcx, [rip + gui_items]
    mov rdx, QWORD PTR [rcx+rax*8]
    mov rcx, QWORD PTR [rip + gui_idx_ws]
    call scan_ws_parent
    cmp rax, r14
    jne gui_sm_mixed
    inc rbx
    jmp gui_sm_pl
gui_sm_mixed:
    // padres mixtos: menu solo del primer item
    mov QWORD PTR [rsp+80], 1
    mov QWORD PTR [rsp+120], 0
    mov r12, 1
    // liberar pidls sobrantes (1..n)
    mov ebx, 1
gui_sm_freemix:
    lea rax, [rip + gui_fullpidl]
    mov rax, QWORD PTR [rax+rbx*8]
    test rax, rax
    jz gui_sm_fmnext
    mov rcx, rax
    call CoTaskMemFree
    lea rax, [rip + gui_fullpidl]
    mov QWORD PTR [rax+rbx*8], 0
gui_sm_fmnext:
    inc rbx
    cmp rbx, QWORD PTR [rsp+80]
    // ojo: [rsp+80] ya es 1; usar r15 (n original)
    cmp rbx, r15
    jb gui_sm_freemix
gui_sm_bind:
    // 4) SHBindToParent(first) -> folder + child[0]
    lea rax, [rip + gui_fullpidl]
    mov rcx, QWORD PTR [rax]
    lea rdx, [rip + gui_iid_folder]
    lea r8, [rsp+88]
    lea r9, [rip + gui_childpidl]
    call SHBindToParent
    test eax, eax
    js gui_sm_cleanup
    mov rax, QWORD PTR [rsp+88]
    test rax, rax
    jz gui_sm_cleanup
    mov rbx, rax
    // resto de child pidls si multi mismo-padre
    mov rax, QWORD PTR [rsp+80]
    cmp rax, 1
    jbe gui_sm_uiobj
    mov r13d, 1
gui_sm_brest:
    cmp r13, QWORD PTR [rsp+80]
    jae gui_sm_uiobj
    lea rax, [rip + gui_fullpidl]
    mov rcx, QWORD PTR [rax+r13*8]
    lea rdx, [rip + gui_iid_folder]
    lea r8, [rsp+128]
    mov QWORD PTR [rsp+128], 0
    lea r9, [rsp+136]
    mov QWORD PTR [rsp+136], 0
    call SHBindToParent
    test eax, eax
    js gui_sm_uchild_fail
    // soltar folder extra, guardar child
    mov rcx, QWORD PTR [rsp+128]
    test rcx, rcx
    jz gui_sm_bnext
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+16]
gui_sm_bnext:
    mov rax, QWORD PTR [rsp+136]
    lea rdx, [rip + gui_childpidl]
    mov QWORD PTR [rdx+r13*8], rax
    inc r13
    jmp gui_sm_brest
gui_sm_uchild_fail:
    // si un hijo falla, achicar a los ok (r13)
    mov QWORD PTR [rsp+80], r13
    cmp r13, 0
    je gui_sm_cleanup
gui_sm_uiobj:
    // 5) GetUIObjectOf(folder, hwnd, n, childs, IID_IContextMenu, 0, &ctx)
    mov rcx, rbx
    mov rdx, QWORD PTR [rsp+64]
    mov r8, QWORD PTR [rsp+80]
    lea r9, [rip + gui_childpidl]
    lea rax, [rip + gui_iid_ctxmenu]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 0
    lea rax, [rsp+96]
    mov QWORD PTR [rsp+48], rax
    mov rax, QWORD PTR [rbx]
    call QWORD PTR [rax+80]
    test eax, eax
    js gui_sm_cleanup
    mov rax, QWORD PTR [rsp+96]
    test rax, rax
    jz gui_sm_cleanup
    mov r12, rax
    // 6) QI IContextMenu2/3 (para INITMENUPOPUP/DRAW/MEASURE)
    lea rax, [rip + gui_ctxmenu2]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_ctxmenu3]
    mov QWORD PTR [rax], 0
    mov rcx, r12
    lea rdx, [rip + gui_iid_ctxmenu2]
    lea r8, [rip + gui_ctxmenu2]
    mov rax, QWORD PTR [r12]
    call QWORD PTR [rax]
    mov rcx, r12
    lea rdx, [rip + gui_iid_ctxmenu3]
    lea r8, [rip + gui_ctxmenu3]
    mov rax, QWORD PTR [r12]
    call QWORD PTR [rax]
    // 7) popup + QueryContextMenu
    call CreatePopupMenu
    test rax, rax
    jz gui_sm_cleanup
    mov QWORD PTR [rsp+104], rax
    mov rcx, r12
    mov rdx, rax
    xor r8d, r8d
    mov r9d, 1
    mov QWORD PTR [rsp+32], 0x7FFF
    mov QWORD PTR [rsp+40], 0
    mov rax, QWORD PTR [r12]
    call QWORD PTR [rax+24]
    test eax, eax
    js gui_sm_destroymenu
    mov rcx, QWORD PTR [rsp+104]
    mov edx, TPM_RETURNCMD
    or edx, TPM_RIGHTBUTTON
    mov r8d, DWORD PTR [rsp+72]
    mov r9d, DWORD PTR [rsp+76]
    mov rax, QWORD PTR [rsp+64]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 0
    call TrackPopupMenuEx
    mov QWORD PTR [rsp+112], rax
    // globals ctx2/3 siguen activos hasta el Release (ya no hay menu).
    jmp gui_sm_cleanup
gui_sm_destroymenu:
    mov rcx, QWORD PTR [rsp+104]
    call DestroyMenu
    mov QWORD PTR [rsp+104], 0
    jmp gui_sm_cleanup
gui_sm_cleanup:
    // Invoke si cmd>=1 (antes de liberar)
    mov rax, QWORD PTR [rsp+112]
    test rax, rax
    jz gui_sm_freeall
    // CMINVOKECOMMANDINFO en pila (56B en [rsp+128..183])
    lea rdi, [rsp+128]
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov DWORD PTR [rsp+128], 56
    mov rax, QWORD PTR [rsp+64]
    mov QWORD PTR [rsp+136], rax
    mov rax, QWORD PTR [rsp+112]
    sub rax, 1
    mov QWORD PTR [rsp+144], rax
    mov QWORD PTR [rsp+152], 0
    mov QWORD PTR [rsp+160], 0
    mov DWORD PTR [rsp+168], SW_SHOWNORMAL
    mov DWORD PTR [rsp+172], 0
    mov QWORD PTR [rsp+176], 0
    mov rax, QWORD PTR [rsp+96]
    test rax, rax
    jz gui_sm_freeall
    mov rcx, rax
    lea rdx, [rsp+128]
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+32]
gui_sm_freeall:
    mov rcx, QWORD PTR [rsp+96]
    test rcx, rcx
    jz gui_sm_noctx
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+16]
    mov QWORD PTR [rsp+96], 0
gui_sm_noctx:
    mov rax, QWORD PTR [rip + gui_ctxmenu2]
    test rax, rax
    jz gui_sm_no2
    mov rcx, rax
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+16]
    lea rax, [rip + gui_ctxmenu2]
    mov QWORD PTR [rax], 0
gui_sm_no2:
    mov rax, QWORD PTR [rip + gui_ctxmenu3]
    test rax, rax
    jz gui_sm_no3
    mov rcx, rax
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+16]
    lea rax, [rip + gui_ctxmenu3]
    mov QWORD PTR [rax], 0
gui_sm_no3:
    mov rcx, QWORD PTR [rsp+88]
    test rcx, rcx
    jz gui_sm_nofold
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+16]
    mov QWORD PTR [rsp+88], 0
gui_sm_nofold:
    mov rcx, QWORD PTR [rsp+104]
    test rcx, rcx
    jz gui_sm_nomen
    call DestroyMenu
    mov QWORD PTR [rsp+104], 0
gui_sm_nomen:
    // CoTaskMemFree full pidls (todas las parseadas: r15 o r12? usar max)
    mov r13, QWORD PTR [rsp+80]
    // liberar TODAS las full (incluye mixtas ya liberadas=0)
    xor ebx, ebx
gui_sm_freeloop:
    cmp rbx, 256
    jae gui_sm_ret
    lea rax, [rip + gui_fullpidl]
    mov rax, QWORD PTR [rax+rbx*8]
    test rax, rax
    jz gui_sm_fnext
    mov rcx, rax
    call CoTaskMemFree
    lea rax, [rip + gui_fullpidl]
    mov QWORD PTR [rax+rbx*8], 0
gui_sm_fnext:
    inc rbx
    // solo hasta el max parseado: rastrear con r15 si mixto
    cmp rbx, r15
    jae gui_sm_ret
    jmp gui_sm_freeloop
gui_sm_ret:
    mov QWORD PTR [rsp+112], 0
    add rsp, 200
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_parent_len(RCX=path) -> RAX=len del dir (pos del ultimo '\').
gui_parent_len:
    mov rax, rcx
    call gui_wcslen
    mov rdx, rax
gui_pl_l:
    test rdx, rdx
    jz gui_pl_zero
    dec rdx
    cmp WORD PTR [rcx+rdx*2], 0x5C
    jne gui_pl_l
    mov rax, rdx
    ret
gui_pl_zero:
    xor eax, eax
    ret

// gui_wprefix_eq(RSI=a, RDX=b, RCX=lenW) -> EAX 1 iguales.
gui_wprefix_eq:
    test rcx, rcx
    jz gui_pe_yes
gui_pe_l:
    movzx eax, WORD PTR [rsi]
    movzx r8d, WORD PTR [rdx]
    cmp eax, r8d
    jne gui_pe_no
    add rsi, 2
    add rdx, 2
    dec rcx
    jnz gui_pe_l
gui_pe_yes:
    mov eax, 1
    ret
gui_pe_no:
    xor eax, eax
    ret

// gui_menu_forward(ECX=msg, RDX=wParam, R8=lParam) -> EAX 1 atendido.
// Prefiere IContextMenu3::HandleMenuMsg2, fallback a IContextMenu2.
gui_menu_forward:
    push rbx
    sub rsp, 64
    mov DWORD PTR [rsp+40], ecx
    mov QWORD PTR [rsp+48], rdx
    mov QWORD PTR [rsp+56], r8
    mov rcx, QWORD PTR [rip + gui_ctxmenu3]
    test rcx, rcx
    jz gui_mf_try2
    mov edx, DWORD PTR [rsp+40]
    mov r8, QWORD PTR [rsp+48]
    mov r9, QWORD PTR [rsp+56]
    lea rax, [rsp+32]
    mov QWORD PTR [rsp+32], rax
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+56]
    test eax, eax
    jz gui_mf_yes
gui_mf_try2:
    mov rcx, QWORD PTR [rip + gui_ctxmenu2]
    test rcx, rcx
    jz gui_mf_no
    mov edx, DWORD PTR [rsp+40]
    mov r8, QWORD PTR [rsp+48]
    mov r9, QWORD PTR [rsp+56]
    mov rax, QWORD PTR [rcx]
    call QWORD PTR [rax+48]
    test eax, eax
    jnz gui_mf_no
gui_mf_yes:
    mov eax, 1
    add rsp, 64
    pop rbx
    ret
gui_mf_no:
    xor eax, eax
    add rsp, 64
    pop rbx
    ret

// gui_has_sub(RCX=hay ANSI, RDX=needle ANSI, R8=len) -> EAX 1 si contiene.
gui_has_sub:
    push rbx
    push rsi
    push rdi
    test rcx, rcx
    jz ghs_no
    test r8, r8
    jz ghs_no
    mov rsi, rcx
    mov rbx, rdx
ghs_outer:
    cmp BYTE PTR [rsi], 0
    je ghs_no
    xor edi, edi
ghs_cmp:
    cmp rdi, r8
    jae ghs_yes
    mov al, BYTE PTR [rsi+rdi]
    mov dl, BYTE PTR [rbx+rdi]
    cmp al, dl
    jne ghs_next
    inc rdi
    jmp ghs_cmp
ghs_next:
    inc rsi
    jmp ghs_outer
ghs_yes:
    mov eax, 1
    pop rdi
    pop rsi
    pop rbx
    ret
ghs_no:
    xor eax, eax
    pop rdi
    pop rsi
    pop rbx
    ret

// gui_parse_flags(RCX=lpCmdLine ANSI). Setea mode/focus/pinned/panel +
// install_req/uninstall_req (autoarranque).
gui_parse_flags:
    push rbx
    sub rsp, 64
    mov rbx, rcx
    // debounce por defecto = 120 ms: filtrar en cada tecla congelaba el UI
    // (90 ms por tecla con 3M records, 1.3 s con una query de ruta).
    // --debounce 0 lo deja instantaneo; --debounce N lo ajusta.
    lea rax, [rip + gui_debounce]
    mov QWORD PTR [rax], 120
    lea rax, [rip + gui_mode]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_focus_req]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_pinned]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_panel]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_install_req]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_uninstall_req]
    mov QWORD PTR [rax], 0
    test rbx, rbx
    jz gpf_ret
    lea rdx, [rip + gui_flag_window]
    mov r8d, 8
    mov rcx, rbx
    call gui_has_sub
    test eax, eax
    jz gpf_focus
    lea rax, [rip + gui_mode]
    mov QWORD PTR [rax], 1
gpf_focus:
    lea rdx, [rip + gui_flag_focus]
    mov r8d, 7
    mov rcx, rbx
    call gui_has_sub
    test eax, eax
    jz gpf_install
    lea rax, [rip + gui_focus_req]
    mov QWORD PTR [rax], 1
gpf_install:
    lea rdx, [rip + gui_flag_install]
    mov r8d, 17
    mov rcx, rbx
    call gui_has_sub
    test eax, eax
    jz gpf_uninstall
    lea rax, [rip + gui_install_req]
    mov QWORD PTR [rax], 1
gpf_uninstall:
    lea rdx, [rip + gui_flag_uninstall]
    mov r8d, 19
    mov rcx, rbx
    call gui_has_sub
    test eax, eax
    jz gpf_noexcl
    lea rax, [rip + gui_uninstall_req]
    mov QWORD PTR [rax], 1
gpf_noexcl:
    // --no-excludes: sin exclusiones por defecto (afecta al indexado)
    lea rdx, [rip + gui_flag_noexcl]
    mov r8d, 13
    mov rcx, rbx
    call gui_has_sub
    test eax, eax
    jz gpf_excl
    mov ecx, 1
    xor edx, edx
    xor r8d, r8d
    call scan_set_opts
gpf_excl:
    // --exclude <ruta> (hasta 16, con comillas y '=' admitidos)
    mov rcx, rbx
    call gui_parse_excl
    // --debounce N: retardo en ms antes de filtrar (0 = sin debounce, default)
    mov rcx, rbx
    lea rdx, [rip + gui_flag_debounce]
    mov r8d, 10
    call gui_has_sub
    test eax, eax
    jz gpf_ret
    mov rsi, rbx
gpd_scan:
    cmp BYTE PTR [rsi], 0
    je gpf_ret
    mov rdi, rsi
    lea rcx, [rip + gui_flag_debounce]
    mov r8d, 10
gpd_cmp:
    test r8d, r8d
    jz gpd_hit
    movzx eax, BYTE PTR [rdi]
    movzx edx, BYTE PTR [rcx]
    cmp eax, edx
    jne gpd_adv
    inc rdi
    inc rcx
    dec r8d
    jmp gpd_cmp
gpd_adv:
    inc rsi
    jmp gpd_scan
gpd_hit:
    mov rsi, rdi
gpd_skipsp:
    cmp BYTE PTR [rsi], 0x20
    jne gpd_digits
    inc rsi
    jmp gpd_skipsp
gpd_digits:
    xor r10d, r10d
gpd_dloop:
    movzx ecx, BYTE PTR [rsi]
    cmp ecx, 0x30
    jb gpd_done
    cmp ecx, 0x39
    ja gpd_done
    sub ecx, 0x30
    imul r10d, r10d, 10
    add r10d, ecx
    inc rsi
    jmp gpd_dloop
gpd_done:
    lea rax, [rip + gui_debounce]
    mov QWORD PTR [rax], r10
gpf_ret:
    add rsp, 64
    pop rbx
    ret

// gui_parse_excl(RCX=lpCmdLine ANSI). Registra hasta 16 exclusiones custom
// via scan_add_exclude (copia+lowercase internamente). ANSI->wide con CP_ACP.
// Formatos: "--exclude <ruta>", "--exclude=<ruta>", "--exclude \"<ruta>\"".
gui_parse_excl:
    push rbx
    push rsi
    push rdi
    sub rsp, 80
    mov rsi, rcx
    test rsi, rsi
    jz gpx_ret
    xor ebx, ebx
gpx_scan:
    cmp BYTE PTR [rsi], 0
    je gpx_ret
    // buscar "--exclude" empezando en rsi
    mov rdi, rsi
    lea rcx, [rip + gui_flag_exclude]
    mov r8d, 9
gpx_cmp:
    test r8d, r8d
    jz gpx_hit
    movzx eax, BYTE PTR [rdi]
    movzx edx, BYTE PTR [rcx]
    cmp eax, edx
    jne gpx_adv
    inc rdi
    inc rcx
    dec r8d
    jmp gpx_cmp
gpx_adv:
    inc rsi
    jmp gpx_scan
gpx_hit:
    mov rsi, rdi
    cmp BYTE PTR [rsi], 0x3D
    jne gpx_spc
    inc rsi
gpx_spc:
    cmp BYTE PTR [rsi], 0x20
    jne gpx_tok
    inc rsi
    jmp gpx_spc
gpx_tok:
    cmp BYTE PTR [rsi], 0x22
    je gpx_qtok
    mov rdi, rsi
gpx_len:
    movzx eax, BYTE PTR [rdi]
    test eax, eax
    jz gpx_conv
    cmp eax, 0x20
    je gpx_conv
    // cmdline entrecomillada completa: el token puede cerrar con '"' — cortar ahi
    cmp eax, 0x22
    je gpx_conv
    inc rdi
    jmp gpx_len
gpx_qtok:
    inc rsi
    mov rdi, rsi
gpx_qlen:
    movzx eax, BYTE PTR [rdi]
    test eax, eax
    jz gpx_conv
    cmp eax, 0x22
    je gpx_conv
    inc rdi
    jmp gpx_qlen
gpx_conv:
    mov rdx, rdi
    sub rdx, rsi
    jz gpx_after
    cmp rdx, 256
    ja gpx_after
    // cchMultiByte = largo exacto del token: con -1 convertiria hasta el NUL
    // de toda la cmdline y arrastraria la comilla final ("--exclude X" quoted).
    mov r9, rdx
    xor ecx, ecx
    xor edx, edx
    mov r8, rsi
    lea rax, [rip + gui_excl_wbuf]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 260
    call MultiByteToWideChar
    test eax, eax
    jz gpx_after
    // eax = chars escritos (sin NUL: conversion con largo explicito)
    test eax, eax
    jz gpx_after
    mov rdx, rax
    lea rcx, [rip + gui_excl_wbuf]
    call scan_add_exclude
    inc ebx
    cmp ebx, 16
    jae gpx_ret
gpx_after:
    movzx eax, BYTE PTR [rdi]
    test eax, eax
    jz gpx_ret
    cmp eax, 0x22
    jne gpx_cont
    inc rdi
gpx_cont:
    mov rsi, rdi
    jmp gpx_scan
gpx_ret:
    add rsp, 80
    pop rdi
    pop rsi
    pop rbx
    ret

// gui_edit_len() -> RAX=len (GetWindowTextLengthW del edit).
gui_edit_len:
    push rbx
    sub rsp, 64
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz gel_zero
    call GetWindowTextLengthW
    // eax=len (puede ser -1 si falla)
    cmp eax, 0
    jl gel_zero
    movsxd rax, eax
    add rsp, 64
    pop rbx
    ret
gel_zero:
    xor eax, eax
    add rsp, 64
    pop rbx
    ret

// gui_show_panel(RCX=hwnd). Window: solo Show; bar: Show + agranda a BAR_H+PANEL.
gui_show_panel:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_panel]
    test rax, rax
    jnz gsp_ret
    lea rax, [rip + gui_panel]
    mov QWORD PTR [rax], 1
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gsp_win
    // bar: mostrar + resize (SetWindowPos NOMOVE|NOZORDER|NOACTIVATE=0x16)
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, SW_SHOW
    call ShowWindow
    mov rcx, QWORD PTR [rip + gui_status]
    mov edx, SW_SHOW
    call ShowWindow
    mov rcx, rbx
    call gui_layout
    mov QWORD PTR [rsp+32], BAR_W
    mov rax, BAR_H
    add rax, BAR_PANEL_H
    mov QWORD PTR [rsp+40], rax
    mov QWORD PTR [rsp+48], 0x16
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call SetWindowPos
    mov rcx, rbx
    call gui_apply_rgn
    jmp gsp_ret
gsp_win:
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, SW_SHOW
    call ShowWindow
    mov rcx, QWORD PTR [rip + gui_status]
    mov edx, SW_SHOW
    call ShowWindow
gsp_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_hide_panel(RCX=hwnd). Window: no-op (ventana vieja siempre visible).
// Bar: oculta list+status + achica a BAR_H. Nunca oculta la barra.
gui_hide_panel:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz ghp_ret
    mov rax, QWORD PTR [rip + gui_panel]
    test rax, rax
    jz ghp_shrink
    lea rax, [rip + gui_panel]
    mov QWORD PTR [rax], 0
ghp_shrink:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghp_hidest
    xor edx, edx
    call ShowWindow
ghp_hidest:
    mov rcx, QWORD PTR [rip + gui_status]
    test rcx, rcx
    jz ghp_resize
    xor edx, edx
    call ShowWindow
ghp_resize:
    mov QWORD PTR [rsp+32], BAR_W
    mov QWORD PTR [rsp+40], BAR_H
    mov QWORD PTR [rsp+48], 0x16
    mov rcx, rbx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    call SetWindowPos
    mov rcx, rbx
    call gui_apply_rgn
ghp_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_refresh_panel(RCX=hwnd): si edit tiene texto -> show, si no -> hide.
gui_refresh_panel:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz grp_ret
    call gui_edit_len
    test rax, rax
    jz grp_hide
    mov rcx, QWORD PTR [rsp+40]
    call gui_show_panel
    call gui_update_empty
    jmp grp_ret
grp_hide:
    mov rcx, QWORD PTR [rsp+40]
    call gui_hide_panel
    call gui_update_empty
grp_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_toggle_pin(RCX=hwnd): alterna TOPMOST via SetWindowPos.
gui_toggle_pin:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_pinned]
    test rax, rax
    jz gtp_on
    // quitar TOPMOST -> NOTOPMOST (NOMOVE|NOSIZE|NOACTIVATE=0x13)
    lea rax, [rip + gui_pinned]
    mov QWORD PTR [rax], 0
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x13
    mov rcx, rbx
    mov rdx, -2
    xor r8d, r8d
    xor r9d, r9d
    call SetWindowPos
    jmp gtp_ret
gtp_on:
    lea rax, [rip + gui_pinned]
    mov QWORD PTR [rax], 1
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x13
    mov rcx, rbx
    mov rdx, -1
    xor r8d, r8d
    xor r9d, r9d
    call SetWindowPos
gtp_ret:
    mov rcx, rbx
    call gui_save_barpos
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_mode_setglyph(): valida fmode (0=Todos, 1=Archivos, 2=Carpetas) y
// repinta el boton (el paint real va en gui_mode_draw). Sin SetWindowTextW:
// el texto con surrogates tumbaba el proceso (ver BENCH).
gui_mode_setglyph:
    sub rsp, 40
    mov eax, DWORD PTR [rip + gui_fmode]
    cmp eax, 2
    jbe gmd_ok
    xor eax, eax
    lea rdx, [rip + gui_fmode]
    mov DWORD PTR [rdx], eax
gmd_ok:
    mov rcx, QWORD PTR [rip + gui_hmode]
    test rcx, rcx
    jz gmd_ret
    xor edx, edx
    xor r8d, r8d
    call InvalidateRect
gmd_ret:
    add rsp, 40
    ret

// gui_init_modeicons(): HICONs de archivo (.txt) y carpeta para el boton
// modo (SHGFI_ICON, USEFILEATTRIBUTES: sin tocar disco). Frame 8+760.
gui_init_modeicons:
    push rbx
    sub rsp, 768
    lea r8, [rsp+64]
    lea rcx, [rip + gui_iconame_file]
    mov edx, 0x80
    mov r9d, 696
    mov DWORD PTR [rsp+32], 0x111
    call SHGetFileInfoW
    test rax, rax
    jz gmi_dir
    mov rax, QWORD PTR [rsp+64]
    lea rdx, [rip + gui_hicon_file]
    mov QWORD PTR [rdx], rax
gmi_dir:
    lea r8, [rsp+64]
    lea rcx, [rip + gui_iconame_dir]
    mov edx, 0x10
    mov r9d, 696
    mov DWORD PTR [rsp+32], 0x111
    call SHGetFileInfoW
    test rax, rax
    jz gmi_ret
    mov rax, QWORD PTR [rsp+64]
    lea rdx, [rip + gui_hicon_dir]
    mov QWORD PTR [rdx], rax
gmi_ret:
    add rsp, 768
    pop rbx
    ret

// gui_mode_draw(RCX=DRAWITEMSTRUCT*): paint owner-draw del boton modo.
// Fondo oscuro + "Todos" (texto BMP) o icono archivo/carpeta centrado.
// Frame: push rbx+rdi + sub 64.
gui_mode_draw:
    push rbx
    push rdi
    sub rsp, 88
    mov rbx, rcx
    mov rcx, QWORD PTR [rbx+32]
    lea rdx, [rbx+40]
    mov r8, QWORD PTR [rip + gui_brush]
    call FillRect
    mov eax, DWORD PTR [rip + gui_fmode]
    cmp eax, 1
    je gmdr_file
    cmp eax, 2
    je gmdr_dir
    // modo 0: glyph BMP con la fuente Segoe + fondo transparente
    mov rcx, QWORD PTR [rbx+32]
    mov edx, 0xF2F2F2
    call SetTextColor
    mov rcx, QWORD PTR [rbx+32]
    mov edx, 1
    call SetBkMode
    mov rcx, QWORD PTR [rbx+32]
    mov rdx, QWORD PTR [rip + gui_hfont]
    call SelectObject
    mov rdi, rax
    mov rcx, QWORD PTR [rbx+32]
    lea rdx, [rip + gui_mode_txt0]
    mov r8d, -1
    lea r9, [rbx+40]
    mov DWORD PTR [rsp+32], 0x25
    call DrawTextW
    mov rcx, QWORD PTR [rbx+32]
    mov rdx, rdi
    call SelectObject
    jmp gmdr_ret
gmdr_file:
    mov rax, QWORD PTR [rip + gui_hicon_file]
    jmp gmdr_icon
gmdr_dir:
    mov rax, QWORD PTR [rip + gui_hicon_dir]
gmdr_icon:
    test rax, rax
    jz gmdr_ret
    mov r10d, DWORD PTR [rbx+48]
    sub r10d, DWORD PTR [rbx+40]
    sub r10d, 16
    sar r10d, 1
    add r10d, DWORD PTR [rbx+40]
    mov r11d, DWORD PTR [rbx+52]
    sub r11d, DWORD PTR [rbx+44]
    sub r11d, 16
    sar r11d, 1
    add r11d, DWORD PTR [rbx+44]
    mov rcx, QWORD PTR [rbx+32]
    mov edx, r10d
    mov r8d, r11d
    mov r9, rax
    mov DWORD PTR [rsp+32], 16
    mov DWORD PTR [rsp+40], 16
    mov QWORD PTR [rsp+48], 0
    mov QWORD PTR [rsp+56], 0
    mov DWORD PTR [rsp+64], 3
    call DrawIconEx
gmdr_ret:
    mov eax, 1
    add rsp, 88
    pop rdi
    pop rbx
    ret

// gui_empty_draw(RCX=DRAWITEMSTRUCT*): overlay "Sin resultados" gris
// centrado sobre fondo oscuro. Frame como gui_mode_draw (probado).
gui_empty_draw:
    push rbx
    push rdi
    sub rsp, 88
    mov rbx, rcx
    mov rcx, QWORD PTR [rbx+32]
    lea rdx, [rbx+40]
    mov r8, QWORD PTR [rip + gui_brush]
    call FillRect
    mov rcx, QWORD PTR [rbx+32]
    mov edx, 0x8A8A8A
    call SetTextColor
    mov rcx, QWORD PTR [rbx+32]
    mov edx, 1
    call SetBkMode
    mov rcx, QWORD PTR [rbx+32]
    mov rdx, QWORD PTR [rip + gui_hfont]
    call SelectObject
    mov rdi, rax
    mov rcx, QWORD PTR [rbx+32]
    lea rdx, [rip + gui_empty_txt]
    mov r8d, -1
    lea r9, [rbx+40]
    mov DWORD PTR [rsp+32], 0x25
    call DrawTextW
    mov rcx, QWORD PTR [rbx+32]
    mov rdx, rdi
    call SelectObject
    mov eax, 1
    add rsp, 88
    pop rdi
    pop rbx
    ret

// gui_on_hotkey(RCX=hwnd): toggle barra (Alt+Espacio). Oculta si visible;
// si oculta: muestra + foco + selecciona texto.
gui_on_hotkey:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    // cada invocacion (mostrar u ocultar) chequea el tick incremental;
    // recargar rcx: gui_maybe_repair lo clobbea cuando dispara CreateThread
    call gui_maybe_repair
    mov rcx, QWORD PTR [rsp+40]
    call IsWindowVisible
    test eax, eax
    jz ghk_show
    mov rcx, QWORD PTR [rsp+40]
    xor edx, edx
    call ShowWindow
    lea rax, [rip + gui_autohid]
    mov QWORD PTR [rax], 0
    jmp ghk_ret
ghk_show:
    mov rcx, QWORD PTR [rsp+40]
    mov edx, SW_SHOW
    call ShowWindow
    lea rax, [rip + gui_autohid]
    mov QWORD PTR [rax], 0
    mov rcx, QWORD PTR [rsp+40]
    call SetForegroundWindow
    mov rcx, QWORD PTR [rip + gui_edit]
    call SetFocus
    mov rcx, QWORD PTR [rip + gui_edit]
    mov edx, EM_SETSEL
    xor r8d, r8d
    mov r9, -1
    call SendMessageW
ghk_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_maybe_repair(): si pasaron >REPAIR_MS desde el ultimo tick, lanza el
// incremental en fondo (una sola instancia). Lo llaman el timer de 500 ms
// y el summon del hotkey.
// Frame sub 56 (sin pushes): args en +32/+40.
gui_maybe_repair:
    sub rsp, 56
    mov rax, QWORD PTR [rip + gui_busy]
    test rax, rax
    jnz gmr_ret
    mov rax, QWORD PTR [rip + gui_idx_ready]
    test rax, rax
    jz gmr_ret
    mov rax, QWORD PTR [rip + gui_hrepair]
    test rax, rax
    jnz gmr_ret
    call GetTickCount64
    mov rdx, QWORD PTR [rip + gui_lasttick]
    sub rax, rdx
    cmp rax, REPAIR_SLICE_MS
    jb gmr_ret
    lea rdx, [rip + gui_gen]
    mov r9, QWORD PTR [rdx]
    xor ecx, ecx
    xor edx, edx
    lea r8, [rip + gui_repair]
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    call CreateThread
    test rax, rax
    jz gmr_ret
    lea rdx, [rip + gui_hrepair]
    mov QWORD PTR [rdx], rax
gmr_ret:
    add rsp, 56
    ret

// gui_repair(RCX=mygen): tick + repara subarboles cambiados in-place
// (tombstones + append + reparent), refilter via GUI_APP_DONE.
// Frame 152: +64 mygen, +72 ws, +80 nchanged, +88 diri, +96 recbase,
//   +104 mtbase, +112 reccnt; attr32 en [+120..+152).
gui_repair:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 152
    mov QWORD PTR [rsp+64], rcx
    mov rbx, QWORD PTR [rip + gui_idx_ws]
    test rbx, rbx
    jz gr_cleanup
    mov QWORD PTR [rsp+72], rbx
    mov rax, QWORD PTR [rbx + WS_MTIME_BASE]
    test rax, rax
    jz gr_finish
    mov QWORD PTR [rsp+104], rax
    mov rcx, rbx
    call scan_ws_recbase
    mov QWORD PTR [rsp+96], rax
    mov rcx, rbx
    call scan_ws_reccnt
    mov QWORD PTR [rsp+112], rax
    // tope anti-trunc: si faltan <128K slots, a F5
    mov rax, QWORD PTR [rbx + WS_R_END]
    sub rax, QWORD PTR [rbx + WS_R_BASE]
    mov ecx, 12
    xor edx, edx
    div ecx
    sub eax, 131072
    cmp QWORD PTR [rsp+112], rax
    ja gr_cleanup
    // si el usuario esta buscando, no mutar el indice ahora
    mov rax, QWORD PTR [rip + gui_busy]
    test rax, rax
    jnz gr_cleanup
    // tick (Rust): dirs cambiados. Barrido por franjas: cursor global (in/out)
    // + presupuesto de ms, para repartir el trabajo y no pegar picos de CPU.
    mov rcx, QWORD PTR [rsp+96]
    mov rdx, QWORD PTR [rsp+112]
    mov r8, QWORD PTR [rsp+104]
    lea r9, [rip + gui_tick_changed]
    mov QWORD PTR [rsp+32], TICK_NCH
    lea rax, [rip + gui_tick_buf]
    mov QWORD PTR [rsp+40], rax
    mov QWORD PTR [rsp+48], 32768
    lea rax, [rip + gui_sweep_cursor]
    mov QWORD PTR [rsp+56], rax
    call skc_dir_tick
    mov QWORD PTR [rsp+80], rax
    test rax, rax
    jz gr_finish
    cmp rax, TICK_NCH
    jbe gr_loop0
    mov QWORD PTR [rsp+80], TICK_NCH
gr_loop0:
    mov QWORD PTR [rsp+88], 0
gr_dir:
    mov rax, QWORD PTR [rsp+88]
    cmp rax, QWORD PTR [rsp+80]
    jae gr_finish_post
    // gen: F5 manda, abortamos (el join de F5 acota)
    mov rax, QWORD PTR [rip + gui_gen]
    cmp rax, QWORD PTR [rsp+64]
    jne gr_cleanup
    mov rax, QWORD PTR [rip + gui_busy]
    test rax, rax
    jnz gr_cleanup
    lea rdx, [rip + gui_tick_changed]
    mov ecx, DWORD PTR [rsp+88]
    mov edx, DWORD PTR [rdx+rcx*4]
    mov DWORD PTR [rsp+120], edx
    // vive? (tombstoneado por un ancestro ya procesado)
    mov rax, QWORD PTR [rsp+96]
    mov ecx, edx
    imul rcx, rcx, 12
    cmp QWORD PTR [rax+rcx], 0
    je gr_next
    mov ebx, edx
    // path del dir (Rust, buffer propio)
    mov rcx, QWORD PTR [rsp+96]
    mov edx, ebx
    lea r8, [rip + gui_tick_buf]
    mov r9d, 32768
    call skc_path_for
    test rax, rax
    jz gr_next
    mov r13, rax
    // existe?
    lea rcx, [rip + gui_tick_buf]
    call GetFileAttributesW
    cmp eax, -1
    je gr_deleted
    // cambio: tombstone hijos (no el dir)
    mov rcx, QWORD PTR [rsp+96]
    mov rdx, QWORD PTR [rsp+112]
    mov r8d, ebx
    xor r9d, r9d
    call skc_tombstone_sub
    // reccnt0 (la raiz nueva ocupa ese slot)
    mov rcx, QWORD PTR [rsp+72]
    call scan_ws_reccnt
    mov r12, rax
    // rescan del subarbol (append; query/index intactos)
    mov rcx, QWORD PTR [rsp+72]
    lea rdx, [rip + gui_tick_buf]
    mov r8, r13
    call scan_root_ws
    // si no crecio, no hay que reparentar (pero si actualizar mtime)
    mov rcx, QWORD PTR [rsp+72]
    call scan_ws_reccnt
    mov r14, rax
    cmp rax, r12
    je gr_updtime
    // hijos de la raiz nueva -> dir viejo (conserva bit is_dir)
    mov rcx, QWORD PTR [rsp+96]
    mov rdx, r14
    mov r8, r12
    mov r9d, ebx
    call skc_reparent
    // tombstone a la raiz nueva (slot reccnt0, commiteado: recien escrito)
    mov rax, QWORD PTR [rsp+96]
    mov rcx, r12
    imul rcx, rcx, 12
    mov QWORD PTR [rax+rcx], 0
gr_updtime:
    // mtime fresca (o SENTINEL+tombstone si se fue en el medio)
    lea rcx, [rip + gui_tick_buf]
    xor edx, edx
    lea r8, [rsp+120]
    call GetFileAttributesExW
    test eax, eax
    jz gr_deleted
    mov rax, QWORD PTR [rsp+104]
    mov ecx, ebx
    mov rdx, QWORD PTR [rsp+140]
    mov QWORD PTR [rax+rcx*8], rdx
    jmp gr_next
gr_deleted:
    // borrado: tombstone incl. el dir + SENTINEL, sin rescan
    mov rcx, QWORD PTR [rsp+96]
    mov rdx, QWORD PTR [rsp+112]
    mov r8d, ebx
    mov r9d, 1
    call skc_tombstone_sub
    mov rax, QWORD PTR [rsp+104]
    mov ecx, ebx
    mov rdx, -1
    mov QWORD PTR [rax+rcx*8], rdx
    jmp gr_next
gr_next:
    inc QWORD PTR [rsp+88]
    jmp gr_dir
gr_finish_post:
    call GetTickCount64
    lea rdx, [rip + gui_lasttick]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rip + gui_hrepair]
    test rcx, rcx
    jz gr_noclose1
    call CloseHandle
    lea rax, [rip + gui_hrepair]
    mov QWORD PTR [rax], 0
gr_noclose1:
    // repair cambio el indice: forzar busqueda completa (no incremental)
    // al refiltrar, evita arrastrar records tombstoneados.
    lea rax, [rip + gui_prevlen]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_prevwild]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_prevpathq]
    mov QWORD PTR [rax], 0
    mov rcx, QWORD PTR [rip + gui_hwnd]
    mov edx, GUI_APP_DONE
    mov r8, QWORD PTR [rip + gui_gen]
    xor r9d, r9d
    call PostMessageW
    xor eax, eax
    jmp gr_epilogue
gr_finish:
    call GetTickCount64
    lea rdx, [rip + gui_lasttick]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rip + gui_hrepair]
    test rcx, rcx
    jz gr_noclose2
    call CloseHandle
    lea rax, [rip + gui_hrepair]
    mov QWORD PTR [rax], 0
gr_noclose2:
    xor eax, eax
    jmp gr_epilogue
gr_cleanup:
    // calibra igual que finish: sin esto el timer reintentaria cada 500 ms
    call GetTickCount64
    lea rdx, [rip + gui_lasttick]
    mov QWORD PTR [rdx], rax
    mov rcx, QWORD PTR [rip + gui_hrepair]
    test rcx, rcx
    jz gr_epilogue
    call CloseHandle
    lea rax, [rip + gui_hrepair]
    mov QWORD PTR [rax], 0
gr_epilogue:
    add rsp, 152
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_check_autohide(RCX=hwnd). Solo bar (window = no-op).
// Otra app en foreground (no barra/desktop/shell/menu) -> oculta TODA la
// barra (SW_HIDE) y marca gui_autohid=1. Desktop/shell/NULL con barra
// oculta por auto (autohid==1) -> muestra (SW_SHOWNA) y limpia la marca.
// Manual (hotkey) pone/limpia autohid=0 y el timer lo respeta.
// Frame push rbx + sub 160 (alineado): [rsp+64]=fg, [rsp+72..135]=clase.
gui_check_autohide:
    push rbx
    sub rsp, 160
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gca_ret
    test rbx, rbx
    jz gca_ret
    call GetForegroundWindow
    cmp rax, rbx
    je gca_ret
    test rax, rax
    jz gca_desktop
    mov QWORD PTR [rsp+64], rax
    call GetDesktopWindow
    cmp rax, QWORD PTR [rsp+64]
    je gca_desktop
    call GetShellWindow
    cmp rax, QWORD PTR [rsp+64]
    je gca_desktop
    mov rcx, QWORD PTR [rsp+64]
    lea rdx, [rsp+72]
    mov r8d, 32
    call GetClassNameW
    test eax, eax
    jz gca_hide
    cmp eax, 7
    je gca_maybe7
    cmp eax, 6
    je gca_maybe6
    jmp gca_hide
gca_maybe7:
    // Progman | WorkerW ?
    movzx eax, WORD PTR [rsp+72]
    cmp eax, 0x50
    je gca_chk_prog
    movzx eax, WORD PTR [rsp+72]
    cmp eax, 0x57
    je gca_chk_work
    jmp gca_hide
gca_chk_prog:
    cmp WORD PTR [rsp+74], 0x72
    jne gca_hide
    cmp WORD PTR [rsp+76], 0x6F
    jne gca_hide
    cmp WORD PTR [rsp+78], 0x67
    jne gca_hide
    cmp WORD PTR [rsp+80], 0x6D
    jne gca_hide
    cmp WORD PTR [rsp+82], 0x61
    jne gca_hide
    cmp WORD PTR [rsp+84], 0x6E
    jne gca_hide
    jmp gca_desktop
gca_chk_work:
    cmp WORD PTR [rsp+74], 0x6F
    jne gca_hide
    cmp WORD PTR [rsp+76], 0x72
    jne gca_hide
    cmp WORD PTR [rsp+78], 0x6B
    jne gca_hide
    cmp WORD PTR [rsp+80], 0x65
    jne gca_hide
    cmp WORD PTR [rsp+82], 0x72
    jne gca_hide
    cmp WORD PTR [rsp+84], 0x57
    jne gca_hide
    jmp gca_desktop
gca_maybe6:
    // #32768 (menu Shell) -> es nuestro: no tocar
    cmp WORD PTR [rsp+72], 0x23
    jne gca_hide
    cmp WORD PTR [rsp+74], 0x33
    jne gca_hide
    cmp WORD PTR [rsp+76], 0x32
    jne gca_hide
    cmp WORD PTR [rsp+78], 0x37
    jne gca_hide
    cmp WORD PTR [rsp+80], 0x36
    jne gca_hide
    cmp WORD PTR [rsp+82], 0x38
    jne gca_hide
    jmp gca_ret
gca_hide:
    mov rcx, rbx
    call IsWindowVisible
    test eax, eax
    jz gca_ret
    mov rcx, rbx
    xor edx, edx
    call ShowWindow
    lea rax, [rip + gui_autohid]
    mov QWORD PTR [rax], 1
    jmp gca_ret
gca_desktop:
    mov rcx, rbx
    call IsWindowVisible
    test eax, eax
    jnz gca_ret
    lea rax, [rip + gui_autohid]
    cmp QWORD PTR [rax], 0
    je gca_ret
    mov rcx, rbx
    mov edx, SW_SHOWNA
    call ShowWindow
    lea rax, [rip + gui_autohid]
    mov QWORD PTR [rax], 0
gca_ret:
    add rsp, 160
    pop rbx
    ret

// gui_on_escape(RCX=hwnd): limpia edit y filtro, mata timer de búsqueda.
// Esc 2 pasos (bar): con texto -> limpia y colapsa el panel; sin texto ->
// oculta la barra entera (ShowWindow SW_HIDE + autohid=0, el timer no la
// revive; vuelve con el hotkey). En --window hide_panel es no-op y la
// ventana nunca se oculta. El índice queda intacto (lista a 0, idx=).
gui_on_escape:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov QWORD PTR [rsp+40], rcx
    // [rsp+48] = había texto al entrar (define si este Esc era el 1.o o el 2.o)
    call gui_edit_len
    mov QWORD PTR [rsp+48], rax
    mov rcx, QWORD PTR [rsp+40]
    mov rdx, TIMER_SEARCH
    call KillTimer
    mov rcx, QWORD PTR [rip + gui_edit]
    test rcx, rcx
    jz ges_hide
    lea rdx, [rip + gui_empty]
    call SetWindowTextW
ges_hide:
    lea rax, [rip + gui_total]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_count]
    mov QWORD PTR [rax], 0
    lea rax, [rip + gui_prevlen]
    mov QWORD PTR [rax], 0
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ges_panel
    mov edx, LVM_SETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
ges_panel:
    // Esc 1 (o ya sin texto): colapsar panel siempre (window: no-op)
    mov rcx, QWORD PTR [rsp+40]
    call gui_hide_panel
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_status
    mov rcx, QWORD PTR [rsp+40]
    call gui_update_title
    call gui_update_empty
    // Esc 2 (entró sin texto): ocultar la barra entera, solo en modo bar
    cmp QWORD PTR [rsp+48], 0
    jne ges_keep
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz ges_keep
    mov rcx, QWORD PTR [rsp+40]
    call IsWindowVisible
    test eax, eax
    jz ges_keep
    mov rcx, QWORD PTR [rsp+40]
    xor edx, edx
    call ShowWindow
    lea rax, [rip + gui_autohid]
    mov QWORD PTR [rax], 0
ges_keep:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_on_ctlcolor(RCX=hdc, RDX=hwndCtl) -> RAX=brush oscuro + texto claro
// (gris para el overlay de vacio).
gui_on_ctlcolor:
    push rbx
    sub rsp, 64
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_hempty]
    test rax, rax
    jz goc_nb
    cmp rdx, rax
    jne goc_nb
    mov QWORD PTR [rsp+32], 1
    jmp goc_bk
goc_nb:
    mov QWORD PTR [rsp+32], 0
goc_bk:
    mov edx, 0x1E1E1E
    call SetBkColor
    mov rcx, rbx
    cmp QWORD PTR [rsp+32], 0
    jne goc_gray
    mov edx, 0xF2F2F2
    jmp goc_tx
goc_gray:
    mov edx, 0x8A8A8A
goc_tx:
    call SetTextColor
    mov rax, QWORD PTR [rip + gui_brush]
    test rax, rax
    jnz goc_ret
    mov eax, 6
goc_ret:
    add rsp, 64
    pop rbx
    ret

// gui_init_font: crea Segoe UI 11pt ClearType (altura = -11*dpi/72) en gui_hfont.
// Frame push rbx + sub 128 (8+128=136 = 8 mod 16: pila 16B antes de call).
// hdc en RBX; args de CreateFontW en [rsp+32..104].
gui_init_font:
    push rbx
    sub rsp, 128
    xor ecx, ecx
    call GetDC
    test rax, rax
    jz gifont_ret
    mov rbx, rax
    mov rcx, rax
    mov edx, LOGPIXELSY
    call GetDeviceCaps
    // Segoe UI 11pt con antialias grayscale (quality=4 en +88): en fondo
    // oscuro el ClearType (5) deja franja RGB en los bordes del glifo.
    imul eax, eax, 11
    xor edx, edx
    mov ecx, 72
    div ecx
    neg eax
    mov ecx, eax
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov DWORD PTR [rsp+32], 400
    mov DWORD PTR [rsp+40], 0
    mov DWORD PTR [rsp+48], 0
    mov DWORD PTR [rsp+56], 0
    mov DWORD PTR [rsp+64], 1
    mov DWORD PTR [rsp+72], 0
    mov DWORD PTR [rsp+80], 0
    mov DWORD PTR [rsp+88], 4
    mov DWORD PTR [rsp+96], 0
    lea rax, [rip + gui_fontface]
    mov QWORD PTR [rsp+104], rax
    call CreateFontW
    lea rcx, [rip + gui_hfont]
    mov QWORD PTR [rcx], rax
    xor ecx, ecx
    mov rdx, rbx
    call ReleaseDC
gifont_ret:
    add rsp, 128
    pop rbx
    ret

// gui_enable_acrylic(RCX=hwnd): intenta ACCENT_ENABLE_ACRYLICBLURBEHIND via
// SetWindowCompositionAttribute (carga dinamica de user32; sin DWM o en Win
// viejo falla -> fallback: WS_EX_LAYERED alfa 184 intacto). Al aplicar con
// exito quita WS_EX_LAYERED (el combo acrilico+layered+region es inestable
// al mostrar/redimensionar) con SWP_FRAMECHANGED. No toca la region.
// Frame push rbx + sub 96 (8+96=104 = 8 mod 16, alineado): policy
// [rsp+48..63], attrdata [rsp+64..87], hwnd [rsp+88].
gui_enable_acrylic:
    push rbx
    sub rsp, 96
    mov QWORD PTR [rsp+88], rcx
    lea rcx, [rip + gui_dll_user32]
    call GetModuleHandleW
    test rax, rax
    jz gac_fallback
    mov rcx, rax
    lea rdx, [rip + gui_fn_swca]
    call GetProcAddress
    test rax, rax
    jz gac_fallback
    mov rbx, rax
    mov DWORD PTR [rsp+48], ACCENT_ACRYLIC
    mov DWORD PTR [rsp+52], 0
    mov DWORD PTR [rsp+56], 0x99261814
    mov DWORD PTR [rsp+60], 0
    mov DWORD PTR [rsp+64], WCA_ACCENT_POLICY
    mov DWORD PTR [rsp+68], 0
    lea rax, [rsp+48]
    mov QWORD PTR [rsp+72], rax
    mov QWORD PTR [rsp+80], 16
    mov rcx, QWORD PTR [rsp+88]
    lea rdx, [rsp+64]
    call rbx
    test eax, eax
    jz gac_fallback
    // exito: combo acrilico correcto = SIN WS_EX_LAYERED (con layered+alpha
    // +region la composicion es inestable al mostrar/redimensionar).
    mov rcx, QWORD PTR [rsp+88]
    mov edx, GWL_EXSTYLE
    call GetWindowLongPtrW
    and rax, 0xFFFFFFFFFFF7FFFF
    mov rdx, rax
    mov rcx, QWORD PTR [rsp+88]
    call SetWindowLongPtrW
    mov rcx, QWORD PTR [rsp+88]
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], 0
    mov QWORD PTR [rsp+48], 0x37
    call SetWindowPos
    jmp gac_ret
gac_fallback:
    mov rcx, QWORD PTR [rsp+88]
    xor edx, edx
    mov r8d, BAR_ALPHA
    mov r9d, LWA_ALPHA
    call SetLayeredWindowAttributes
gac_ret:
    add rsp, 96
    pop rbx
    ret

// gui_apply_rgn(RCX=hwnd). Region redondeada pildora (BAR_W x h, elipse
// BAR_R x BAR_R = radio BAR_R/2; CreateRoundRectRgn no toma radio).
// h=BAR_H colapsada, BAR_H+BAR_PANEL_H expandida. Window mode: quita region.
// Convive con WS_EX_LAYERED. Se llama al crear, en resize y en cada modo.
// +1 en x2/y2: los bordes de la region son exclusivos; sin +1 la caja sale
// 699x34 en vez de 700x35 (verificado con GetRgnBox).
gui_apply_rgn:
    push rbx
    sub rsp, 80
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gar_clear
    mov eax, BAR_H
    mov rcx, QWORD PTR [rip + gui_panel]
    test rcx, rcx
    jz gar_haveh
    mov eax, BAR_H + BAR_PANEL_H
gar_haveh:
    inc eax
    mov r9d, eax
    xor ecx, ecx
    xor edx, edx
    mov r8d, BAR_W + 1
    mov QWORD PTR [rsp+32], BAR_R
    mov QWORD PTR [rsp+40], BAR_R
    call CreateRoundRectRgn
    test rax, rax
    jz gar_ret
    mov rcx, rbx
    mov rdx, rax
    mov r8d, 1
    call SetWindowRgn
    jmp gar_ret
gar_clear:
    mov rcx, rbx
    xor edx, edx
    mov r8d, 1
    call SetWindowRgn
gar_ret:
    add rsp, 80
    pop rbx
    ret

// gui_save_barpos(RCX=hwnd). Guarda x,y (GetWindowRect) en HKCU\Software\seek
// valores DWORD x/y. Solo bar mode. Todo lo que lee el kernel va en la pila
// (trampa .data documentada en README). Frame push rbx + sub 368 (alineado).
gui_save_barpos:
    push rbx
    sub rsp, 368
    mov rbx, rcx
    mov rax, QWORD PTR [rip + gui_mode]
    test rax, rax
    jnz gsb_ret
    test rbx, rbx
    jz gsb_ret
    mov QWORD PTR [rsp+80], 0
    lea rdx, [rsp+96]
    mov rcx, rbx
    call GetWindowRect
    test eax, eax
    jz gsb_ret
    mov eax, DWORD PTR [rsp+96]
    mov DWORD PTR [rsp+168], eax
    mov eax, DWORD PTR [rsp+100]
    mov DWORD PTR [rsp+172], eax
    lea rsi, [rip + gui_seekkey]
    lea rdi, [rsp+128]
    mov ecx, 14
    rep movsw
    mov DWORD PTR [rsp+160], 0x00000078
    mov DWORD PTR [rsp+164], 0x00000079
    mov DWORD PTR [rsp+176], 0x00690070
    mov DWORD PTR [rsp+180], 0x0000006E
    mov rax, QWORD PTR [rip + gui_pinned]
    mov DWORD PTR [rsp+184], eax
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+128]
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], KEY_WRITE
    mov QWORD PTR [rsp+48], 0
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+56], rax
    mov QWORD PTR [rsp+64], 0
    call RegCreateKeyExW
    test eax, eax
    jnz gsb_ret
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+160]
    xor r8d, r8d
    mov r9d, REG_DWORD
    lea rax, [rsp+168]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 4
    call RegSetValueExW
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+164]
    xor r8d, r8d
    mov r9d, REG_DWORD
    lea rax, [rsp+172]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 4
    call RegSetValueExW
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+176]
    xor r8d, r8d
    mov r9d, REG_DWORD
    lea rax, [rsp+184]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 4
    call RegSetValueExW
    // modo (Todos/Archivos/Carpetas): nombre "mode\0" (10 bytes) + DWORD
    mov DWORD PTR [rsp+188], 0x006F006D
    mov DWORD PTR [rsp+192], 0x00650064
    mov DWORD PTR [rsp+196], 0
    mov eax, DWORD PTR [rip + gui_fmode]
    mov DWORD PTR [rsp+200], eax
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+188]
    xor r8d, r8d
    mov r9d, REG_DWORD
    lea rax, [rsp+200]
    mov QWORD PTR [rsp+32], rax
    mov QWORD PTR [rsp+40], 4
    call RegSetValueExW
    mov rcx, QWORD PTR [rsp+80]
    call RegCloseKey
gsb_ret:
    add rsp, 368
    pop rbx
    ret

// gui_load_barpos(). Lee HKCU\Software\seek {x,y DWORD}; si falta usa
// centrado x=(screenW-BAR_W)/2, y=BAR_Y. Clamp al primario. Setea
// gui_barx/gui_bary. Llamar con gui_screenw/h ya leidos.
gui_load_barpos:
    push rbx
    sub rsp, 368
    mov QWORD PTR [rsp+80], 0
    // defaults
    mov rax, QWORD PTR [rip + gui_screenw]
    sub rax, BAR_W
    cmp rax, 0
    jle glb_xzero
    shr rax, 1
    jmp glb_xhave
glb_xzero:
    xor eax, eax
glb_xhave:
    lea rcx, [rip + gui_barx]
    mov QWORD PTR [rcx], rax
    lea rcx, [rip + gui_bary]
    mov QWORD PTR [rcx], BAR_Y
    // subkey a pila
    lea rsi, [rip + gui_seekkey]
    lea rdi, [rsp+128]
    mov ecx, 14
    rep movsw
    mov DWORD PTR [rsp+160], 0x00000078
    mov DWORD PTR [rsp+164], 0x00000079
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+128]
    xor r8d, r8d
    mov r9d, KEY_READ
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+32], rax
    call RegOpenKeyExW
    test eax, eax
    jnz glb_clamp
    // x
    mov DWORD PTR [rsp+176], 4
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+160]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+168]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+176]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glb_tryy
    cmp DWORD PTR [rsp+176], 4
    jne glb_tryy
    mov eax, DWORD PTR [rsp+168]
    movsxd rax, eax
    lea rcx, [rip + gui_barx]
    mov QWORD PTR [rcx], rax
glb_tryy:
    mov DWORD PTR [rsp+180], 4
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+164]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+172]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+180]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glb_close
    cmp DWORD PTR [rsp+180], 4
    jne glb_close
    mov eax, DWORD PTR [rsp+172]
    movsxd rax, eax
    lea rcx, [rip + gui_bary]
    mov QWORD PTR [rcx], rax
glb_trypin:
    mov DWORD PTR [rsp+176], 0x00690070
    mov DWORD PTR [rsp+180], 0x0000006E
    mov DWORD PTR [rsp+188], 4
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+176]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+184]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+188]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glb_close
    cmp DWORD PTR [rsp+188], 4
    jne glb_close
    mov eax, DWORD PTR [rsp+184]
    test eax, eax
    jz glb_pinzero
    mov eax, 1
glb_pinzero:
    lea rcx, [rip + gui_pinned]
    mov QWORD PTR [rcx], rax
glb_trymode:
    mov DWORD PTR [rsp+176], 0x006F006D
    mov DWORD PTR [rsp+180], 0x00650064
    mov DWORD PTR [rsp+184], 0
    mov DWORD PTR [rsp+192], 4
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+176]
    xor r8d, r8d
    xor r9d, r9d
    lea rax, [rsp+188]
    mov QWORD PTR [rsp+32], rax
    lea rax, [rsp+192]
    mov QWORD PTR [rsp+40], rax
    call RegQueryValueExW
    test eax, eax
    jnz glb_close
    cmp DWORD PTR [rsp+192], 4
    jne glb_close
    mov eax, DWORD PTR [rsp+188]
    cmp eax, 2
    jbe glb_modeok
    xor eax, eax
glb_modeok:
    lea rcx, [rip + gui_fmode]
    mov QWORD PTR [rcx], rax
glb_close:
    mov rcx, QWORD PTR [rsp+80]
    call RegCloseKey
glb_clamp:
    // clamp x a [0, screenW-BAR_W] (0 si pantalla angosta)
    mov rax, QWORD PTR [rip + gui_screenw]
    sub rax, BAR_W
    cmp rax, 0
    jle glb_cxzero
    mov rbx, rax
    mov rax, QWORD PTR [rip + gui_barx]
    cmp rax, 0
    jge glb_cxhi
    lea rcx, [rip + gui_barx]
    mov QWORD PTR [rcx], 0
    jmp glb_cy
glb_cxhi:
    cmp rax, rbx
    jle glb_cy
    lea rcx, [rip + gui_barx]
    mov QWORD PTR [rcx], rbx
    jmp glb_cy
glb_cxzero:
    lea rcx, [rip + gui_barx]
    mov QWORD PTR [rcx], 0
glb_cy:
    mov rax, QWORD PTR [rip + gui_screenh]
    sub rax, BAR_H
    cmp rax, 0
    jle glb_cyzero
    mov rbx, rax
    mov rax, QWORD PTR [rip + gui_bary]
    cmp rax, 0
    jge glb_cyhi
    lea rcx, [rip + gui_bary]
    mov QWORD PTR [rcx], 0
    jmp glb_ret
glb_cyhi:
    cmp rax, rbx
    jle glb_ret
    lea rcx, [rip + gui_bary]
    mov QWORD PTR [rcx], rbx
    jmp glb_ret
glb_cyzero:
    lea rcx, [rip + gui_bary]
    mov QWORD PTR [rcx], 0
glb_ret:
    add rsp, 368
    pop rbx
    ret

// gui_startup_install() -> EAX 0 ok / 1 error. Escribe HKCU\...\Run valor
// seek = "ruta-del-exe" y avisa con MessageBoxW (binario -mwindows, sin consola).
// Frame push rbx + sub 131296: args [rsp+32..71], hKey [rsp+80],
// subkey [rsp+96..187], valor [rsp+192..201], exepath [rsp+208..65743],
// quoted [rsp+65744..131283]. Todo lo que lee el kernel vive en la pila
// (RegCreate/SetValue devuelven 998/NOACCESS con punteros a .data/.bss).
gui_startup_install:
    push rbx
    // marco 128KB > 4KB: sondeo pagina por pagina (chkstk manual) o el
    // primer toque salta la guard page y muere con AV.
    mov rax, rsp
    mov ecx, 33
gsin_probe:
    sub rax, 4096
    mov QWORD PTR [rax], 0
    dec ecx
    jnz gsin_probe
    sub rsp, 131296
    mov QWORD PTR [rsp+80], 0
    lea rsi, [rip + gui_runkey]
    lea rdi, [rsp+96]
    mov ecx, 46
    rep movsw
    mov DWORD PTR [rsp+192], 0x00650073
    mov DWORD PTR [rsp+196], 0x006B0065
    mov WORD PTR [rsp+200], 0
    xor ecx, ecx
    lea rdx, [rsp+208]
    mov r8d, 32768
    call GetModuleFileNameW
    test eax, eax
    jz gsin_err
    cmp eax, 32768
    jae gsin_err
    mov ebx, eax
    lea rsi, [rsp+208]
    lea rdi, [rsp+65744]
    mov WORD PTR [rdi], 0x22
    add rdi, 2
    mov ecx, ebx
    rep movsw
    mov WORD PTR [rdi], 0x22
    mov WORD PTR [rdi+2], 0
    // RegCreateKeyExW(HKCU, Run, 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL)
    // args: rcx,rdx,r8,r9 + pila [rsp+32]=5 [rsp+40]=6 [rsp+48]=7 [rsp+56]=8 [rsp+64]=9
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+96]
    xor r8d, r8d
    xor r9d, r9d
    mov QWORD PTR [rsp+32], 0
    mov QWORD PTR [rsp+40], KEY_WRITE
    mov QWORD PTR [rsp+48], 0
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+56], rax
    mov QWORD PTR [rsp+64], 0
    call RegCreateKeyExW
    test eax, eax
    jnz gsin_err
    // RegSetValueExW(hKey, seek, 0, REG_SZ, quoted, (len+3)*2)
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+192]
    xor r8d, r8d
    mov r9d, REG_SZ
    lea rax, [rsp+65744]
    mov QWORD PTR [rsp+32], rax
    mov eax, ebx
    add eax, 3
    add eax, eax
    mov QWORD PTR [rsp+40], rax
    call RegSetValueExW
    mov ebx, eax
    mov rcx, QWORD PTR [rsp+80]
    call RegCloseKey
    test ebx, ebx
    jnz gsin_err
    xor ecx, ecx
    lea rdx, [rip + gui_msg_inst_ok]
    lea r8, [rip + gui_title_bar]
    mov r9d, MB_ICONINFO
    call MessageBoxW
    xor eax, eax
    jmp gsin_ret
gsin_err:
    xor ecx, ecx
    lea rdx, [rip + gui_msg_err]
    lea r8, [rip + gui_title_bar]
    mov r9d, MB_ICONERR
    call MessageBoxW
    mov eax, 1
gsin_ret:
    add rsp, 131296
    pop rbx
    ret

// gui_startup_uninstall() -> EAX 0 ok / 1 error. Borra el valor seek.
// Si no existia, avisa igual (estado final = no arranca) y devuelve 0.
// Frame push rbx + sub 368: hKey [rsp+80], subkey [rsp+96..], valor [rsp+192..].
gui_startup_uninstall:
    push rbx
    sub rsp, 368
    mov QWORD PTR [rsp+80], 0
    lea rsi, [rip + gui_runkey]
    lea rdi, [rsp+96]
    mov ecx, 46
    rep movsw
    mov DWORD PTR [rsp+192], 0x00650073
    mov DWORD PTR [rsp+196], 0x006B0065
    mov WORD PTR [rsp+200], 0
    mov rcx, HKEY_CURRENT_USER
    lea rdx, [rsp+96]
    xor r8d, r8d
    mov r9d, KEY_SETVAL
    lea rax, [rsp+80]
    mov QWORD PTR [rsp+32], rax
    call RegOpenKeyExW
    test eax, eax
    jnz gsu_err
    mov rcx, QWORD PTR [rsp+80]
    lea rdx, [rsp+192]
    call RegDeleteValueW
    mov ebx, eax
    mov rcx, QWORD PTR [rsp+80]
    call RegCloseKey
    cmp ebx, ERR_FILENOTFOUND
    je gsu_absent
    test ebx, ebx
    jnz gsu_err
    xor ecx, ecx
    lea rdx, [rip + gui_msg_uninst_ok]
    lea r8, [rip + gui_title_bar]
    mov r9d, MB_ICONINFO
    call MessageBoxW
    xor eax, eax
    jmp gsu_ret
gsu_absent:
    xor ecx, ecx
    lea rdx, [rip + gui_msg_notinst]
    lea r8, [rip + gui_title_bar]
    mov r9d, MB_ICONINFO
    call MessageBoxW
    xor eax, eax
    jmp gsu_ret
gsu_err:
    xor ecx, ecx
    lea rdx, [rip + gui_msg_err]
    lea r8, [rip + gui_title_bar]
    mov r9d, MB_ICONERR
    call MessageBoxW
    mov eax, 1
gsu_ret:
    add rsp, 368
    pop rbx
    ret

// BUG1+BUG2: navegacion teclado + iconos sistema.
// Convenciones: SendMessageW(rcx=hwnd,edx=msg,r8=wparam,r9=lparam).
// Pila 16B antes de call (push rbp+7 => sub ≡8; push rbx solo => sub ≡0).

// gui_init_imagelist(): HIMAGELIST del sistema -> LVM_SETIMAGELIST + gui_himagelist.
// SHGetFileInfoW("",0,&sfi,696,SHGFI_SYSICONINDEX|SHGFI_SMALLICON) devuelve el handle.
gui_init_imagelist:
    push rbx
    sub rsp, 768
    mov rbx, QWORD PTR [rip + gui_list]
    test rbx, rbx
    jz gii_ret
    cmp QWORD PTR [rip + gui_himagelist], 0
    jne gii_ret
    lea rdi, [rsp+64]
    xor eax, eax
    mov ecx, 87
    rep stosq
    lea rcx, [rip + gui_empty]
    xor edx, edx
    lea r8, [rsp+64]
    mov r9d, 696
    mov QWORD PTR [rsp+32], 0x4001
    call SHGetFileInfoW
    test rax, rax
    jz gii_ret
    lea rcx, [rip + gui_himagelist]
    mov QWORD PTR [rcx], rax
    mov rcx, rbx
    mov edx, LVM_SETIMAGELIST
    mov r8d, LVSIL_SMALL
    mov r9, rax
    call SendMessageW
gii_ret:
    add rsp, 768
    pop rbx
    ret

// gui_icon_for_path(RCX=path WCHAR, EDX=is_dir) -> EAX=iIcon sistema.
// Cache ext->indice (64 entradas, por extension en minusculas con punto).
// Dirs usan slot unico gui_icon_dir (FILE_ATTR_DIR). Sin overlay .lnk.
gui_icon_for_path:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 808
    mov rbx, rcx
    mov r12d, edx
    test rbx, rbx
    jz gif_zero
    cmp r12d, 0
    jne gif_dir
    // --- archivo: extraer ext a [rsp+64] (16 WCHAR) ---
    mov rcx, rbx
    call gui_wcslen
    mov r13, rax
    lea rdi, [rsp+64]
    mov WORD PTR [rdi], 0
    test r13, r13
    jz gif_search
    // buscar ultimo '.' tras ultimo '\'
    mov r14, -1
    mov r15, r13
    dec r15
gif_scan:
    cmp r15, 0
    jl gif_nodot
    movzx eax, WORD PTR [rbx+r15*2]
    cmp eax, 0x5C
    je gif_nodot
    cmp eax, 0x2E
    jne gif_snext
    mov r14, r15
    jmp gif_havedot
gif_snext:
    dec r15
    jmp gif_scan
gif_nodot:
    jmp gif_search
gif_havedot:
    // extlen = len - dot
    mov rax, r13
    sub rax, r14
    cmp rax, 15
    jbe gif_extok
    mov rax, 15
gif_extok:
    mov r15, rax
    test r15, r15
    jz gif_search
    lea rsi, [rbx+r14*2]
    lea rdi, [rsp+64]
    mov rcx, r15
gif_cpl:
    movzx eax, WORD PTR [rsi]
    cmp eax, 0x41
    jb gif_cstore
    cmp eax, 0x5A
    ja gif_cstore
    add eax, 32
gif_cstore:
    mov WORD PTR [rdi], ax
    add rsi, 2
    add rdi, 2
    dec rcx
    jnz gif_cpl
    mov WORD PTR [rdi], 0
gif_search:
    // buscar en cache
    mov rax, QWORD PTR [rip + gui_icon_n]
    test rax, rax
    jz gif_miss
    xor r13d, r13d
gif_cmp:
    mov rax, QWORD PTR [rip + gui_icon_n]
    cmp r13, rax
    jae gif_miss
    lea rsi, [rsp+64]
    mov rax, r13
    shl rax, 5
    lea rdi, [rip + gui_icon_exts]
    add rdi, rax
    mov ecx, 16
gif_wcmp:
    movzx eax, WORD PTR [rsi]
    movzx edx, WORD PTR [rdi]
    cmp eax, edx
    jne gif_next
    test eax, eax
    jz gif_hit
    add rsi, 2
    add rdi, 2
    dec ecx
    jnz gif_wcmp
    jmp gif_hit
gif_next:
    inc r13
    jmp gif_cmp
gif_hit:
    lea rax, [rip + gui_icon_idx]
    mov eax, DWORD PTR [rax+r13*4]
    jmp gif_ret
gif_miss:
    // SHGetFileInfoW(path, NORMAL, &sfi, 696, 0x4011)
    lea rdi, [rsp+96]
    xor eax, eax
    mov ecx, 87
    rep stosq
    mov rcx, rbx
    mov edx, FILE_ATTR_NORM
    lea r8, [rsp+96]
    mov r9d, 696
    mov QWORD PTR [rsp+32], 0x4011
    call SHGetFileInfoW
    test rax, rax
    jz gif_zero
    mov eax, DWORD PTR [rsp+104]
    mov r15d, eax
    // guardar si hay hueco
    mov rax, QWORD PTR [rip + gui_icon_n]
    cmp rax, 256
    jae gif_retd
    mov r13, rax
    mov rax, r13
    shl rax, 5
    lea rdi, [rip + gui_icon_exts]
    add rdi, rax
    lea rsi, [rsp+64]
    mov ecx, 16
    rep movsw
    lea rax, [rip + gui_icon_idx]
    mov DWORD PTR [rax+r13*4], r15d
    lea rax, [rip + gui_icon_n]
    inc QWORD PTR [rax]
    mov eax, r15d
    jmp gif_ret
gif_retd:
    mov eax, r15d
    jmp gif_ret
gif_dir:
    mov rax, QWORD PTR [rip + gui_icon_dir_ok]
    test rax, rax
    jnz gif_dirhit
    lea rdi, [rsp+96]
    xor eax, eax
    mov ecx, 87
    rep stosq
    mov rcx, rbx
    mov edx, FILE_ATTR_DIR
    lea r8, [rsp+96]
    mov r9d, 696
    mov QWORD PTR [rsp+32], 0x4011
    call SHGetFileInfoW
    test rax, rax
    jz gif_zero
    mov eax, DWORD PTR [rsp+104]
    lea rcx, [rip + gui_icon_dir]
    mov DWORD PTR [rcx], eax
    lea rcx, [rip + gui_icon_dir_ok]
    mov QWORD PTR [rcx], 1
    jmp gif_ret
gif_dirhit:
    mov eax, DWORD PTR [rip + gui_icon_dir]
    jmp gif_ret
gif_zero:
    xor eax, eax
gif_ret:
    add rsp, 808
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    pop rbp
    ret

// gui_select_idx(ECX=idx): seleccion unica + mark + visible + foco.
gui_select_idx:
    push rbx
    push r12
    sub rsp, 104
    mov ebx, ecx
    mov r12, QWORD PTR [rip + gui_list]
    test r12, r12
    jz gsi_ret2
    mov rcx, r12
    mov edx, LVM_GETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jle gsi_ret2
    cmp rbx, rax
    jae gsi_ret2
    // LVITEM 64B en [rsp+32]: zero
    lea rdi, [rsp+32]
    xor eax, eax
    mov ecx, 8
    rep stosq
    mov DWORD PTR [rsp+32], LVIF_STATE
    mov DWORD PTR [rsp+48], 0x3
    // clear all: wParam=-1, state=0
    mov DWORD PTR [rsp+44], 0
    mov rcx, r12
    mov edx, LVM_SETITEMSTATE
    mov r8, -1
    lea r9, [rsp+32]
    call SendMessageW
    // set nuevo
    mov DWORD PTR [rsp+36], ebx
    mov DWORD PTR [rsp+44], 0x3
    mov rcx, r12
    mov edx, LVM_SETITEMSTATE
    movsxd r8, ebx
    lea r9, [rsp+32]
    call SendMessageW
    mov rcx, r12
    mov edx, LVM_SETSELECTIONMARK
    xor r8d, r8d
    movsxd r9, ebx
    call SendMessageW
    mov rcx, r12
    mov edx, LVM_ENSUREVISIBLE
    movsxd r8, ebx
    xor r9d, r9d
    call SendMessageW
    mov rcx, r12
    call SetFocus
gsi_ret2:
    add rsp, 104
    pop r12
    pop rbx
    ret

// gui_move_sel_delta(ECX=delta signed): mark+delta con clamp.
gui_move_sel_delta:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 72
    mov ebx, ecx
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz gms_ret
    mov QWORD PTR [rsp+40], rcx
    mov edx, LVM_GETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jle gms_ret
    mov r12, rax
    mov rcx, QWORD PTR [rsp+40]
    mov edx, LVM_GETSELECTIONMARK
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    cmp rax, 0
    jl gms_nosel
    cmp rax, r12
    jae gms_nosel
    movsxd rdx, ebx
    add rax, rdx
    cmp rax, 0
    jge gms_hiclamp
    xor eax, eax
    jmp gms_go
gms_hiclamp:
    cmp rax, r12
    jl gms_go
    mov rax, r12
    dec rax
    jmp gms_go
gms_nosel:
    cmp ebx, 0
    jge gms_first
    mov rax, r12
    dec rax
    jmp gms_go
gms_first:
    xor eax, eax
gms_go:
    mov ecx, eax
    call gui_select_idx
gms_ret:
    add rsp, 72
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

// gui_handle_nav(ECX=vk) -> EAX 1 atendido / 0 no.
gui_handle_nav:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 72
    mov ebx, ecx
    cmp ebx, VK_DOWN
    je ghn_down
    cmp ebx, VK_UP
    je ghn_up
    cmp ebx, VK_NEXT
    je ghn_next
    cmp ebx, VK_PRIOR
    je ghn_prior
    cmp ebx, VK_HOME
    je ghn_home
    cmp ebx, VK_END
    je ghn_end
    cmp ebx, VK_RETURN
    je ghn_ret
    xor eax, eax
    jmp ghn_out
ghn_down:
    mov ecx, 1
    call gui_move_sel_delta
    mov eax, 1
    jmp ghn_out
ghn_up:
    mov ecx, -1
    call gui_move_sel_delta
    mov eax, 1
    jmp ghn_out
ghn_next:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghn_one
    mov edx, LVM_GETCOUNTPERPAGE
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jg ghn_pgok
ghn_one:
    mov eax, 10
    jmp ghn_pggo
ghn_pgok:
    cmp rax, 1000
    jbe ghn_pggo
    mov eax, 10
ghn_pggo:
    mov ecx, eax
    call gui_move_sel_delta
    mov eax, 1
    jmp ghn_out
ghn_prior:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghn_mone
    mov edx, LVM_GETCOUNTPERPAGE
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jg ghn_ppok
ghn_mone:
    mov eax, 10
    jmp ghn_pgo
ghn_ppok:
    cmp rax, 1000
    jbe ghn_pgo
    mov eax, 10
ghn_pgo:
    neg rax
    mov ecx, eax
    call gui_move_sel_delta
    mov eax, 1
    jmp ghn_out
ghn_home:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghn_home1
    mov edx, LVM_GETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jle ghn_home1
    xor ecx, ecx
    call gui_select_idx
ghn_home1:
    mov eax, 1
    jmp ghn_out
ghn_end:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghn_end1
    mov edx, LVM_GETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jle ghn_end1
    dec rax
    mov ecx, eax
    call gui_select_idx
ghn_end1:
    mov eax, 1
    jmp ghn_out
ghn_ret:
    mov rcx, QWORD PTR [rip + gui_list]
    test rcx, rcx
    jz ghn_ret1
    mov edx, LVM_GETITEMCOUNT
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    test rax, rax
    jle ghn_ret1
    mov r12, rax
    mov rcx, QWORD PTR [rip + gui_list]
    mov edx, LVM_GETSELECTIONMARK
    xor r8d, r8d
    xor r9d, r9d
    call SendMessageW
    cmp rax, 0
    jl ghn_retsel
    cmp rax, r12
    jb ghn_reopen
ghn_retsel:
    xor ecx, ecx
    call gui_select_idx
ghn_reopen:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_open_focused
ghn_ret1:
    mov eax, 1
ghn_out:
    add rsp, 72
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

// gui_edit_proc subclass del Edit: flechas mueven seleccion, Enter abre, Esc colapsa.
gui_edit_proc:
    push rbx
    push r12
    sub rsp, 56
    mov rbx, rcx
    mov r12, r9
    mov r10d, edx
    mov r11, r8
    cmp edx, WM_KEYDOWN
    jne ged_call
    mov eax, r11d
    cmp eax, VK_DOWN
    je ged_nav
    cmp eax, VK_UP
    je ged_nav
    cmp eax, VK_NEXT
    je ged_nav
    cmp eax, VK_PRIOR
    je ged_nav
    cmp eax, VK_HOME
    je ged_nav
    cmp eax, VK_END
    je ged_nav
    cmp eax, VK_RETURN
    je ged_ret
    cmp eax, 0x51
    je ged_ctrlq
    cmp eax, 0x4F
    je ged_ctrlo
    cmp eax, 0x43
    je ged_ctrlc
    cmp eax, VK_ESCAPE
    je ged_esc
    jmp ged_call
ged_ctrlq:
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz ged_call
    xor ecx, ecx
    call PostQuitMessage
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_ctrlo:
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz ged_call
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_open_folder
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_ctrlc:
    mov ecx, 0x11
    call GetKeyState
    test ax, 0x8000
    jz ged_call
    mov ecx, 0x10
    call GetKeyState
    test ax, 0x8000
    jz ged_call
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_copy_path
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_ret:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_hist_push
    mov ecx, VK_RETURN
    call gui_handle_nav
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_nav:
    mov ecx, eax
    call gui_handle_nav
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_esc:
    mov rcx, QWORD PTR [rip + gui_hwnd]
    call gui_on_escape
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_call:
    mov rcx, QWORD PTR [rip + gui_edit_old]
    test rcx, rcx
    jz ged_zero
    mov rdx, rbx
    mov r8d, r10d
    mov r9, r11
    mov QWORD PTR [rsp+32], r12
    call CallWindowProcW
    add rsp, 56
    pop r12
    pop rbx
    ret
ged_zero:
    xor eax, eax
    add rsp, 56
    pop r12
    pop rbx
    ret

// gui_enum_close(RCX=hwnd, RDX=lparam) para EnumWindows: si la clase de la
// ventana es "seek-gui" le manda WM_CLOSE (posteado, no bloquea) y marca
// gui_enum_found=1 para que el llamador reintente hasta que la vieja muera.
// Devuelve 1 (seguir enumerando). Buffer propio de 64 WCHAR en stack.
gui_enum_close:
    push rbx
    // 128 del buffer + margen; rsp queda alineado (8+160)
    sub rsp, 160
    // hwnd
    mov rbx, rcx
    // lpClassName
    lea rdx, [rsp+16]
    // nMaxCount (WCHAR)
    mov r8d, 64
    call GetClassNameW
    test eax, eax
    jz gec_no
    // clase "seek-gui" en UTF-16: 's','e','e','k' (imm64 via reg: no hay
    // cmp r/m64, imm64)
    mov rax, 0x006B006500650073
    cmp QWORD PTR [rsp+16], rax
    jne gec_no
    // '-','g','u','i'
    mov rax, 0x006900750067002D
    cmp QWORD PTR [rsp+24], rax
    jne gec_no
    // fin exacto del nombre (WCHAR nulo)
    cmp WORD PTR [rsp+32], 0
    jne gec_no
    // fase kill (gui_hwnd=0): cerrar toda ventana seek-gui ajena. Con
    // ventana propia (watchdog): solo las MAYORES que la mia — cierra
    // asimetrico, exactamente una instancia mata a la otra (nunca ambas)
    mov rax, QWORD PTR [rip + gui_hwnd]
    test rax, rax
    jz gec_do
    cmp rbx, rax
    jbe gec_no
gec_do:
    mov rcx, rbx
    mov edx, WM_CLOSE
    xor r8d, r8d
    xor r9d, r9d
    call PostMessageW
    lea rax, [rip + gui_enum_found]
    mov QWORD PTR [rax], 1
gec_no:
    add rsp, 160
    pop rbx
    mov eax, 1
    ret

// gui_single_watch: watchdog de instancia unica. Corre en el timer de
// 500ms con la ventana propia ya creada (gui_hwnd!=0; en fase kill no hace
// nada, ahi manda el loop de WinMain). Cierra las seek-gui ajenas con hwnd
// mayor: el menor sobrevive y siempre hay un unico cerrador. Ademas
// reintenta Alt+Space si al arrancar no lo conseguimos.
gui_single_watch:
    mov rax, QWORD PTR [rip + gui_hwnd]
    test rax, rax
    jz gsw_no
    // shadow space + alineacion (40 = 8 mod 16)
    sub rsp, 40
    cmp QWORD PTR [rip + gui_hotkey_ok], 0
    jne gsw_enum
    // recuperar el hotkey si la instancia que lo tenia ya murio
    mov rcx, rax
    mov edx, HOTKEY_ID
    mov r8d, MOD_ALT
    mov r9d, VK_SPACE
    call RegisterHotKey
    test eax, eax
    jz gsw_enum
    mov QWORD PTR [rip + gui_hotkey_ok], 1
gsw_enum:
    lea rcx, [rip + gui_enum_close]
    xor edx, edx
    call EnumWindows
    add rsp, 40
gsw_no:
    ret

.data
gui_cls_main: .short 's','e','e','k','-','g','u','i',0
gui_title: .short 's','e','e','k','-','g','u','i',0
gui_title_bar: .short 's','e','e','k',0
gui_mtxname: .short 's','e','e','k','-','g','u','i','-','i','n','s','t','a','n','c','e','-','v','1',0
gui_cls_edit: .short 'E','D','I','T',0
gui_cls_list: .short 'S','y','s','L','i','s','t','V','i','e','w','3','2',0
gui_cls_status: .short 'm','s','c','t','l','s','_','s','t','a','t','u','s','b','a','r','3','2',0
gui_cls_static: .short 'S','T','A','T','I','C',0
gui_cls_button: .short 'B','U','T','T','O','N',0
gui_logo_txt: .short 's','e','e','k',0
gui_hint_txt: .short 'A','l','t','+','E','s','p','a','c','i','o',0
gui_pin_txt: .short 0xD83D,0xDCCC,0
gui_mode_txt0: .short 0x2630,0
gui_empty_txt: .short 'S','i','n',' ','r','e','s','u','l','t','a','d','o','s',0
gui_iconame_file: .short 'x','.','t','x','t',0
gui_theme_dark: .short 'D','a','r','k','M','o','d','e','_','E','x','p','l','o','r','e','r',0
gui_explorer_name: .short 'e','x','p','l','o','r','e','r','.','e','x','e',0
gui_select_prefix: .short '/','s','e','l','e','c','t',',','"',0
gui_val_recents: .short 'r','e','c','e','n','t','s',0
gui_iconame_dir: .short 'x',0
gui_empty: .short 0
gui_fontface: .short 'S','e','g','o','e',' ','U','I',0
gui_dll_user32: .short 'u','s','e','r','3','2','.','d','l','l',0
gui_dll_uxtheme: .short 'u','x','t','h','e','m','e','.','d','l','l',0
gui_fn_swca: .asciz "SetWindowCompositionAttribute"
gui_fn_swtheme: .asciz "SetWindowTheme"
gui_cue_bar: .short 'B','u','s','c','a','r',' ','e','n',' ','t','o','d','o','s',' ','l','o','s',' ','d','i','s','c','o','s',0
gui_flag_window: .ascii "--window\0"
gui_flag_bar: .ascii "--bar\0"
gui_flag_focus: .ascii "--focus\0"
gui_flag_debounce: .ascii "--debounce\0"
gui_flag_install: .ascii "--install-startup\0"
gui_flag_uninstall: .ascii "--uninstall-startup\0"
gui_flag_exclude: .ascii "--exclude\0"
gui_flag_noexcl: .ascii "--no-excludes\0"
gui_runkey: .short 'S','o','f','t','w','a','r','e',0x5C,'M','i','c','r','o','s','o','f','t',0x5C,'W','i','n','d','o','w','s',0x5C,'C','u','r','r','e','n','t','V','e','r','s','i','o','n',0x5C,'R','u','n',0
gui_runval: .short 's','e','e','k',0
gui_seekkey: .short 'S','o','f','t','w','a','r','e',0x5C,'s','e','e','k',0
gui_msg_inst_ok: .short 's','e','e','k',' ','a','r','r','a','n','c','a',' ','c','o','n',' ','W','i','n','d','o','w','s','.',0
gui_msg_uninst_ok: .short 's','e','e','k',' ','y','a',' ','n','o',' ','a','r','r','a','n','c','a',' ','c','o','n',' ','W','i','n','d','o','w','s','.',0
gui_msg_notinst: .short 's','e','e','k',' ','n','o',' ','e','s','t','a','b','a',' ','e','n',' ','e','l',' ','a','r','r','a','n','q','u','e','.',0
gui_msg_err: .short 'E','r','r','o','r',' ','d','e',' ','r','e','g','i','s','t','r','o','.',0
gui_col0: .short 'N','o','m','b','r','e',0
gui_col1: .short 'C','a','r','p','e','t','a',0
gui_col2: .short 'M','o','d','i','f','i','c','a','d','o',0
gui_fmt_date: .short '%','0','4','d','-','%','0','2','d','-','%','0','2','d',0
gui_cue: .short 'B','u','s','c','a','r',' ','a','r','c','h','i','v','o','s',' ','(','t','o','d','o','s',' ','l','o','s',' ','d','i','s','c','o','s',')',0
gui_p_arch: .short 'a','r','c','h','i','v','o','s','='
gui_p_idx: .short 'i','d','x','='
gui_p_match: .short 'c','o','i','n','c','i','d','e','n','c','i','a','s','='
gui_p_time: .short 'f','i','l','t','r','o','='
gui_p_arena: .short 'a','r','e','n','a','='
gui_p_disk: .short 'd','i','s','c','o','s','='
gui_titlepre: .short 's','e','e','k','-','g','u','i',' ','-',' '
gui_titlemid: .short ' ','r','e','s','u','l','t','a','d','o','s',' ','(',' '
gui_titlesuf: .short ' ','a','r','c','h',')',0
gui_verb_open: .short 'o','p','e','n',0
// GUIDs little-endian: {DDDDDDDD-0000-0000-C000-000000000046}
gui_iid_ctxmenu: .long 0x000214e4
.short 0x0000, 0x0000
.byte 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46
gui_iid_ctxmenu2: .long 0x000214f4
.short 0x0000, 0x0000
.byte 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46
gui_iid_ctxmenu3: .long 0x000214f5
.short 0x0000, 0x0000
.byte 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46
gui_iid_folder: .long 0x000214e6
.short 0x0000, 0x0000
.byte 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46

.bss
gui_hinst: .space 8
gui_hwnd: .space 8
gui_hmutex: .space 8
gui_enum_found: .space 8
gui_hotkey_ok: .space 8
gui_edit: .space 8
gui_list: .space 8
gui_status: .space 8
gui_mode: .space 8
gui_focus_req: .space 8
gui_pinned: .space 8
gui_fmode: .space 8
gui_hmode: .space 8
gui_hicon_file: .space 8
gui_hicon_dir: .space 8
gui_hempty: .space 8
gui_hrepair: .space 8
gui_lasttick: .space 8
gui_tick_changed: .space 4096
gui_tick_buf: .space 65536
gui_panel: .space 8
gui_screenw: .space 8
gui_screenh: .space 8
gui_barx: .space 8
gui_bary: .space 8
gui_brush: .space 8
gui_hlogo: .space 8
gui_hhint: .space 8
gui_hpin: .space 8
gui_hthread: .space 8
gui_gen: .space 8
gui_busy: .space 8
gui_debounce: .space 8
gui_sort_col: .space 8
gui_sort_dir: .space 8
gui_sweep_cursor: .space 8
gui_hist_n: .space 8
gui_hist_pos: .space 8
gui_qlen: .space 8
gui_query: .space 2050
gui_files: .space 8
gui_total: .space 8
gui_count: .space 8
gui_ms: .space 8
gui_disks: .space 8
gui_trunc: .space 8
gui_sp: .space 8
gui_stack: .space 524288
gui_items: .space 800000
gui_pat: .space 65536
gui_child: .space 65536
gui_strip: .space 65536
gui_pathw: .space 65536
gui_find: .space 608
gui_drivebuf: .space 8
gui_msg: .space 48
gui_icc: .space 8
gui_wcx: .space 80
gui_lvc: .space 40
gui_sb0: .space 192
gui_sb1: .space 192
gui_sb2: .space 192
gui_sb3: .space 192
gui_sb4: .space 192
gui_sbline: .space 1024
gui_titlebuf: .space 256
gui_selidx: .space 1024
gui_selok: .space 1024
gui_fullpidl: .space 2048
gui_childpidl: .space 2048
gui_ctxmenu2: .space 8
gui_ctxmenu3: .space 8
gui_idx_ws: .space 8
gui_idx_ready: .space 8
gui_fqalen: .space 8
gui_fqa: .space 8192
// query normalizada (una vez por filtrado): UTF-8 para nombres, UTF-16 para rutas
gui_fqnlen: .space 8
gui_fqn: .space 1024
gui_qnlen: .space 8
gui_qn: .space 2048
// valor de is_glob para skc_score_rec: 0 normal, 1 glob, 2 anclado
gui_globval: .space 8
// firma de 64 bits por record (pre-filtro del filtro por nombre) + la
// mascara de condiciones de la query
gui_bloom: .space 8
gui_qmask: .space 8
gui_prevqa: .space 8192
gui_prevlen: .space 8
gui_prevwild: .space 8
gui_prevpathq: .space 8
gui_pathbuf: .space 65536
gui_excl_wbuf: .space 520
gui_th_base: .space 8
gui_th_abeg: .space 8
gui_th_abrk: .space 8
gui_th_flo: .space 8
gui_th_fhi: .space 8
gui_th_fskip: .space 8
gui_th_start: .space 64
gui_th_end: .space 64
gui_th_tot: .space 64
gui_th_got: .space 64
gui_th_h: .space 64
gui_th_bufs: .space 6400000
gui_convpath: .space 65536
gui_cmpbuf: .space 65536
gui_install_req: .space 8
gui_uninstall_req: .space 8
gui_autohid: .space 8
gui_exepath: .space 65536
gui_exequoted: .space 65540
gui_edit_old: .space 8
gui_himagelist: .space 8
gui_hfont: .space 8
gui_icon_n: .space 8
gui_icon_exts: .space 8192
gui_icon_idx: .space 1024
gui_icon_dir_ok: .space 8
gui_icon_dir: .space 8
gui_hist: .space 32768
