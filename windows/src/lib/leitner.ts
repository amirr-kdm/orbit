import { LeitnerBox, LeitnerWord, uid } from "./model";
import { addDays, dayKey } from "./dates";

/** Days to wait after a word reaches section 1…5 (the 1, 2, 4, 8, 16 day rule) */
export const SECTION_DAYS = [1, 2, 4, 8, 16];
export const LEARNED = 6;
export const SEP = " › ";

export const topicOf = (name: string) => (name.includes(SEP) ? name.split(SEP)[0] : undefined);
export const shortName = (name: string) => (name.includes(SEP) ? name.slice(name.indexOf(SEP) + SEP.length) : name);

export const newWord = (term: string, meaning: string): LeitnerWord => ({ id: uid(), term, meaning, box: 1, due: dayKey(new Date()) });

/** Wrong answers go back to section 1 (due tomorrow); right ones climb a section, and after the last one the word is learned */
export function review(w: LeitnerWord, correct: boolean, today = new Date()): LeitnerWord {
  if (!correct) return { ...w, box: 1, due: dayKey(addDays(today, 1)) };
  const box = Math.min(LEARNED, w.box + 1);
  return { ...w, box, due: box >= LEARNED ? w.due : dayKey(addDays(today, SECTION_DAYS[box - 1])) };
}

export const isDue = (w: LeitnerWord, today = new Date()) => w.box < LEARNED && w.due <= dayKey(today);
export const dueWords = (b: LeitnerBox, today = new Date()) => b.words.filter((w) => isDue(w, today));
export const dueCount = (boxes: LeitnerBox[] | undefined, today = new Date()) => (boxes ?? []).reduce((n, b) => n + dueWords(b, today).length, 0);
export const learnedCount = (b: LeitnerBox) => b.words.filter((w) => w.box >= LEARNED).length;

/** Add words from lines like "term - meaning", "term, meaning" or "term<TAB>meaning" */
export function parseWords(text: string): LeitnerWord[] {
  return text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map((l) => {
    const m = l.match(/^(.*?)\s*(?:\t|\s-\s|,|;|=|:)\s*(.+)$/);
    return newWord(m ? m[1].trim() : l, m ? m[2].trim() : "");
  });
}
