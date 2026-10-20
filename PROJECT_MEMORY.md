# PROJECT_MEMORY — bitácora de seek-asm

## 2026-10-09 — Instancia única en seek-gui (la nueva reemplaza a la actual)
- Cambio: `src/gui.s` — mutex con nombre "seek-gui-instance-v1" en `WinMain`; si `ERROR_ALREADY_EXISTS`, loop `EnumWindows` + `PostMessage(WM_CLOSE)` a toda ventana clase `seek-gui` + `WaitForSingleObject(mutex,500)`, con early-break al ver 0 ventanas viejas. Watchdog `gui_single_watch` en el timer de 500ms cierra duplicados con hwnd mayor que el propio (cierre asimétrico) y reintenta `RegisterHotKey` si falló.
- Por qué: pedido del usuario ("que no se pueda abrir dos veces… se cierra la actual y se abre la nueva"); el lanzamiento simultáneo 0ms dejaba 2 instancias para siempre sin watchdog.
- Evidencia: 3 escenarios (normal/300ms/0ms) → siempre 1 instancia; cross-mode barra→`--window` reemplaza; hotkey ocupado por seek-gui; golden GUI notepad=12 y CLI=12 (2351548 archivos); 0 crashes nuevos en WER. Detalle y scripts en `BENCH.md` entrada "Instancia unica".
- Trampas GAS costadas aquí: comentarios `//` solo en línea propia (trailing = error de división); `EnumWindows` rcx=func/rdx=lParam; `CreateMutexW` rcx=lpAttr/edx=owner/r8=lpName; clase UTF-16LE vs QWORD ANSI; no existe `cmp r/m64,imm64`.
- Pendiente: acrylic/mica sigue apagado (B11 AV sin aislar; struct SWCA ya corregido para reactivarlo después).

## 2026-10-11 - Rust+ASM: busqueda por ruta, exclude wildcard, 4 fixes
- Cambio: crate `rs/seekcore` (Rust `no_std` staticlib, `panic=abort`) enlazado en seek.exe y seek-gui.exe (`build.bat` corre cargo primero). Matchers C exportados: `skc_query_is_pathq`, `skc_match_path`, `skc_excl_glob`, `skc_match_rec` (ruta desde record 12B, UTF-8->U16 con surrogate pairs, caps plen/qlen/depth/hops).
- Por que: pedido del usuario "integrando codigo rust con ensamblador; verificar busqueda y exclusion de rutas".
- Evidencia: CLI suite 9/9 (golden notepad=12 y dll-no-excl=52647 intactos; ruta exacta=1; glob `windows\system32\*.dll`=4433; `/`=21108; excludes plain/wildcard/path/dos-wildcards ok). GUI: pathq -> 4 con columna Carpeta; `--exclude *seek-asm*` -> *.exe 6450->6446 y pathq 4->0 (registro verificado con gdb: token limpio, len=10). Harness `skc_rec_test.c` 12/12.
- Fixes: (1) guard page de Windows: `sub rsp,65600` saltaba el guard -> probe de paginas estilo `__chkstk` en `gui_filter_worker`; (2) alineacion rsp en `scan_root_ws`/`mft_ensure` (`and rsp,-16`, epilogo `lea rsp,[rbp-56]`); (3) `skc_match_rec`: doble `\` + nombres UTF-8 de 2 bytes; (4) `gui_parse_excl`: `MultiByteToWideChar` con `cch=-1` arrastraba la comilla final de la cmdline -> largo exacto del token.
- Trampas: el dbg de gui.s se desactualiza en cada edit (reconstruir antes de trazar); PowerShell `-File` no pasa arrays (`-guiArgs 'string'`); Alt/Space inyectado por la captura contamina el edit - leer conteos con SendMessage al momento.
- Pendiente: bugs viejos sin tocar (icono tardio sin iImage, archivos faltantes, pill auto-abre, primera indexacion lenta).
- Addendum (mismo dia): un test CLI sin dos-puntos (g\proyectos\...) dio 0 y parecio regresion; la causa fue la query (los paths llevan G:). Igual se agrego normalizacion letter: inicial en match_text (lib.rs): g\proyectos\seek-asm\seek ahora matchea en CLI y GUI. Re-verificado: sin colon=3, con colon=1, goldens notepad=12 / glob=4433 intactos, harness 12/12, GUI *.exe=6448 y pathq=2 con binarios oficiales 14:53.

## 2026-10-12 - Restyling moderno GUI (solo src/gui.s)
- Cambio: Segoe UI 11pt ClearType (quality=5); edit+lista planos sin CLIENTEDGE; pildora 700x40 r18; paleta 1E1E1E/F2F2F2/seleccion DC783A/hot 2D2D2D; sin cabecera (LVS_NOCOLUMNHEADER); columnas 210+440; status STATIC oscuro de una linea con SetWindowTextW (respeta B12, sin SB_SETBKCOLOR).
- Por que: pedido "se ve muy vieja la interfaz" (cabecera y status blancos, fuente sin suavizar, bordes hundidos).
- Evidencia: runI/runJ/runK (*.exe=6446, pathq=2, viva), screenshots antes/despues, 0 choques seek en WER. Bug extra: prelen 15 de gui_p_match copiaba la 'f' siguiente ("coincidencias=f6446") -> 14.
- Trampas: scrollbar horizontal sale si cols > cliente (684 menos vscroll); edit de README por numero de linea con python (el edit textual falla por acentos).
- Pendiente: memoria de ultimos abiertos (pedido previo, sin implementar); scrollbar vertical sigue nativo claro; seleccion total azulada pre-existente; iconos repetidos.

## 2026-10-12 - Esquinas: radio 18 real, fuente grayscale, pin oscuro
- Cambio (solo src/gui.s): BAR_R 18->36 (elipse: radio real 9->18); font quality 5->4 (grayscale, sin franja RGB); pin BUTTON->STATIC SS_NOTIFY (cara blanca eliminada; toggle intacto).
- Por que: reporte "esquinas pixel con blanco" (zoom x8: escalera GDI + franja ClearType + cara blanca del pin con tema).
- Evidencia: captura x8 sobre fondo blanco, pin-toggle 4/4, runL (6446/2/viva), pin reseteado a off.
- Trampas: `//` trailing en .equ = build roto en silencio (verificar timestamp del exe); primer toggle tras restore confunde si pin=1 persistido (era toggle correcto, no swallow).
- Pendiente: memoria de ultimos abiertos; scrollbar vertical nativo; seleccion azulada; iconos.

## 2026-10-12 - Ranking por relevancia + boton Archivos/Carpetas (Rust+ASM)
- Cambio: scoring en Rust (tiers 6/5/4 + boost modo 2000 + largo), empaquetado (score<<32|~idx), sort+unpack (single/incremental/merge reescrito), boton modo owner-draw con iconos (Todos/Archivos/Carpetas, persiste `mode`).
- Por que: pedido "mayor coincidencia primero" + "boton para priorizar carpetas o archivos".
- Evidencia: harness 15/15; runN/runO/runP (orden exacta>prefijo>subcadena; dirs vs files por modo); ciclo 0>1>2>0 con registro; WER limpio.
- Bugs: SIB *12, label duplicada, emoji-via-STW = AV comctl, frames desalineados (N debe ser 8 mod 16), nombre `mode` sin NUL (save+load).
- Trampas: tipear por WM_CHAR con scope PID (SetWindowTextW no dispara; first-match agarra stales).
- Pendiente: columna fecha + orden por columnas (pedido siguiente); recents; scrollbar vertical; seleccion azulada; iconos lista.

## 2026-10-12 - Busqueda inteligente: tildes, espacios, relativas, mayusculas
- Cambio: Rust (`fold` Latin-1 aA-cC-eE-iI-nN-oO-uU-yY, `normalize_q`/`normalize_qa` con trim+`./`-strip+trail+colon, matchers de bytes por caracter decodificado, `skc_qpre` helper) + `cli_trim_query` en main.s + prefilter con fskip tri-estado y 2da chance 0xC3 (single+worker).
- Por que: pedido "inteligente con mayusculas, espacios vacios, rutas relativas, etc".
- Evidencia: harness smart 34/34 (tildes exact/prefix/glob, trim, ./, trail, CJK `?` legado, qpre, excludes); rank+rec harnesses OK; CLI 12/12/12 (golden+trailing+caps) y dll 52673 estable (crecimiento de disco, no regression); GUI `camion`>camion.txt, `  NOTEPAD  `>12, `ati`>76K ordenados, `atico`>atico.txt primero.
- Bug cazado: prefilter con primer byte crudo perdia queries con blancos (0 resultados); fskip 0/1/2 + 0xC3 lo resuelve sin tocar match.s.
- Trampa: no pipear builds a `Select-Object -First` (mata el pipe, exe queda viejo); 5 choques WER 14:09-14:22 mismo bucket = binario rank3 (frame desalineado, ya fixeado); 0 choques desde build_rank4.
- Divergencia documentada: CLI nombres = ASCII literal (match.s intacto por perf); todo lo demas full-smarts.
- Pendiente: columna fecha + orden por columnas; recents; resto viejo.

## 2026-10-12 - Visual: seleccion real + estado vacio
- Cambio (solo src/gui.s): `gcd_item` verifica seleccion con `LVM_GETITEMSTATE` en vivo (nuevo `.equ LVM_GETITEMSTATE`); overlay owner-draw `IDC_EMPTY` ("Sin resultados" gris) con show/hide en refresh_panel/final/prog/escape + layout en ambas ramas + `gui_update_empty`.
- Por que: todas las filas pintaban azul con selected=0 (medido ST=0x201 x65 via gdb, pixel #3A78DC exacto, disassembly correcto); panel negro con 0 resultados.
- Evidencia: navy+1 sola fila azul con flecha (row0=3, resto 0), overlay visible/oculto por screenshot, `notepad` 12 intacto, filtro=1ms, WER limpio.
- Bugs: frame `update_empty` desalineado (push+sub40: N debe ser 8 mod 16) = BEX64 (fix sub64); overlay tapado por lista (z-order) = SetWindowPos TOP en creacion+show; STATIC-text que nunca pinta = owner-draw.
- Trampas: hook de refresh en final/prog NO alcanza (el per-keystroke es refresh_panel); Write-Output no sale de callbacks nativos (juntar en lista); CopyFromScreen pierde contra auto-hide (PrintWindow para ocultas).
- Pendiente: columna fecha + orden por columnas; recents; scrollbar vertical nativo; causa raiz del SELECTED stale (verdad en vivo lo vuelve cosmetico).

## 2026-10-14 - Fix cierre al tipear (AV 0xc0000005 en filtro incremental)
- Cambio (solo src/gui.s): revertidos 2 cambios malos � (1) gui_ss_mcopy vuelve a mov eax/not eax (mov eax pone en cero el alto; el 
ot rax de 64 bits guardaba ~score en gui_items y la siguiente tecla lo usaba como idx*12 = AV en gui_ss_incloop); (2) gtw_pathq vuelve al buffer de stack [rsp+64] por hilo (el gui_rep_buf global compartido entre 8 hilos causaba race; [rsp+32..63] son los args y el buffer arranca en +64: sin solape). Etiqueta gui_rep_buf eliminada.
- Por que: reporte "se traba y se cierra"; WER mostraba 1 choque seek-gui.exe 0xc0000005 offset 0x2d36 = mov [r14+rdx],r10 del loop incremental leyendo gui_items con alto basura.
- Evidencia: rebuild 18:06 fresco; CLI notepad/pathq ok; GUI --window: 
otepad=12 viva, *.exe=7219 viva + *.exex=0 viva (paralelo+incremental sin AV); WER sin choques nuevos (solo el de las 18:04 previo al fix).
- Trampa: mov eax,m32 ya deja el alto en 0 � no era basura; el 
ot debe ser de 32 bits para desempaquetar ~idx.

## 2026-10-15 - Deteccion de archivos nuevos en vivo + Esc en dos pasos
- Cambio (solo `src/gui.s`): (1) auto-reparacion enganchada al timer de 500 ms (`gw_timer_hide` llama `gui_maybe_repair`); `REPAIR_MS` 120000->30000; `gr_cleanup` calibra `gui_lasttick` (sin esto el guard anti-trunc reintentaba cada 500 ms); `gui_on_hotkey` recarga hwnd de `[rsp+40]` tras `gui_maybe_repair` (pisa RCX cuando dispara `CreateThread`). (2) Esc en dos pasos: con texto -> limpia + colapsa panel; sin texto -> oculta la barra entera (`SW_HIDE` + `gui_autohid=0`, el timer no la revive; vuelve con `Alt+Espacio`); guard `gui_mode` para no ocultar la ventana en `--window`.
- Por que: reporte "a los nuevos archivos no me los detecta, tengo que cerrar y volver a abrir" (el tick solo corria desde el hotkey con gate de 120 s y nunca desde el timer de la barra); pedido de Esc en dos pasos.
- Evidencia: `build.bat` EXIT=0; `seek.exe`/`seek-gui.exe` 07:51:14 > `gui.s` 07:51:04 (incluye el Esc en dos pasos). Prueba funcional a cargo del usuario (el agente no corre e2e por pedido explicito). `seek_dbg.exe`/`seek-gui_dbg.exe` borrados.
- Trampas: `gui_maybe_repair` pisa RCX cuando dispara `CreateThread` - todo caller debe recargar hwnd del stack; el segundo Esc debe setear `gui_autohid=0` o `gui_check_autohide` revive la barra al volver el foco al escritorio; `gui_hide_panel` es no-op en `--window` (mismo guard `gui_mode`).
- Pendiente: verificar el tick en uso (archivo nuevo con la app abierta, ~30 s + barrido); features viejas (columna fecha + orden por cabecera, recents, scrollbar vertical nativo, seleccion azulada, iconos repetidos).

## 2026-10-15 - Correccion: 0 resultados intermitentes (repair vs filtro)
- Cambio (solo `src/gui.s`): carrera entre el hilo de repair (`gui_repair`/`skc_dir_tick`, que tombstonea y re-escanea records) y el filtro en el hilo UI (`gui_start_search`). Fix: flag `gui_busy` (0/1) puesto a 1 al entrar a `gui_start_search` y 0 en su salida (`gui_ss_ret`); `gui_maybe_repair` no lanza si busy=1; el hilo de repair aborta (`gr_cleanup`) si busy=1 al arrancar o en cada dir del loop; al terminar con cambios (`gr_finish_post`) se resetean `gui_prevlen`/`gui_prevwild`/`gui_prevpathq` para forzar busqueda completa al refiltrar (no incremental sobre records tombstoneados).
- Por que: reporte "busco algo y me da 0 resultados, a veces funciona, aveces no" (intermitente, coincidente con el tick cada 30 s).
- Evidencia: build.bat EXIT=0; seek-gui.exe 20:55:54 > gui.s 20:33:31.
- Trampas: el repair muta records por tombstone (`mov QWORD [rec],0`) mientras el filtro los lee -> resultados parciales/0; el incremental solo re-filtra los resultados previos, por eso hay que forzar full search tras un repair con cambios.
- Pendiente: verificar en uso (busquedas repetidas mientras corre el tick); si persiste, revisar Rust matchers (`skc_score_name`/`skc_score_rec`) y el prefilter fskip.

## 2026-10-15 - Columna fecha + orden por cabecera
- Cambio (`src/gui.s` + `rs/seekcore/src/lib.rs`): se quito LVS_NOCOLUMNHEADER (cabecera visible); columna "Modificado" (130 px) con mtime formateado YYYY-MM-DD via FileTimeToSystemTime + wsprintfW; LVN_COLUMNCLICK -> gui_sort_column (toggle col/dir) -> Rust skc_sort_items (quicksort iterativo por nombre/carpeta/fecha, asc/desc). Rust: skc_sort_items con modo 0/1/2 y ascending.
- Evidencia: build.bat EXIT=0; seek-gui.exe 22:04:20 > gui.s 22:04:17.
- Trampas: LVN_COLUMNCLICK = -108; WS_MTIME_BASE=96; SYSTEMTIME offsets year=0 month=2 day=6; trailing `//` en GAS = division.
- Pendiente: (2) resaltar coincidencia, (7) filtro en hilo, (8) acrilico (re-enable manual), (14) indice a disco, (15) harness de tests. Acrilico se dejo desactivado por riesgo de AV.

## 2026-10-15 - Recientes persistentes (HKCU\\Software\\seek "recents")
- Cambio (solo `src/gui.s`): `gui_save_recents` (gwmain_exit) serializa `gui_hist` como REG_MULTI_SZ en "recents"; `gui_load_recents` (gw_create) lo lee y repuebla `gui_hist`/`gui_hist_n`. El historial sobrevive entre sesiones.
- Evidencia: build.bat EXIT=0; seek-gui.exe 21:54:01 > gui.s 21:54:00.
- Trampas: trailing `//` en GAS = division (error); comentarios solo en linea propia. RegQueryValueExW requiere lpData en el 5.o slot y size en el 6.o.
- Pendiente: (1) columna fecha + orden por cabecera, (12) resaltar coincidencia, (7) filtro en hilo, (8) acrilico, (14) indice a disco, (15) harness de tests.

## 2026-10-15 - Debounce opcional + historial de busquedas (Ctrl+Up/Down)
- Cambio (solo `src/gui.s`): (6) `--debounce N` (ms, default 0=sin debounce): `gui_parse_flags` parsea el entero; `gw_cmd_change` programa `TIMER_SEARCH` con ese intervalo en vez de filtrar inmediato; el handler de timer dispara `gui_start_search` (one-shot). (13) historial en memoria (16 entradas x 1024 WCHAR en `gui_hist`): `gui_hist_push` guarda el texto del Edit si no esta vacio ni duplica el ultimo (se llama en Enter y al abrir un resultado); `gui_hist_up/down` recuerdan la entrada anterior/siguiente con Ctrl+Up/Ctrl+Down (Ctrl+Down al final limpia el Edit). `gui_hist_n`/`gui_hist_pos` en .bss.
- Evidencia: build.bat EXIT=0; seek-gui.exe 21:47:43 > gui.s 21:47:37.
- Trampas: el timer de debounce se mata antes de reprogramar para no acumular; si `gui_debounce=0` se mantiene el comportamiento sincrono (sin cambios de timing).
- Pendiente: (1) columna fecha + orden por cabecera, (2) recientes persistentes en registro, (12) resaltar coincidencia, (7) filtro en hilo, (8) acrilico, (14) indice a disco, (15) harness de tests.

## 2026-10-15 - Lote UX: seleccion azul, iconos 256, scrollbar oscura, salir, abrir carpeta, copiar ruta
- Cambio (solo `src/gui.s` + `build.bat`): (4) seleccion custom-draw 0xDC783A -> 0xF07800 (azul vivid); (5) cache de iconos 64 -> 256 entradas (gui_icon_exts 2048->8192, gui_icon_idx 256->1024, tope 64->256); (3) scrollbar oscura via SetWindowTheme(hwnd, "DarkMode_Explorer") tras crear el ListView (build.bat + -luxtheme); (9) Ctrl+Q sale (PostQuitMessage) en wndproc y edit subclass; (10) Ctrl+O abre la carpeta contenedora del seleccionado (gui_open_folder: ShellExecuteW explorer /select,"path"); (11) Ctrl+Shift+C copia la ruta al portapapeles (gui_copy_path: OpenClipboard/GlobalAlloc/CF_UNICODETEXT).
- Evidencia: build.bat EXIT=0; seek-gui.exe 21:30:56 > gui.s 21:30:52.
- Pendiente: (1) columna fecha + orden por cabecera, (2) recientes, (6) debounce, (12) resaltar coincidencia, (13) historial en Edit, (7) filtro en hilo, (8) acrilico, (14) indice a disco, (15) harness de tests.

## 2026-10-15 - Apertura de archivos durante el indexado
- Cambio (solo `src/gui.s`): `gui_idx_path` ya no devuelve 0 mientras indexa. Rama nueva `gip_indexing` reconstruye la ruta (UTF-8) caminando la cadena de padres en un buffer propio del hilo UI (rsp+128, max 128 niveles) y convierte con MultiByteToWideChar + strip, sin tocar los buffers compartidos del ws (WB_SEG/DIRPATH/BPCIDX) que el indexer escribe. Enter/doble-click y menu contextual ahora funcionan antes de que termine el indexado.
- Por que: reporte "no me deja abrir nada hasta que no termine de indexar" (gui_idx_path estaba gated en gui_idx_ready).
- Evidencia: build.bat EXIT=0; seek-gui.exe 21:28:26 > gui.s 21:28:19.
- Trampas: el walk de padres usa el record (name ptr + parent u32, alto bit enmascarado); tombstone (name=0) aborta; tope de 128 niveles evita bucles; DF=0 (cld) antes de rep movsb.
- Pendiente: verificar en uso (abrir archivos con idx parcial); si falla, revisar gui_open_focused/gui_show_menu que tambien llaman gui_idx_path.

## 2026-10-19 - Barrido por franjas: fin del uso fijo de CPU + deteccion en vivo verificada
- Cambio (`rs/seekcore/src/lib.rs` + `src/gui.s`): `skc_dir_tick` ahora recibe un **cursor** (in/out) y hace el barrido **por franjas**: procesa un arco contiguo del circulo de records y se corta al agotar `TICK_BUDGET_MS`=500 ms (const en Rust); el cursor global `gui_sweep_cursor` se resetea al reindexar (`gui_start_index`). El gate del timer paso de `REPAIR_MS`=30 s a `REPAIR_SLICE_MS`=10 s: una franja de 500 ms cada 10 s en vez de un pico de ~6 s cada 30 s. Firma: `skc_dir_tick(rec, n, mt, out, cap, tmp, tmpcap, cursor)`.
- Por que: el uso fijo de CPU (~20% de un core, picos de 6 s) era el tick completo: stat de ~300K dirs + reconstruccion de la ruta completa de cada uno. Medido con muestras de 2 s: `51,6 | 43,8 | 74,2 | 60,9 | 46,1 | 0 | 0 | ...` (picos) -> despues `~500 ms de trabajo cada 10 s` = 4-6% de un core, 0.3-0.4% del total en 16 hilos, sin picos.
- Evidencia: archivo creado con la app corriendo (`zzfin_173118.txt`) aparece en los resultados en 50-90 s (status leido por Win32: `WM_SETTEXT` + `WM_COMMAND EN_CHANGE` y el STATIC del status). Antes fallaba: 0 resultados a los 5 min. El tick detecta dirs reales (`G:\steam`, `G:\Dev\npm-cache`, dirs de npm/opencode) y el reccnt crece (3.010.338 -> 3.053.417) = el rescan append funciona.
- Trampas: (1) **alineacion de pila**: con 6 pushes + `sub rsp,192` el `rsp` queda en 8 (mod 16) -> los `call` desalineados revientan en `memmove` de ntdll (0xC0000005 en ntdll, no en mi codigo). Con 200 queda alineado. (2) El 8.o argumento de una llamada va en `[rsp+56]`: en `gui_repair` los locales arrancan en `[rsp+64]` (`mygen`), asi que un 9.o argumento pisaba `mygen` -> el presupuesto quedo como const en Rust. (3) `gui_strcpy` copia tambien el NUL; en `gui_utoa` los digitos se generan hacia abajo (el mas significativo queda en la direccion mas baja) y se copian **hacia adelante**.
- Pendiente: (2) resaltar coincidencia en el nombre, (3) filtro en hilo aparte, (4) acrilico, (5) indice a disco, (6) harness de tests. Ajustables segun preferencia: `REPAIR_SLICE_MS` (10 s) y `TICK_BUDGET_MS` (500 ms) - subir el budget baja la latencia de deteccion y sube la CPU.

## 2026-10-19 - Fix: la busqueda por ruta en la GUI no matcheaba nada (0 resultados)
- Cambio (solo `src/gui.s`): en los dos call sites de `skc_score_rec` se corrigio el orden de los 4 argumentos de pila. La firma Rust es `skc_score_rec(rec, idx, q, qlen, is_glob, mode, buf, buflen)` (4 en registros rcx/rdx/r8/r9 + 4 en pila +32/+40/+48/+56), pero el ASM pasaba `(is_glob, buf, buflen, mode)`: el Rust recibia `buflen` = el modo (0/1) y salia por `buflen < 8` -> 0 para todo record. Call sites: `gui_ss_pathq` (loop single) y `gtw_pathq` (worker del filtro paralelo).
- Por que: el usuario reporto "no me permite buscar rutas enteras de carpetas, no esta indexando C:, no esta encontrando varias carpetas". Las tres quejas eran el mismo bug: cualquier query con `\` o `/` devolvia 0 coincidencias (tambien con el filtro incremental, que fuerza busqueda completa para pathq). C: SI esta indexado (4 discos: C:, D:, E:, G: - `GetDriveTypeW` acepta DRIVE_FIXED(3) y DRIVE_REMOVABLE(2)); la percepcion de "no indexa C:" venia de que `C:\...` no encontraba nada.
- Evidencia: antes `C:\Users\perca`=0 y `Users\perca`=0 (con `perca` a secas=372); despues `C:\Users\perca`=335193, `C:\`=395893, `C:\Users`=335278, `C:\Program Files`=54511, `G:\Proyectos\seek-asm`=58, `perca\Desktop`=1541, `C:\Users\perca\*.txt`=10696, `C:/Users/perca`=310019, `C:\Users\perca\Desktop\*`=1540. Las carpetas SI matchean por nombre (`noblex-32ld868-fw`=1, `frontend`=1493). `C:\Windows`=0 y `C:\Users\perca\AppData\Local\Temp`=0 son las exclusiones por defecto de scan.s (`\windows\`, `appdata\local\temp`, `\node_modules\`, `$Recycle.Bin`, `prefetch`, `__pycache__`...), no un bug.
- Trampas: (1) el layout de `NMLVDISPINFO`/`LVITEMW` NO tiene `lParam` entre `stateMask` y `pszText` (SDK y MinGW coinciden): `pszText`=48, `cchTextMax`=56, `iImage`=60 relativos al NMLVDISPINFO - los offsets de la app en `gui_fill_item` estan bien, no tocarlos. (2) `LVM_GETITEMW` sobre una lista virtual devuelve la cache del ultimo pintado: si la ventana esta oculta (auto-hide) devuelve basura, no un bug del handler. (3) `NMLVDISPINFO` en MinGW sin `-DUNICODE` es la variante ANSI: usar `NMLVDISPINFOW` en los tests. (4) Para probar funciones Rust sin la app: linkear `libseekcore.a` con un .c chico (`gcc test.c libseekcore.a -lkernel32`) y armar un indice falso en memoria.
- Pendiente: (a) la query de ruta cuesta ~1.5-2.5 s sobre 3M records (reconstruye la ruta de cada record y congela el hilo UI): optimizacion candidata = cache de ruta por padre en el worker (buffer por hilo, no static: el filtro paralelo usa 8 hilos) o `--debounce`. (b) Decidir si el modo "todo" matchea tambien contra la ruta (hoy la query sin `\` matchea solo el nombre, al estilo de un buscador de nombres; Everything matchea la ruta completa).

## 2026-10-20 - Velocidad: filtro de ruta 1.3s -> 90-180ms, tipeo 40-80ms -> 0-5ms
- Cambio (`rs/seekcore/src/lib.rs` + `src/gui.s`): (1) `skc_score_rec` cachea la **pila de ancestros por hilo** dentro del buffer que ya usaba (el indice esta en orden DFS, asi que el padre casi siempre esta en la pila: la ruta se arma con un prefijo + el nombre, O(1), en vez de recorrer la cadena de padres y convertirla, O(profundidad)); el cache se resetea al empezar cada filtrado (`gui_pathbuf[0]=0` y `[rsp+64]=0` en el worker). (2) la query se **normaliza una vez por filtrado** (`skc_qnorm8` UTF-8 / `skc_qnorm` UTF-16) en vez de por record (antes cada `skc_score_name`/`match_text` normalizaba con un array de 1-2KB en la pila). (3) **modo anclado**: `is_glob`=2 (prefijo) o 3 (glob anclado): si la query arranca con la unidad (`X:\...`) el match es un prefijo de la ruta, asi que se compara al vuelo y se corta al divergir. (4) **debounce por defecto = 120 ms** (antes 0 = filtrar en cada tecla); `--debounce 0` lo deja instantaneo, `--debounce N` lo ajusta.
- Evidencia: `C:\`=1264->93ms, `C:\Users\perca`=1336->181ms, `G:\Proyectos\seek-asm`=1157->129ms, `C:\Users\perca\*.txt`=1685->406ms, nombre `perca`=102->79ms; tipeo (probe con WM_SETTEXT+EN_CHANGE): el envio de cada tecla paso de 37-84ms a **0-5ms** y el incremental (query que extiende la anterior) da 0ms. Coincidencias verificadas: 291649 / 352389 / 10687 / 59 / 1542.
- Trampas (todas pisadas en el camino): (1) **en GAS `mov rcx, QWORD PTR [rip + sym]` carga el CONTENIDO de sym, no su direccion**: para pasar un puntero va `lea` (un `mov` hizo que el Rust leyera desde un puntero basura: 115s de filtro, 0 coincidencias y crash en msvcrt). (2) Las rutas del indice llevan el prefijo `\\?\` (4 chars) de las rutas largas: el match anclado tiene que saltar esos 4 chars (si no, 0 resultados). (3) La pila de ancestros del cache tiene 64 entradas: las cadenas mas profundas hay que NO cachearlas (si no, escrituras fuera del arreglo: cache corrupto + crash). (4) El cache se actualiza **siempre**, aun cuando el record no matchea: si se saltea, la pila queda vieja y las rutas siguientes se arman con prefijos equivocados. (5) Alineacion de pila: con N pushes el `sub rsp, X` tiene que dejar el `rsp` en 16 (mod 16) en los `call` (un `call` desalineado revienta en el memmove de ntdll).
- Pendiente: (1) indice invertido (trigramas) para que el filtro por nombre no escanee los 3M records: hoy el piso es ~80-100ms por tecla nueva y 0ms si la query extiende la anterior (el incremental solo aplica si la anterior dejo <=100K resultados). (2) Filtro en hilo aparte (el UI se congela 80-400ms durante el filtrado). (3) Indexar las unidades en paralelo: el scanner usa buffers del ws compartidos (WB_SEG/WB_DIRPATH/WB_BPCIDX) y hoy se secuencializa por eso (el CLI los paraleliza y races). (4) (2) resaltar coincidencia, (4) acrilico, (5) indice a disco, (6) harness de tests.
- Harness: `rs/seekcore` se puede testear sin la app: un .c chico que linkea `libseekcore.a` (`gcc test.c rs/seekcore/target/x86_64-pc-windows-gnu/release/libseekcore.a -lkernel32`) arma un indice falso en memoria (records de 12B + nombres UTF-8 con prefijo de largo) y compara los scores contra una referencia en C. Asi se detectaron los bugs 2, 3 y 4 de arriba (el harness tiene que incluir el prefijo `\\?\` y arboles de >64 niveles).

## 2026-10-20 — Firma de 64 bits (estrechar candidatos) + crash preexistente

- Que es Minato-Morreale ISOP: generacion de covers irredundantes de
  producto-de-sumas desde un BDD (Minato, IEICE 1993, sobre el operador recursivo
  de Morreale, IEEE TC 1970) = **sintesis logica**, no indexacion de texto. Su
  recurrence (isop = v0*isop0 + v1*isop1 + isop_d) si es el modelo correcto del
  buscador: no recorrer los 3M records sino **estrechar el conjunto de candidatos**.
  En texto ese "producto de condiciones" = indices de postings / FM-index.
- Implementado como **firma de 64 bits por record** (caracteres plegados del
  nombre) + mascara de la query: el filtro descarta records sin leer el nombre de
  la arena. Archivos: `rs/seekcore/src/lib.rs` (skc_bloom_build/skc_bloom_mask/
  sig_bit), `src/scan.s` (scan_bloom + escritura al emitir), `src/gui.s`
  (gui_bloom/gui_qmask + test en single y worker).
- Trampas del camino: `VirtualAlloc` con los argumentos cruzados (el tamano como
  direccion) y `flProtect=0` (invalido) hacian que la reserva de 96 MB fallara y
  que el filtro se quedara **sin pre-filtro** (57 s por filtrado en vez de ~100 ms).
  El largo del nombre en el scanner esta en `[rsp+96]` (bytes); `[rsp+136]` es el
  puntero de la arena. `//` al final de linea en GAS es division (comentario solo
  en linea propia). `;` no es comentario en estos .s.
- Crash **preexistente** (ya estaba antes de este trabajo): la app muere 4-7 s
  despues de abrir, en el arranque, con el PC en la base del modulo y la pila
  corrupta. Se verifico que **no** lo causa la firma (deshabilitada al 100% el
  crash sigue). El CLI (`seek.exe`) indexa los 4 discos sin problema. Queda
  abierto: ver README.
- Bugs de memoria corregidos en `skc_score_rec`: escritura del cache de ancestros
  con indice >= 64 (fuera de rango) y el separador `\` del path sin comprobar
  `o2 < cap` (un WCHAR de mas, justo en los registros guardados del worker).
- El target `x86_64-pc-windows-gnu` faltaba en el toolchain activo de rustup
  (lo reinstale con `rustup target add x86_64-pc-windows-gnu`).

## 2026-10-20 — Repo git inicializado y publicado

- `seek-asm` paso a ser repo git (antes no lo era): `git init -b main` + primer
  commit con los 19 archivos fuente (asm, rust, rc, manifests, docs).
- `.gitignore` nuevo: excluye `*.exe`, `*.o`, `*.a`, `*.res` (generados por
  windres), `rs/seekcore/target/`, `*.log` y `dump/`.
- Publicado en https://github.com/Owning01/seek-asm (repo **publico**, rama `main`).
- Verificado antes de publicar: sin tokens/keys en el arbol (los `ghp_*` del ASM
  son etiquetas internas, no secretos).
