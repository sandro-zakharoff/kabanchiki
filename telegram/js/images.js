// Kabanchiki Mini App — client-side image optimizer.
//
// Photos are shrunk BEFORE upload: ≤1920px long side, WebP q0.82 where the
// browser can encode it (Chrome/Android), JPEG q0.85 otherwise (iOS Safari),
// plus a 480px thumbnail for lists. Re-encoding through a canvas drops every
// byte of metadata — EXIF, GPS, maker notes — while `imageOrientation:
// "from-image"` keeps the pixels upright. Target weight: 150–450 KB per photo.

const MAX_SIDE = 1920;
const THUMB_SIDE = 480;
const QUALITY_FULL = 0.82;
const QUALITY_THUMB = 0.75;
const QUALITY_JPEG_FULL = 0.85;

let webpSupport = null; // lazily probed once

async function canEncodeWebp() {
  if (webpSupport !== null) return webpSupport;
  const c = document.createElement("canvas");
  c.width = c.height = 2;
  const blob = await new Promise((res) => c.toBlob(res, "image/webp"));
  webpSupport = !!blob && blob.type === "image/webp";
  return webpSupport;
}

async function decode(file) {
  try {
    return await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    // Older engines: no options bag (orientation is usually still applied
    // by the platform decoder for camera photos).
    return await createImageBitmap(file);
  }
}

function scaleToCanvas(bmp, maxSide) {
  const k = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
  const w = Math.max(1, Math.round(bmp.width * k));
  const h = Math.max(1, Math.round(bmp.height * k));
  const canvas = document.createElement("canvas");
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext("2d");
  ctx.imageSmoothingQuality = "high";
  ctx.drawImage(bmp, 0, 0, w, h);
  return canvas;
}

async function encode(canvas, preferWebp, quality, jpegQuality) {
  if (preferWebp) {
    const webp = await new Promise((res) => canvas.toBlob(res, "image/webp", quality));
    if (webp && webp.type === "image/webp") return { blob: webp, mime: "image/webp", ext: "webp" };
  }
  const jpg = await new Promise((res) => canvas.toBlob(res, "image/jpeg", jpegQuality));
  if (!jpg) throw new Error("encode failed");
  return { blob: jpg, mime: "image/jpeg", ext: "jpg" };
}

/**
 * file -> { full: {blob, mime, ext, width, height}, thumb: {blob, mime, ext} }
 */
export async function optimizeImage(file) {
  const bmp = await decode(file);
  const preferWebp = await canEncodeWebp();

  const fullCanvas = scaleToCanvas(bmp, MAX_SIDE);
  const full = await encode(fullCanvas, preferWebp, QUALITY_FULL, QUALITY_JPEG_FULL);
  full.width = fullCanvas.width;
  full.height = fullCanvas.height;

  const thumbCanvas = scaleToCanvas(bmp, THUMB_SIDE);
  const thumb = await encode(thumbCanvas, preferWebp, QUALITY_THUMB, 0.8);

  bmp.close?.();
  return { full, thumb };
}

/** XHR upload with progress (fetch has no upload progress events). */
export function xhrUpload({ url, method = "POST", headers = {}, body, onProgress, timeoutMs = 90000 }) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open(method, url);
    xhr.timeout = timeoutMs;
    for (const [k, v] of Object.entries(headers)) xhr.setRequestHeader(k, v);
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    };
    xhr.onload = () => {
      let data = {};
      try { data = JSON.parse(xhr.responseText || "{}"); } catch { /* not json */ }
      if (xhr.status >= 200 && xhr.status < 300) resolve(data);
      else reject(new Error(data.error || data.message || `upload ${xhr.status}`));
    };
    xhr.onerror = () => reject(new Error("network"));
    xhr.ontimeout = () => reject(new Error("timeout"));
    xhr.send(body);
  });
}

export function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",", 2)[1] ?? "");
    r.onerror = () => reject(r.error);
    r.readAsDataURL(blob);
  });
}
