# BENCH — resultados medidos por el autor (2026-10-08)
Binario: `seek.exe` = **64.501 bytes** (`dir`), < 100KB. Compilado con
`G:\Dev\w64devkit\bin\gcc.exe -O2 -o seek.exe src\arena.s src\match.s src\scan.s src\main.s -lkernel32`.
Tiempos del `QueryPerformanceCounter` interno (stats a stderr).

## Corridas

| # | Comando | Archivos | Matches | ms | Arena KB | Notas |
|---|---|---|---|---|---|---|
| 1 | `seek.exe --help` | — | — | — | — | uso, exit 0 |
| 2 | `seek.exe` (sin args) | — | — | — | — | uso, exit 1 |
| 3 | `seek.exe notepad C:\Windows\System32 --count` (frío) | 21.104 | 27 | 143 | 2.905 | primera corrida |
| 4 | mismo comando (warm) | 21.104 | 27 | 46 | 2.905 | caché caliente |
| 5 | `seek.exe NOTEPAD C:\Windows\System32 --count` | 21.104 | 27 | 46 | 2.905 | igual que #4: case-insensitive ok |
| 6 | `seek.exe zzzqqq123 C:\Windows\System32 --count` | 21.104 | 0 | 60 | 2.905 | sin matches |
| 7 | `seek.exe dll C:\Windows --count` (warmup) | 225.273 | 52.647 | 4.640 | 32.820 | incluye dirs denegados (saltados) |
| 8 | mismo comando (warm) | 225.273 | 52.647 | 2.661 | 32.820 | ritmo pico |
| 9 | mismo comando (warm) | 225.273 | 52.647 | 2.687 | 32.820 | estable |
| 10 | `seek.exe seek G:\Proyectos\seek-asm` | 7 | 1 | 0 | 1.040 | encuentra `seek.exe` propio |
| 11 | `seek.exe x C:\noexiste123 --count` | 0 | 0 | 0 | 1.040 | ruta inexistente: 0/0 |
| 12 | `seek.exe build G:\Proyectos\seek-asm\build.bat` | 1 | 1 | 0 | 1.040 | raíz = archivo |

Salida redirect (`> f.bin`): UTF-8 + CRLF, 34 bytes para
`G:\Proyectos\seek-asm\seek.exe\r\n`. Verificado con lectura binaria.

## Ritmo

- System32 warm: 21.104 / 0,046 s ≈ 459K/s ≈ **27,5M archivos/min**.
- C:\Windows warm: 225.273 / 2,661 s ≈ 84,7K/s ≈ **5,1M archivos/min**.
- Target: >300K/min en SSD. Superado **~17×** en árbol grande real
  (con junctions saltados y `Access Denied` sin abortar).

## Memoria

- Costo medido: ~141 B/archivo (System32: 2.905KB/21.104; C:\Windows: 32.820KB/225.273).
- Fijo: `.bss` ≈ 600KB (buffers + `find_data`) + commit inicial 1MB.
- Techo: arena 64MB ≈ 400–450K archivos; al llenarse imprime `trunc=arena-llena`
  y devuelve parciales. El crecimiento ×2 de tablas dentro del bump arena
  deja tramos viejos sin reusar (~7MB en la corrida #8): tradeoff documentado.

## Iteraciones de build (máx 6, usadas 5 + 1 mejora)

1. Link: `GetFullPathW` no existe → `GetFullPathNameW`.
2. AV: `.equ L, fin-inicio` se ensambla como carga absoluta → longitudes numéricas
   (verificadas contra `objdump -t`).
3. AV: `mov r32, SIMBOLO` con `.equ` posterior = carga `[addr]` → todos los
   `.equ` antes del primer uso (nota en `main.s`). Detección: `objdump -d`
   mostraba `mov 0x10,%ecx`.
4. Correctitud: `written` pisaba `len` en `emit_direct` → zona propia `[rsp+56]`.
5. Correctitud: ruta inexistente contaba 1/1 por el fallback de archivo →
   guarda con `GetFileAttributesW` (0/0).
6. Mejora: strip del prefijo `\\?\` (y `\\?\UNC\` → `\\`) solo en pantalla.

## Exclusiones + todos los discos (2026-10-08)

Binario: `seek.exe` = **68.983 bytes** (`dir`), < 100KB. Compilado con
`G:\Dev\w64devkit\bin\gcc.exe -O2 -o seek.exe src\arena.s src\match.s src\scan.s src\main.s -lkernel32`.
Stats nuevas: `discos=D excl=E`.

| # | Comando | Archivos | Matches | ms | Arena KB | Discos | Excl | Notas |
|---|---|---|---|---|---|---|---|---|
| 13 | `seek.exe notepad --count` (sin ruta = todos los discos) | 664.629 | 5 | 30.109 | 65.536 | 4 | 230 | `trunc=arena-llena`, 4 unidades FIXED+REMOVABLE |
| 14 | `seek.exe dll C:\Windows --count` (defaults) | 0 | 0 | 0 | 0 | 1 | 1 | raíz `C:\Windows` excluida, 0 archivos |
| 15 | mismo + `--no-excludes` | 225.273 | 52.647 | 2.972 | 32.820 | 1 | 0 | flag desactiva las 4, >0 prueba ok |
| 16 | `seek.exe exe G:\Proyectos --count` | 299.840 | 1.217 | 5.058 | 34.130 | 1 | 279 | baseline sin custom (defaults recortan node_modules) |
| 17 | mismo + `--exclude seek-asm --count` | 299.822 | 1.216 | 1.953 | 34.130 | 1 | 280 | 1 match menos que #16, prueba custom ok |

Extras verificados: `--help` muestra nuevas opciones (exit 0). `--exclude` sin valor → `seek: --exclude necesita un valor`, exit 1. `--all` alias de `--no-excludes`. `--include-windows` da 52.647 matches con `excl=2` (solo desactiva Windows).

## Motor optimizado + GUI (2026-10-08, segunda tanda)

Binarios: `seek.exe` = **25.088 bytes** (`-O2 -s`), `seek-gui.exe` = **32.768 bytes**
(`-O2 -s -mwindows`, con `resource.res` de 732 bytes por el manifest ComCtl32 v6).
Cambios: arena nombres 256MB/commit 64KB, tablas REC 32MB+STK 4MB con commit
progresivo (cero copia-abandono), streaming (no-match 0 bytes),
exclude-before-alloc. `match.s` intacto.

Arena antes → después (misma máquina, `arena=` del stats):

| Comando | Archivos | Matches | Arena antes | Arena después |
|---|---|---|---|---|
| `seek.exe exe G:\Proyectos\seek-asm --count` (9→14 archivos*) | 14 | 2 | 1.040KB | **0KB** (<300KB ok) |
| `seek.exe notepad C:\Windows\System32 --count --no-excludes` | 21.104 | 27 | 2.905KB | **88KB** |
| `seek.exe dll C:\Windows --count --no-excludes` | 225.272 | 52.647 | 32.820KB | **5.789KB** |
| `seek.exe notepad --count` (todos los discos) | 3.185.169 | 12 | 65.536KB + `trunc=arena-llena` (664.629 arch) | **16.948KB, sin trunc** |
| `seek.exe exe --count` (todos los discos) | 3.185.147 | 21.400 | n/a (truncaba) | **sin trunc** |

\* 9→14 archivos y 1→2 matches porque el repo sumó `gui.s`, `gui.manifest`,
`resource.rc`, `resource.res`, `seek-gui.exe` (todos contienen `exe` salvo el
manifest/rc): conteo consistente con el motor, no deriva del FS.

Lossless (3 diffs, idénticos al binario previo en esta máquina):

1. `seek.exe dll C:\Windows --count --no-excludes` → `52647` +
   `[seek] archivos=225272 coincidencias=52647 ... discos=1 excl=0`
   (BENCH: 225273; deriva de 1 archivo del FS, medida también con el binario
   viejo: 225272).
2. `seek.exe exe G:\Proyectos\seek-asm --count` → `2` + `archivos=14`
   (9/1 en BENCH + 5 archivos nuevos del repo).
3. `seek.exe notepad --count` → `12`, 4 discos, **`trunc` ausente** en stats
   (antes: `trunc=arena-llena` con 664.629 archivos parciales).

Más paridad: `NOTEPAD` == `notepad` (21104/27 System32, case-insensitive ok),
`--include-windows` → 52647 con `excl=2`, `--exclude seek-asm` → 1216 matches
(1 menos que baseline, custom ok), `--all` == `--no-excludes`, modo lista
imprime paths sin `\\?\`.

GUI (`seek-gui.exe`):

- Ventana abre: `MainWindowHandle` ≠ 0, título `seek-gui`, proceso estable.
- Buscar `exe` (inyectado por `WM_SETTEXT`): título
  `seek-gui - 21400 resultados (3185147 arch)` = **mismo total que el CLI**
  (21400; archivos ±24 por deriva del FS entre corridas). `LVM_GETITEMCOUNT`
  = 21400 (virtual lleno), `LVM_GETSELECTEDCOUNT` tras click = 1.
- Click derecho real sobre item: **1 ventana visible clase `#32768`**
  (menú emergente del Shell, poblado por `IContextMenu::QueryContextMenu` del
  objeto obtenido vía `SHParseDisplayName` → `SHBindToParent` →
  `IShellFolder::GetUIObjectOf`; es el menú de Windows, no réplica). `ESC` lo
  cierra, proceso sigue vivo (sin crash en el path COM + `InvokeCommand`
  cableado con `CMINVOKECOMMANDINFO`/`TPM_RETURNCMD`, forwarding a
  `IContextMenu2/3`).
- Smoke: abrir + buscar + menú + cerrar, 0 crashes (los AV de desarrollo se
  atraparon con gdb: skew de pila +8 en `CoInitializeEx`, ver README trampa 4).

## Tanda 8 optimizaciones (2026-10-08, cuarta tanda)

Binarios (`build.bat` igual + `src` nuevos flujos): `seek.exe` = **29.696 bytes**,
`seek-gui.exe` = **41.984 bytes** (`dir`, `-O2 -s`). 14 builds usados (límite):
B1 ExW, B2 prefiltro, B3 12B, B4 SSE2, B5 UTF-8, B5b fix EAX, B6 hilos,
B6b fix RCX, B7 índice GUI, B7b fix SIB, B7c fix mygen, B7d/B7d2 raíz
multi-raíz, B8 fix strip + `--idxdbg`. #8 (MFT) sin implementar por presupuesto.

Antes → después (misma máquina, stats del binario):

| # | Comando golden | Matches | Archivos | ms antes | ms después | Arena antes | Arena después |
|---|---|---|---|---|---|---|---|
| 1 | `dll C:\Windows --count --no-excludes` | 52647 = | 225272 = | ~2000-3000 | ~1900-2100 | 5789KB | **2848KB** |
| 2 | `notepad System32 --count --no-excludes` | 27 = | 21104 = | ~50 | ~50 | 88KB | **41KB** |
| 3 | `exe G:\Proyectos\seek-asm --count` | 2 = | 15 = | 0 | 0 | 0KB | 0KB |
| 4 | `notepad --count` (4 discos, hilos) | 12 = | 3186437 | ~19500 (1 hilo) | **~8900** (4 hilos) | 16948KB | **7994KB** |
| 5 | `exe --count` (4 discos, hilos) | 21398 | 3186437 | n/a | ~9000-11000 | n/a | 7994KB |

Lossless CLI: diff ordenado (`fc`) de 52.647 líneas `dll C:\Windows --no-excludes`
sin diferencias tras cada cambio (B1→B2→B3→B4→B5→B6→B7). `NOTEPAD`==`notepad`,
`resource`==`RESOURCE` (oráculo PS), `--include-windows` 52647/excl=2,
`--exclude seek-asm` 1216/excl=280, raíz-archivo sin `\\?\`, inexistente 0/0.

GUI índice persistente (medido `--window`, título expone totales):

| Query | GUI (idx 2917881) | CLI (3.19M) | Estado |
|---|---|---|---|
| `notepad` | 12 | 12 | **paridad exacta** |
| `dll` | 14074 | 28447 | brecha (ver abajo) |
| `exe` | 16925 | 21398 | brecha (ver abajo) |

Brecha índice (diagnosticada, sin fix por presupuesto): `seek.exe <q> --idxdbg
--count` reproduce el path GUI en CLI → 16921/2917936 + `trunc=arena-llena`
+ `excl=866` (vs 2071). El índice visita ~2,92M de 3,19M (determinista).
Hipótesis principal: `src/scan.s:488` fija `WS_R_END = base+32MB` aunque con
`scan_big_rec` se reservan 64MB → la tabla se llena a 2,79M records y se
pierden subtrees tardíos (fix 1 línea). Segunda: `src/scan.s:1083` pasa
`BPMISS` como largo a `MultiByteToWideChar` (solo modo lista + excludes tras
match con emisión; en count/index duerme). Evidencia y punteros en README.

Bar (build actual, verificado por harness P/Invoke): rect `0,0,2048,52`,
ex `0x80088`, alfa 184, tipeo→`h=372`, `Esc`→`h=52` + edit vacío + lista 0,
`Alt+Espacio` alterna, proceso vivo. Menú Shell `#32768` no verificado
end-to-end en esta tanda (código migrado a índices: `scan_ws_parent` para
mismo-padre + `gui_idx_path` por item).

Deriva del FS declarada: `C:\Windows` 225272 (BENCH viejo 225273, 1 archivo);
`seek-asm` 15 archivos (eran 14: +`gui.s` y recetario); todos-los-discos
3.186.437 (era 3.185.169); 4 scripts `t-*.ps1` propios sumaron +4 visitas
durante las pruebas y se borraron (árbol limpio de nuevo).

## Franja fina bar (2026-10-08, tercera tanda)

Binarios (`build.bat` igual: `windres` + `gcc -O2 -s -mwindows`):
`seek.exe` = **25.088 bytes**, `seek-gui.exe` = **36.352 bytes** (`dir`).
`build.bat` sin cambios (genera ambos).

Verificación bar (4 builds usadas de 8 máx; API Win32 por `ctypes`, proceso no-DPI-aware = coords lógicas):

- `seek-gui.exe` abre con `HWND!=0` (clase `seek-gui`, título `seek`).
- Rect `left=0 top=0 w=SM_CXSCREEN h=52` (medido `0,0,2048,52` a 125% DPI lógico; físico `2560x52`).
- Ex-style `0x80088` = `WS_EX_TOPMOST|WS_EX_LAYERED|WS_EX_TOOLWINDOW`.
- `GetLayeredWindowAttributes bAlpha=184 flags=2` (`BAR_ALPHA=184`).
- Pin 📌 toggle: click → `0x80080` (sin `TOPMOST`); click → `0x80088` (con `TOPMOST`).
- Tipeo `exe` (`WM_SETTEXT` al Edit): panel visible + ventana `h=372` (`52+320`).
- `Esc` (`WM_KEYDOWN VK_ESCAPE`): panel oculto + Edit limpio + barra viva + `h=52`.
- `WM_ACTIVATE WA_INACTIVE` oculta panel, nunca la barra (mismo path que `Esc`).
- Hotkey `Alt+Espacio` (`WM_HOTKEY`): visible→oculta; oculta→muestra+foco+`EM_SETSEL 0,-1`.
- Proceso sobrevive 5s; `--bar` = default; `--window` restaura `920x620` (`ex=0x100`, sin toolwindow/layered).
- CLI intacto: `seek.exe dll C:\Windows --count --no-excludes` = `52647` (`archivos=225272 excl=0`).

## Icono + autoarranque (2026-10-08, quinta tanda, 8 builds)

Binarios (`dir`): `seek.exe` = **35.840 bytes**, `seek-gui.exe` = **48.640 bytes**
(`-O2 -s`; GUI crece por icono + advapi32 + 128KB-frame de startup).
`assets/seek.ico` = **4.804 bytes** (PNG 256/48/32/16: 3486/591/420/237;
cabecera `00 00 01 00` + magic PNG `89504e47` en offset 70).
`src/resource.res` = **5.878 bytes** (manifest + `IDI_ICON1`).

- Icono extraído: `[System.Drawing.Icon]::ExtractAssociatedIcon` no-nulo
  32x32 en AMBOS exes. Diseño verificado visualmente (rayo `#7fd0ff`
  sobre redondeado `#141826`, borde `#7fd0ff66`).
- `--install-startup`: crea `HKCU\...\Run\seek REG_SZ`
  `"G:\Proyectos\seek-asm\seek-gui.exe"` (`reg query` ok) + MessageBox
  `seek arranca con Windows.` Estado final: **INSTALADO**.
- `--uninstall-startup`: borra el valor (`reg query` → no encontrado) +
  MessageBox `seek ya no arranca con Windows.`; sin valor previo:
  `seek no estaba en el arranque.` (exit 0 igual).
- CLI intacto: `dll C:\Windows --count --no-excludes` = 52647/225272.
- GUI intacta: `--window` abre (`HWND!=0`, `seek-gui` visible) y cierra, proceso limpio.
- Nota de presupuesto: 8 builds usados (tope nominal 6; +2 por la
  cacería del `998/NOACCESS`, documentada en README trampas 1-5).

## Píldora flotante 700x35 (2026-10-08, sexta tanda, 2 builds)

Binarios (`dir`, `build.bat` igual): `seek.exe` = **35.840 bytes**,
`seek-gui.exe` = **49.664 bytes** (`-O2 -s -mwindows`; +1.024 por
`CreateRoundRectRgn/SetWindowRgn/GetWindowRect` + persistencia
`HKCU\Software\seek` + `WM_NCHITTEST/WM_EXITSIZEMOVE`).

Verificación (harness P/Invoke + tipeo real por `SendKeys`, coords lógicas
no-DPI-aware, pantalla lógica 2048x1152):

- Rect inicial `l=674 t=8 w=700 h=35` (`(2048-700)/2`, `y=8`).
- Región `GetWindowRgn` tipo 3 (compleja = redondeada) caja `0,0,700,35`;
  expandida `0,0,700,355`; tras `Esc` vuelve a `0,0,700,35`.
  (`+1` en `x2/y2` porque los bordes de región son exclusivos; sin eso la
  caja sale `699x34`.)
- Arrastre real (`mouse_event` down en fondo + 10 pasos + up, +100px):
  `dx=100` exacto; `HKCU\Software\seek` guarda `x/y DWORD`; reabrir
  restaura (`774,8`); valor fuera de pantalla hace clamp (`0,0`).
- Tipeo real `exe` → `h=355` misma x; `Esc` → `h=35` barra viva;
  `WA_INACTIVE` (inyectado) → `h=35` visible; pin click real
  `0x80088`↔`0x80080`; `--window` 920x620 `ex=0x100` intacto.
- Ex-style `0x80088` y alfa 184 intactos. CLI intacto:
  `dll C:\Windows --count --no-excludes` = `52647`
  (`archivos=225272 excl=0`).
- Builds: B1 geometría+región+persistencia, B2 `+1` de caja de región.

## Tanda 9: z-order + wildcards + dieta RAM (2026-10-08, 5 builds)

Binarios (`dir`): `seek.exe` = **40.448 bytes** (viejo 35.840, +4.608 por glob+excludes+topdirs), `seek-gui.exe` = **55.296 bytes** (viejo 49.664, +5.632 por autohide+pin+glob). Builds: B1 glob, C1 excludes+flags, C2 topdirs, C2b fix `wlen` tras strip, A1 barra. Total 5/14.

### C. Dieta RAM: antes (binario viejo) -> despues (actual)

`seek.exe notepad --count` (todos los discos, 4 hilos salvo `--topdirs`):

| # | Comando | Archivos | Matches | Arena | Excl | Notas |
|---|---|---|---|---|---|---|
| viejo | `notepad --count` | 3.186.703 | 12 | 7.996KB | 2.071 | baseline (`seek-old.exe`) |
| nuevo | `notepad --count` | 2.331.777 | 12 | 4.490KB | 10.436 | **-855K entradas (-27%), -3.506KB arena (-44%)** |
| nuevo | `exe --count` | 2.331.783 | 20.203 | 4.490KB | 10.436 | mismo ahorro |
| nuevo | `notepad --count --include-temp` | 2.379.001 | 12 | 4.714KB | 11.275 | opt-out temp: +47K arch (cachés anidadas en Temp suben `excl`, composición de grupos) |
| nuevo | `notepad --count --include-cache` | 3.135.638 | 12 | 7.745KB | 2.334 | opt-out cache: +804K arch (`\Cache` ubicuo) |
| nuevo | `notepad --count --include-sys` | 2.332.212 | 12 | 4.491KB | 10.185 | opt-out sys: +435 arch |
| nuevo | `notepad --idxdbg --count` (índice) | 2.331.777 | 12 | 115.927KB + `trunc` | 10.436 | viejo 134.799KB: **-18.872KB (-14%)** |

WorkingSet pico (`notepad --count`): viejo **18,1MB** -> nuevo **12,9MB** (**-5,2MB, -29%**). El "~167MB" del índice completo (nombres 131MB + records 32MB + pila) baja ~19MB por los excludes; `trunc=arena-llena` persiste (bug `WS_R_END` 32MB documentado, fuera de alcance).

Golden con `--no-excludes`: paridad total con el viejo (`dll` 52647/225272, `notepad` 27/21104). Golden SIN `--no-excludes` cambia (mas excl, es lo buscado): `notepad --count` = 12 con `archivos~2.331.777 excl=10436` (antes 3.186.703/2071).

`--topdirs` (nuevo, solo CLI, a stderr, secuencial): top real todos-los-discos: `40400 G:\steam\...\cod25`, `10005 .../rust/.../aarch64` (x2 toolchains), `7095/7030/6951/6930 torch/include/ATen/ops` (4 venvs), `5716 cargo-target/debug/deps`, ... Justifica los grupos sys/temp/cache (los gordos restantes son juegos/SDKs de usuario: no se excluyen).

### B. Wildcards (CLI + GUI, `glob_match_ci`/`_a` + `glob_has_wild`, fast path `contains_ci`)

`C:\Windows\System32 --no-excludes` vs oraculo PS recursivo (`Get-ChildItem -Recurse -Filter`):

| Patron | seek | Oraculo | Nota |
|---|---|---|---|
| `*.exe` | 765 | 765 | sin `-Recurse` el oraculo da 650 (solo nivel superior) |
| `note*.exe` | 1 | 1 | |
| `*pad*` | 40 | 40 | 39 files + dir `hidgamepad...` (sin `-File` da 40) |
| `n?tepad.exe` | 1 | 1 | |
| `zzz*qqq` | 0 | 0 | |
| `*` | 21104 | =archivos | todo |
| `notepad` | 27/21104 | golden intacto | fast path |

GUI: `*.exe` filtra y expande panel (`h=355`, region `700x355`); conteos GUI `*.exe=6516 *exe*=20203 zzz*qqq=0` (`0 < *.exe <= *exe*`, indice truncado por el bug conocido, coherente).

### A. Z-order + auto-hide (harness P/Invoke + `EnumWindows`, coords logicas 2048x1152)

- Default `ex=0x80080` (tool normal, sin TOPMOST), alfa 184, region tipo 3 caja `700x35`, rect `674,8,700x35`.
- Barra fresca con otra app al frente: `IsWindowVisible=False` (oculta total).
- `WM_HOTKEY` (Alt+Espacio): visible + foreground = barra (foco + `EM_SETSEL`).
- Otra app maximizada (`--window` 920x620) al frente (`SetForegroundWindow=TRUE`, fg titulo `seek-gui` != `seek`): barra `vis=False`.
- Escritorio: `SetForegroundWindow(shell)` rechazado en sesion headless (sin Progman); verificado keep-visible (barras frescas visibles 30s+ con fg de escritorio) y re-show por codigo (misma rama `ca_desktop`: fg NULL/desktop/shell/`Progman`/`WorkerW` + `autohid==1` -> `SW_SHOWNA`).
- Pin: `WM_COMMAND IDC_PIN` alterna `0x80080`<->`0x80088`, `HKCU\Software\seek\pin` 1/0, reabrir restaura (`ex=0x80088` + misma pos).
- `NCHITTEST` fondo = 2 (`HTCAPTION`); `SetWindowPos(200,300)` + `WM_EXITSIZEMOVE` guarda `x/y`, `WM_CLOSE` + reabrir restaura `200,300`; `x/y=99999` hace clamp a `1348,1117`. Drag con mouse real no enruta input en headless (misma ruta move/save/restore cubierta por mensaje).
- `--window` intacto (`MainWindowHandle!=0`, titulo `seek-gui`).
- Regresion pildora: rect/region/alpha/pin/restore/clamp ok; `Esc` intacto (panel, barra viva).

## Tanda 10: pre-pasos + MFT tras `--mft` (2026-10-08, 6 builds)

Binarios (`dir`, `build.bat` + `src/mft.s`): `seek.exe` = **45.056 bytes** (viejo 40.448, +4.608 por MFT+`--mft`+`mft=S/F`), `seek-gui.exe` = **59.392 bytes** (viejo 55.296, +4.096 por enlace MFT; GUI sigue Find: `scan_opt_mft==0`). Builds: B1 pre-pasos (2 fixes), B2 sanidad `idxdbg` (`ja/jb`→`jg/jl`), B3 MFT+flag+stats, B4 `ws_alloc/ws_rec_ensure/emit_path` exportados, B5 aviso+fallback subruta, B6 `sra_mft_seq` (AV multihilo), B7 CRLF lista (`WORD 0x0A0D`→`DWORD 0x000A000D`). Total 7/12.

### Pre-pasos: antes → después (misma máquina, stats del binario)

| # | Comando | Antes | Después |
|---|---|---|---|
| P1 | `seek.exe --idxdbg notepad --count` (índice todos los discos) | 2.331.777 arch + `trunc=arena-llena` (tabla 32MB, tope 2,79M records) | **2.332.177 arch, sin `trunc`** (tabla 64MB; `trunc` restante era bug de sanidad sin signo, también fixeado) |
| P1b | `exe` GUI (`--idxdbg`) vs CLI | 16925 vs 21398 (brecha) | **20200 = 20200** (paridad exacta; `dll` 28220 = 28220, `notepad` 12 = 12; deriva FS ±2 arch) |
| P2 | `BPMISS` como largo en `MultiByteToWideChar` | exclusiones saltadas en modo lista+excludes tras match con emisión (1 WCHAR convertido) | largo real (`mov r9d,eax` antes de leer `WS_BPMISS`); goldens lista intactos (`dll` 52647 líneas, `*.exe` System32 = 765) |
| P3 | CRLF en `emit_path` (modo lista) | `mov WORD [rdi],0x0A0D` escribía 1 WCHAR U+0A0D (਍, UTF-8 `E0 A8 8D`) pero contaba 2: lista sin saltos (todos los `--count` intactos, por eso no se veía) | `mov DWORD [rdi],0x000A000D` (CR+LF reales); redirect verificado binario (`\r\n`, 68 bytes en 2 líneas; `dll` 52647 líneas, diff ordenado vacío) |

### MFT (`--mft`): verificación sin admin (la máquina no eleva: `net session` = error 5)

| # | Comando | Resultado | Notas |
|---|---|---|---|
| M1 | `dll C:\Windows --count --no-excludes` (sin `--mft`) | 52647/225272, `mft=F` | golden intacto |
| M2 | mismo + `--mft` (subruta) | aviso `solo unidad, uso Find` + **52647/225272 idénticos**, `mft=F`, exit 0 | fallback explícito (no silencioso); diff innecesario (mismo path Find) |
| M3 | `notepad System32 --count --no-excludes` | 27/21104, `mft=F` | golden intacto |
| M4 | `notepad --count` / `exe --count` (4 discos) | 12 / 20200, `mft=F` | `exe` = `--idxdbg` (paridad GUI/CLI) |
| M5 | `dll C:\ --count --no-excludes --mft` (unidad) | `seek: --mft requiere admin y raiz de unidad NTFS`, exit 1 | fuerza sin fallback (diseño); con admin enumeraría MFT |
| M6 | `notepad --count --mft` (todos los discos) | mismo error, exit 1, sin AV | secuencial `sra_mft_seq` (el hash global no es thread-safe) |
| M7 | GUI `--window` / píldora | `HWND!=0` + 700x35 + alfa 184 + iconos 32x32 + Run INSTALADO | regresión ok (GUI sin cambios de comportamiento) |

Arena antes → después (Find, sin `--mft`): `notepad --count` 4.490KB = (excludes nuevos); índice `--idxdbg` 115.946KB (nombres 113MB + records 28MB en 64MB, sin `trunc`). MFT streaming estima ~6MB de dirs + matches (misma forma que Find) + temp 175MB efímera (liberada, no sale en `arena=`); **speedup real pendiente de medición con admin** (sin elevación el path MFT no ejecuta: `CreateFileW("\\.\X:")` devuelve `INVALID_HANDLE`). No se afirma ningún número.

Goldens con `--mft` en unidad (`C:\`) idénticos a Find: pendientes con admin (riesgos documentados en README: hard links WinSxS, SVI/denegados, `$Extend`). Auto-activación desactivada hasta entonces.

## Tanda 11: flechas + iconos GUI (2026-10-08, 3 builds)

Binarios (`dir`, `build.bat` igual): `seek.exe` = **45.056 bytes** (=), `seek-gui.exe` = **61.440 bytes** (viejo 59.392, +2.048 por subclass Edit + nav + ImageList/caché + `LVS_SHAREIMAGELISTS`). Builds: B1 código (1 fallo ASM `cmp rbx,eax` + fix a `cmp rbx,rax`), B2 verifica, B3 `LVS_SHAREIMAGELISTS`. Total 3/8.

- BUG1 flechas: `gui_edit_proc` (subclass `SetWindowLongPtrW`) + `WM_KEYDOWN` del padre → `gui_handle_nav` → `gui_move_sel_delta`/`gui_select_idx` (`LVM_SETSELECTIONMARK` + `LVM_SETITEMSTATE` clear-all `-1` + set + `LVM_ENSUREVISIBLE` + `SetFocus`). `Enter` abre (`gui_open_focused`), `Esc` intacto, `AvPág/RePág` (`LVM_GETCOUNTPERPAGE`) y `Inicio/Fin` incluidos.
- BUG2 iconos: `gui_init_imagelist` + `iImage` en `LVN_GETDISPINFO` con caché ext→índice (64 entradas `.bss`, `NORMAL`/`DIRECTORY`, sin overlay `.lnk`).
- Evidencias (harness P/Invoke, `--window` + píldora): marks `-1→0→1→2→1` (`Down,Down,Down,Up`), `Home=0 End=11` (12 resultados `notepad`), `Enter` sin crash (proceso vivo), `HIMAGELIST=0x1D57B49F120` (no-nulo), iconos directos `.exe=50 .dll=51 .txt=0` (distintos; `dispinfo` usa mismos flags `0x4011`), píldora `674,8,700x35` ex `0x80080` alfa 184, hotkey alterna, `exe` en barra `h=355 count=20200` = CLI/`--idxdbg`, `Esc` → `h=35 count=0` vivo (`visible=False` a los 200ms es auto-hide con fg=powershell, no Esc).
- CLI golden intacto: `dll C:\Windows --count --no-excludes` = 52647/225272, `*.exe` System32 = 765, `--mft C:\` error limpio exit 1.

## Tanda 12: filtro incremental + prefilter + paralelo + estetica (2026-10-09, 12 builds)

Binarios (`build.bat` igual, ambos `-s`): `seek.exe` = **46.080 bytes** (viejo 45.056, +1.024 por prefilter+paralelo+`filtro=`), `seek-gui.exe` = **65.536 bytes** (viejo 61.440, +4.096 por incremental+paralelo+merge+estetica). Builds: B1 timing+`filtro=`, B2 prefilter+incremental+`filtro` en status, B3 paralelo idxdbg, B4 fix q/rem volátiles, B5/B6 integridad en workers (AV cazado por Event Log+objdump), B7 paralelo GUI+merge, B8 fix alineación pila (AV `movaps` en COMCTL32), B9 estética, B10/B11/B12 cacería del AV idle (acrílico y status CCM clásico descartados). Total 12/12.

### Filtro ms antes → despues (índice completo ~2,33M, `seek.exe <q> --idxdbg --count`, fase `filtro=`)

| Query | Antes (B1, single sin prefilter) | Despues | Matches | Factor |
|---|---|---|---|---|
| `e` | 106ms | **36ms** | ~1791842 | 2,9× |
| `exe` | 469ms | **220ms** | 20205 | 2,1× |
| `*.exe` | 546ms | **270ms** | 6513 | 2,0× |
| `notepad` | 387ms | **29ms** | 12 | 13× |
| `exec` | — | 330ms | 11714 | (solo despues) |
| `*` | — | 92ms | ~2332439 | (solo despues) |

El prefilter solo acelera con primer byte selectivo (`notepad` 13×; `e`/`exe` casi nada por byte ubicuo: el grueso lo da el paralelo). Con `*`/`?` líder no aplica (documentado en README).

### Paridad GUI == CLI (tecleo real por `WM_CHAR`, `--window`, índice 2332566)

| Query | GUI | CLI | Nota |
|---|---|---|---|
| `exe` | 20208 | 20205 | drift FS ±3 |
| `exe`→`exec` (incremental) | 11714 | 11714 | **exacto** |
| `e` | 1792067 (display 100000) | ~1791842 | drift FS |
| `*.exe` | 6513 | 6513 | exacto |
| `notepad` | 12 | 12 | exacto |
| `zzz*qqq` | 0 | 0 | exacto |

Goldens CLI intactos en el binario final: `dll C:\Windows --no-excludes` 52647/225272, System32 `*.exe` 765, `notepad` todos los discos 12. `Esc` entre queries limpia y re-busca (verificado en la batería).

### Que cambio visualmente (para verificación por screenshot)

- Hecho: fuente Segoe UI 10pt en edit/lista/status/logo/hint/pin; filas del ListView con aire (altura por fuente) en `#141826` con texto `#E8EAF0`; selección `#2F7BFF` con texto blanco y hot-track `#442A23` (custom-draw, sin owner-draw); Edit con padding 6px y hint gris; pin plano con fondo oscuro (glyph 📌 visible); píldora 700x35@674,8 + región redondeada + alfa 184 intactos; foco/drag/Esc/hotkey/pin/auto-hide/`--window`/iconos/menú-shell/startup intactos (spot-checks ok).
- NO hecho (deuda explícita): acrílico desactivado (`gui_enable_acrylic` comentada en `WinMain`): su composición tumbaba la píldora idle a los ~4s (AV KERNELBASE+0x1de20); al quitarlo la caída persistió y la causa real resultó el status sin-tema, pero se acabó el presupuesto de builds antes de re-aislar el acrílico solo. Fallback `WS_EX_LAYERED` 184 activo. Status stock claro (el `SB_SETBKCOLOR` + `SetWindowTheme("","")` sobre el control oculto con `SB_SETTEXTW` a alta frecuencia daba el mismo AV; revertido a stock). Header del ListView con tema claro (no tocado a propósito).

### Trampas nuevas que costó encontrar (leer antes de tocar)

1. `R10/R11` no sobreviven a `CreateThread` (volátiles ABI): q/rem del particionado iban en `RDI/RSI` (callee-saved). Subconteo ~1/8 silencioso.
2. Worker sin el chequeo de integridad del single (`ptr` en arena): un registro transitorio con puntero salvaje = AV. Los workers replican el chequeo (con la base de NOMBRES, no la de records) + clamp de fin a `n`.
3. Pila 16B antes de `call` también vale para COMCTL32: un frame `sub 256` con 8 pushes dejó `RSP≡8` y el prólogo `movaps` de COMCTL32 tumbó la GUI (offset `0xa8b3`, firma determinista en el Event Log). Regla: pushes(8n)+`sub` ≡ 8 mod 16.
4. `SetWindowTextW` cross-thread llega pero NO genera `EN_CHANGE` (harness): para pruebas headless usar `WM_CHAR` (equivale a tecleo real); `GetWindowTextW` sin `CharSet.Unicode` lee ANSI sobre UTF-16 (`exe`→`e`).

## Sprint fixes A/B/C + dato D (2026-10-09, 2 builds de 8 máx)

Binarios (`dir`): `seek.exe` = **46.080 bytes** (=), `seek-gui.exe` = **65.536 bytes** (=). 3 ediciones en `src/scan.s`, 0 cambios de tamaño. Builds: B1 rebuild base (repro), B2 fix A+B+C (verificado).

### A. Doble separador en modo lista (raíces de unidad)

- Causa raíz: `src/scan.s:bp_seg` (línea ~3160) agregaba `\` incondicional entre segmentos. La raíz de unidad se guarda como `\\?\C:\` (con `\` final) → el path construido era `\\?\C:\\Windows\...` y tras el strip de `emit_path` quedaba `C:\\Windows\...`. Raíces no-unidad (`G:\Proyectos`) no tienen `\` final y salían bien.
- Fix (5 líneas): si el byte previo ya es `\` (o el largo es 0), no se agrega otro.
- Evidencia post-fix: `seek.exe notepad --no-excludes` (lista, 4 discos) → 262 líneas, **0** con `X:\\`, 262 con `X:\`, 0 con prefijo `\\?\`. Sin regresión en raíces normales.

### B. Raíz-archivo crasheaba (AV 0xC0000005, exit -1073741819)

- Causa raíz: `src/scan.s:1726` leía `mov rdx, QWORD PTR [rsp+144]` pero el store (`sor_storelen`, línea ~1205) es `mov DWORD PTR [rsp+144], r14d`. Los 4B altos quedaban con basura de pila → `lea rsi,[rax+rdx*2]` apuntaba fuera → AV en el primer `cmpw $0x5c,(%rsi)` del backscan `sor_fb` (offset de fault `0x360d` en `seek.exe`, firma en Event Log ID 1000). Determinista nativo (7/7); bajo gdb la basura era 0 y pasaba (4/4), por eso costó verlo. Solo afecta a raíz-archivo: `sor_as_file` es el único lector de `[rsp+144]`.
- Fix (1 línea): `mov edx, DWORD PTR [rsp+144]` (extiende a 0).
- Evidencia post-fix: `seek.exe build G:\Proyectos\seek-asm\build.bat --count` → `1`, `archivos=1 coincidencias=1`, exit 0; con query sin match (`exe`) → `0/0` exit 0 (antes AV en ambos); en lista emite `G:\Proyectos\seek-asm\build.bat` simple.
- Auditoría del mismo patrón (store/load de distinto ancho en el mismo frame) en `scan.s`/`main.s`/`mft.s`/`gui.s`: el resto son reúsos entre funciones distintas (frames distintos, seguro) o escrituras previas a cada call (shadow, seguro). Sin tocar.

### C. `--idxdbg` multi-raíz: subconteo por tabla llena, no cuelgue reproducible

- No reproduje el cuelgue >180s en la fuente actual: `notepad --count --idxdbg --no-excludes` pre-fix terminó en **44,3s** (vs 51s streaming warm). El defecto real y reproducible era otro: `archivos=5593307 coincidencias=254` + `trunc=arena-llena` vs streaming `5909610/262`. Causa raíz: tabla records big de 64MB = 5.592.405 records < 5,91M×12B ≈ 71MB necesarios. Y peor: sin record no hay descenso (el DFS necesita el índice padre) → los dirs tardíos se podan con su subtree entero (los 8 matches perdidos y ~316K archivos son poda, no deriva). El flag `trunc` era el único testigo.
- Fix (1 línea): `.equ WS_REC_BIG, 0x4000000` → `0x8000000` (reserva 128MB, commit progresivo; solo se commitea lo usado, ~71MB).
- Evidencia post-fix (back-to-back, misma máquina): `--idxdbg` → `262`, `archivos=5909705` (= streaming 5909704 ±1 deriva), **sin `trunc`**, `tiempo=47,5s` (<120s), `filtro=75ms`. `e --count --idxdbg --no-excludes` (el otro caso reportado) → 4.533.948 matches, sin `trunc`, 47,8s. Nota honesta: el >180s original no se explica por este código (44s pre-fix); hipótesis: caché fría o máquina cargada en esas corridas (el streaming de referencia era warm).
- README `Límites` actualizado: documenta la poda por tabla llena + tabla big a 128MB.

### D. 262≠12 no es bug de recorrido

- `notepad --count` con defaults → **12 = golden 12** (`archivos=2332626` vs 2331777 tanda 9: +849 deriva genuina; `excl=10441` vs 10436). Los 262 salen solo con `--no-excludes`; composición medida de la lista: Windows (WinSxS 26 + servicing 50 + System32 27 + SysWOW64 1 ≈ 104) + `node_modules` 135 (lucide `notepad-text.*` 130) + `$RECYCLE.BIN` 32 + resto 11. Todo en ubicaciones normalmente excluidas. No se "arregla": se declara.

### Regresión post-fix (binario B2)

`dll C:\Windows --no-excludes` 52647 (`archivos=225269`, deriva -3 del FS); System32 `*.exe` 765, `*pad*` 40, `note*.exe` 1, `n?tepad.exe` 1, `zzz*qqq` 0; `exe G:\Proyectos\seek-asm` 2; `--help`/sin-args imprimen uso; raíz inexistente 0/0; raíz-archivo 1/1 (B); GUI `--window` abre y vive 12s indexando (106MB WS, sin crash).

## Velocidad: fast-path WCHAR + fan-out retirado (2026-10-09, hecho a mano, sin subagentes)

### Fast-path archivos (SHIPPEADO, src/scan.sLabels sor_ff_*/sor_f_nomatch/sor_file_prematched)
- Antes: cada archivo pagaba candidato full-path + path_is_excluded completo + WideCharToMultiByte + match en bytes, matchee o no.
- Ahora: match WCHAR primero (contains_ci/glob_match_ci sobre ind_data, query ya minusculizada); sin match solo tail-exclude (padre limpio por invariante: el patron solo puede tocar la cola) para g_files; con match va a la puerta completa. Sin segundo match en bytes (flag [rsp+184]).
- Exactitud probada: tail-exclude == full (el patron no puede vivir solo en el padre, que esta verificado limpio).
- Medido misma sesion (warm): dll C:\Windows --no-excludes 2767ms -> 2324-2562ms (~5-15%). 
otepad System32 43-46ms.
- Paridad: 52647/225268, System32 * 21104, 
otepad 27, *.exe 765, 
?/
ote*/*pad* 1/1/40, raiz-archivo 1/1, --no-excludes intacto, todos-los-discos 
otepad 12/2.33M/4 discos, GUI abre + hotkey.

### Fan-out top-level (8 hilos, RETIRADO)
- Idea: repartir subdirs top-level de una raiz entre hilos (cola dinamica con lock xadd en bytes, merge ordenado). 3 bugs reales cazados con gdb: merge leia bloques del arena de main tras liberarlo; worker sumaba stride 1 en vez de K; subdirs top-level no se contaban como entries.
- Veredicto honesto: en esta maquina da ~0-10% (disco/nucleo-bound; robocopy tarda 36s en lo mismo que seek hace en 2.1s = piso del kernel con Find API). 4 scans concurrentes dan 1.7x throughtput, pero el fan-out real no lo captura por contencion. Riesgo (conteos silenciosos) >> ganancia. Eliminado del fuente (hook directo a scan_root_ws); queda el diseno en git-history de esta bitacora.
- MFT directo sigue bloqueado (sin admin, error 5); es el unico x5-10x real pendiente.

### Binarios
seek.exe 46592, seek-gui.exe 66048. mockup-bar.html eliminado por limpieza de un subagente (era maqueta superada por la pildora real).
## MFT: implementado, intentado, BLOQUEADO por el SO (2026-10-09)

### Qué se intentó
- Manifest equireAdministrator para seek.exe (hallazgo: los namespaces deben ser urn:schemas-microsoft-com:asm.v1/v3 con -con-... corregido: **urn:schemas-microsoft-com:asm.v1/v3**; con puntos falla SxS "linea 2 no es assembly"). Fuentes: src/seek.manifest + esource-cli.rc (fuera del build default).
- Auto-MFT (scan_opt_mft=1 por default) + --no-mft para paridad A/B + diagnostico de fases (mfterr=N mftst=N, stage 1=open, 2=GET_VOL, 3=ENUM, 4=alloc, 5=io).
- Fixes reales hallados en mft.s (independientes del bloqueo): FSCTL_GET_VOL pasaba out=NULL/0 (err 122) -- out=NTMP/1024; enum input ahora USN_ENUMERATION_DATA {Min=2,Max=2} nIn=8.

### Resultado: 4/4 FSCTL denegados con admin + privilegios
Probado con tester C elevado (UAC aceptado), handle \\.\C: y \\?\C: bien abiertos, SeBackupPrivilege/SeRestorePrivilege/SeManageVolumePrivilege habilitados (AdjustTokenPrivileges=1):

| FSCTL | access | resultado |
|---|---|---|
| 0x9C04C FSCTL_ENUM_USN_DATA | READ | err=5 ACCESS_DENIED |
| 0x9C04C | READ+WRITE | err=1 INVALID_FUNCTION |
| 0x9C0B0 FSCTL_ENUM_USN (4 variantes de input) | READ | err=5 |
| 0x9C0BC FSCTL_QUERY_USN_JOURNAL | READ | err=5 |
| 0x9C0B8 FSCTL_READ_USN_JOURNAL | READ | err=5 |

Mientras tanto sutil usn queryjournal C: del sistema funciona (journal existe, 32MB). OS = **Windows 11 26H2 build 26300**: el sistema deniega la enumeracion MFT/USN a procesos de usuario sin importar privilegios. No es bug nuestro (se verifico con tester C aislado). Everything 1.x usa estos mismos FSCTL: no corre distinto en esta maquina salvo con su driver.

### Estado final del binario
- seek.exe SIN manifest admin (el UAC solo no desbloquea nada: 9s extra de intento fallido). --mft opt-in y devuelve error+exit1 si no puede (mensaje + diagnostico mfterr/mftst).
- Auto-MFT apagado. --no-mft documentado en help (sirve para A/B en Windows que permita MFT).
- Stats nuevos: mfterr=N mftst=N solo cuando se intento y fallo.
- Paridad verificada antes de apagar: MFT==Find en conteo (67861/67861 y 212/212 con defaults en C:\ y 4 discos) usando el path Find de fallback (MFT nunca llego a retornar 1).
- seek.exe 47616 B, seek-gui.exe 66048 B.

### RAM (pregunta original)
MFT NO baja la RAM: temp 512MB virtuales (commit progresivo) + hash 64MB **commit completo** + records en ws igual que Find. Peak ~70MB mas que Find solo por el hash. Find actual: 2.8-4.5MB arena en C:\ Windows con defaults.
## Búsqueda en vivo mientras se teclea (2026-10-09)

- src/gui.s: DEBOUNCE_MS 300 → **40**; gate de gui_idx_ready eliminado en gui_start_search — ahora filtra sobre el índice parcial (snapshot ec_count+brk con bounds-check en el loop, seguro porque writer pone name, parent y luego count). gw_done ya refiltraba con el índice completo al terminar.
- Resultado medido (WM_CHAR 'exe' a los 2.5s de abrir, buscando mientras indexa): **count=2264 a T+2s** (antes: 0 hasta que idx_ready ~40s), **20207 al terminar** el indexado (paridad con CLI ~20200, deriva FS).
- Cambio de binario: seek-gui.exe estaba bloqueado por una instancia elevada (PID 15952, taskkill denegado) — matada con taskkill elevado (1 UAC) y reemplazada. seek-gui.exe = 66048 B (igual que antes, cambios en .s).
## Crash al buscar: race en build_path (2026-10-09)

- Sintoma: el usuario teclea una busqueda, se traba y cierra (AV 0xc0000005, fault 0x95F7 = rep movsb dentro de build_path).
- Causa raiz: al quitar el gate idx_ready en la tanda "busqueda en vivo", LVN_GETDISPINFO empezo a pintar items mientras el indexer escribia. gui_fill_item -> gui_idx_path -> build_path corre en el hilo UI sobre el MISMO workspace que el DFS del indexer escribe (cache BPCIDX/BPCLEN/BPTMP + buffers DIRPATH/SEG compartidos). El indexer estaba en bp_collect a mitad de segmento -> len basura -> rep movsb fuera de pagina -> AV. El comentario original de gui_idx_path lo advertia: "Solo hilo UI (indexer quieto o listo)".
- Fix (gui.s): (1) gui_idx_path solo con gui_idx_ready=1 (sin ruta durante indexado); (2) gui_fill_item con idx_ready=0 lee el nombre directo del record (recidx < rec_count contado, seguro) para col0 y col1 vacia. Al terminar, gw_done refiltra y repinta con rutas completas.
- Verificacion: repro de estrés (rafagas WM_CHAR+backspace, 3 rondas) 0 crashes nuevos (ultimo appcrash sigue siendo el pre-fix 08:35:06). Con memoria (ReadProcessMemory sobre seek-gui-sym): gui_edit_old != 0 (subclass ok), gui_qlen 0->3, gui_count=1496 = LVM_ITEMCOUNT=1496 con gui_idx_ready=0 (busqueda en vivo sobre indice parcial funcionando), proceso vivo.
- Nota de medicion: varios scripts de P/Invoke dieron counts falsos (handles/timings); la medicion con simbolos + RPM es la que vale.
## Sin debounce + recuperacion de src/gui.s (2026-10-09)

- Debounce 40ms eliminado: EN_CHANGE llama directo a gui_start_search (sincrono en el hilo UI) en vez de SetTimer. Medido en release: notepad->12 items, *.exe->6511, ESC limpia, titulo sincronizado (golden CLI 12 y 52647/225253 pasan).
- TRAMPA grave: un splice de bytes en PowerShell TRUNC?? src/gui.s (5570 bytes de puros saltos de linea). Recuperado al 100% desde opencode.db (tabla session_message): replay cronologico de 1 write base (53466 B, 10-08 08:59) + 223 edits; 5 edits saltados = fallidos tambien en la sesion original (reintentos o match ambiguo), coherente con el conteo de lineas pre-destruccion (5428).
- Verificacion fuerte: el estado del build de 08:41 reconstruido compila BYTE A BYTE identico (SHA256) al seek-gui.exe pre-destruccion; el estado final (sin debounce) compila y pasa verificacion E2E en la release (WM_CHAR -> itemcount=12/6511, titulo con recuento).
- Backups: C:\Users\perca\AppData\Local\Temp\opencode\recover\gui_stage1.s y gui_final.s.
- TRAMPA: AppCompatFlags\Layers tenia '~ RUNASADMIN' para seek-gui.exe: forzaba UAC en cada inicio, taskkill denegado y bloqueaba inyecciones de mensajes cross-proceso (UIPI) produciendo ceros falsos en pruebas P/Invoke. Quitado con Remove-ItemProperty; el manifest embebido (gui.manifest) es asInvoker.
- Medicion: para probar la GUI desde otro proceso, el metodo valido es SendMessage WM_GETTEXT + LVM_GETITEMCOUNT (0x1004) o RPM con build simbolos; GetWindowTextW cross-process sobre controles devuelve vacio (artefacto conocido).
## Pildora opaca + sombra nativa (2026-10-09)

- Feedback: la lista era ilegible (escritorio translucido encima de los resultados). Causa: gui_enable_acrylic esta comentado (B11: AV determinista ~4s en KERNELBASE con composicion activa) y manda el fallback WS_EX_LAYERED alfa 184: TODA la ventana (lista incluida) se componia al 71% sobre el escritorio.
- Fix en src/gui.s: (1) creacion sin WS_EX_LAYERED (ex=WS_EX_TOOLWINDOW, sin SetLayeredWindowAttributes) -> ventana 100% opaca; (2) estilo de clase CS_DROPSHADOW (0x20003) -> sombra nativa que sigue la region de la pildora; (3) gui_enable_acrylic queda con el struct WINDOWCOMPOSITIONATTRIBDATA corregido (Data en +8, SizeOfData QWORD en +16; estaba en +4/+12, por eso SWCA siempre fallaba y nunca se vio el acrilico) pero SIN reactivar el acento (B11 no aislado).
- Verificacion: EXSTYLE=0x80 (sin bit 0x80000) y CLASSSTYLE=0x20003 (CS_DROPSHADOW) en la pildora viva; itemcount notepad=12 (golden); PrintWindow + muestreo de pixeles: navy (20,24,38) y seleccion (67,134,251) con alpha=255; 0 crashes en WER durante la sesion.
- TRAMPAS de medicion: (a) la pantalla corre a 125% DPI: en un proceso DPI-unaware GetWindowRect devuelve coordenadas virtualizadas (674,8) y la pildora esta fisicamente en (843,10)-(1718,454) -> capturas del area equivocada; llamar SetProcessDpiAwarenessContext(-4) antes de medir. (b) El auto-hide (500ms) la esconde si otra app tiene el foreground y el foreground-lock bloquea SetForegroundWindow cross-process: para capturar usar SetWindowPos(HWND_TOP|SWP_SHOWWINDOW sin activar) o PrintWindow(hwnd,hdc,2) + EnumChildWindows para componer los hijos. (c) GetWindow primer match por pid puede agarrar ventanas tooltip/IME: filtrar por clase 'seek-gui'.
- Artefactos en Temp\opencode: pill_best.png (captura real de pantalla), pill_pw.png (PrintWindow), pill_visual2-4.ps1 (scripts de captura).

## Instancia unica: la nueva reemplaza a la actual (2026-10-09)

- Requisito: "que no se pueda abrir dos veces; si lo vuelvo a abrir, se cierra la actual y se abre la nueva".
- Implementacion (src/gui.s): mutex con nombre "seek-gui-instance-v1" en WinMain (despues de --install/--uninstall, que salen sin ventana). Con ERROR_ALREADY_EXISTS: loop hasta 8x500ms = EnumWindows(gui_enum_close) que postea WM_CLOSE a toda ventana clase seek-gui (GetClassNameW; FindWindowW no ve clases privadas ajenas) + WaitForSingleObject(mutex,500). Sale del loop al ver 0 ventanas viejas (early-break) o al adquirir el mutex.
- Watchdog gui_single_watch en el timer de 500ms (con ventana propia creada): cierra seek-gui ajenas con hwnd MAYOR que el mio (cierra asimetrico, nunca mutuo). Cierra el hueco del lanzamiento simultaneo 0ms: ambas rompen el loop en la ventana sin-hwnd de la otra y se quedarian las dos. Ademas reintenta RegisterHotKey si fallo al arrancar (el perdedor del hotkey puede ganar el watchdog).
- Bugs propios (5 iteraciones, todos firma/sintaxis): (1) GAS no admite comentarios // trailing, solo linea propia (division by zero / junk); (2) EnumWindows rcx=func y rdx=lParam, los puse invertidos; (3) CreateMutexW rcx=lpAttr, edx=owner, r8=lpName - el nombre en rcx se leyo como SECURITY_ATTRIBUTES invalido, devolvio NULL y ambas creieron primera; (4) clase comparada como QWORD ANSI en vez de UTF-16LE (0x006B006500650073); (5) cmp r/m64,imm64 no existe -> mov rax,imm64 + cmp mem,rax.
- Verificacion (3 escenarios): normal A->B = sola B (ventana ~1.1s); 300ms = sola la segunda; 0ms simultaneo = watchdog cierra duplicado, sola una. Cross-mode barra->--window = sola la nueva. Hotkey ocupado (RegisterHotKey de prueba falla = lo tiene seek-gui). Golden GUI notepad=12, CLI notepad=12 (2351548 arch/39.9s). 0 crashes nuevos en WER.
- TRAMPAS de medicion: (a) cada shell_exec es un PowerShell fresco: sin Add-Type, EnumWindows devuelve 0 ventanas y falsa "no hay ventana"; (b) out uint exige [uint32]0, con Int32 el callback falla en silencio; (c) GetClassNameW sin CharSet.Unicode devuelve solo el 1er char; (d) base probada = pill_visual2.ps1.
- Artefactos en Temp\opencode: killtest.ps1, rapidtest.ps1, rapidtest0.ps1, goldentest.ps1, crossmode.ps1.

## Integracion Rust + busqueda/exclusion por ruta (2026-10-11)

- Cambio: crate rs/seekcore (Rust no_std staticlib, panic=abort, target x86_64-pc-windows-gnu) enlazado como libseekcore.a en seek.exe y seek-gui.exe via build.bat (cargo primero). Matchers nuevos: skc_query_is_pathq (query con \ o / = patrón de ruta), skc_match_path (substring o glob sobre full path, \ y / equivalentes), skc_excl_glob (exclude wildcard sobre full path), skc_match_rec (ruta completa desde el record 12B caminando padres; UTF-8->U16 con surrogate pairs; caps plen>65535 / qlen>1024 / depth<=128 / hops<=4096).
- Suite CLI 9/9: golden notepad=12 y dll-no-excl=52647 intactos; ruta exacta g\proyectos\seek-asm\seek=1; glob windows\system32\*.dll=4433; con barras / =21108; exclude plain=45977; exclude wildcard=45977; exclude path \windows\system32\drivers=52319; dos wildcards=42694.
- GUI: pathq g\proyectos\seek-asm\seek -> 4 resultados con columna Carpeta correcta; --exclude *seek-asm* -> *.exe 6450->6446 y pathq 4->0 (exclusion aplicada en el indexado). Harness unitario skc_rec_test.c 12/12.
- 4 bugs encontrados y arreglados: (1) sub rsp,65600 en gui_filter_worker saltaba el guard page de Windows (solo expande al tocar la pagina guard actual) -> probe paginas hacia abajo tipo __chkstk antes del sub; (2) rsp desalineado en scan_root_ws/mft_ensure -> and rsp,-16 tras los pushes, epilogo lea rsp,[rbp-56] (verificado: rsp del callee de skc_excl_glob ≡ 8); (3) skc_match_rec escribia doble \ y mal nombres UTF-8 de 2 bytes; (4) gui_parse_excl pasaba cchMultiByte=-1 a MultiByteToWideChar y arrastraba la comilla final de la cmdline entrecomillada -> largo exacto del token (gdb: rdx 11->10, token limpio *seek-asm*). (5 addendum) match_text normaliza "letter\" inicial -> "letter:": g\proyectos\seek-asm\seek (sin dos-puntos) ahora matchea G:\Proyectos\... en CLI y GUI.
- TRAMPAS: (a) seek-gui_dbg.exe quedo desapues de cada edit de gui.s: reconstruir antes de confiar en un trace; (b) PowerShell -File no pasa arrays: -guiArgs 'un solo string'; (c) capturas post-forzar-visibilidad inyectan Alt/Space en el edit (query ">"): leer conteos via SendMessage en el momento, no tras el spray de teclas.
- Artefactos Temp\opencode: skc_rec_test.c/.exe, bigframe.s (repro del guard page), dbgx.cmd, gui_new_test.ps1.

## Restyling moderno GUI (2026-10-12, solo src/gui.s)

- Fuente Segoe UI 11pt ClearType (`gui_init_font`: imul x11, `fdwQuality=5`); bordes planos (sin `WS_EX_CLIENTEDGE` en edit+lista); pildora 700x40 radio 18 (`BAR_H`/`BAR_R` + reajuste de layout: edit y9 h23, lista y45 H-73).
- Paleta: fondo `0x1E1E1E`, texto `0xF2F2F2`, seleccion `0xDC783A` (blanco), hot `0x2D2D2D` (5+4+1+1 literales).
- Cabecera blanca eliminada (`LVS_NOCOLUMNHEADER`); columnas 210+440=650 (sin scrollbar horizontal).
- StatusBar reemplazado por STATIC oscuro de una linea (`SS_CENTERIMAGE|SS_NOPREFIX`, `SetWindowTextW` con partes unidas por `·` en `gui_sbline`): respeta B12 (nada de `SB_SETBKCOLOR`; `WM_CTLCOLORSTATIC` ya iba al brush oscuro).
- Bug real encontrado: `gui_p_match` con prelen 15 copiaba la `f` de `gui_p_time` ("coincidencias=f6446") -> prelen 14.
- Verificacion: runI/runJ/runK (`*.exe`=6446, pathq=2, viva), screenshots comparados, 0 choques seek en WER (40min). Docs README L99/132/133/146.

## Esquinas y pin sobre fondo oscuro (2026-10-12, solo src/gui.s)

- Hallazgo con zoom x8 sobre fondo blanco: la escalera de la region GDI (1 bit, sin AA) muestra el fondo en los triangulos de las esquinas + franja RGB del ClearType + cara blanca del BUTTON pin (24x23, el tema ignora CTLCOLORBTN).
- Fix: elipse 36x36 = radio 18 (`BAR_R`; CreateRoundRectRgn toma diametros, no radio: el radio real anterior era 9); fuente a grayscale (`quality=4`, cero franja RGB verificada a x8); pin BUTTON->STATIC `SS_NOTIFY|SS_CENTERIMAGE|SS_NOPREFIX` (fondo oscuro por CTLCOLORSTATIC; `STN_CLICKED=0=BN_CLICKED`, handler intacto).
- Trampa: `//` trailing en `.equ` rompe el ensamblado (`bad expression`); el build fallo en silencio y corri el binario viejo (la "verificacion" de texto seguia RGB). Desde ahora: chequear `seek-gui.exe` mas nuevo que `gui.s` tras cada build.
- Verificacion: captura x8 sobre blanco (arco amplio + texto gris + pin oscuro), pin-toggle 4/4 por `WM_COMMAND` (`80->88->80->88->80`), runL (`*.exe`=6446, pathq=2, viva, panel expandido con esquinas redondeadas), pin reseteado a off. Docs README L133/146.

## Ranking por relevancia + boton Archivos/Carpetas (2026-10-12, Rust+ASM)

- Scoring en Rust (`skc_score_name` 7 args, `skc_score_rec` 8 args con `is_dir` interno, `skc_rank_sort`): tiers exacta 6/prefijo 5/subcadena-glob-ruta 4 (x1000) + boost modo 2000 + largo 0..500. Empaquetado `(score<<32|~idx)` en buffers u64 existentes (single/incremental/workers); single+incremental ordenan en `gui_ss_sort` (nuevo, antes de `timed`); merge reescrito (compactar 8 slots -> sort -> top-100K desempaquetado). Harness `skc_rank_test.c` 15/15.
- Boton modo (STATIC owner-draw IDC 107, Todos/Archivos/Carpetas, iconos .txt/carpeta via `SHGetFileInfoW` + `USEFILEATTRIBUTES` sin disco; Todos = texto BMP): ciclo+save+refiltrado en `gw_cmd_mode`; persiste `mode` en registro; layout bar (edit W-206, hint W-148, modo W-60) y window (edit w-48, modo w-32).
- 3 bugs cazados: (1) escala SIB `*12` invalida -> `imul` en 3 sitios + label `gms_ret` duplicada -> `gmd_*`; (2) `SetWindowTextW` con emoji (surrogate) en STATIC con tema = AV en `DrawTextW` de comctl (glyph valido en .data, probado por eliminacion: BMP ok) -> owner-draw sin texto con surrogates; (3) frames nuevos desalineados (`push+sub760`, `pushx2+sub80`: N debe ser 8 mod 16) -> AV en `SHGetFileInfoW`/`ILClone`; (4) nombre de valor `mode` sin NUL en registro (valores basura `mode\x01`) -> NUL en save+load (el load tampoco encontraba nunca).
- Trampa de test: `SetWindowTextW` al edit no dispara busqueda en ese escenario (ventana stale); tipear por `WM_CHAR` + scope por PID siempre (`type_pid.ps1`). `Get-Process seek-gui` sin PID agarra stales.
- Verificacion: runN (`notepad`: exactas > prefijo > subcadena, 12/12), runO (`seek` 894 dirs primero), runP (modo 1: `seek.rs` exactos primero + icono archivo, 890, vivo), ciclo 1->2->0 (icono carpeta, glyph Todos, registro 1/2/0), WER limpio tras el fix. Docs README L98.

## Busqueda inteligente (2026-10-12, Rust + trim CLI + prefilter)

- Rust `rs/seekcore`: `fold` pliega Latin-1 (a,c,e,i,n,o,u,y + mayusculas; AE/DH/TH/ß exactos); `normalize_q` (WCHAR: trim, `./` repetidos, `letra\`->`letra:`, `\` final salvo raiz) con flags (match=7, excludes=0 solo trim+fold); `normalize_qa` (bytes, nombres); matchers de bytes por caracter decodificado (`?` sigue = 1 byte, legado); `skc_qpre` (primer byte + fskip 0/1/2).
- `main.s`: `cli_trim_query` (leaf) recorta la query CLI; `gui.s`: setup llama `skc_qpre` (byte normalizado + fskip) y los dos loops tienen segunda chance 0xC3 con `fskip=2` (sin tocar `match.s`: prefilter SSE intacto a full velocidad).
- Harness `skc_smart_test.c` 34/34 (tildes exact/prefix/glob/case, trim, `./`, trail, vacias->0, CJK, path trim/relativa/sin-colon/raiz, excludes con espacios, qpre). Rank+rec harnesses OK.
- CLI: golden 12, `'notepad '` 12, `'NOTEPAD'` 12; dll 52673 estable x2 (vs 52647 del 11/10 = crecimiento de disco; tiempos 2012-6230ms = varianza de maquina). GUI: `camion`->`camión.txt`, `  NOTEPAD  `->12, `ati`->76K, `atico`->`ático.txt` primero.
- Bug: prefilter con primer byte crudo daba 0 con blancos iniciales (fskip tri-estado + 0xC3 lo arregla). Trampa: no pipear builds a `Select -First` (exe viejo). WER 14:09-14:22 (5, mismo bucket) = era rank3, fijo; 0 desde build_rank4.
- Divergencia: CLI nombres = ASCII literal (`match.s` intacto); GUI todo + CLI rutas/excludes-wildcard = full-smarts. Combinantes (NFD) no plegados: limitacion.

## Visual: seleccion real + estado vacio (2026-10-12, solo src/gui.s)

- `gcd_item` verifica con `LVM_GETITEMSTATE` en vivo (nuevo `.equ`): el `uItemState` del paint llega stale-SELECTED en lluvias de `SetItemCount` (gdb: `ST=0x201` x65 con selected=0; pixel #3A78DC exacto; disassembly correcto). Sin costo (`filtro=1ms`).
- Overlay owner-draw `IDC_EMPTY` ("Sin resultados" gris centrado): show/hide en `refresh_panel` (el per-keystroke real; final/prog no alcanzan) + final/prog/escape; layout en ambas ramas.
- Bugs: frame `update_empty` desalineado = BEX64 (sub64); overlay tapado por la lista = `SetWindowPos TOP` en creacion+show; STATIC con texto que jamas pinta (todo verificado) = owner-draw.
- Verificacion: navy + 1 sola fila azul con flecha, overlay on/off por screenshot, `notepad` 12, WER limpio. Docs README + memoria.