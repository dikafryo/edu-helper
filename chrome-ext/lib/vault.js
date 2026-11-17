/**
 * Local PIN vault for pen도우미.
 * - PIN never stored. Only PBKDF2 salt + AES-GCM ciphertext/iv in chrome.storage.local.
 * - PBKDF2 iterations >= 200000. WebCrypto only. No network / no sync / no console secrets.
 */
const ITER = 210000;
const PIN_MIN = 4;
const PIN_MAX = 12;
const MAX_FAIL = 5;
const UNLOCK_MS_DEFAULT = 10 * 60 * 1000; // 10 min

function b64(buf) {
  const u8 = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
  let s = '';
  for (let i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]);
  return btoa(s);
}
function fromB64(s) {
  const bin = atob(s);
  const u8 = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  return u8;
}
function rand(n) {
  const u8 = new Uint8Array(n);
  crypto.getRandomValues(u8);
  return u8;
}
function normalizePin(pin) {
  const p = String(pin == null ? '' : pin).trim();
  if (!/^\d{4,12}$/.test(p)) throw new Error('PIN은 숫자 4~12자리입니다. 6자리 이상을 권장합니다.');
  return p;
}

async function deriveKey(pin, saltU8) {
  const enc = new TextEncoder();
  const base = await crypto.subtle.importKey('raw', enc.encode(pin), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: saltU8, iterations: ITER, hash: 'SHA-256' },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

async function encryptPayload(pin, obj) {
  const salt = rand(16);
  const iv = rand(12);
  const key = await deriveKey(normalizePin(pin), salt);
  const pt = new TextEncoder().encode(JSON.stringify(obj));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, pt);
  return { v: 1, iter: ITER, salt: b64(salt), iv: b64(iv), ct: b64(ct) };
}

async function decryptPayload(pin, blob) {
  if (!(blob && blob.salt && blob.iv && blob.ct)) throw new Error('금고 없음');
  const salt = fromB64(blob.salt);
  const iv = fromB64(blob.iv);
  const ct = fromB64(blob.ct);
  const key = await deriveKey(normalizePin(pin), salt);
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ct);
  return JSON.parse(new TextDecoder().decode(pt));
}

/** Hash-only lock (no password vault required). Stores salted PBKDF2 verify blob. */
async function makePinVerify(pin) {
  const salt = rand(16);
  const enc = new TextEncoder();
  const base = await crypto.subtle.importKey('raw', enc.encode(normalizePin(pin)), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: ITER, hash: 'SHA-256' },
    base,
    256
  );
  return { v: 1, iter: ITER, salt: b64(salt), hash: b64(bits) };
}

async function verifyPinHash(pin, verify) {
  if (!(verify && verify.salt && verify.hash)) return false;
  const salt = fromB64(verify.salt);
  const enc = new TextEncoder();
  const base = await crypto.subtle.importKey('raw', enc.encode(normalizePin(pin)), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: Number(verify.iter) || ITER, hash: 'SHA-256' },
    base,
    256
  );
  const a = b64(bits);
  return a === verify.hash;
}

export {
  ITER, PIN_MIN, PIN_MAX, MAX_FAIL, UNLOCK_MS_DEFAULT,
  encryptPayload, decryptPayload, makePinVerify, verifyPinHash, normalizePin
};
