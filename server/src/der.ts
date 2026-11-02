/**
 * Just enough DER to read an X.509 certificate's SubjectPublicKeyInfo and
 * validity (platform.ts → the Game Center verifier). No chain building, no
 * extensions: the certificate comes from Apple's own host over TLS, and the
 * key inside it is what WebCrypto needs (`importKey("spki", …)`).
 */

export interface Tlv {
  tag: number;
  /** First byte of the content. */
  start: number;
  /** One past the last byte of the content. */
  end: number;
  /** First byte of the header (the tag). */
  head: number;
}

/** The TLV at `at`; throws on a malformed length. */
export function readTlv(der: Uint8Array, at: number): Tlv {
  if (at + 2 > der.length) throw new Error("der: truncated");
  const tag = der[at];
  let len = der[at + 1];
  let p = at + 2;
  if (len & 0x80) {
    const n = len & 0x7f;
    if (n === 0 || n > 4 || p + n > der.length) throw new Error("der: length");
    len = 0;
    for (let i = 0; i < n; i++) len = len * 256 + der[p + i];
    p += n;
  }
  if (p + len > der.length) throw new Error("der: truncated");
  return { tag, start: p, end: p + len, head: at };
}

/** The children of a constructed TLV, in order. */
export function children(der: Uint8Array, outer: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let p = outer.start;
  while (p < outer.end) {
    const t = readTlv(der, p);
    out.push(t);
    p = t.end;
  }
  return out;
}

/** tbsCertificate's fields after the optional [0] version. */
function tbsFields(der: Uint8Array): Tlv[] {
  const cert = readTlv(der, 0);
  if (cert.tag !== 0x30) throw new Error("der: not a certificate");
  const tbs = children(der, cert)[0];
  if (!tbs || tbs.tag !== 0x30) throw new Error("der: no tbsCertificate");
  const fields = children(der, tbs);
  if (fields.length && fields[0].tag === 0xa0) fields.shift(); // version
  // serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo
  if (fields.length < 6) throw new Error("der: short tbsCertificate");
  return fields;
}

/** The whole SubjectPublicKeyInfo TLV (what `importKey("spki")` takes). */
export function spkiOf(der: Uint8Array): Uint8Array {
  const spki = tbsFields(der)[5];
  if (spki.tag !== 0x30) throw new Error("der: no subjectPublicKeyInfo");
  return der.slice(spki.head, spki.end);
}

/** notBefore / notAfter in ms since the epoch (UTCTime or GeneralizedTime). */
export function validityOf(der: Uint8Array): { notBefore: number; notAfter: number } {
  const validity = tbsFields(der)[3];
  if (validity.tag !== 0x30) throw new Error("der: no validity");
  const [nb, na] = children(der, validity);
  if (!nb || !na) throw new Error("der: validity");
  return { notBefore: readTime(der, nb), notAfter: readTime(der, na) };
}

function readTime(der: Uint8Array, t: Tlv): number {
  const s = String.fromCharCode(...der.subarray(t.start, t.end));
  let m: RegExpMatchArray | null;
  if (t.tag === 0x17 && (m = s.match(/^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/))) {
    const yy = Number(m[1]);
    return Date.UTC(yy < 50 ? 2000 + yy : 1900 + yy, Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  if (t.tag === 0x18 && (m = s.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.\d+)?Z$/))) {
    return Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  }
  throw new Error("der: time");
}
