package dev.memesearcher.meme_searcher

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.io.FileInputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "dev.memesearcher.meme_searcher/media_actions"
    private val saveRequestCode = 41027
    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "dev.memesearcher.meme_searcher/magic_conch", MagicConchViewFactory()
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "copy", "copyFile" -> copyToClipboard(call, result)
                "share" -> share(call, result)
                "save" -> save(call, result)
                "getAppVersion" -> result.success(displayVersion())
                else -> result.notImplemented()
            }
        }
    }

    private fun copyToClipboard(call: MethodCall, result: MethodChannel.Result) {
        try {
            val media = stage(call)
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            // ClipData preserves the original bytes (including GIF animation); FileProvider
            // confines the exposed URI to our short-lived media_share cache directory.
            clipboard.setPrimaryClip(ClipData.newUri(contentResolver, media.name, media.uri))
            result.success(mapOf("mode" to "clipboard_file"))
        } catch (error: IllegalArgumentException) {
            result.error("invalid_media", error.message, null)
        } catch (error: Exception) {
            result.error("copy_failed", "원본 파일을 클립보드에 복사하지 못했어요.", null)
        }
    }

    private fun share(call: MethodCall, result: MethodChannel.Result) {
        try {
            val media = stage(call)
            val send = Intent(Intent.ACTION_SEND).apply {
                type = media.mime
                putExtra(Intent.EXTRA_STREAM, media.uri)
                clipData = ClipData.newUri(contentResolver, media.name, media.uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(send, "밈 공유"))
            result.success(mapOf("mode" to "share"))
        } catch (error: IllegalArgumentException) {
            result.error("invalid_media", error.message, null)
        } catch (error: Exception) {
            result.error("share_failed", "공유 화면을 열지 못했어요.", null)
        }
    }

    private fun save(call: MethodCall, result: MethodChannel.Result) {
        if (pendingSave != null) {
            result.error("save_in_progress", "다른 저장 작업이 진행 중이에요.", null)
            return
        }
        try {
            val source = validatedSource(call)
            val name = safeName(call.argument<String>("name") ?: source.name)
            val mime = safeMime(call.argument<String>("mime") ?: "application/octet-stream")
            pendingSave = PendingSave(source, result)
            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mime
                putExtra(Intent.EXTRA_TITLE, name)
            }, saveRequestCode)
        } catch (error: IllegalArgumentException) {
            pendingSave = null
            result.error("invalid_media", error.message, null)
        } catch (error: Exception) {
            pendingSave = null
            result.error("save_failed", "저장 위치를 열지 못했어요.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != saveRequestCode) return
        val pending = pendingSave ?: return
        pendingSave = null
        val destination = data?.data
        if (resultCode != Activity.RESULT_OK || destination == null) {
            pending.result.error("cancelled", "저장을 취소했어요.", null)
            return
        }
        try {
            contentResolver.openOutputStream(destination, "w")!!.use { out ->
                FileInputStream(pending.source).use { input -> input.copyTo(out) }
            }
            pending.result.success(mapOf("mode" to "document"))
        } catch (error: Exception) {
            pending.result.error("save_failed", "원본 파일을 저장하지 못했어요.", null)
        }
    }

    private fun stage(call: MethodCall): StagedMedia {
        val source = validatedSource(call)
        val name = safeName(call.argument<String>("name") ?: source.name)
        val mime = safeMime(call.argument<String>("mime") ?: "application/octet-stream")
        val staging = File(cacheDir, "media_share").apply { mkdirs() }
        staging.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 24 * 60 * 60 * 1000L }?.forEach { it.delete() }
        val destination = File(staging, "${UUID.randomUUID()}-$name")
        source.inputStream().use { input -> destination.outputStream().use { input.copyTo(it) } }
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", destination)
        return StagedMedia(destination.name, mime, uri)
    }

    private fun validatedSource(call: MethodCall): File {
        val rawPath = call.argument<String>("path")?.trim().orEmpty()
        require(rawPath.isNotEmpty()) { "원본 경로가 비어 있어요." }
        val file = File(rawPath).canonicalFile
        require(file.isFile) { "원본 파일을 찾을 수 없어요." }
        val allowedRoots = listOf(filesDir.canonicalFile, cacheDir.canonicalFile)
        require(allowedRoots.any { root -> file.path.startsWith(root.path + File.separator) }) {
            "앱 데이터 밖의 파일은 처리할 수 없어요."
        }
        return file
    }

    private fun safeName(value: String): String = value
        .replace(Regex("[^A-Za-z0-9._ -]"), "_")
        .trim().take(120).ifEmpty { "meme.bin" }

    private fun safeMime(value: String): String = when (value.lowercase()) {
        "image/jpeg", "image/png", "image/webp", "image/gif" -> value.lowercase()
        else -> "application/octet-stream"
    }

    @Suppress("DEPRECATION")
    private fun displayVersion(): String? =
        packageManager.getPackageInfo(packageName, 0).versionName

    private data class StagedMedia(val name: String, val mime: String, val uri: Uri)
    private data class PendingSave(val source: File, val result: MethodChannel.Result)
}

private class MagicConchViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = MagicConchPlatformView(context)
}

private class MagicConchPlatformView(private val context: Context) : PlatformView {
    private val webView = WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.allowFileAccessFromFileURLs = false
        settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        webViewClient = MagicConchClient(context)
        loadUrl("https://conch.example/index.html")
    }

    override fun getView(): View = webView
    override fun dispose() { webView.stopLoading(); webView.destroy() }
}

private class MagicConchClient(private val context: Context) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
        request.url.host != "conch.example"

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
        localResponse(request.url)

    @Suppress("DEPRECATION")
    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? = localResponse(Uri.parse(url))

    private fun localResponse(uri: Uri): WebResourceResponse? {
        if (uri.scheme != "https" || uri.host != "conch.example") return forbidden()
        val requested = uri.path?.removePrefix("/") ?: return forbidden()
        if (requested != "index.html" && !requested.startsWith("assets/")) return forbidden()
        if (requested.split('/').any { it.isBlank() || it == "." || it == ".." || it.contains('\\') }) return forbidden()
        val asset = "flutter_assets/assets/magical_conch/$requested"
        return try {
            val stream = context.assets.open(asset)
            WebResourceResponse(mimeType(requested), "UTF-8", 200, "OK", mapOf("Cache-Control" to "no-store"), stream)
        } catch (_: Exception) { notFound() }
    }

    private fun mimeType(path: String) = when {
        path.endsWith(".html") -> "text/html"
        path.endsWith(".js") -> "application/javascript"
        path.endsWith(".css") -> "text/css"
        path.endsWith(".png") -> "image/png"
        path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
        path.endsWith(".svg") -> "image/svg+xml"
        path.endsWith(".webp") -> "image/webp"
        path.endsWith(".gif") -> "image/gif"
        path.endsWith(".woff2") -> "font/woff2"
        else -> "application/octet-stream"
    }
    private fun forbidden() = response(403, "Forbidden")
    private fun notFound() = response(404, "Not Found")
    private fun response(status: Int, reason: String) = WebResourceResponse("text/plain", "UTF-8", status, reason, emptyMap(), "".byteInputStream())
}
