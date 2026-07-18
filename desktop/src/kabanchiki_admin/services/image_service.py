"""Client-side image optimizer (Pillow).

Photos are shrunk BEFORE upload: ≤1920 px long side, WebP q82 (JPEG q85 when
WebP is unavailable), plus a 480 px thumbnail for lists and an optional square
crop for avatars. Re-encoding drops all metadata — EXIF, GPS, maker notes —
while the EXIF orientation is applied first so pixels stay upright.
Target weight: 150–450 KB per photo, 20–60 KB per thumbnail.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageOps

MAX_SIDE = 1920
THUMB_SIDE = 480
AVATAR_SIDE = 512
QUALITY_FULL = 82
QUALITY_THUMB = 75


@dataclass
class OptimizedImage:
    data: bytes
    mime: str
    ext: str
    width: int
    height: int


@dataclass
class OptimizedPhoto:
    full: OptimizedImage
    thumb: OptimizedImage


def _load_upright(path: str) -> Image.Image:
    img = Image.open(path)
    # Apply the EXIF orientation, then forget the metadata entirely.
    img = ImageOps.exif_transpose(img)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGB")
    return img


def _encode(img: Image.Image, quality: int) -> OptimizedImage:
    if img.mode == "RGBA":
        # Photos are opaque in practice; flatten to keep JPEG possible.
        background = Image.new("RGB", img.size, (255, 255, 255))
        background.paste(img, mask=img.split()[3])
        img = background
    buf = io.BytesIO()
    try:
        img.save(buf, "WEBP", quality=quality, method=4)
        mime, ext = "image/webp", "webp"
    except Exception:  # noqa: BLE001 - WebP codec missing: JPEG fallback
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=quality + 3, optimize=True)
        mime, ext = "image/jpeg", "jpg"
    return OptimizedImage(buf.getvalue(), mime, ext, img.width, img.height)


def _scaled(img: Image.Image, max_side: int) -> Image.Image:
    k = min(1.0, max_side / max(img.width, img.height))
    if k >= 1.0:
        return img
    size = (max(1, round(img.width * k)), max(1, round(img.height * k)))
    return img.resize(size, Image.LANCZOS)


def optimize_photo(path: str) -> OptimizedPhoto:
    """Full-size rendition + thumbnail for one source file."""
    src = Path(path)
    if not src.is_file():
        raise FileNotFoundError(path)
    img = _load_upright(str(src))
    full = _encode(_scaled(img, MAX_SIDE), QUALITY_FULL)
    thumb = _encode(_scaled(img, THUMB_SIDE), QUALITY_THUMB)
    return OptimizedPhoto(full=full, thumb=thumb)


def optimize_avatar(
    path: str,
    crop: tuple[float, float, float, float] | None = None,
) -> OptimizedImage:
    """Square avatar; `crop` is (x, y, size, size) in source-image pixels
    (already orientation-corrected), e.g. from the QML pan/zoom crop UI."""
    img = _load_upright(path)
    if crop is not None:
        x, y, w, h = (max(0.0, v) for v in crop)
        box = (
            int(min(x, img.width - 1)),
            int(min(y, img.height - 1)),
            int(min(x + w, img.width)),
            int(min(y + h, img.height)),
        )
        if box[2] - box[0] > 4 and box[3] - box[1] > 4:
            img = img.crop(box)
    else:
        side = min(img.width, img.height)
        left = (img.width - side) // 2
        top = (img.height - side) // 2
        img = img.crop((left, top, left + side, top + side))
    img = img.resize((AVATAR_SIDE, AVATAR_SIDE), Image.LANCZOS)
    return _encode(img, 85)


def image_size(path: str) -> tuple[int, int]:
    """Orientation-corrected dimensions (for the crop UI's math)."""
    img = _load_upright(path)
    return img.width, img.height
