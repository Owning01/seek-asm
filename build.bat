@echo off
cd /d %~dp0
cd src
G:\Dev\w64devkit\bin\windres.exe resource.rc -O coff -o resource.res
G:\Dev\w64devkit\bin\windres.exe resource-cli.rc -O coff -o resource-cli.res
cd /d %~dp0
REM seekcore: staticlib Rust no_std (matching de rutas). windows-gnu = MinGW-compatible.
cargo build --release --manifest-path rs\seekcore\Cargo.toml --target x86_64-pc-windows-gnu
if errorlevel 1 exit /b 1
set CORE=rs\seekcore\target\x86_64-pc-windows-gnu\release\libseekcore.a
G:\Dev\w64devkit\bin\gcc.exe -O2 -s -o seek.exe src\arena.s src\match.s src\scan.s src\mft.s src\main.s src\resource.res %CORE% -lkernel32
G:\Dev\w64devkit\bin\gcc.exe -O2 -s -mwindows -o seek-gui.exe src\gui.s src\arena.s src\match.s src\scan.s src\mft.s src\resource.res %CORE% -lcomctl32 -lshell32 -lole32 -luuid -luser32 -lgdi32 -lkernel32 -ladvapi32 -luxtheme
