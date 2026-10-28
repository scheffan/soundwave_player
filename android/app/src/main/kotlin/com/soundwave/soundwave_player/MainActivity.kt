package com.soundwave.soundwave_player

import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Size
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

// AudioServiceActivity (en lugar de FlutterActivity) es lo que permite que
// just_audio_background mantenga la música sonando con la pantalla apagada.
class MainActivity : AudioServiceActivity() {
    private val worker = Executors.newFixedThreadPool(3)
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "soundwave/media")
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "querySongs" -> runAsync(result) {
                querySongs(call.argument<Int>("minDurationMs") ?: 10000)
            }
            "artwork" -> runAsync(result) {
                artwork(
                    (call.argument<Number>("id") ?: 0).toLong(),
                    call.argument<Int>("size") ?: 200,
                )
            }
            "openFmRadio" -> result.success(openFmRadio())
            else -> result.notImplemented()
        }
    }

    private fun runAsync(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("media_error", e.message, null) }
            }
        }
    }

    // Lee la biblioteca de Android (MediaStore). Incluye memoria interna y microSD,
    // porque el sistema indexa todos los volúmenes externos.
    private fun querySongs(minDurationMs: Int): List<Map<String, Any?>> {
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.SIZE,
        )
        val selection =
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= ?"
        val songs = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            collection, projection, selection, arrayOf(minDurationMs.toString()),
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val trackCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
            val dateCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val sizeCol = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                songs.add(
                    mapOf(
                        "id" to id,
                        "title" to (c.getString(titleCol) ?: ""),
                        "artist" to c.getString(artistCol),
                        "album" to c.getString(albumCol),
                        "albumId" to c.getLong(albumIdCol),
                        "durationMs" to c.getLong(durationCol),
                        "path" to (c.getString(dataCol) ?: ""),
                        "track" to c.getInt(trackCol),
                        "dateAdded" to c.getLong(dateCol),
                        "size" to c.getLong(sizeCol),
                        "uri" to ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id,
                        ).toString(),
                    ),
                )
            }
        }
        return songs
    }

    // Devuelve la tapa del disco como JPEG, o null si la canción no tiene.
    private fun artwork(id: Long, size: Int): ByteArray? {
        val uri = ContentUris.withAppendedId(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id)
        val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                contentResolver.loadThumbnail(uri, Size(size, size), null)
            } catch (e: Exception) {
                null
            }
        } else {
            embeddedPicture(uri, size)
        }
        bitmap ?: return null
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return out.toByteArray()
    }

    private fun embeddedPicture(uri: Uri, size: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            val bytes = retriever.embeddedPicture ?: return null
            val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            var sample = 1
            while (opts.outWidth / (sample * 2) >= size && opts.outHeight / (sample * 2) >= size) {
                sample *= 2
            }
            BitmapFactory.decodeByteArray(
                bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample },
            )
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }

    // Android no tiene una API pública para el sintonizador FM. Lo único fiable es
    // abrir la app de radio de fábrica, si el fabricante instaló una.
    private fun openFmRadio(): Boolean {
        val packages = listOf(
            "com.sec.android.app.fm",
            "com.miui.fm",
            "com.motorola.fmplayer",
            "com.android.fmradio",
            "com.caf.fmradio",
            "com.huawei.android.FMRadio",
            "com.lge.fmradio",
            "com.sonyericsson.fmradio",
            "com.oppo.fmradio",
            "com.coloros.fmradio",
            "com.vivo.FMRadio",
            "com.mediatek.FMRadio",
            "com.transsion.fmradio",
        )
        for (pkg in packages) {
            val intent = packageManager.getLaunchIntentForPackage(pkg) ?: continue
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            return true
        }
        return false
    }
}
