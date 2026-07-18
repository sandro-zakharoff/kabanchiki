package com.kabanchiki.app.core.images

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Client-side image optimizer: photos shrink BEFORE upload — ≤1920 px long
 * side, WebP q82 on API 30+ (JPEG q85 below), plus a 480 px thumbnail.
 * Re-encoding drops all metadata (EXIF, GPS); the EXIF orientation is applied
 * first so pixels stay upright. Target: 150–450 KB per photo.
 */
object ImageOptimizer {

    const val MAX_SIDE = 1920
    const val THUMB_SIDE = 480
    const val AVATAR_SIDE = 512

    data class Encoded(val bytes: ByteArray, val mime: String, val ext: String)
    data class Optimized(val full: Encoded, val thumb: Encoded)

    fun optimize(context: Context, uri: Uri): Optimized {
        val upright = loadUpright(context, uri)
        try {
            val full = encode(scale(upright, MAX_SIDE), quality = 82, jpegQuality = 85)
            val thumb = encode(scale(upright, THUMB_SIDE), quality = 75, jpegQuality = 80)
            return Optimized(full, thumb)
        } finally {
            upright.recycle()
        }
    }

    /** Square avatar; crop is (x, y, size) in upright source pixels. */
    fun optimizeAvatar(context: Context, uri: Uri, crop: FloatArray? = null): Encoded {
        val src = loadUpright(context, uri)
        val square = if (crop != null && crop[2] > 4f) {
            val x = crop[0].roundToInt().coerceIn(0, src.width - 2)
            val y = crop[1].roundToInt().coerceIn(0, src.height - 2)
            val size = crop[2].roundToInt()
                .coerceAtMost(src.width - x)
                .coerceAtMost(src.height - y)
            Bitmap.createBitmap(src, x, y, size, size)
        } else {
            val side = min(src.width, src.height)
            Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
        }
        if (square !== src) src.recycle()
        val scaled = Bitmap.createScaledBitmap(square, AVATAR_SIDE, AVATAR_SIDE, true)
        if (scaled !== square) square.recycle()
        val out = encode(scaled, quality = 85, jpegQuality = 88)
        scaled.recycle()
        return out
    }

    /** Upright dimensions for the crop UI's math. */
    fun imageSize(context: Context, uri: Uri): Pair<Int, Int> {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, opts) }
        val rotated = exifRotation(context, uri) % 180 != 0
        return if (rotated) opts.outHeight to opts.outWidth else opts.outWidth to opts.outHeight
    }

    // ---------------------------------------------------------------- internals

    private fun exifRotation(context: Context, uri: Uri): Int =
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                when (ExifInterface(stream).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
                )) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270
                    else -> 0
                }
            } ?: 0
        }.getOrDefault(0)

    private fun loadUpright(context: Context, uri: Uri): Bitmap {
        // Bounds first: decode subsampled so a 50 MP source never OOMs.
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val raw = context.contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: error("cannot decode image")

        val rotation = exifRotation(context, uri)
        if (rotation == 0) return raw
        val matrix = Matrix().apply { postRotate(rotation.toFloat()) }
        val upright = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
        if (upright !== raw) raw.recycle()
        return upright
    }

    private fun scale(src: Bitmap, maxSide: Int): Bitmap {
        val k = min(1f, maxSide.toFloat() / max(src.width, src.height))
        if (k >= 1f) return src
        return Bitmap.createScaledBitmap(
            src, (src.width * k).roundToInt().coerceAtLeast(1),
            (src.height * k).roundToInt().coerceAtLeast(1), true,
        )
    }

    private fun encode(bitmap: Bitmap, quality: Int, jpegQuality: Int): Encoded {
        val out = ByteArrayOutputStream()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, quality, out)
            Encoded(out.toByteArray(), "image/webp", "webp")
        } else {
            bitmap.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
            Encoded(out.toByteArray(), "image/jpeg", "jpg")
        }
    }
}
