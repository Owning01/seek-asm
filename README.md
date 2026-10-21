# seek — buscador ultra-rápido en ensamblador x86-64

`seek <patron> [ruta] [--count] [--exclude <txt>]... [--no-excludes] [--include-windows] [--include-nodemodules] [--include-sys] [--include-cache] [--include-temp] [--topdirs] [--mft]`. Búsqueda por subcadena, sin distinguir
mayúsculas, sobre nombres de archivo. `*` = cualquier secuencia (incluida vacía), `?` = exactamente un caracter (full-match del nombre; sin comodines sigue siendo subcadena). Unicode WCHAR.
**Patrón de ruta**: si el patrón contiene `\` o `/` (ej. `g\proyectos\seek-asm\seek` o `windows\system32\*.dll`), matchea contra la ruta completa, no solo el nombre. Las `\` y `/` son equivalentes. Igual en CLI y GUI.
100% ensamblador GAS (`.intel_syntax noprefix`), cero archivos `.c`, más el crate Rust `rs/seekcore` (`no_std`, `staticlib`) con los matcher (`skc_query_is_pathq`, `skc_match_path`, `skc_excl_glob`, `skc_match_rec`) enlazado en ambos ejecutables.

## Uso

```bat
seek --help
seek notepad C:\Windows\System32 --count
seek seek G:\Proyectos\seek-asm
seek notepad                 :: sin ruta: todos los discos locales
seek build G:\Proyectos\seek-asm\build.bat   :: la raíz puede ser un archivo
seek exe G:\Proyectos --exclude seek-asm --count
seek dll C:\Windows --count --no-excludes
seek dll C:\Windows --count --include-windows
seek "g\proyectos\seek-asm\seek"          :: patrón de ruta: matchea la ruta completa
seek "windows\system32\*.dll" --count     :: ruta con wildcard
seek exe --exclude "*seek-asm*" --count   :: exclude con wildcard (patrón, no substring)
```

- Sin `ruta`: enumera unidades con `GetLogicalDrives` + `GetDriveTypeW`, recorre `DRIVE_FIXED(3)` y `DRIVE_REMOVABLE(2)`, salta el resto. Con `ruta`: un solo árbol (comportamiento anterior).
- `--count`: solo imprime el conteo a stdout. El resto imprime un path por línea.
- `--exclude <txt>`: repetible, máx 16, cada una máx 128 WCHAR. Match case-insensitive sobre full path. **Con `*`/`?` = wildcard (full-match, `skc_excl_glob`); sin comodines = substring (`contains_ci`)**. Igual en la GUI (`seek-gui.exe --exclude ...`, el flag llega por la cmdline y se registra antes de indexar: verificado `*.exe` 6450→6446 con `--exclude *seek-asm*`). Si falta valor, error exit 1. Exceder 16 = error.
- `--no-excludes` (alias `--all`): desactiva las 4 exclusiones por defecto (las `--exclude` custom siguen aplicando).
- `--include-windows`: desactiva solo la exclusión de Windows.
- `--include-nodemodules`: desactiva solo la de `node_modules`.
- `--include-sys`: desactiva solo el grupo sistema (pagefile/hiberfil/swapfile + `$WinREAgent`/`Recovery`/`Config.Msi`/`MSOCache`/`$Windows.~BT`/`$Windows.~WS`/`Windows.old`/`PerfLogs`/`Prefetch`/`SoftwareDistribution`).
- `--include-cache`: desactiva solo el grupo cachés (`INetCache`, `\Cache` —cubre `*Chrome*\*Cache*` y todo dir `Cache`—, `Code Cache`, `Service Worker`, `__pycache__`).
- `--include-temp`: desactiva solo el grupo Temp (`Windows\Temp`, `AppData\Local\Temp`). Ojo: al re-incluir Temp se visitan subárboles con cachés anidadas y `excl=` puede subir (composición de grupos).
- `--topdirs`: diagnóstico (solo CLI): tras el scan lista a stderr los 20 dirs con más entradas directas (`<conteo> <path>`), modo secuencial monohilo. No altera stdout (conteos/matches intactos).
- `--mft`: enumeración MFT directa (NTFS, requiere admin, solo raíz de unidad `X:\`; ver sección MFT). Fuerza MFT: si el volumen no abre, falla con mensaje y exit 1 (sin fallback). Con subruta avisa (`--mft solo unidad, uso Find`) y usa Find (mismo resultado). Sin `--mft` nunca se intenta MFT.
- Stats siempre a stderr: `[seek] archivos=A coincidencias=M tiempo=Tms arena=KKB discos=D excl=E mft=F|S filtro=Fms` (`S` = MFT usado, `F` = Find/fallback; `filtro=` = ms de la fase de filtro sobre el índice: real con `--idxdbg`, `0` en scan streaming donde el filtrado va inline sin fase separada).
- Salida 0 = ok. 1 = error de uso/args/memoria. `--help` y sin args imprimen uso.

## Exclusiones por defecto (activas salvo flag)

Match substring case-insensitive sobre full path (con `contains_ci`; customs lowercased al registrar):

- `\Windows\` o termina en `\Windows` (cubre raíz `X:\Windows` con prefijo `\\?\`).
- `\node_modules\` o termina en `\node_modules`.
- `$Recycle.Bin`.
- `System Volume Information`.
- Grupo sistema (`--include-sys` lo desactiva): archivos `pagefile.sys`, `hiberfil.sys`, `swapfile.sys`; dirs `$WinREAgent`, `Recovery`, `Config.Msi`, `MSOCache`, `$Windows.~BT`, `$Windows.~WS`, `Windows.old`, `PerfLogs`, `Prefetch`, `SoftwareDistribution`.
- Grupo Temp (`--include-temp` lo desactiva): `Windows\Temp`, `AppData\Local\Temp`.
- Grupo cachés (`--include-cache` lo desactiva): `INetCache`, `\Cache` (cubre `*Chrome*\*Cache*` y cualquier dir `Cache`), `Code Cache`, `Service Worker`, `__pycache__`. (`*.tmp` no se excluye: es patrón, no substring.)

## Wildcards `*` y `?` (CLI y GUI, mismo `match.s`)

- `*` = cualquier secuencia (incluida vacía), `?` = exactamente un caracter (un byte en UTF-8; en ASCII equivale a un WCHAR). Full-match sobre el nombre. Fold A-Z igual que `contains_ci`.
- Sin `*`/`?` el motor usa `contains_ci` como siempre (fast path, cero regresión).
- `*` solo equivale a todo (coincide con los `archivos` visitados).
- Verificado en `C:\Windows\System32` (`--no-excludes`, idéntico al oráculo PowerShell recursivo `Get-ChildItem -Recurse -Filter`):

| Patrón | seek | Oráculo |
|---|---|---|
| `*.exe` | 765 | 765 |
| `note*.exe` | 1 | 1 |
| `*pad*` | 40 | 40 (39 files + dir `hidgamepad...`) |
| `n?tepad.exe` | 1 | 1 |
| `zzz*qqq` | 0 | 0 |
| `notepad` (sin comodines) | 27/21104 | golden intacto |
| `*` | 21104 (=archivos) | todo |

## Búsqueda por ruta (CLI y GUI, `rs/seekcore`)

- Detección `skc_query_is_pathq`: la query contiene `\` o `/` → matchea la ruta completa (nombre + padres), no solo el nombre.
- `/` y `\` equivalentes: `g/proyectos/seek-asm` = `g\proyectos\seek-asm`.
- **`letra\` al inicio sin `:` también vale**: `g\proyectos\seek-asm\seek` = `g:\proyectos\seek-asm\seek` (normalización `letter:` en `match_text`, vale para CLI y GUI).
- Sin comodines = substring case-insensitive sobre la ruta (`skc_match_path`); con `*`/`?` = full-match sobre la ruta (`windows\system32\*.dll`).
- `skc_match_rec` resuelve la ruta desde el record 12B (cadena de padres) y decodifica el nombre UTF-8 (palabras de 2 bytes UTF-16 incluidas), sin tocar disco.
- Verificado CLI (suite 9/9): ruta exacta=1, `windows\system32\*.dll`=4433, con `/`=21108, negative=0. GUI: `g:\proyectos\seek-asm\seek` → 4 con columna Carpeta correcta.
- Exclusiones con wildcard: `--exclude "*seek-asm*"` (CLI y GUI) full-match sobre la ruta vía `skc_excl_glob`; sin comodines sigue siendo substring.
- Addendum 2026-10-11: normalizacion `letter:` en `match_text` — `g\proyectos\seek-asm\seek` (sin `:`) ahora matchea `G:\Proyectos\...` en CLI y GUI (antes solo valia con dos-puntos; un test sin `:` dio 0 y parecia regresion). Verificado: sin colon=3 (--no-excludes), con colon=1, goldens intactos, harness 12/12.
- Fix 2026-10-19: **la GUI no matcheaba NINGUNA query de ruta** (0 resultados para cualquier ruta). Causa: los 4 argumentos de pila de `skc_score_rec(rec, idx, q, qlen, is_glob, mode, buf, buflen)` estaban ordenados como `(is_glob, buf, buflen, mode)` en los dos call sites (`gui_ss_pathq` del loop single y `gtw_pathq` del worker paralelo): el Rust recibia `buflen` = el modo (0/1) y salia por `buflen < 8` → 0 para todo record. Corregido en ambos. Verificado: `C:\Users\perca`=335193, `C:\`=395893, `C:\Program Files`=54511, `G:\Proyectos\seek-asm`=58, `perca\Desktop`=1541, `C:\Users\perca\*.txt`=10696, `C:/Users/perca`=310019. Costo: ~1.5-2.5 s por query de ruta sobre 3M records (reconstruye la ruta de cada record; el hilo UI se congela).
- **Velocidad (2026-10-20)**: el filtro por ruta paso de 1.3 s a **90-180 ms** y el tipeo de 40-80 ms a **0-5 ms** por tecla. Piezas: (1) `skc_score_rec` cachea la **pila de ancestros por hilo** dentro del buffer (el indice esta en orden DFS: el padre casi siempre ya esta en la pila, asi que la ruta se arma con un prefijo + el nombre en vez de recorrer la cadena de padres y convertirla); (2) la query se **normaliza una vez por filtrado** (`skc_qnorm8`/`skc_qnorm`) y no por record; (3) **modo anclado** (`is_glob`=2/3): si la query arranca con la unidad (`X:\...`) el match es un **prefijo** de la ruta, asi que se compara al vuelo y se corta al divergir (sin armar la ruta entera) - el prefijo `\\?\` de las rutas largas se saltea; (4) **debounce por defecto de 120 ms** (antes 0 = filtrar en cada tecla): la tecla se procesa al instante y el filtro corre al pausar. Medido: `C:\`=93 ms (antes 1264), `C:\Users\perca`=181 ms (antes 1336), `C:\Users\perca\*.txt`=406 ms (antes 1685), `G:\Proyectos\seek-asm`=129 ms (antes 1157), nombre `perca`=79 ms, y el incremental (query que extiende la anterior) = 0 ms.

## Decisión de conteo (vista filtrada)

- Directorio excluido: no se desciende, no cuenta en `g_files`, no emite matches dentro.
- Archivo excluido: no cuenta match y tampoco cuenta en `g_files`.
- `excl=N` cuenta rutas saltadas por exclusión (dirs + archivos). `discos=D` cuenta unidades recorridas (1 en modo una-ruta).

## Qué es lossless (garantía de la optimización)

El motor CLI produce **los mismos conteos y matches** que los binarios previos
(verificado por corrida golden + `fc` sin diferencias en 52.647 líneas
ordenadas tras cada cambio):

- Mismo matching: `contains_ci`/`contains_ci_a` sobre el **nombre** (no el path), case-insensitive ASCII A-Z, resto intacto (UTF-8 por auto-sincronía).
- `g_files` cuenta todo lo visitado no-excluido (dirs + archivos), igual que antes.
- Solo cambia **qué se guarda y cómo se recorre**: hilos por disco (misma salida, en orden por unidad), records de 12B, nombres UTF-8, streaming.
- Verificado: `dll C:\Windows --count --no-excludes` = 225272/52647, `notepad C:\Windows\System32 --count --no-excludes` = 21104/27, `exe G:\Proyectos\seek-asm --count` = 15/2, `--include-windows` = 52647 con `excl=2`, `--exclude seek-asm` resta 2 en `G:\Proyectos` (`seek.exe`+`seek-gui.exe`).
- Excepción conocida (resuelta 2026-10-08): el índice GUI cubría ~2,92M de 3,19M. Causa: `WS_R_END=base+32MB` con 64MB reservados + sanidad `idxdbg` con comparaciones sin signo. Fix: tope real según `scan_big_rec` (`wir_rend_big`) + `jg/jl` en sanidad + largo real tras `build_path` (BPMISS). Hoy `--idxdbg` cubre todo sin `trunc` (`exe` 20200 = CLI, `dll` 28220 = CLI, `notepad` 12 = CLI).

## GUI `seek-gui.exe` (100% ASM): índice persistente

### Relevancia y boton de modo (2026-10-12, Rust `skc_score_*`)

- Los resultados se ordenan por relevancia, no por orden de indice: coincidencia exacta (6) > prefijo (5) > subcadena/glob/ruta (4), con bonus por nombre corto y +2000 si coincide con el modo. El score viaja empaquetado `(score<<32 | ~idx)` en los mismos buffers u64 (sin cambiar layouts); ordena `skc_rank_sort` (Rust, `sort_unstable`) y se desempaqueta al mostrar.
- Boton junto al pin (STATIC owner-draw con iconos reales del sistema): Todos (☰) > Archivos > Carpetas. Prioriza (+2000) sin filtrar; persiste en `HKCU\Software\seek` valor `mode`; recicla con refiltrado completo al cambiar.
- `skc_score_name` (7 args, `is_dir` del parent del record) y `skc_score_rec` (8 args, `is_dir` leido adentro: evita el 9no arg sin slot en el frame del worker). Harness `skc_rank_test.c` 15/15.
- Selección real (2026-10-12): el `uItemState` del paint llega con `SELECTED` stale para todas las filas en lluvias de `SetItemCount` (medido `ST=0x201` con 0 seleccionados); `gcd_item` verifica con `LVM_GETITEMSTATE` en vivo. Sin costo medible (`filtro=1ms`).
- Estado vacío (2026-10-12): overlay owner-draw `IDC_EMPTY` ("Sin resultados" gris centrado) sobre la lista cuando hay query sin matches; se oculta solo. El STATIC con texto jamás pintó (texto/fuente/colores/z verificados) y se pasó a owner-draw.
- Búsqueda inteligente (2026-10-12): insensible a acentos Latin-1 (`camion` encuentra `camión`, `NINO` encuentra `niño`; Æ/Ð/Þ/ß exactos, combinantes no), trim de blancos y tabs en ambos extremos (CLI y GUI), `./` `../` iniciales ignorados, `\` final ignorado (salvo raíz), `letra\` = `letra:` y `/` = `\` (todo en Rust `normalize_q/normalize_qa/skc_qpre`; `?` sigue = 1 byte).
- Prefilter SSE intacto a full velocidad: `skc_qpre` devuelve primer byte normalizado + fskip tri-estado (0=filtro, 1=sin filtro, 2=filtro+segunda chance `0xC3` para iniciales plegables a-z). Divergencia: nombres en CLI = ASCII literal (`match.s` intacto por perf); rutas y excludes-wildcard del CLI + todo el GUI = full-smarts.

```bat
seek-gui.exe              :: pildora flotante 700x40 arriba (default): logo seek + Edit + Alt+Espacio + pin
seek-gui.exe --bar        :: explicito = default
seek-gui.exe --window     :: ventana vieja 920x620 (Edit + resultados + status)
seek-gui.exe --focus      :: robar foco al arrancar (por defecto NO roba foco)
seek-gui.exe --install-startup    :: autoarranque: crea HKCU\...\Run valor seek y sale
seek-gui.exe --uninstall-startup  :: quita el valor seek y sale
```

- Instancia unica: al abrir seek-gui.exe otra vez, la instancia actual recibe `WM_CLOSE` y muere; gana la nueva (visible en ~1-3s). Vale entre modos (`--bar`/`--window`) y tambien en doble lanzamiento simultaneo (watchdog de 500ms cierra el duplicado).
## Icono (`assets/seek.ico`, 4.804 bytes)

- Rayo cyan `#7fd0ff` sobre cuadrado oscuro redondeado `#141826` (branding de `mockup-bar.html`: fondo `rgba(20,24,38)` + borde chip `#7fd0ff66`). Radio 22%, borde cyan 40%, rayo polígono `(0.62,0.10)...(0.38,0.90)` con supersampling 4x.
- Generado con script temporal solo-stdlib (Python `zlib+struct`, sin Pillow ni red): PNG 256/48/32/16 empaquetados como ICO (cabecera `00 00 01 00`, un PNG por entrada). Script borrado, `.ico` conservado.
- `src/resource.rc`: `#define IDI_ICON1 101` + `IDI_ICON1 ICON "../assets/seek.ico"` (relativa a `src/`, cwd de `windres`) + manifest intacto. `build.bat` enlaza `resource.res` en AMBOS exes; la GUI además lo carga como icono de clase/título (`LoadIconW` en `WinMain`).
- Verificado: `[System.Drawing.Icon]::ExtractAssociatedIcon` no-nulo 32x32 en `seek.exe` y `seek-gui.exe`.

## Autoarranque con Windows (100% ASM, Advapi32)

- `seek-gui.exe --install-startup`: `GetModuleFileNameW` → entrecomilla → `RegCreateKeyExW(HKCU\Software\Microsoft\Windows\CurrentVersion\Run, KEY_WRITE)` → `RegSetValueExW(seek, REG_SZ, "ruta")` → `MessageBoxW("seek arranca con Windows.")` y sale (código 0). Sin consola (`-mwindows`), el aviso es gráfico.
- `seek-gui.exe --uninstall-startup`: `RegOpenKeyExW` + `RegDeleteValueW(seek)` → `MessageBoxW("seek ya no arranca con Windows.")`. Si no existía: `MessageBoxW("seek no estaba en el arranque.")`, también código 0.
- Al logon Windows ejecuta `"ruta"` sin args → abre la barra normal (sin flags nuevos de UI).
- Desinstalar el autoarranque: `seek-gui.exe --uninstall-startup` (o borrar el valor `seek` en `HKCU\...\Run` con `regedit`).
- Verificado 2026-10-08: install crea `seek REG_SZ "G:\Proyectos\seek-asm\seek-gui.exe"` (`reg query` ok), uninstall lo borra, estado final INSTALADO.
- Trampas ASM que costó encontrar (leer antes de tocar):
  1. `HKEY_CURRENT_USER` como inmediato 32b (`mov rcx, 0x80000001`) ensambla `movabs` cero-extendido (`0x0000000080000001`, handle inválido). Definir `.equ HKEY_CURRENT_USER, 0xFFFFFFFF80000001` (se verifica con `objdump`: `mov $0xffffffff80000001,%rcx`).
  2. En `RegCreateKeyExW` el 4.º arg (`lpClass`) va en `R9`, NO en pila: `[rsp+32]=5 … [rsp+64]=9`. Un slot corrido = AV.
  3. Stores `DWORD` en slots de pila dejan basura alta (`0x7ffe00020006`); el forwarder advapi32→kernelbase propaga 64b. Usar stores `QWORD` en args de pila (verificado en disassembly + gdb).
  4. El kernel devuelve `998/NOACCESS` si los punteros leídos apuntan a páginas RW de imagen (`.data`/`.bss`): subkey, valor y quoted van COPIADOS A LA PILA (probado: con puntero `.data` falla, con pila funciona; el probe C con string en `.rdata` RO funciona).
  5. Marco > 4KB necesita `_chkstk` manual (sondeo página por página) o el primer toque salta la guard page y muere con AV (verificado SIGSEGV en gdb; fix: loop de 33 páginas para el marco de 128KB del quoted path).

- Modo bar por defecto: píldora flotante `700x35`, `x=(SM_CXSCREEN-700)/2`, `y=8` (margen para que se vea el redondeo superior), `WS_EX_LAYERED|WS_EX_TOOLWINDOW` (`0x80080`, tool normal: **sin** `TOPMOST` por defecto), `SetLayeredWindowAttributes(alpha=184)`, sin bordes de sizing, sin icono taskbar (toolwindow), título `seek`. `--window` restaura la ventana vieja.
- Pin 📌 = opt-in de `TOPMOST` (toggle con `SetWindowPos`, `0x80080`↔`0x80088`), estado persistido en `HKCU\Software\seek` valor `pin` (default 0 = normal). Al reabrir se restaura (si `pin==1` se repone `TOPMOST` tras crear).
- Auto-hide total: timer 500ms + `WM_ACTIVATE WA_INACTIVE` comparan `GetForegroundWindow` contra la barra/desktop. Si otra app tiene el foreground (no barra, no desktop/shell/`Progman`/`WorkerW`, no menú `#32768`), se oculta **toda** la barra (`SW_HIDE`, marca `autohid=1`). `Alt+Espacio` la restaura + foco + selecciona texto (`EM_SETSEL 0,-1`) y limpia la marca (igual el hide manual). En escritorio vacío (fg NULL/desktop/shell) con marca de auto → se muestra sola (`SW_SHOWNA`); el hide manual se respeta (no re-muestra). `--window` sin cambios (el chequeo es no-op).
- Alfa fijo `184/255` como constante `BAR_ALPHA` arriba de `src/gui.s` (futuro flag `--alpha N`). Fondo oscuro `RGB(30,30,30)` (brush + `WM_CTLCOLOREDIT/STATIC` + `LVM_SETBKCOLOR/TEXTCOLOR`). Pildora 700x40 radio 18.
- Tema oscuro (2026-10-09, refrescado 2026-10-12, solo `src/gui.s`): fuente Segoe UI 11pt con antialias grayscale en todos los controles (`CreateFontW(-11*dpi/72, quality=4)` + `WM_SETFONT`); ListView con `NM_CUSTOMDRAW` (filas `#1E1E1E`, texto `#F2F2F2`, selección `#DC783A` con texto blanco, hot-track sutil `#2D2D2D`; la altura de fila crece con la fuente, sin owner-draw) y sin cabecera (`LVS_NOCOLUMNHEADER`); Edit y lista planos sin `WS_EX_CLIENTEDGE` hundido; Edit oscuro con hint gris (`EM_SETCUEBANNER` de siempre) + padding interno 6px (`EM_SETMARGINS`); pin STATIC (`SS_NOTIFY`, sin cara blanca) con fondo oscuro (`WM_CTLCOLORBTN`) para que el glyph se vea; logo/hint heredan fuente y colores. Foco inicial igual (solo `--focus`/`--window`).
- Acrílico: `gui_enable_acrylic` intenta `SetWindowCompositionAttribute(ACCENT_ENABLE_ACRYLICBLURBEHIND)` (carga dinámica de user32, sin tocar `build.bat`) con tinte `#141826`. Estado 2026-10-09: DESACTIVADO (llamada comentada en `WinMain`) porque la composición tumbaba la píldora idle a los ~4s (AV en KERNELBASE); al quitar el acrílico la caída persistió y la causa real era el status sin-tema (abajo), pero sin builds restantes para re-aislarlo quedó apagado. Fallback activo: `WS_EX_LAYERED` alfa 184 + región redondeada intactas. Reactivar = descomentar 2 líneas en `WinMain` tras `SetLayeredWindowAttributes`.
- Layout píldora (compacto 35px): logo `seek` (8,9,34,17) + Edit búsqueda (50,7,W-178,21; foco inicial solo con `--focus` o `--window`) + hint `Alt+Espacio` (W-120,10,80,16) + botón pin 📌 (W-32,6,24,23; toggle `TOPMOST` opt-in, ver arriba). Panel de resultados (ListView virtual existente) cuelga debajo con el mismo ancho/x solo mientras hay texto (`EN_CHANGE/SETFOCUS` → `Show` + `SetWindowPos 35+320=355`; `Esc`/`WA_INACTIVE` → ver auto-hide: con otra app al frente se oculta la barra entera, no solo el panel). `Esc` en dos pasos: el 1.º limpia el Edit y colapsa el panel (barra viva); el 2.º, ya sin texto, oculta la barra entera (`autohid=0`, vuelve con `Alt+Espacio`; en `--window` no oculta la ventana). `WM_ACTIVATE WA_INACTIVE` invoca el chequeo de auto-hide.
- Bordes redondeados: `CreateRoundRectRgn(0,0,700,h+1,12,12)` + `SetWindowRgn` al crear, en cada `WM_SIZE` y en cada cambio de modo (`h=35` colapsada, `355` expandida; `+1` porque los bordes de región son exclusivos, sin eso la caja sale 699x34). Convive con `WS_EX_LAYERED`. En `--window` la región se quita.
- Movible: `WM_NCHITTEST` devuelve `HTCAPTION` sobre el fondo de la píldora (los hijos Edit/pin/resultados no llegan al padre, así que arrastrar desde el fondo mueve y desde los controles opera normal). Al soltar (`WM_EXITSIZEMOVE`, más respaldo en `WM_DESTROY`) guarda `x,y` (`DWORD`) en `HKCU\Software\seek` (`RegCreateKeyExW` + `RegSetValueExW`, todo en pila por la trampa 4 de autoarranque). Al abrir restaura si existe y hace clamp al monitor primario (`[0,screenW-700]` × `[0,screenH-35]`); si no, centrado por defecto.
- Hotkey global `Alt+Espacio` (`RegisterHotKey(MOD_ALT,VK_SPACE)`, `UnregisterHotKey` al salir): si oculta → muestra + foco + selecciona texto (`EM_SETSEL 0,-1`); si visible → la oculta (toggle).

- Edit de búsqueda (todos los discos locales, exclusiones por defecto). **Sin debounce**: filtra en cada tecla, sin espera (busqueda sincrona en el hilo UI). Busca **durante el indexado inicial** sobre el índice parcial (snapshot rec_count+abrk con bounds-check; seguro porque el writer guarda name, parent y recién después count) y `gw_done` refiltra con el índice completo al terminar. Acepta `*`/`?` (misma semantica que el CLI: full-match; sin comodines es subcadena).
- Índice persistente: una indexación al abrir (hilo `gui_indexer`, un `scan_root_ws` por unidad en un ws con records de 128MB, arena viva), cada tecla filtra en memoria (`contains_ci_a` o `glob_match_ci_a` si el patron trae `*`/`?`, por record, total + primeros 100K en `gui_items`). `Esc` limpia filtro y lista (no el índice). Status `idx=` (archivos indexados) + coincidencias del filtro + `filtro=Nms` (QPC alrededor del filtrado). Re-escaneo manual con F5 (join total al indexer, ws nuevo; al terminar re-filtra si hay texto).
- Columna fecha + orden (2026-10-15): columna "Modificado" (130 px) con mtime formateado YYYY-MM-DD; cabecera visible (se quito LVS_NOCOLUMNHEADER); clic en cabecera ordena por esa columna (asc/desc) via LVN_COLUMNCLICK -> gui_sort_column -> Rust skc_sort_items (nombre/carpeta/fecha). El orden se aplica sobre gui_items y se refresca el ListView.
- Auto-reparación en vivo (2026-10-15, `src/gui.s` + tick de `seekcore`): el timer de 500 ms llama `gui_maybe_repair`; cada `REPAIR_SLICE_MS`=10 s (una sola instancia, hilo de fondo `gui_repair`) corre `skc_dir_tick` sobre el índice: stat por dir con u64 mtime por record (lazy-init), y por cada dir cambiado tombstones de sus hijos + rescan append + reparent al slot viejo (mtime fresca; dir borrado = tombstone + mtime `-1`). Al terminar refiltra el query vía `GUI_APP_DONE`. Si faltan <128K slots libres o F5 cambió `gui_gen`, aborta sin tocar nada (`gr_cleanup`). Archivos nuevos aparecen solos estando abierto (~1-2 min + barrido), sin cerrar/reabrir. Medido: archivo creado → visible en resultados en 50-90 s.
- Barrido por franjas (2026-10-19, fin del uso fijo de CPU): el barrido completo de ~3M records (stat de ~300K dirs + reconstrucción de rutas) costaba **~6 s de CPU de golpe cada 30 s** (~20% de un core, con picos visibles de 6 s). Ahora `skc_dir_tick` recibe un **cursor** (in/out) y un **presupuesto de `TICK_BUDGET_MS`=500 ms** por llamada: procesa un arco contiguo del círculo de records y sigue desde el cursor en la próxima franja (`gui_sweep_cursor`, se resetea al reindexar). Resultado medido: **~500 ms de CPU cada 10 s (4-6% de un core, 0.3-0.4% del total en 16 hilos) sin picos**; el recorrido completo tarda ~2 min, así que un archivo nuevo aparece entre 0 y ~2 min. Ajustables en `src/gui.s` (`REPAIR_SLICE_MS`) y `rs/seekcore/src/lib.rs` (`TICK_BUDGET_MS`).
- Motor de filtro (CLI `--idxdbg` y GUI comparten `match.s` + mismo algoritmo):
  - Incremental: si la query nueva extiende la anterior (`exe`→`exec`, ambas sin `*`/`?`, anterior prefijo de la nueva y total previo ≤ 100K) se filtran SOLO los resultados previos; si no, filtrado completo. Mismo resultado exacto (con globs o al acortar, siempre completo).
  - Prefiltro por primer byte (SSE2, 16B/chunk en `match.s:prefilter_firstbyte`): descarta nombres sin el primer byte del query (con su mayúscula si es a-z) antes del `contains`/`glob` completo. Con comodín líder (`*`/`?` primero) no aplica (el primer byte no es literal).
  - Paralelo: T hilos (`GetSystemInfo`, tope 8) sobre particiones contiguas del índice + merge ordenado por índice (mismo orden y mismo cap 100K que el single). Solo si el conjunto a filtrar supera 200K registros; debajo, single-thread (menos overhead). Workers con el mismo chequeo de integridad que el loop single (puntero en arena + `bad` contado; sin divergencia).
- ListView report **virtual** (`LVS_OWNERDATA|LVS_REPORT|LVS_NOCOLUMNHEADER`, columnas Nombre 210|Carpeta 440 (total 650, sin scrollbar horizontal), `ListView_SetItemCountEx`): el control pide el texto por `LVN_GETDISPINFO` (`gui_idx_path`: `build_path` + `MBTWC` + strip `\\?\`), cero copias. Status oscuro de una linea (STATIC `SS_CENTERIMAGE`, `idx/coincidencias/filtro/arena/discos` via `SetWindowTextW`; el StatusBar con `SB_SETBKCOLOR` tumbaba la píldora idle, B12). En modo `--window` el título muestra `total + idx`; en bar el título queda fijo `seek`.
- Verificado pildora (2026-10-08, build nuevo A/B/C): rect `674,8,700x35` (centrado, logico), ex `0x80080` (tool normal, sin TOPMOST) / `0x80088` con pin, `bAlpha=184`, region `GetWindowRgn` tipo 3 (redondeada) caja `0,0,700,35` (expandida `0,0,700,355` con texto `*.exe`), hotkey restaura visible + foreground (`WM_HOTKEY`), otra app maximizada al frente oculta TODA la barra (`IsWindowVisible=False`), pin toggle `0x80080`<->`0x80088` con persistencia (`pin` 1/0) y restore al reabrir, `NCHITTEST` fondo = 2 (`HTCAPTION`), move + `WM_EXITSIZEMOVE`/`WM_CLOSE` persiste `x/y` y reabrir restaura (`200,300`), `x=99999` hace clamp a `1348,1117` (pantalla logica 2048x1152), filtro GUI `*.exe` > 0 / `zzz*qqq` = 0, `--window` 920x620 intacto. CLI intacto con `--no-excludes`: 52647 (`archivos=225272 excl=0`) y 27 (`archivos=21104`). Nota headless: el drag con mouse real no enruta input (se cubre move/save/restore por mensaje); el re-show exacto hidden->shown con fg a escritorio no observable sin Progman (`SetForegroundWindow(shell)` rechazado), pero el keep-visible con fg de escritorio si (barras frescas visibles 30s+) y el hide con fg de otra app tambien.
- Brecha conocida (2026-10-08, presupuesto de builds agotado 14/14): el índice cubre ~2,92M de 3,19M archivos y el filtro subcuenta igual (`exe` 16925 vs 21398 CLI; `dll` 14074 vs 28447; `notepad` 12/12 exacto). Reproductor CLI sin GUI: `seek.exe <q> --idxdbg --count` (mismo path: big+index, un ws, raíces secuenciales, filtro lineal + chequeo de integridad; vuelca a stats con `trunc=` si hay inconsistencia). Hipótesis principal con evidencia en fuente: `src/scan.s:488` calcula `WS_R_END = base+32MB` aunque se reservaron 64MB (`scan_big_rec`), con lo que el índice se trunca a 2,79M records (fix de 1 línea: usar el tamaño reservado). Segundo bug real (angosto, modo lista + excludes con match previo en el mismo dir): `src/scan.s:1083` pasa `BPMISS` (1) como largo a `MultiByteToWideChar` (debió guardar `EAX` del `build_path` antes de leer `WS_BPMISS`); en count/index duerme (sin emits), en lista+excludes salta exclusiones tras un match con emisión. Ambos quedan para un follow-up (2 builds estimados).
- Motor completo por búsqueda (cuenta el total aparte), cap de **display 100K** (`GUI_MAXDISPLAY`): pasado el cap se sigue contando pero no se guarda. Mismo `contains_ci`/`glob_match_ci` + `path_is_excluded` que el CLI.
- Click derecho: **menú exacto de Windows** (no réplica): `SHParseDisplayName` (path sin `\\?\`) → `SHBindToParent` → `IShellFolder::GetUIObjectOf(IID_IContextMenu)` → `QueryContextMenu` + `TrackPopupMenuEx(TPM_RETURNCMD)` → `InvokeCommand`. `WM_INITMENUPOPUP/WM_DRAWITEM/WM_MEASUREITEM` reenviados a `IContextMenu2/3`. Multi-selección con un solo `GetUIObjectOf` si comparten padre (mismo dir); padres mixtos → menú del primer item. Doble-click/Enter (`LVN_ITEMACTIVATE`) → `ShellExecuteW(open)`.
- Atajos de teclado (2026-10-08): con resultados en pantalla `Abajo/Arriba` mueven la selección (`LVM_SETSELECTIONMARK` + `LVM_SETITEMSTATE LVIS_SELECTED|LVIS_FOCUSED` + `LVM_ENSUREVISIBLE` + foco a la lista); `Enter` abre el seleccionado (`ShellExecuteW(open)`; sin selección previa selecciona el 1.º); `AvPág/RePág` saltan una página (`LVM_GETCOUNTPERPAGE`), `Inicio/Fin` van al primero/último. Funciona con foco en el Edit (subclass `gui_edit_proc` vía `SetWindowLongPtrW`, sin robar el diálogo) y con foco en lista/barra (`WM_KEYDOWN` del padre). `Esc` en dos pasos (con texto limpia + colapsa panel; el 2.º, sin texto, oculta la barra entera), `F5` re-indexa, `Alt+Espacio` alterna, `Ctrl+Q` sale, `Ctrl+O` abre la carpeta del seleccionado, `Ctrl+Shift+C` copia la ruta, `Ctrl+Up/Down` recorre el historial de búsquedas, `--debounce N` retarda el filtro (ms, 0=sin).
- Iconos de archivo (2026-10-08): el ListView usa el ImageList del sistema (`SHGetFileInfoW("", SHGFI_SYSICONINDEX|SHGFI_SMALLICON)` + `LVM_SETIMAGELIST LVSIL_SMALL`, estilo `LVS_SHAREIMAGELISTS` para no destruirlo al cerrar). `LVN_GETDISPINFO` rellena `iImage` por extensión (`SHGetFileInfoW(path, SHGFI_SYSICONINDEX|SHGFI_SMALLICON|SHGFI_USEFILEATTRIBUTES)`, atributo `NORMAL` en archivos y `DIRECTORY` en dirs) con caché ext→índice de 64 entradas en `.bss` (extensión en minúsculas con punto, máx 15 WCHAR). Medido: `.exe`=50, `.dll`=51, `.txt`=0 (distintos). Sin overlay de acceso directo `.lnk` (`SHGFI_LINKOVERLAY` omitido a propósito).
- Verificado píldora (2026-10-08): `HWND!=0`, rect `674,8,700x35`, ex `0x80088`, `GetLayeredWindowAttributes bAlpha=184`, región compleja `0,0,700,35`, pin toggle quita/pone `TOPMOST` (`0x80080`↔`0x80088`), tipeo real `exe` muestra panel (`h=355` misma x, región `0,0,700,355`), `Esc` oculta panel y deja barra viva (`h=35`), `WA_INACTIVE` colapsa sin ocultar, arrastre +100px verificado con `mouse_event` (persiste y restaura, clamp ok), proceso vivo. CLI intacto: `dll C:\Windows --count --no-excludes` = 52647.

## Arquitectura

| Archivo | Rol |
|---|---|
| `src/arena.s` | `arena_init/alloc/used/free` + `table_rec/stk_base/ensure` (arena global, hoy solo la usa `main.s` para conversiones + la GUI para resultados/filtro). Nombres: reserva 256MB, commit inicial 64KB. Sin `HeapAlloc`/`malloc`. |
| `src/match.s` | `lowercase_query` + `contains_ci` (WCHAR, inner vectorizado SSE2 de a 8 + cola escalar) + `contains_ci_a` (bytes UTF-8, escalar) + `glob_match_ci`/`glob_match_ci_a` (full-match con `*`/`?`, backtracking con estrella) + `glob_has_wild` (fast-path: sin comodines se usa `contains_ci`). Solo ASCII A-Z se pliega. Leafs. |
| `src/scan.s` | Workspaces privados por hilo (bloque 640KB + regiones propias: nombres 256MB, records 32/64MB, pila 4MB; cero locks). `scan_root_ws` (DFS), `scan_run` (1 raíz), `scan_run_all` (1 `CreateThread` por unidad FIXED/REMOVABLE, suma y flush en orden; con `--mft` secuencial `sra_mft_seq`: MFT no es thread-safe), `scan_one_root` (compat), `scan_worker`, `ws_*` (+`ws_alloc`/`ws_rec_ensure`/`emit_path` exportados para MFT), `build_path`/`emit_path`/`flush_out` por ws, `scan_idxdbg` (diagnóstico `--idxdbg`). Records 12B (`name_ptr:8, parent_idx:4` bit31=is_dir, raíz con parent `0xFFFFFFFF`). Nombres UTF-8 con prefijo de largo en bytes. `path_is_excluded` con prefiltro barato + `contains_ci`. `FindFirstFileExW(Basic+LARGE_FETCH)` con fallback. Modos: `scan_opt_index` (índice: guarda todo, no emite), `scan_big_rec` (records 64MB). Hook MFT tras el record raíz (solo drive-root, solo con `--mft`; force-fail salta el DFS). |
| `src/mft.s` | `mft_try_root(ws)` (1 enumeró / 0 fallback) + `mft_ensure` recursivo + hash FRN→tmp (4M×16B) + temp 512MB. Solo `scan_opt_mft==1` (`--mft`), solo drive-root, sin `--topdirs`. `mft_used` (S/F en stats), `mft_force_fail` (error exit 1 en `main.s`). Aviso + Find en subruta (`mft_warn_fallback`); restauración total del ws al fallar. Solo kernel32 (`CreateFileW`/`DeviceIoControl`/`GetLastError`). |
| `src/gui.s` | `WinMain` + `WndProc` + indexer + filtro + menú Shell COM + autoarranque `--install/--uninstall-startup` (Advapi32 HKCU Run, ver sección autoarranque). Índice persistente en un ws (una indexación al abrir, F5 re-indexa). Cada tecla filtra en memoria (`contains_ci_a` por record). `Esc` limpia filtro (no índice). Reusa `ws_*`, `scan_root_ws`, `build_path`, `path_is_excluded`, `contains_ci`. |
| `src/gui.manifest` + `src/resource.rc` | Manifest ComCtl32 v6 + icono `IDI_ICON1` (`../assets/seek.ico`, ver sección icono), compilado con `windres` a `resource.res` (5.878 bytes). |
| `src/main.s` | `global main` (`argc/argv` del CRT de gcc). Convierte UTF-8→WCHAR (reintenta ACP), parsea `--exclude/--no-excludes/--all/--include-windows/--include-nodemodules/--include-sys/--include-cache/--include-temp/--topdirs/--mft/--idxdbg`, detecta wildcards (`glob_has_wild`), timing `QueryPerformanceCounter`, stats a stderr en un solo `WriteFile` (+` mft=S/F`, error `--mft` exit 1). Frame 544. |
| `rs/seekcore/src/lib.rs` | Crate Rust `no_std` (`staticlib`, `panic=abort`, target `x86_64-pc-windows-gnu`), enlazado como `.a` en ambos ejes. Exporta C: `skc_query_is_pathq` (detecta `\`/`/` en la query), `skc_match_path` (match sobre full path, `\`≡`/`), `skc_excl_glob` (exclude wildcard sobre full path, 4 args: query,len,path,len), `skc_match_rec` (match sobre el record 12B: camina la cadena de padres, UTF-8→U16 con soporte de surrogate pairs, caps de seguridad plen>65535/qlen>1024/depth≤128/hops≤4096). ASCII case-insensitive. |
| `build.bat` | `cargo build --release` (seekcore) primero, `windres` (`resource.res` con manifest+icono); `seek.exe` (arena+match+scan+mft+main+`resource.res`+`libseekcore.a`, `-lkernel32`) y `seek-gui.exe` (`-mwindows`, gui+arena+match+scan+mft+`resource.res`+`libseekcore.a`, `-lcomctl32 -lshell32 -lole32 -luuid -luser32 -lgdi32 -lkernel32 -ladvapi32`). `windres resource.rc -O coff -o resource.res`. |

Flujo: `main` convierte y minusculiza el patrón → `scan_run` normaliza la raíz
a absoluta con prefijo `\\?\` (long paths), indexa con `FindFirstFileExW` /
`FindNextFileW` (fallback a `FindFirstFileW`), compara solo el nombre, reconstruye el full path desde la
cadena de padres **solo** al imprimir un match.

## Tácticas de RAM y velocidad

- Un workspace privado por hilo (bloque 640KB + nombres + records + pila), cero `HeapAlloc`/`malloc`, cero locks: cada hilo suma al final y el main flushea en orden (salida determinista).
- Nombres UTF-8 en arena (~45% menos que UTF-16 en `C:\Windows`: 5789→2848KB count, 8845→4313KB lista). Query a UTF-8 una vez por raíz.
- Records de 12B con `is_dir` en el bit 31 del padre; raíz con parent `0xFFFFFFFF`.
- `FindFirstFileExW(FindExInfoBasic+LARGE_FETCH)` con fallback; prefiltro de primer carácter en exclusiones; `contains_ci` WCHAR con inner SSE2 de a 8.
- Un `WriteConsoleW` por flush de 64KB (32768 WCHAR). Si stdout está redirigido,
  fallback automático a UTF-8 + `WriteFile`. El prefijo `\\?\` se quita en pantalla.
- `Access Denied` se salta sin abortar. Symlinks/junctions (`REPARSE_POINT`)
  se saltan para evitar ciclos. `.` y `..` se ignoran.
- Diagnóstico oculto: `--idxdbg` (solo CLI, no sale en `--help`) reproduce el path del indexador GUI y vuelca el resultado a stats (con `trunc=` si el índice se trunca o hay inconsistencia).

## Límites

- Por workspace: nombres 256MB + records 32MB (128MB con `scan_big_rec`: índice GUI/idxdbg) + pila 4MB + bloque 640KB. Si se agota: `trunc=arena-llena` en stats y resultados parciales (no aborta). Ojo: sin record no hay descenso (el DFS necesita el índice del padre): los dirs que llegan con la tabla llena no se registran y sus subtrees enteros no se visitan ni cuentan; el flag `trunc` es el único testigo.
- GUI: display capado a 100K items (el filtro cuenta el total completo aparte).
- Matching case-insensitive solo ASCII A-Z; el resto compara exacto (UTF-8 intacto por auto-sincronía).
- Sin MFT por defecto: cada corrida CLI re-escanea (hilos por disco, secuencial con `--mft`); la GUI indexa una vez y filtra en memoria (siempre Find; MFT no se auto-activa sin paridad admin verificada).
- `--mft` solo raíz de unidad (`X:\` o `\\?\X:\`); subrutas, `--topdirs` y volúmenes no-NTFS usan Find con aviso (el fallo de apertura sí es error).

## Benchmark real (medido 2026-10-08, build actual)

Binario CLI: **46.080 bytes** (`-O2 -s`); GUI: **65.536 bytes**. Ver `BENCH.md` para la tabla completa (tanda 12: filtro `e` 106→36ms, `exe` 469→220ms, `*.exe` 546→270ms, `notepad` 387→29ms).

| Raíz | Archivos | Matches | Tiempo | Ritmo |
|---|---|---|---|---|
| `C:\Windows\System32` (`--no-excludes`) | 21.104 | 27 | ~50 ms (warm) | ~25M/min |
| `C:\Windows` (`--no-excludes`) | 225.272 | 52.647 | ~1,9 s (warm) | ~7M/min |
| Todos los discos (`notepad --count`, defaults nuevos) | ~2.331.777 | 12 | ~11 s (4 hilos) | ~12M/min |
| Todos los discos (`exe --count`) | ~2.331.783 | 20.203 | ~11-19 s (4 hilos) | idem |
| Índice GUI (`exe`, persistente) | 2.917.881 (idx) | 16.925 | filtro ~0,1-0,2 s/tecla | parcial: ver brecha conocida |

Target >300K archivos/min: superado ~17-70× según corrida.

## MFT directo (`--mft`, 100% ASM, `src/mft.s`)

- `mft_try_root(ws)` → 1 si enumeró, 0 si fallback. Solo con `--mft` (`scan_opt_mft=1`); sin flag nunca se intenta. Llamado desde `scan_root_ws` tras crear el record raíz (cubre `scan_run`, `scan_one_root` y cada unidad de `scan_run_all`/GUI).
- Requisitos: admin (abrir `\\.\X:` con `CreateFileW`+`FSCTL_GET_NTFS_VOLUME_DATA`+bucle `FSCTL_ENUM_USN_DATA` 64KB, solo `USN_RECORD_V2`), NTFS, raíz de unidad. Multihilo desactivado con `--mft` (`sra_mft_seq`: 1 ws por unidad, secuencial; el hash FRN→tmp global no es thread-safe).
- Paridad por diseño: mismos records 12B, nombres UTF-8, mismos `path_is_excluded` (full path reconstruido vía `build_path` del padre + nombre) y mismo matching (`contains_ci_a`/`glob_match_ci_a`); directorios siempre, archivos solo si match (streaming) o todos (índice); reparse (`0x400`), `.`/`..`, FRN<16 (salvo raíz 5) y huérfanos se ignoran como Find (invisibles, sin contar). Tabla FRN→tmp (hash abierto 4M×16B) + temp 512MB (commit progresivo) + resolución recursiva memoizada; estado del ws restaurado si falla.
- Fallbacks explícitos (nunca parciales): subruta o `--topdirs` → aviso a stderr + Find (`mft=F`, mismo resultado, exit 0). Volumen que no abre → `seek: --mft requiere admin y raiz de unidad NTFS`, exit 1 (sin fallback). Sin `--mft` el comportamiento es 100% Find (`mft=F`).
- Estado 2026-10-08 (sin admin en la máquina): goldens sin `--mft` intactos (`dll C:\Windows --no-excludes` 52647/225272, System32 27/21104, `*.exe` 765, `exe` todos los discos 20200 = `--idxdbg` 20200, `dll` 28220 = idxdbg, `notepad` 12 = idxdbg, `--idxdbg` sin `trunc`); con `--mft` en subruta: aviso + idéntico (`mft=F`); en unidad o todos los discos: error limpio exit 1. Speedup real pendiente de medición con admin (el path MFT no se pudo ejecutar: requiere `SeBackupPrivilege`/elevación). Auto-activación (GUI o CLI por defecto) desactivada hasta paridad admin verificada (hard links de WinSxS, SVI/denegados y `$Extend` son las brechas conocidas a comprobar).
- Brechas conocidas del path MFT (a verificar con admin): hard links (si `ENUM_USN` devuelve 1 registro por FRN, se subcuentan vs Find que cuenta cada entrada); dirs denegados incluso para admin (SVI) se verían en MFT pero Find los salta (`--no-excludes` en raíz diferiría); solo V2 (`Min=Max=2`); tope ~4M entradas en hash.

## Roadmap V2 (MFT directo) — MVP detrás de `--mft`

MVP usa `FindFirstFileExW` por defecto a propósito (con fallback). V2 implementado parcial: flag `--mft` que abre el volumen y enumera con `FSCTL_ENUM_USN_DATA` al mismo record de 12B vía tabla FRN→idx (auto-uso desactivado: sin paridad admin verificada queda detrás del flag, como exige el diseño). Pendiente con admin (1-2 builds): paridad `C:\` con `--mft` vs Find, medición de speedup, y entonces auto (handle abre → MFT, si no fallback silencioso) + soporte de subrutas por prefijo.

## Toolchain (fijo, no instalar nada)

- `G:\Dev\w64devkit\bin\gcc.exe` (GCC 16.2.0), `as.exe`, `ld.exe`.
- Sin nasm/ml64/link. Compila con `build.bat`.

## Trampas GAS que costaron 3 iteraciones (leer antes de tocar)

1. La API es `GetFullPathNameW`, no `GetFullPathW` (no existe en `libkernel32.a`).
2. `mov r32, SIMBOLO` en sintaxis Intel de GAS es **carga absoluta** `[addr]`,
   no inmediato, si el `.equ` está definido **después** del uso (forward-ref).
   Regla: todo `.equ` numérico va antes del primer uso (ver nota en `main.s`).
   Se detecta con `objdump -d`: `mov 0x10,%ecx` en vez de `mov $0x10,%ecx`.
3. `mov r8, LEN` / `mov rcx, LEN` con `.equ` previo sí ensambla inmediato.
4. Pila 16B antes de `call` (ABI x64): con `push rbp` + 7 regs (64B) el `sub`
   debe ser ≡8 mod 16 (72/136/168/…), no múltiplo de 16. Con +8 de skew,
   `CoInitializeEx` muere en `ntdll!RtlDosApplyFileIsolationRedirection_Ustr`
   (0xc0000005). Probado: alineado → S_OK; con +8 → AV.
5. Slots de pila con el mismo ancho en store y load: `mov DWORD [rsp+144],r14d`
   + `mov rdx,QWORD [rsp+144]` deja los 4B altos con basura → puntero salvaje
   y AV determinista fuera del depurador (bajo gdb la basura era 0 y pasaba).
   Regla: el load usa el ancho del store (`mov edx,DWORD [...]`, extiende a 0).

6. Comentarios `//` solo en linea propia: GAS en posicion trailing los lee como
   division (`division by zero` / `junk ... after expression`). Trailing validos:`#` y
   `/* ... */`. Costo 3 iteraciones de build.

## Firma de 64 bits por record (estrechar candidatos, "producto de condiciones")

Optimizacion del filtro por nombre: cada record lleva una **firma de 64 bits** con
los caracteres plegados que aparecen en su nombre (26 letras + 10 digitos + ASCII
bajo + hash de los demas). El filtro evalua la query entera como un producto de
condiciones: si a la query le falta un bit, ese record **no puede matchear** y se
descarta **sin leer el nombre** (que vive disperso en la arena, ~130 MB).
Sustituye al pre-filtro por primer byte (SSE2) que leia el nombre de cada record.

- `rs/seekcore/src/lib.rs`: `skc_bloom_build` (arma la firma desde el nombre UTF-8),
  `skc_bloom_mask` (arma la mascara de la query), `sig_bit` (mapeo char -> bit).
- `src/scan.s`: `scan_bloom` (puntero a la tabla de firmas, 96 MB reservados) y
  escritura de la firma al emitir cada record (`sor_dir_nobloom` / `sor_file_nobloom`).
- `src/gui.s`: `gui_bloom` (tabla), `gui_qmask` (mascara de la query) y el test en
  el loop single y en el worker del filtro.

Guardas: el indice del record debe caber en la tabla (<12M) y el largo del nombre
<= 4096 bytes; ademas el Rust topa el largo a 4096.

## Crash preexistente al arrancar (ABIERTO, sin resolver)

Hechos medidos (build actual):
- La app muere **4-7 s despues de abrir**, antes de que arranque el indexer y sin
  escribir ninguna query. El crash **no depende de la firma**: con la firma
  100% deshabilitada (sin tabla, sin mascara, sin test en el filtro y sin escritura
  en el scanner) el crash sigue igual.
- Excepcion 0xC0000005; el PC queda en la **base del modulo** (ejecuta la cabecera
  MZ del propio seek-gui.exe) y la pila del hilo principal aparece corrupta.
- Ocurre igual en modo `--window` y en modo barra, y **no** ocurre en `seek.exe`
  (el CLI indexa los 4 discos sin problema: 2.924.465 archivos en 107 s).
- En el arranque aparecen **dos procesos seek-gui**: la app se relanza/duplica y el
  watchdog de instancia unica (`gui_single_watch` -> `gui_enum_close`) cierra la
  otra; la ruta de cierre es suspecta (mismo "AV determinista ~4s" que el acrylic
  ya desactivado en el codigo).
- Herramientas usadas: gdb (mingw) con `catch signal SIGSEGV`; WER LocalDumps no
  genera dump en esta maquina (WerSvc no arranca) y no hay cdb instalado.

Corregido de paso (bugs reales de memoria, del cache de rutas):
- `skc_score_rec`: el cache de ancestros escribia en `idxp/lenp` con indice
  `lvl >= SC_DEPTH` (64) cuando la cadena era mas profunda -> escritura fuera de
  rango. Ahora `lvl < SC_DEPTH`.
- `skc_score_rec`: la escritura del separador `\` no comprobaba `o2 < cap` -> un
  WCHAR de mas al final del path (justo donde el worker tiene los registros
  guardados en la pila).

## Crash al arrancar: causa raiz y arreglo (2026-10-20)

La app murria 4-7 s despues de abrir (0xC0000005) y se trababa antes de cerrar.
Causa raiz: **desbalance de 8 bytes en el marco de `gui_start_index`** (el epilogue
liberaba 72 con `add rsp, 72` pero el prologo reservaba 80 con `sub rsp, 80`).
El `ret` final saltaba 8 bytes antes de lo debido y tomaba como direccion de
retorno el `rbx` guardado = **hInstance = la base del modulo**: el PC quedaba en
la cabecera MZ del propio seek-gui.exe y el proceso muria al ejecutar los
primeros bytes del encabezado PE. La sintoma era exactamente "se traba y se
cierra rapido".
Arreglo: `add rsp, 72` -> `add rsp, 80` en `gsi_ret`.

Segundo bug (mismo arranque): la tabla de firmas de 96 MB se reservaba con
`MEM_RESERVE` **sin commitear**, asi que el `*out = m` de `skc_bloom_build`
fault-eaba (AV al escribir). Arreglo: `MEM_RESERVE|MEM_COMMIT` (0x3000).

Verificado: la app vive (>5 min, index completo, CPU ociosa), y el filtro por
nombre con la firma da 5-15 ms contra 136-187 ms sin ella, con conteos
identicos (A/B: perca 388, proyecto 148, Documentos 5, zzlat 0).
