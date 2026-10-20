#![no_std]
//! seekcore: matching de rutas para seek-asm.
//!
//! El ensamblador linkea libseekcore.a y llama estas funciones `extern "C"`.
//! Sin std ni runtime: el binario final no necesita libs extra. Todo es UTF-16LE
//! (WCHAR) con comparacion ASCII case-insensitive, igual que match.s.
//!
//! Semantica (igual que el asm):
//! - contains: needle dentro del texto (subcadena).
//! - glob: full-match con `*` (cualquier secuencia, tambien `\`) y `?` (un WCHAR).

use core::panic::PanicInfo;

#[panic_handler]
fn panic(_info: &PanicInfo) -> ! {
    // No puede pasar: cero indexing fuera de rango (todo con checks).
    loop {}
}

#[inline(always)]
fn fold(c: u16) -> u16 {
    if c >= b'A' as u16 && c <= b'Z' as u16 {
        return c + 32;
    }
    // Latin-1 acentuado -> base minuscula (busqueda "inteligente":
    // "camion" encuentra "camión", "NINO" encuentra "niño").
    match c {
        0xC0..=0xC5 => b'a' as u16, // À-Å
        0xC7 => b'c' as u16,         // Ç
        0xC8..=0xCB => b'e' as u16, // È-Ë
        0xCC..=0xCF => b'i' as u16, // Ì-Ï
        0xD1 => b'n' as u16,         // Ñ
        0xD2..=0xD5 | 0xD8 => b'o' as u16, // Ò-Õ, Ø
        0xD9..=0xDC => b'u' as u16, // Ù-Ü
        0xDD => b'y' as u16,         // Ý
        0xE0..=0xE5 => b'a' as u16, // à-å
        0xE7 => b'c' as u16,         // ç
        0xE8..=0xEB => b'e' as u16, // è-ë
        0xEC..=0xEF => b'i' as u16, // ì-ï
        0xF1 => b'n' as u16,         // ñ
        0xF2..=0xF5 | 0xF8 => b'o' as u16, // ò-õ, ø
        0xF9..=0xFC => b'u' as u16, // ù-ü
        0xFD | 0xFF => b'y' as u16, // ýÿ
        _ => c, // Æ, Ð, Þ, ß y resto: exacto
    }
}

// Flags de normalize_q.
const NQ_REL: u32 = 1; // quitar ./ .\ ../ ..\ iniciales
const NQ_TRAIL: u32 = 2; // quitar '\' finales (salvo raiz)
const NQ_COLON: u32 = 4; // letra+'\' inicial -> letra+':'

// Normaliza la query a `qb` (fold + `/`->`\`, trim de blancos, rutas
// relativas, colon de unidad). Devuelve el largo efectivo (0 = vacia).
fn normalize_q(qs: &[u16], qb: &mut [u16; QMAX], flags: u32) -> usize {
    let mut n = 0usize;
    for &c in qs.iter() {
        if n >= QMAX {
            break;
        }
        qb[n] = if c == b'/' as u16 { b'\\' as u16 } else { fold(c) };
        n += 1;
    }
    // trim de blancos (0x20, 0x09) al final y al inicio
    while n > 0 && (qb[n - 1] == 0x20 || qb[n - 1] == 0x09) {
        n -= 1;
    }
    let mut s = 0usize;
    while s < n && (qb[s] == 0x20 || qb[s] == 0x09) {
        s += 1;
    }
    // rutas relativas: quitar ./ .\ ../ ..\ iniciales (repetidos)
    if flags & NQ_REL != 0 {
        loop {
            if s + 1 < n && qb[s] == b'.' as u16 && qb[s + 1] == b'\\' as u16 {
                s += 2;
                continue;
            }
            if s + 2 < n
                && qb[s] == b'.' as u16
                && qb[s + 1] == b'.' as u16
                && qb[s + 2] == b'\\' as u16
            {
                s += 3;
                continue;
            }
            break;
        }
        // blancos que quedaron tras el strip ("./  x")
        while s < n && (qb[s] == 0x20 || qb[s] == 0x09) {
            s += 1;
        }
    }
    // letra sin dos-puntos: "g\..." -> "g:\..." (antes del trim final)
    if flags & NQ_COLON != 0 && n - s >= 2 && n < QMAX {
        let c0 = qb[s];
        if c0 >= b'a' as u16 && c0 <= b'z' as u16 && qb[s + 1] == b'\\' as u16 {
            let mut i = n;
            while i > s + 1 {
                qb[i] = qb[i - 1];
                i -= 1;
            }
            qb[s + 1] = b':' as u16;
            n += 1;
        }
    }
    // quitar '\' finales salvo raiz ("\" o "X:\")
    if flags & NQ_TRAIL != 0 {
        while n - s > 1 && qb[n - 1] == b'\\' as u16 {
            if n - s == 3 && qb[s + 1] == b':' as u16 {
                break;
            }
            n -= 1;
        }
    }
    // compactar [s..n) al inicio
    let m = n - s;
    let mut i = 0usize;
    while i < m {
        qb[i] = qb[s + i];
        i += 1;
    }
    m
}

/// Subcadena ASCII case-insensitive. `needle` ya viene plegado desde el asm,
/// pero se pliega de nuevo (idempotente) por seguridad.
fn contains_ci(hay: &[u16], needle: &[u16]) -> bool {
    let n = needle.len();
    if n == 0 || hay.len() < n {
        return false;
    }
    'outer: for i in 0..=hay.len() - n {
        for j in 0..n {
            if fold(hay[i + j]) != fold(needle[j]) {
                continue 'outer;
            }
        }
        return true;
    }
    false
}

/// Full-match glob con backtracking de dos punteros (iterativo, sin recursion).
/// `*` consume cualquier secuencia incluidos separadores `\`.
fn glob_ci(text: &[u16], pat: &[u16]) -> bool {
    let (mut t, mut p) = (0usize, 0usize);
    let mut star: Option<usize> = None; // posicion en pat del ultimo '*'
    let mut mark = 0usize; // posicion en text para reiniciar tras '*'
    while t < text.len() {
        if p < pat.len() && pat[p] == b'*' as u16 {
            star = Some(p);
            mark = t;
            p += 1;
        } else if p < pat.len() && (pat[p] == b'?' as u16 || fold(pat[p]) == fold(text[t])) {
            t += 1;
            p += 1;
        } else if let Some(sp) = star {
            p = sp + 1;
            mark += 1;
            t = mark;
        } else {
            return false;
        }
    }
    while p < pat.len() && pat[p] == b'*' as u16 {
        p += 1;
    }
    p == pat.len()
}

unsafe fn sl16<'a>(p: *const u16, n: u64) -> &'a [u16] {
    if p.is_null() || n == 0 {
        &[]
    } else {
        core::slice::from_raw_parts(p, n as usize)
    }
}

const QMAX: usize = 1024;

/// Match de texto pleno: si `is_glob` full-match glob, si no subcadena.
/// `q` se normaliza (minusculas+acentos, `/` -> `\`, trim, `./`, colon).
// Match con la query YA normalizada (needle plegado). `needle` es el mismo
// para todos los records de un filtrado: no se normaliza por record.
unsafe fn match_text_n(text: &[u16], needle: &[u16], is_glob: i32) -> i32 {
    if needle.is_empty() {
        return 0;
    }
    let ok = if is_glob != 0 {
        // glob de ruta: matchea cualquier subrumbo (como Everything):
        // probar el patron contra todos los sufijos del path.
        let mut i = 0usize;
        let mut hit = false;
        while i <= text.len() {
            if glob_ci(&text[i..], needle) {
                hit = true;
                break;
            }
            i += 1;
        }
        hit
    } else {
        contains_ci(text, needle)
    };
    ok as i32
}

unsafe fn match_text(text: &[u16], q: *const u16, qlen: u64, is_glob: i32) -> i32 {
    if qlen == 0 || qlen > QMAX as u64 {
        return 0;
    }
    let qs = sl16(q, qlen);
    let mut qb = [0u16; QMAX];
    let n = normalize_q(qs, &mut qb, NQ_REL | NQ_TRAIL | NQ_COLON);
    if n == 0 {
        return 0;
    }
    match_text_n(text, &qb[..n], is_glob)
}

/// `skc_query_is_pathq(q, qlen) -> 1/0`: la query contiene `\` o `/`
/// (es una query de ruta, no de nombre).
#[no_mangle]
pub unsafe extern "C" fn skc_query_is_pathq(q: *const u16, qlen: u64) -> i32 {
    for &c in sl16(q, qlen) {
        if c == b'\\' as u16 || c == '/' as u16 {
            return 1;
        }
    }
    0
}

/// `skc_match_path(path, plen, q, qlen, is_glob) -> 1/0`.
/// `path` WCHAR (separadores `\`), `q` WCHAR (viene en lowercase del asm).
#[no_mangle]
pub unsafe extern "C" fn skc_match_path(
    path: *const u16,
    plen: u64,
    q: *const u16,
    qlen: u64,
    is_glob: i32,
) -> i32 {
    if plen > 65535 {
        return 0;
    }
    match_text(sl16(path, plen), q, qlen, is_glob)
}

/// `skc_excl_glob(path, plen, pat, patlen) -> 1/0`: full-match glob de
/// exclusion (4 args: usable desde frames sin espacio para arg5).
#[no_mangle]
pub unsafe extern "C" fn skc_excl_glob(
    path: *const u16,
    plen: u64,
    pat: *const u16,
    patlen: u64,
) -> i32 {
    let (p, pt) = (sl16(path, plen), sl16(pat, patlen));
    if plen > 65535 || pt.is_empty() || pt.len() > QMAX {
        return 0;
    }
    // trim + fold (sin tocar separadores: el patron manda literal)
    let mut pb = [0u16; QMAX];
    let n = normalize_q(pt, &mut pb, 0);
    if n == 0 {
        return 0;
    }
    glob_ci(p, &pb[..n]) as i32
}

/// Record de indice: `[0..8]` ptr nombre (arena; len WORD en `ptr-2`),
/// `[8..12]` parent (bit31=dir; `0xFFFFFFFF` = raiz, nombre incluido).
///
/// `skc_match_rec(rec, idx, q, qlen, is_glob, buf, buflen) -> 1/0`:
/// arma la ruta completa del record `idx` en `buf` (WCHAR, sin NUL) y matchea.
#[no_mangle]
pub unsafe extern "C" fn skc_match_rec(
    rec: *const u8,
    idx: u64,
    q: *const u16,
    qlen: u64,
    is_glob: i32,
    buf: *mut u16,
    buflen: u64,
) -> i32 {
    if rec.is_null() || buf.is_null() || buflen < 8 {
        return 0;
    }
    const DEPTH: usize = 128;
    let mut chain = [(0u64, 0u32); DEPTH]; // (ptr nombre, len) del mas profundo a la raiz
    let mut d = 0usize;
    let mut cur = idx;
    let mut hops = 0u32;
    loop {
        if d >= DEPTH || hops > 4096 {
            return 0; // cadena corrupta o demasiado profunda
        }
        let r = rec.add((cur * 12) as usize);
        let nptr = *(r as *const u64);
        if nptr < 2 {
            return 0;
        }
        let nlen = *((nptr - 2) as *const u16) as u32;
        chain[d] = (nptr, nlen);
        d += 1;
        let par = *(r.add(8) as *const u32);
        if par == 0xFFFF_FFFF {
            break;
        }
        cur = (par & 0x7FFF_FFFF) as u64;
        hops += 1;
    }
    let total: usize = chain[..d].iter().map(|c| c.1 as usize).sum::<usize>() + (d - 1);
    if total as u64 > buflen {
        return 0;
    }
    let out = core::slice::from_raw_parts_mut(buf, total);
    let mut o = 0usize;
    for k in (0..d).rev() {
        let (np, nl) = chain[k];
        let name = core::slice::from_raw_parts(np as *const u8, nl as usize);
        // separador: omitir si el output ya termina en '\' (el segmento padre,
        // ej. raiz "C:\", ya provee el separador) — igual que build_path [rdi-1].
        if k != d - 1 && !(o > 0 && out[o - 1] == b'\\' as u16) {
            out[o] = b'\\' as u16;
            o += 1;
        }
        o += utf8_to_u16(name, &mut out[o..]);
    }
    match_text(&out[..o], q, qlen, is_glob)
}

/// Convierte un nombre del indice (UTF-8, prefijo WORD de bytes) a UTF-16 en
/// `dst`. Bytes invalidos -> '?'. Devuelve u16 escritos (<= bytes de entrada).
fn utf8_to_u16(src: &[u8], dst: &mut [u16]) -> usize {
    let mut i = 0usize;
    let mut o = 0usize;
    while i < src.len() && o < dst.len() {
        let b = src[i];
        if b < 0x80 {
            dst[o] = b as u16;
            i += 1;
            o += 1;
        } else if b < 0xC2 || i + 1 >= src.len() {
            dst[o] = b'?' as u16;
            i += 1;
            o += 1;
        } else if b < 0xE0 {
            let c = ((b as u32 & 0x1F) << 6) | (src[i + 1] as u32 & 0x3F);
            dst[o] = c as u16;
            i += 2;
            o += 1;
        } else if b >= 0xF0 && b < 0xF5 && i + 3 < src.len() {
            let c = ((b as u32 & 0x07) << 18)
                | ((src[i + 1] as u32 & 0x3F) << 12)
                | ((src[i + 2] as u32 & 0x3F) << 6)
                | (src[i + 3] as u32 & 0x3F);
            let c = c - 0x10000;
            dst[o] = 0xD800 + (c >> 10) as u16;
            if o + 1 < dst.len() {
                dst[o + 1] = 0xDC00 + (c & 0x3FF) as u16;
                o += 1;
            }
            i += 4;
            o += 1;
        } else if b < 0xF0 && i + 2 < src.len() {
            let c = ((b as u32 & 0x0F) << 12)
                | ((src[i + 1] as u32 & 0x3F) << 6)
                | (src[i + 2] as u32 & 0x3F);
            dst[o] = c as u16;
            i += 3;
            o += 1;
        } else {
            dst[o] = b'?' as u16;
            i += 1;
            o += 1;
        }
    }
    o
}

// ---------- ranking por relevancia (GUI) ----------

// Helpers sobre BYTES UTF-8 con fold de acentos (Latin-1).
// Decodifican por caracter: "camion" matchea "camión".
#[inline(always)]
fn fold_cp(cp: u32) -> u32 {
    if cp < 0x100 {
        fold(cp as u16) as u32
    } else {
        cp
    }
}

// Decodifica un caracter UTF-8 en `pos` (avanza). Devuelve
// (codepoint plegado, ancho en bytes). Invalido -> (U+FFFD, 1).
fn dnext(s: &[u8], pos: &mut usize) -> Option<(u32, usize)> {
    let b = *s.get(*pos)?;
    if b < 0x80 {
        *pos += 1;
        return Some((fold(b as u16) as u32, 1));
    }
    if b >= 0xC2 && b < 0xE0 {
        if let Some(&c2) = s.get(*pos + 1) {
            if c2 & 0xC0 == 0x80 {
                let cp = (((b & 0x1F) as u32) << 6) | ((c2 & 0x3F) as u32);
                *pos += 2;
                return Some((fold_cp(cp), 2));
            }
        }
        *pos += 1;
        return Some((0xFFFD, 1));
    }
    if b >= 0xE0 && b < 0xF0 {
        if *pos + 2 < s.len() {
            let (c2, c3) = (s[*pos + 1], s[*pos + 2]);
            if c2 & 0xC0 == 0x80 && c3 & 0xC0 == 0x80 {
                let cp = (((b & 0x0F) as u32) << 12)
                    | (((c2 & 0x3F) as u32) << 6)
                    | ((c3 & 0x3F) as u32);
                *pos += 3;
                return Some((fold_cp(cp), 3));
            }
        }
        *pos += 1;
        return Some((0xFFFD, 1));
    }
    if b >= 0xF0 && b < 0xF5 {
        if *pos + 3 < s.len() {
            let (c2, c3, c4) = (s[*pos + 1], s[*pos + 2], s[*pos + 3]);
            if c2 & 0xC0 == 0x80 && c3 & 0xC0 == 0x80 && c4 & 0xC0 == 0x80 {
                let cp = (((b & 0x07) as u32) << 18)
                    | (((c2 & 0x3F) as u32) << 12)
                    | (((c3 & 0x3F) as u32) << 6)
                    | ((c4 & 0x3F) as u32);
                *pos += 4;
                return Some((cp, 4));
            }
        }
        *pos += 1;
        return Some((0xFFFD, 1));
    }
    *pos += 1;
    Some((0xFFFD, 1))
}

fn eq_ci_a(a: &[u8], b: &[u8]) -> bool {
    let (mut i, mut j) = (0usize, 0usize);
    loop {
        match (dnext(a, &mut i), dnext(b, &mut j)) {
            (None, None) => return true,
            (Some((x, _)), Some((y, _))) if x == y => {}
            _ => return false,
        }
    }
}

// Matchea `needle` completo desde `h` (posicion byte). true = consumido.
fn match_at(hay: &[u8], needle: &[u8], mut h: usize) -> bool {
    let mut q = 0usize;
    loop {
        if q >= needle.len() {
            return true;
        }
        if h >= hay.len() {
            return false;
        }
        let (x, _) = match dnext(hay, &mut h) {
            Some(v) => v,
            None => return false,
        };
        let (y, _) = match dnext(needle, &mut q) {
            Some(v) => v,
            None => return true,
        };
        if x != y {
            return false;
        }
    }
}

fn starts_ci_a(hay: &[u8], needle: &[u8]) -> bool {
    match_at(hay, needle, 0)
}

fn contains_ci_a(hay: &[u8], needle: &[u8]) -> bool {
    if needle.is_empty() {
        return false;
    }
    let mut i = 0usize;
    while i < hay.len() {
        if match_at(hay, needle, i) {
            return true;
        }
        i += 1;
    }
    false
}

fn glob_ci_a(text: &[u8], pat: &[u8]) -> bool {
    let (mut t, mut p) = (0usize, 0usize);
    let mut star: Option<usize> = None;
    let mut mark = 0usize;
    while t < text.len() {
        if p < pat.len() && pat[p] == b'*' {
            star = Some(p);
            mark = t;
            p += 1;
        } else if p < pat.len() && pat[p] == b'?' {
            // '?' = exactamente un byte (legado, igual que match.s)
            t += 1;
            p += 1;
        } else if p < pat.len() {
            // literal: compara decodificado (plegado); avanza por anchos
            let (mut tt, mut pp) = (t, p);
            match (dnext(text, &mut tt), dnext(pat, &mut pp)) {
                (Some((x, _)), Some((y, _))) if x == y => {
                    t = tt;
                    p = pp;
                }
                _ if star.is_some() => {
                    let sp = star.unwrap();
                    p = sp + 1;
                    mark += 1;
                    t = mark;
                }
                _ => return false,
            }
        } else if let Some(sp) = star {
            p = sp + 1;
            mark += 1;
            t = mark;
        } else {
            return false;
        }
    }
    while p < pat.len() && pat[p] == b'*' {
        p += 1;
    }
    p == pat.len()
}

// Trim de blancos + quitar ./ .\ ../ ..\ iniciales. Devuelve el offset.
fn trim_rel(q: &[u8]) -> usize {
    let n = q.len();
    let mut s = 0usize;
    while s < n && (q[s] == 0x20 || q[s] == 0x09) {
        s += 1;
    }
    loop {
        if s + 1 < n && q[s] == b'.' && (q[s + 1] == b'\\' || q[s + 1] == b'/') {
            s += 2;
            continue;
        }
        if s + 2 < n
            && q[s] == b'.'
            && q[s + 1] == b'.'
            && (q[s + 2] == b'\\' || q[s + 2] == b'/')
        {
            s += 3;
            continue;
        }
        break;
    }
    s
}

// `skc_qpre(q, qlen) -> u64`: primer byte normalizado en bits[0:8] +
// fskip tri-estado en bits[8:16] (0=filtro, 1=sin filtro, 2=filtro con
// segunda chance 0xC3). 2 = inicial plegable a acento (a,c,e,i,n,o,u,y):
// el prefilter ASCII perderia "atico" empezado con query "at...".
#[no_mangle]
pub unsafe extern "C" fn skc_qpre(q: *const u8, qlen: u64) -> u64 {
    if q.is_null() || qlen == 0 || qlen > QMAX as u64 {
        return 1u64 << 8;
    }
    let qs = core::slice::from_raw_parts(q, qlen as usize);
    let s = trim_rel(qs);
    if s >= qs.len() {
        return 1u64 << 8;
    }
    let b = qs[s];
    if b >= 0x80 {
        return (b as u64) | (1u64 << 8);
    }
    let st = match fold(b as u16) as u8 {
        b'a' | b'c' | b'e' | b'i' | b'n' | b'o' | b'u' | b'y' => 2u64,
        _ => 0u64,
    };
    (b as u64) | (st << 8)
}

// Normaliza query UTF-8 (nombres): trim de blancos, quitar ./ .\ ../ ..\
// iniciales y '\' finales. Devuelve el largo efectivo en `out`.
fn normalize_qa(q: &[u8], out: &mut [u8; QMAX]) -> usize {
    let mut n = core::cmp::min(q.len(), QMAX);
    for i in 0..n {
        out[i] = q[i];
    }
    while n > 0 && (out[n - 1] == 0x20 || out[n - 1] == 0x09) {
        n -= 1;
    }
    // rel-strip sobre la ventana ya trimada (misma regla que skc_qpre)
    let mut s = trim_rel(&out[..n]);
    // blancos que quedaron tras el rel-strip ("./  x")
    while s < n && (out[s] == 0x20 || out[s] == 0x09) {
        s += 1;
    }
    while n > s && out[n - 1] == b'\\' {
        n -= 1;
    }
    let m = n - s;
    let mut i = 0usize;
    while i < m {
        out[i] = out[s + i];
        i += 1;
    }
    m
}

// Boost por modo de prioridad: 1 = archivos, 2 = carpetas.
#[inline(always)]
fn mode_boost(mode: i32, is_dir: bool) -> u32 {
    if (mode == 1 && !is_dir) || (mode == 2 && is_dir) {
        2000
    } else {
        0
    }
}

// `skc_qnorm8(q, qlen, out, outcap) -> u64`: normaliza la query UTF-8 (fold,
// '/'->'\', trim, rutas relativas, '\' final) y la deja en `out`. Devuelve el
// largo efectivo (0 = vacia). Se llama UNA vez por filtrado: normalizar por
// record costaba un memset de 1KB por record (3 GB por filtrado).
#[no_mangle]
pub unsafe extern "C" fn skc_qnorm8(q: *const u8, qlen: u64, out: *mut u8, outcap: u64) -> u64 {
    if q.is_null() || out.is_null() || outcap == 0 || qlen == 0 || qlen > QMAX as u64 {
        return 0;
    }
    let qs = core::slice::from_raw_parts(q, qlen as usize);
    let mut qb = [0u8; QMAX];
    let n = normalize_qa(qs, &mut qb);
    if n == 0 || n as u64 > outcap {
        return 0;
    }
    core::ptr::copy_nonoverlapping(qb.as_ptr(), out, n);
    n as u64
}

// `skc_qnorm(q, qlen, out, outcap) -> u64`: idem para la query UTF-16 (paths).
#[no_mangle]
pub unsafe extern "C" fn skc_qnorm(q: *const u16, qlen: u64, out: *mut u16, outcap: u64) -> u64 {
    if q.is_null() || out.is_null() || outcap == 0 || qlen == 0 || qlen > QMAX as u64 {
        return 0;
    }
    let qs = sl16(q, qlen);
    let mut qb = [0u16; QMAX];
    let n = normalize_q(qs, &mut qb, NQ_REL | NQ_TRAIL | NQ_COLON);
    if n == 0 || n as u64 > outcap {
        return 0;
    }
    core::ptr::copy_nonoverlapping(qb.as_ptr(), out, n * 2);
    n as u64
}

// `skc_score_name(nptr, nlen, q, qlen, is_glob, is_dir, mode) -> u32`:
// 0 = no hay match; si no, tier*1000 + boost(2000) + largo(0..500).
// Tiers: exacta 6, prefijo 5, subcadena/glob 4.
// `q`/`qlen` = la query YA normalizada (ver skc_qnorm8).
#[no_mangle]
pub unsafe extern "C" fn skc_score_name(
    nptr: *const u8,
    nlen: u64,
    q: *const u8,
    qlen: u64,
    is_glob: i32,
    is_dir: i32,
    mode: i32,
) -> u32 {
    if nptr.is_null() || q.is_null() || nlen == 0 || nlen > 4096 {
        return 0;
    }
    if qlen == 0 || qlen > QMAX as u64 {
        return 0;
    }
    let n = core::slice::from_raw_parts(nptr, nlen as usize);
    // los largos en bytes ya no mandan (los acentos cambian el ancho); los
    // tiers comparan por caracter.
    let qq = core::slice::from_raw_parts(q, qlen as usize);
    let dir = is_dir != 0;
    let tier: u32 = if is_glob != 0 {
        if !glob_ci_a(n, qq) {
            return 0;
        }
        4
    } else if eq_ci_a(n, qq) {
        6
    } else if starts_ci_a(n, qq) {
        5
    } else if contains_ci_a(n, qq) {
        4
    } else {
        return 0;
    };
    let lb = 500u32.saturating_sub(core::cmp::min(nlen as u32, 500));
    tier * 1000 + mode_boost(mode, dir) + lb
}

// `skc_score_rec(rec, idx, q, qlen, is_glob, mode, buf, buflen) -> u32`:
// 0 = no hay match; si no, tier*1000 + boost(2000) + largo(0..500).
// Match sobre la RUTA completa del record (nombre + padres), en UTF-16.
//
// Cache por hilo dentro de `buf` (el worker paralelo usa uno por hilo):
//   [0..2)    u32    profundidad de la pila de ancestros
//   [4..260)  u64[64] indice de cada ancestro (raiz primero)
//   [260..388) u32[64] largo de la ruta de cada ancestro
//   [512..)   la ruta actual (WCHAR)
// El indice esta en orden DFS: el padre de un record casi siempre esta en la
// pila, asi que la ruta se arma con un prefijo + el nombre (O(1)) en vez de
// recorrer toda la cadena de padres y convertirla (O(profundidad)).
// IMPORTANTE: hay que resetear la profundidad (a 0) antes de cada filtrado:
// el cache es de una pasada sobre el indice.
// Firma de 64 bits por record: que caracteres (plegados) aparecen en el
// nombre. Es la condicion NECESARIA del "producto" de la query: si a la query
// le falta un bit, ese record NO puede matchear -> se descarta sin leer el
// nombre (que vive en la arena, 130MB dispersos). 64 bits: 26 letras +
// 10 digitos + los ASCII bajos + un hash de los demas.
#[inline(always)]
fn sig_bit(c: u16) -> u64 {
    let f = fold(c);
    if f >= b'a' as u16 && f <= b'z' as u16 {
        1u64 << (f - b'a' as u16)
    } else if f >= b'0' as u16 && f <= b'9' as u16 {
        1u64 << (26 + (f - b'0' as u16))
    } else if f < 64 {
        1u64 << f
    } else {
        1u64 << (40 + ((f as u64 * 7) & 23))
    }
}

// `skc_bloom_build(name8, nlen, out) -> u64`: arma la firma del nombre UTF-8
// (decodifica, pliega y prende los bits) y la deja en `out`.
#[no_mangle]
pub unsafe extern "C" fn skc_bloom_build(name8: *const u8, nlen: u64, out: *mut u64) -> u64 {
    if name8.is_null() || out.is_null() {
        return 0;
    }
    // tope defensivo: un nombre de archivo no pasa de 255 chars (~1020 bytes UTF-8)
    let n = if nlen > 4096 { 4096 } else { nlen as usize };
    let s = core::slice::from_raw_parts(name8, n);
    let mut m = 0u64;
    let mut i = 0usize;
    while i < s.len() {
        match dnext(s, &mut i) {
            Some((c, _)) => {
                m |= sig_bit(c as u16);
            }
            None => break,
        }
    }
    *out = m;
    m
}

// `skc_bloom_mask(q, qlen) -> u64`: la firma de la query (WCHAR, ya plegada).
// 0 = query sin condiciones (no se puede estrechar). Los comodines '*' y '?'
// no son condiciones (no aparecen en los nombres).
#[no_mangle]
pub unsafe extern "C" fn skc_bloom_mask(q: *const u16, qlen: u64) -> u64 {
    if q.is_null() {
        return 0;
    }
    let s = core::slice::from_raw_parts(q, qlen as usize);
    let mut m = 0u64;
    for &c in s.iter() {
        if c == b'*' as u16 || c == b'?' as u16 {
            continue;
        }
        m |= sig_bit(c);
    }
    m
}

const SC_IDX: usize = 4; // WCHARs
const SC_LEN: usize = 4 + 64 * 4; // WCHARs (260)
const SC_PATH: usize = 512; // WCHARs
const SC_DEPTH: usize = 64;

// El prefijo de la ruta (los primeros `olen` WCHAR) tiene que coincidir con
// la query. Se usa en modo anclado: la query arranca con la unidad, asi que
// el match es un prefijo y se corta al divergir. Plega ambos lados (la query
// puede venir plegada o no).
#[inline(always)]
unsafe fn prefix_eq(path: *const u16, olen: usize, q: *const u16, qlen: u64) -> bool {
    let s = path_unit_offset(path, olen);
    let n = qlen as usize;
    if olen - s < n {
        // la ruta es mas corta que la query: no puede contenerla
        return false;
    }
    let mut i = 0usize;
    while i < n {
        if fold(*path.add(s + i)) != fold(*q.add(i)) {
            return false;
        }
        i += 1;
    }
    true
}

// Las rutas del indice vienen con el prefijo "\\?\" (4 chars: dos barras +
// '?' + barra, de las rutas largas de Windows): el match arranca despues de
// el, no en el byte 0.
#[inline(always)]
unsafe fn path_unit_offset(path: *const u16, olen: usize) -> usize {
    if olen >= 4
        && *path == b'\\' as u16
        && *path.add(1) == b'\\' as u16
        && *path.add(2) == b'?' as u16
        && *path.add(3) == b'\\' as u16
    {
        4
    } else {
        0
    }
}

// Glob anclado: el patron arranca con la unidad, asi que el match solo puede
// ser contra el sufijo que empieza en la unidad (no todos los sufijos).
#[inline(always)]
unsafe fn glob_anchored(path: *const u16, olen: usize, q: *const u16, qlen: u64) -> bool {
    let s = path_unit_offset(path, olen);
    if olen - s < qlen as usize {
        return false;
    }
    let text = core::slice::from_raw_parts(path.add(s), olen - s);
    let needle = core::slice::from_raw_parts(q, qlen as usize);
    glob_ci(text, needle)
}

#[no_mangle]
pub unsafe extern "C" fn skc_score_rec(
    rec: *const u8,
    idx: u64,
    q: *const u16,
    qlen: u64,
    is_glob: i32,
    mode: i32,
    buf: *mut u16,
    buflen: u64,
) -> u32 {
    // is_glob: 0 = normal, 1 = glob, 2 = ANCLADO (la query arranca con la
    // unidad, "C:\...": el match es un prefijo de la ruta -> se compara al
    // vuelo y se corta en cuanto diverge, sin terminar de armar la ruta),
    // 3 = glob anclado (idem, pero con comodines).
    let anchored_glob = is_glob == 3;
    let anchored = is_glob == 2 || anchored_glob;
    let is_glob = if is_glob == 1 || anchored_glob { 1 } else { 0 };
    if rec.is_null() || buf.is_null() || buflen < SC_PATH as u64 + 16 {
        return 0;
    }
    if q.is_null() || qlen == 0 || qlen > QMAX as u64 {
        return 0;
    }
    let cap = buflen as usize - SC_PATH;
    let depthp = buf as *mut u32;
    let idxp = buf.add(SC_IDX) as *mut u64;
    let lenp = buf.add(SC_LEN) as *mut u32;
    let path = buf.add(SC_PATH);

    let r = rec.add((idx * 12) as usize);
    let nptr = *(r as *const u64);
    if nptr < 2 {
        return 0;
    }
    let nlen = *((nptr - 2) as *const u16) as usize;
    let par = *(r.add(8) as *const u32);
    let is_dir = (par & 0x8000_0000) != 0;
    let parent = (par & 0x7FFF_FFFF) as u64;

    // ¿el padre esta en la pila de ancestros? (de arriba hacia abajo)
    let mut depth = (*depthp as usize).min(SC_DEPTH);
    let mut p = depth;
    let mut hit = false;
    while p > 0 {
        p -= 1;
        if *idxp.add(p) == parent {
            hit = true;
            break;
        }
    }
    let o: usize;
    if hit {
        // ruta = prefijo del padre + '\' + nombre
        let mut o2 = *lenp.add(p) as usize;
        if o2 > 0 && *path.add(o2 - 1) != b'\\' as u16 {
            if o2 >= cap {
                return 0;
            }
            *path.add(o2) = b'\\' as u16;
            o2 += 1;
        }
        if o2 + nlen > cap {
            return 0;
        }
        let name = core::slice::from_raw_parts(nptr as *const u8, nlen);
        o2 += utf8_to_u16(name, core::slice::from_raw_parts_mut(path.add(o2), nlen));
        o = o2;
        // OJO: el cache se actualiza SIEMPRE (aun sin match): si se salteara,
        // la pila de ancestros quedaria vieja y las rutas siguientes se
        // armarian con prefijos equivocados. Y si la pila esta llena, no se
        // empuja (el proximo record reconstruye la ruta entera).
        if p + 1 < SC_DEPTH {
            *idxp.add(p + 1) = idx;
            *lenp.add(p + 1) = o as u32;
            *depthp = (p + 2) as u32;
        } else {
            *depthp = SC_DEPTH as u32;
        }
        if anchored_glob {
            if !glob_anchored(path, o, q, qlen) {
                return 0;
            }
        } else if anchored && !prefix_eq(path, o, q, qlen) {
            return 0;
        }
    } else {
        // cache miss: reconstruir la ruta desde la raiz
        const DEPTH: usize = 128;
        let mut chain = [(0u64, 0u64, 0u32); DEPTH];
        let mut d = 0usize;
        let mut cur = idx;
        let mut hops = 0u32;
        loop {
            if d >= DEPTH || hops > 4096 {
                return 0;
            }
            let rr = rec.add((cur * 12) as usize);
            let np = *(rr as *const u64);
            if np < 2 {
                return 0;
            }
            let nl = *((np - 2) as *const u16) as u32;
            chain[d] = (cur, np, nl);
            d += 1;
            let p2 = *(rr.add(8) as *const u32);
            if p2 == 0xFFFF_FFFF {
                break;
            }
            cur = (p2 & 0x7FFF_FFFF) as u64;
            hops += 1;
        }
        let total: usize = chain[..d].iter().map(|c| c.2 as usize).sum::<usize>() + (d - 1);
        if total > cap {
            return 0;
        }
        let mut o2 = 0usize;
        let mut lvl = 0usize;
        // la pila de ancestros tiene SC_DEPTH entradas: si la cadena es mas
        // profunda NO se cachea (el proximo record reconstruye tambien).
        let cacheable = d <= SC_DEPTH;
        for j in (0..d).rev() {
            let (ci, np, nl) = chain[j];
            if j != d - 1 && !(o2 > 0 && *path.add(o2 - 1) == b'\\' as u16) {
                if o2 >= cap {
                    return 0;
                }
                *path.add(o2) = b'\\' as u16;
                o2 += 1;
            }
            let name = core::slice::from_raw_parts(np as *const u8, nl as usize);
            o2 += utf8_to_u16(name, core::slice::from_raw_parts_mut(path.add(o2), nl as usize));
            if cacheable {
                // la pila de ancestros tiene SC_DEPTH entradas: si la cadena
                // es mas profunda NO se cachea (el siguiente record
                // reconstruye tambien la ruta).
                if lvl < SC_DEPTH {
                    *idxp.add(lvl) = ci;
                    *lenp.add(lvl) = o2 as u32;
                }
            }
            lvl += 1;
        }
        *depthp = if cacheable { lvl as u32 } else { 0 };
        o = o2;
    }

    if anchored_glob {
        if !glob_anchored(path, o, q, qlen) {
            return 0;
        }
    } else if anchored {
        // la query es un prefijo de la ruta: basta con comparar
        if !prefix_eq(path, o, q, qlen) {
            return 0;
        }
    } else if match_text_n(
        core::slice::from_raw_parts(path, o),
        core::slice::from_raw_parts(q, qlen as usize),
        is_glob,
    ) == 0 {
        return 0;
    }
    let lb = 500u32.saturating_sub(core::cmp::min(o as u32, 500));
    4000 + mode_boost(mode, is_dir) + lb
}

// `skc_rank_sort(pairs, n)`: ordena u64 empaquetados
// `(score<<32 | (0xFFFFFFFF-idx))` de mayor a menor in-place
// (= score desc, idx asc). Sin alloc.
#[no_mangle]
pub unsafe extern "C" fn skc_rank_sort(pairs: *mut u64, n: u64) {
    if pairs.is_null() || n < 2 {
        return;
    }
    let s = core::slice::from_raw_parts_mut(pairs, n as usize);
    s.sort_unstable_by(|a, b| b.cmp(a));
}

// ---------- tick incremental: archivos nuevos sin reindexar ----------

#[link(name = "kernel32")]
extern "system" {
    fn GetFileAttributesExW(path: *const u16, level: u32, data: *mut AttrData) -> i32;
    fn GetLastError() -> u32;
    fn GetTickCount64() -> u64;
}

#[repr(C)]
struct AttrData {
    attr: u32,
    ctime_lo: u32,
    ctime_hi: u32,
    atime_lo: u32,
    atime_hi: u32,
    mtime_lo: u32,
    mtime_hi: u32,
    size_hi: u32,
    size_lo: u32,
}

#[inline(always)]
fn attr_mtime(a: &AttrData) -> u64 {
    ((a.mtime_hi as u64) << 32) | (a.mtime_lo as u64)
}

const SENTINEL: u64 = 0xFFFF_FFFF_FFFF_FFFF; // "se sabe ido": no re-chequear

// Arma la ruta completa del record `idx` en `out` (WCHAR, sin NUL).
// None si la cadena esta corrupta o no entra.
fn build_path_rec(rec: *const u8, idx: u64, out: &mut [u16]) -> Option<usize> {
    const DEPTH: usize = 128;
    let mut chain = [(0u64, 0u32); DEPTH];
    let mut d = 0usize;
    let mut cur = idx;
    let mut hops = 0u32;
    loop {
        if d >= DEPTH || hops > 4096 {
            return None;
        }
        let r = unsafe { rec.add((cur * 12) as usize) };
        let nptr = unsafe { *(r as *const u64) };
        if nptr < 2 {
            return None;
        }
        let nlen = unsafe { *((nptr - 2) as *const u16) } as u32;
        chain[d] = (nptr, nlen);
        d += 1;
        let par = unsafe { *(r.add(8) as *const u32) };
        if par == 0xFFFF_FFFF {
            break;
        }
        cur = (par & 0x7FFF_FFFF) as u64;
        hops += 1;
    }
    let total: usize = chain[..d].iter().map(|c| c.1 as usize).sum::<usize>() + (d - 1);
    if total == 0 || total >= out.len() {
        return None;
    }
    let mut o = 0usize;
    for k in (0..d).rev() {
        let (np, nl) = chain[k];
        let name = unsafe { core::slice::from_raw_parts(np as *const u8, nl as usize) };
        if k != d - 1 && !(o > 0 && out[o - 1] == b'\\' as u16) {
            out[o] = b'\\' as u16;
            o += 1;
        }
        o += utf8_to_u16(name, &mut out[o..]);
    }
    Some(o)
}

// `skc_path_for(rec, idx, buf, buflen) -> u64`: ruta + NUL, largo sin NUL
// (0 = fallo). Para el re-scan de reparacion (buffer propio, sin cache).
#[no_mangle]
pub unsafe extern "C" fn skc_path_for(rec: *const u8, idx: u64, buf: *mut u16, buflen: u64) -> u64 {
    if rec.is_null() || buf.is_null() || buflen < 8 {
        return 0;
    }
    let out = core::slice::from_raw_parts_mut(buf, buflen as usize);
    match build_path_rec(rec, idx, out) {
        Some(o) if (o as u64) + 1 <= buflen => {
            out[o] = 0;
            o as u64
        }
        _ => 0,
    }
}

// `skc_dir_tick(rec, n, mt, out, cap, tmp, tmpcap, cursor) -> u64`:
// recorre dirs vivos, les hace stat y devuelve en `out` los recidx cambiados
// (mtime distinto, borrados o reaparecidos). `mt` = mtimes paralelos (SENTINEL =
// ido confirmado). Lazy-init: almacenado 0 + stat ok = guarda y sigue
// (raices y huecos la primera vez).
// Barrido por franjas: `cursor` es la posicion de entrada/salida (in/out). Se
// procesa un arco contiguo del circulo de records y se para al agotar el
// presupuesto de TICK_BUDGET_MS (asi el trabajo pesado se reparte y no pega
// picos de CPU). El intervalo entre franjas lo decide el ASM (REPAIR_SLICE_MS).
#[no_mangle]
pub unsafe extern "C" fn skc_dir_tick(
    rec: *const u8,
    n: u64,
    mt: *mut u64,
    out: *mut u32,
    cap: u64,
    tmp: *mut u16,
    tmpcap: u64,
    cursor: *mut u64,
) -> u64 {
    const TICK_BUDGET_MS: u64 = 500;
    if rec.is_null() || mt.is_null() || out.is_null() || tmp.is_null() {
        return 0;
    }
    if n == 0 || cap == 0 || tmpcap < 8 {
        return 0;
    }
    let mts = core::slice::from_raw_parts_mut(mt, n as usize);
    let dst = core::slice::from_raw_parts_mut(out, cap as usize);
    let tbuf = core::slice::from_raw_parts_mut(tmp, tmpcap as usize);
    let mut got = 0u64;
    let mut i = if cursor.is_null() { 0 } else { *cursor };
    if i >= n {
        i = 0;
    }
    let t0 = GetTickCount64();
    let mut processed = 0u64;
    loop {
        if i >= n {
            i = 0;
        }
        // presupuesto: se corta el arco (el cursor queda para la proxima)
        if (processed & 31) == 0 && GetTickCount64() - t0 > TICK_BUDGET_MS {
            break;
        }
        let r = rec.add((i * 12) as usize);
        let nptr = *(r as *const u64);
        if nptr >= 2 {
            let par = *(r.add(8) as *const u32);
            if par & 0x8000_0000 != 0 {
                let stored = mts[i as usize];
                let mut ad = AttrData {
                    attr: 0,
                    ctime_lo: 0,
                    ctime_hi: 0,
                    atime_lo: 0,
                    atime_hi: 0,
                    mtime_lo: 0,
                    mtime_hi: 0,
                    size_hi: 0,
                    size_lo: 0,
                };
                // build_path_rec garantiza o < tmpcap: entra el NUL
                if let Some(o) = build_path_rec(rec, i, tbuf) {
                    tbuf[o] = 0;
                    if GetFileAttributesExW(tbuf.as_ptr(), 0, &mut ad) != 0 {
                        if stored == 0 {
                            mts[i as usize] = attr_mtime(&ad); // lazy-init
                        } else if attr_mtime(&ad) != stored {
                            if (got as usize) < dst.len() {
                                dst[got as usize] = i as u32;
                            }
                            got += 1;
                        }
                    } else {
                        let e = GetLastError();
                        if e == 2 || e == 3 {
                            // borrado: reportar salvo ya confirmado
                            if stored != SENTINEL && (got as usize) < dst.len() {
                                dst[got as usize] = i as u32;
                            }
                            if stored != SENTINEL {
                                got += 1;
                            }
                        }
                        // negado/otro: se reintenta la proxima (sin churn)
                    }
                }
            }
        }
        i += 1;
        processed += 1;
        if processed >= n {
            // vuelta completa al origen
            break;
        }
    }
    if !cursor.is_null() {
        *cursor = i;
    }
    got
}

// `skc_tombstone_sub(rec, n, dir, self_) -> u64`: marca name_ptr=0 al
// subarbol (hijos siempre; el propio dir solo con self_!=0). Devuelve bajas.
#[no_mangle]
pub unsafe extern "C" fn skc_tombstone_sub(rec: *const u8, n: u64, dir: u64, self_: i32) -> u64 {
    if rec.is_null() || n == 0 {
        return 0;
    }
    let mut killed = 0u64;
    let mut i = 0u64;
    while i < n {
        let r = rec.add((i * 12) as usize);
        let nptr = *(r as *const u64);
        if nptr >= 2 {
            let mut dead = false;
            if i == dir {
                dead = self_ != 0;
            } else {
                let mut cur = (*(r.add(8) as *const u32) & 0x7FFF_FFFF) as u64;
                let mut hops = 0u32;
                while hops <= 4096 {
                    if cur == dir {
                        dead = true;
                        break;
                    }
                    if cur >= n {
                        break;
                    }
                    let pr = rec.add((cur * 12) as usize);
                    let pp = *(pr.add(8) as *const u32);
                    if pp == 0xFFFF_FFFF {
                        break;
                    }
                    cur = (pp & 0x7FFF_FFFF) as u64;
                    hops += 1;
                }
            }
            if dead {
                *(r as *mut u64) = 0;
                killed += 1;
            }
        }
        i += 1;
    }
    killed
}

// `skc_reparent(rec, n, from, to) -> u64`: los hijos directos de `from`
// pasan a `to` (conserva el bit is_dir propio). Devuelve movidos.
#[no_mangle]
pub unsafe extern "C" fn skc_reparent(rec: *const u8, n: u64, from: u64, to: u64) -> u64 {
    if rec.is_null() || n == 0 || from == to {
        return 0;
    }
    let mut moved = 0u64;
    let mut i = 0u64;
    while i < n {
        let r = rec.add((i * 12) as usize);
        if *(r as *const u64) >= 2 {
            let p = r.add(8) as *mut u32;
            let par = *p;
            if par != 0xFFFF_FFFF && (par & 0x7FFF_FFFF) as u64 == from {
                *p = (par & 0x8000_0000) | ((to & 0x7FFF_FFFF) as u32);
                moved += 1;
            }
        }
        i += 1;
    }
    moved
}

// skc_sort_items: ordena in-place el array `items` (u64 empaquetado score<<32|~idx)
// por la clave elegida por `mode`: 0=nombre (bytes UTF-8, case-fold), 1=carpeta
// (parent idx), 2=fecha (mtime u64). `ascending`: 0=desc, 1=asc.
// recbase: base de records (12B: nameptr u64 + parent u32). mtbase: base de mtimes (u64 por record).
#[no_mangle]
pub unsafe extern "C" fn skc_sort_items(
    items: *mut u64,
    count: usize,
    recbase: *const u8,
    mtbase: *const u64,
    mode: i32,
    ascending: i32,
) {
    if items.is_null() || count < 2 || recbase.is_null() {
        return;
    }
    // extraer idx desde el empaquetado ~idx
    // comparador por clave
    unsafe fn key_name(recbase: *const u8, idx: usize) -> *const u8 {
        let r = recbase.add(idx * 12);
        let nptr = *(r as *const u64);
        nptr as *const u8
    }
    unsafe fn cmp_items(
        a: u64,
        b: u64,
        recbase: *const u8,
        mtbase: *const u64,
        mode: i32,
    ) -> i32 {
        let ia = (!(a as u32)) as usize;
        let ib = (!(b as u32)) as usize;
        match mode {
            2 => {
                // fecha
                if mtbase.is_null() {
                    return 0;
                }
                let ma = *mtbase.add(ia);
                let mb = *mtbase.add(ib);
                if ma < mb {
                    -1
                } else if ma > mb {
                    1
                } else {
                    0
                }
            }
            1 => {
                // carpeta: parent idx
                let ra = recbase.add(ia * 12).add(8) as *const u32;
                let rb = recbase.add(ib * 12).add(8) as *const u32;
                let pa = *ra & 0x7FFF_FFFF;
                let pb = *rb & 0x7FFF_FFFF;
                if pa < pb {
                    -1
                } else if pa > pb {
                    1
                } else {
                    0
                }
            }
            _ => {
                // nombre: bytes UTF-8, fold ASCII
                let pa = key_name(recbase, ia);
                let pb = key_name(recbase, ib);
                if pa.is_null() || pb.is_null() {
                    return 0;
                }
                let la = if pa.is_null() {
                    0usize
                } else {
                    *(pa.sub(2) as *const u16) as usize
                };
                let lb = if pb.is_null() {
                    0usize
                } else {
                    *(pb.sub(2) as *const u16) as usize
                };
                let n = if la < lb { la } else { lb };
                let mut i = 0usize;
                while i < n {
                    let mut ca = *pa.add(i);
                    let mut cb = *pb.add(i);
                    if ca >= b'A' as u8 && ca <= b'Z' as u8 {
                        ca += 32;
                    }
                    if cb >= b'A' as u8 && cb <= b'Z' as u8 {
                        cb += 32;
                    }
                    if ca != cb {
                        return if ca < cb { -1 } else { 1 };
                    }
                    i += 1;
                }
                if la < lb {
                    -1
                } else if la > lb {
                    1
                } else {
                    0
                }
            }
        }
    }

    // quicksort iterativo
    let mut stack: [(usize, usize); 64] = [(0, 0); 64];
    stack[0] = (0, count);
    let mut sp = 1usize;
    while sp > 0 {
        sp -= 1;
        let (lo, hi) = stack[sp];
        if hi.saturating_sub(lo) < 2 {
            continue;
        }
        // median-of-three pivot
        let mid = lo + (hi - lo) / 2;
        // ordenar lo, mid, hi-1
        // simple: pivot = mid
        let pivot_val = *items.add(mid);
        // partition (Hoare)
        let mut i = lo as isize - 1;
        let mut j = hi as isize;
        loop {
            loop {
                i += 1;
                let c = cmp_items(*items.add(i as usize), pivot_val, recbase, mtbase, mode);
                let ord = if ascending != 0 { c } else { -c };
                if !(ord < 0) {
                    break;
                }
            }
            loop {
                j -= 1;
                let c = cmp_items(*items.add(j as usize), pivot_val, recbase, mtbase, mode);
                let ord = if ascending != 0 { c } else { -c };
                if !(ord > 0) {
                    break;
                }
            }
            if i >= j {
                break;
            }
            let tmp = *items.add(i as usize);
            *items.add(i as usize) = *items.add(j as usize);
            *items.add(j as usize) = tmp;
        }
        let p = j as usize;
        // push subranges
        if p > lo && sp < 64 {
            stack[sp] = (lo, p);
            sp += 1;
        }
        if p + 1 < hi && sp < 64 {
            stack[sp] = (p + 1, hi);
            sp += 1;
        }
    }
}
