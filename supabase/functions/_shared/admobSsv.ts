// docs/技術実装仕様書.md §20.5.2
// AdMob Server-Side Verification (SSV) の署名検証ユーティリティ。
// 出典: https://developers.google.com/admob/ios/ssv
//
// 署名アルゴリズムはECDSA P-256 + SHA-256、DERエンコード。
// Web Crypto API の ECDSA verify は raw (r||s, 各32byte) 形式のシグネチャを要求するため、
// AdMobから届くDER形式を自前でraw形式に変換する（Deno標準ライブラリに変換機能がないため）。

const VERIFIER_KEYS_URL = "https://gstatic.com/admob/reward/verifier-keys.json";
const KEY_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 公開鍵は24時間より長くキャッシュしない

interface VerifierKeyEntry {
  keyId: number;
  pem: string;
  base64: string;
}

let cachedKeys: VerifierKeyEntry[] | null = null;
let cachedAt = 0;

async function fetchPublicKeys(): Promise<VerifierKeyEntry[]> {
  const now = Date.now();
  if (cachedKeys && now - cachedAt < KEY_CACHE_TTL_MS) {
    return cachedKeys;
  }
  const res = await fetch(VERIFIER_KEYS_URL);
  if (!res.ok) {
    throw new Error(`failed to fetch AdMob verifier keys: ${res.status}`);
  }
  const json = await res.json();
  cachedKeys = json.keys as VerifierKeyEntry[];
  cachedAt = now;
  return cachedKeys;
}

function base64Decode(input: string): Uint8Array {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

// TS 5.7+ ではUint8Arrayが ArrayBufferLike に対して汎用化され、crypto.subtle系の
// BufferSource引数は具体的な ArrayBuffer 版を要求する。ここで作るUint8Arrayは常に
// 通常のArrayBuffer上に確保されるため、実行時には問題なくキャストで解決する。
function asBufferSource(bytes: Uint8Array): BufferSource {
  return bytes as unknown as BufferSource;
}

/** DERエンコードされたECDSA署名 (SEQUENCE { INTEGER r, INTEGER s }) をraw r||s形式に変換する。 */
function derSignatureToRaw(der: Uint8Array, componentLength = 32): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) {
    throw new Error("invalid DER signature: expected SEQUENCE");
  }
  offset = skipLength(der, offset);

  const r = readDerInteger(der, offset);
  offset = r.nextOffset;
  const s = readDerInteger(der, offset);

  const raw = new Uint8Array(componentLength * 2);
  raw.set(toFixedLength(r.value, componentLength), 0);
  raw.set(toFixedLength(s.value, componentLength), componentLength);
  return raw;
}

function skipLength(der: Uint8Array, offset: number): number {
  const first = der[offset];
  if ((first & 0x80) === 0) {
    return offset + 1;
  }
  const numBytes = first & 0x7f;
  return offset + 1 + numBytes;
}

function readDerInteger(
  der: Uint8Array,
  offset: number
): { value: Uint8Array; nextOffset: number } {
  if (der[offset++] !== 0x02) {
    throw new Error("invalid DER signature: expected INTEGER");
  }
  let len = der[offset++];
  if (len & 0x80) {
    const numBytes = len & 0x7f;
    len = 0;
    for (let i = 0; i < numBytes; i++) {
      len = (len << 8) | der[offset++];
    }
  }
  const value = der.slice(offset, offset + len);
  return { value, nextOffset: offset + len };
}

function toFixedLength(bytes: Uint8Array, length: number): Uint8Array {
  let b = bytes;
  while (b.length > length && b[0] === 0) {
    b = b.slice(1);
  }
  if (b.length > length) {
    throw new Error("DER integer too large for fixed-length component");
  }
  if (b.length < length) {
    const padded = new Uint8Array(length);
    padded.set(b, length - b.length);
    b = padded;
  }
  return b;
}

export interface SsvVerificationResult {
  valid: boolean;
  customData: string | null;
}

/**
 * AdMob SSVコールバックのURLを検証する。
 * 署名対象は「signatureパラメータより前」のクエリ文字列（生の文字列のまま、UTF-8バイト列）。
 */
export async function verifySsvCallback(url: URL): Promise<SsvVerificationResult> {
  const signatureB64 = url.searchParams.get("signature");
  const keyIdStr = url.searchParams.get("key_id");
  const customData = url.searchParams.get("custom_data");

  if (!signatureB64 || !keyIdStr) {
    return { valid: false, customData };
  }

  const rawQuery = url.search.startsWith("?") ? url.search.slice(1) : url.search;
  const signatureMarker = "&signature=";
  const sigIndex = rawQuery.indexOf(signatureMarker);
  if (sigIndex === -1) {
    return { valid: false, customData };
  }
  const dataToVerify = rawQuery.substring(0, sigIndex);

  const keys = await fetchPublicKeys();
  const keyId = Number(keyIdStr);
  const keyEntry = keys.find((k) => k.keyId === keyId);
  if (!keyEntry) {
    return { valid: false, customData };
  }

  const publicKey = await crypto.subtle.importKey(
    "spki",
    asBufferSource(base64Decode(keyEntry.base64)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );

  const rawSignature = derSignatureToRaw(base64Decode(signatureB64));

  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    asBufferSource(rawSignature),
    asBufferSource(new TextEncoder().encode(dataToVerify))
  );

  return { valid, customData };
}
