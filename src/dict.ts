// 二进制词库解析（与 Flutter 版 dict.bin 同格式）：
// Header(12B): [count:u32][indexSize:u32][dataSize:u32]
// Index: [wordLen:u16][word utf8][dataOffset:u32][dataLen:u32]
// Data:  [phoneticLen:u16][phonetic][posLen:u16][pos][transLen:u16][trans][otherLen:u16][other]
export interface DictEntry { phonetic: string; pos: string; trans: string; other: string; }

export class BinaryDict {
  private buf: Uint8Array | null = null;
  private view: DataView | null = null;
  private words: string[] = [];
  private loaded = false;

  async load(url: string) {
    const resp = await fetch(url);
    this.buf = new Uint8Array(await resp.arrayBuffer());
    this.view = new DataView(this.buf.buffer);
    if (this.buf.length < 12) return;
    const count = this.view.getUint32(0, true);
    const idxSize = this.view.getUint32(4, true);
    let p = 12;
    const idxEnd = 12 + idxSize;
    const dec = new TextDecoder();
    while (p + 10 <= idxEnd && this.words.length < count) {
      const wLen = this.view.getUint16(p, true);
      if (p + 2 + wLen + 8 > idxEnd) break;
      this.words.push(dec.decode(this.buf.subarray(p + 2, p + 2 + wLen)));
      p += 2 + wLen + 8;
    }
    this.loaded = count > 0;
  }

  get size() { return this.words.length; }
  get ready() { return this.loaded; }
  allWords() { return this.words; }

  lookup(word: string): DictEntry | null {
    if (!this.loaded || !this.view || !this.buf) return null;
    const w = word.toLowerCase();
    let lo = 0;
    let hi = this.words.length - 1;
    let found = -1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const c = this.words[mid].localeCompare(w);
      if (c === 0) { found = mid; break; }
      if (c < 0) lo = mid + 1; else hi = mid - 1;
    }
    if (found < 0) return null;
    // 重走索引定位 data 偏移（线性缓存可优化，规模 1 万可接受）
    const view = this.view;
    const idxSize = view.getUint32(4, true);
    let p = 12;
    const idxEnd = 12 + idxSize;
    const dec = new TextDecoder();
    while (p + 10 <= idxEnd) {
      const wLen = view.getUint16(p, true);
      if (p + 2 + wLen + 8 > idxEnd) break;
      const wordHere = dec.decode(this.buf!.subarray(p + 2, p + 2 + wLen));
      const dOff = view.getUint32(p + 2 + wLen, true);
      const dLen = view.getUint32(p + 2 + wLen + 4, true);
      if (wordHere === w) return this.decode(dOff, dLen);
      p += 2 + wLen + 8;
    }
    return null;
  }

  private decode(dOff: number, dLen: number): DictEntry {
    const dec = new TextDecoder();
    let p = 12 + this.view!.getUint32(4, true) + dOff;
    const end = p + dLen;
    const readStr = (): string => {
      if (p + 2 > end) return '';
      const len = this.view!.getUint16(p, true);
      p += 2;
      if (p + len > end) return '';
      const s = dec.decode(this.buf!.subarray(p, p + len));
      p += len;
      return s;
    };
    const phonetic = readStr();
    const pos = readStr();
    const trans = readStr();
    const other = readStr();
    return { phonetic, pos, trans, other };
  }

  searchPrefix(prefix: string, limit = 30): Array<{ word: string; entry: DictEntry }> {
    const pl = prefix.toLowerCase();
    return this.words.filter((w) => w.startsWith(pl)).slice(0, limit)
      .map((w) => ({ word: w, entry: this.lookup(w) ?? { phonetic: '', pos: '', trans: '', other: '' } }));
  }
}

export const dict = new BinaryDict();
export const zsbDict = new BinaryDict();
