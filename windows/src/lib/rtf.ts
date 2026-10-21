// Notes written in the Mac app are RTF (base64 in the backup). Turn them into simple HTML for the editor here:
// text, line breaks, bold, italic and underline. Fonts, colours and tables are dropped.

const CP1252: Record<number, string> = { 0x80: "€", 0x91: "‘", 0x92: "’", 0x93: "“", 0x94: "”", 0x95: "•", 0x96: "–", 0x97: "—", 0x85: "…" };
// RTF font charsets → text encodings (Persian/Arabic text from the Mac comes as \fcharset178 bytes)
const CHARSETS: Record<number, string> = { 0: "windows-1252", 161: "windows-1253", 162: "windows-1254", 177: "windows-1255", 178: "windows-1256",
  186: "windows-1257", 204: "windows-1251", 238: "windows-1250", 128: "shift_jis", 134: "gbk", 136: "big5", 129: "euc-kr" };
const esc = (t: string) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export function rtfToHtml(base64: string): string {
  let rtf: string;
  try { rtf = new TextDecoder("latin1").decode(Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))); } catch { return ""; }
  let out = "", i = 0, skip = 0, uc = 1;
  // font number → its charset, from the font table
  const fontCharset: Record<number, number> = {};
  for (const m of rtf.matchAll(/\\f(\d+)[^;{}]*?\\fcharset(\d+)/g)) fontCharset[+m[1]] = +m[2];
  const defCp = /\\ansicpg(\d+)/.exec(rtf)?.[1];
  let font = 0, bytes: number[] = [];
  const encoding = () => { const cs = fontCharset[font]; return cs !== undefined && cs !== 0 ? CHARSETS[cs] ?? "windows-1252" : defCp ? `windows-${defCp}` : "windows-1252"; };
  const flush = () => {
    if (!bytes.length) return;
    let t: string;
    try { t = new TextDecoder(encoding()).decode(new Uint8Array(bytes)); } catch { t = bytes.map((c) => CP1252[c] ?? String.fromCharCode(c)).join(""); }
    bytes = []; text(esc(t));
  };
  const stack: { skip: number; b: boolean; it: boolean; ul: boolean }[] = [];
  let b = false, it = false, ul = false, open = "";
  const style = () => {
    const want = (b ? "<b>" : "") + (it ? "<i>" : "") + (ul ? "<u>" : "");
    if (want === open) return;
    out += open.replace(/<(\w)>/g, "</$1>").split("</").filter(Boolean).reverse().map((t) => "</" + t).join("") + want;
    open = want;
  };
  function text(t: string) { if (skip) return; style(); out += t; }
  while (i < rtf.length) {
    const ch = rtf[i];
    if (bytes.length && !(ch === "\\" && rtf[i + 1] === "'")) flush();
    if (ch === "{") { stack.push({ skip, b, it, ul }); i++; if (rtf.startsWith("\\*", i)) skip++; continue; }
    if (ch === "}") { const s = stack.pop(); if (s) ({ skip, b, it, ul } = s); i++; continue; }
    if (ch === "\\") {
      const next = rtf[i + 1];
      if (next === "\\" || next === "{" || next === "}") { text(next); i += 2; continue; }
      if (next === "'") { if (!skip) bytes.push(parseInt(rtf.substr(i + 2, 2), 16)); i += 4; continue; }
      if (next === "\n" || next === "\r") { text("<br>"); i += 2; continue; }
      const m = /^\\([a-zA-Z]+)(-?\d+)? ?/.exec(rtf.slice(i, i + 40));
      if (!m) { i += 2; continue; }
      i += m[0].length;
      const word = m[1], arg = m[2] === undefined ? undefined : Number(m[2]);
      if (["fonttbl", "colortbl", "stylesheet", "info", "expandedcolortbl", "listtable", "listoverridetable", "pict"].includes(word)) skip++;
      else if (word === "par" || word === "line") text("<br>");
      else if (word === "tab") text("&emsp;");
      else if (word === "b") b = arg !== 0;
      else if (word === "i") it = arg !== 0;
      else if (word === "ul") ul = arg !== 0;
      else if (word === "ulnone") ul = false;
      else if (word === "plain") { b = it = ul = false; }
      else if (word === "f" && arg !== undefined) font = arg;
      else if (word === "uc") uc = arg ?? 1;
      else if (word === "u" && arg !== undefined) { text(esc(String.fromCharCode(arg < 0 ? arg + 65536 : arg))); i += uc; }
      continue;
    }
    if (ch === "\r" || ch === "\n") { i++; continue; }
    text(esc(ch)); i++;
  }
  flush(); b = it = ul = false; style();
  return out.replace(/^(<br>)+/, "");
}
