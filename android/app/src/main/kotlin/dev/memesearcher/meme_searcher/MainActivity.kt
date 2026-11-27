package dev.memesearcher.meme_searcher

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "dev.memesearcher.meme_searcher/media_actions"
    private val saveRequestCode = 41027
    private var pendingSave: PendingSave? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "dev.memesearcher.meme_searcher/magic_conch",
            MagicConchViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "copy", "copyFile" -> copyToClipboard(call, result)
                "share" -> share(call, result)
                "save" -> save(call, result)
                "getAppVersion" -> result.success(displayVersion())
                "installUpdate" -> installUpdate(call, result)
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

    /**
     * Hands a verified, app-private release APK to Android's package installer.
     * The installer, rather than this app, remains responsible for the final
     * user confirmation and signature/version enforcement.
     */
    private fun installUpdate(call: MethodCall, result: MethodChannel.Result) {
        thread(name = "verify-update-apk") {
            val apk = try {
                verifiedUpdateApk(call)
            } catch (error: IllegalArgumentException) {
                result.error("invalid_update", error.message, null)
                return@thread
            } catch (error: Exception) {
                result.error("invalid_update", "업데이트 APK를 확인하지 못했어요.", null)
                return@thread
            }
            runOnUiThread { openUpdateInstaller(apk, result) }
        }
    }

    private fun verifiedUpdateApk(call: MethodCall): File {
        val requestedVersion = call.argument<String>("version")?.trim().orEmpty()
        val expectedSha256 = call.argument<String>("sha256")?.trim().orEmpty().lowercase()
        require(VERSION_PATTERN.matches(requestedVersion)) { "업데이트 버전이 올바르지 않아요." }
        require(SHA256_PATTERN.matches(expectedSha256)) { "SHA-256 형식이 올바르지 않아요." }

        val apk = validatedUpdateApk(call)
        require(sha256(apk) == expectedSha256) { "APK SHA-256이 게시된 값과 달라요." }
        val archive = packageInfoForArchive(apk)
            ?: throw IllegalArgumentException("APK 패키지 정보를 읽을 수 없어요.")
        require(archive.packageName == packageName) { "다른 앱의 APK는 설치할 수 없어요." }
        require(archive.versionName == requestedVersion) { "APK 버전이 요청한 버전과 달라요." }
        require(packageVersionCode(archive) > installedVersionCode()) { "더 새로운 APK만 설치할 수 있어요." }
        require(archiveSignerMatchesInstalledApp(archive)) { "APK 서명이 현재 앱과 일치하지 않아요." }
        return apk
    }

    private fun openUpdateInstaller(apk: File, result: MethodChannel.Result) {
        if (isFinishing || isDestroyed) {
            result.error("install_failed", "설치 화면을 열려면 앱을 다시 열어 주세요.", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                val settingsIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                startActivity(settingsIntent)
                result.success("permissionRequired")
                return
            }

            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
            val installerIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri(apk.name, uri)
            }
            val handler = packageManager.queryIntentActivities(
                installerIntent, PackageManager.MATCH_DEFAULT_ONLY or PackageManager.MATCH_SYSTEM_ONLY
            ).firstOrNull()?.activityInfo
                ?: throw ActivityNotFoundException("No system APK installer")
            installerIntent.setClassName(handler.packageName, handler.name)
            startActivity(installerIntent)
            result.success("installerOpened")
        } catch (error: ActivityNotFoundException) {
            result.error("no_handler", "Android 설치 화면을 찾을 수 없어요.", null)
        } catch (error: SecurityException) {
            result.error("installer_denied", "APK 설치 권한을 확인할 수 없어요.", null)
        } catch (error: Exception) {
            result.error("install_failed", "시스템 설치 화면을 열지 못했어요.", null)
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

    private fun validatedUpdateApk(call: MethodCall): File {
        val rawPath = call.argument<String>("path")?.trim().orEmpty()
        require(rawPath.isNotEmpty()) { "APK 경로가 비어 있어요." }
        val apk = File(rawPath).canonicalFile
        require(apk.isFile && apk.extension.equals("apk", ignoreCase = true)) { "APK 파일을 찾을 수 없어요." }
        val updatesRoot = File(cacheDir, "app_updates").canonicalFile
        require(apk.path.startsWith(updatesRoot.path + File.separator)) {
            "앱 업데이트 캐시 밖의 APK는 설치할 수 없어요."
        }
        return apk
    }

    @Suppress("DEPRECATION")
    private fun packageInfoForArchive(apk: File): PackageInfo? =
        packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNING_CERTIFICATES)

    @Suppress("DEPRECATION")
    private fun installedVersionCode(): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        packageManager.getPackageInfo(packageName, 0).longVersionCode
    } else {
        packageManager.getPackageInfo(packageName, 0).versionCode.toLong()
    }

    @Suppress("DEPRECATION")
    private fun packageVersionCode(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        info.longVersionCode
    } else {
        info.versionCode.toLong()
    }

    /** On Android 9+ we can reject a clearly foreign archive before invoking the installer. */
    private fun archiveSignerMatchesInstalledApp(archive: PackageInfo): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return true
        val signers = archive.signingInfo?.apkContentsSigners ?: return false
        return signers.isNotEmpty() && signers.all { signer ->
            packageManager.hasSigningCertificate(
                packageName,
                signer.toByteArray(),
                PackageManager.CERT_INPUT_RAW_X509
            )
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
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

    private companion object {
        const val APK_MIME = "application/vnd.android.package-archive"
        val SHA256_PATTERN = Regex("^[a-f0-9]{64}$")
        val VERSION_PATTERN = Regex("""^\d+\.\d+\.\d+\.\d+$""")
    }
}

private class MagicConchViewFactory(
    private val binaryMessenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        MagicConchPlatformView(context, viewId, binaryMessenger)
}

private class MagicConchPlatformView(
    private val context: Context,
    viewId: Int,
    binaryMessenger: BinaryMessenger
) : PlatformView {
    private var isForeground = false
    private var isDisposed = false
    private val channel = MethodChannel(
        binaryMessenger,
        "dev.memesearcher.meme_searcher/magic_conch/$viewId"
    )
    private val webView = WebView(context).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.allowUniversalAccessFromFileURLs = false
        settings.allowFileAccessFromFileURLs = false
        settings.mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.mediaPlaybackRequiresUserGesture = false
        webViewClient = MagicConchClient(context) { applyForegroundState() }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setForeground" -> {
                    val foreground = call.arguments as? Boolean
                    if (foreground == null) {
                        result.error("invalid_argument", "foreground must be a boolean.", null)
                    } else {
                        isForeground = foreground
                        applyForegroundState()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        webView.loadUrl("https://conch.example/index.html")
    }

    override fun getView(): View = webView
    override fun dispose() {
        isDisposed = true
        channel.setMethodCallHandler(null)
        webView.stopLoading()
        webView.destroy()
    }

    private fun applyForegroundState() {
        if (isDisposed) return
        val value = if (isForeground) "true" else "false"
        webView.evaluateJavascript("window.__memeConchAudio?.setForeground($value)", null)
    }
}

private class MagicConchClient(
    private val context: Context,
    private val onPageFinished: () -> Unit
) : WebViewClient() {
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
        val uri = request.url
        if (isLocal(uri)) return false
        if (request.isForMainFrame && isOfficialJingleLink(uri)) {
            // The in-page fallback deliberately leaves the locked-down WebView.
            try {
                context.startActivity(Intent(Intent.ACTION_VIEW, uri))
            } catch (_: ActivityNotFoundException) {
                // The visible URL remains available for copying if no browser
                // can handle it on this device.
            }
            return true
        }
        // Embedded navigation is limited to the one official player.  A frame
        // cannot turn into an arbitrary browser surface.
        return request.isForMainFrame || !isYouTubePlayerResource(uri)
    }

    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
        localResponse(request.url)

    @Suppress("DEPRECATION")
    override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? = localResponse(Uri.parse(url))

    override fun onPageFinished(view: WebView, url: String) {
        super.onPageFinished(view, url)
        val uri = Uri.parse(url)
        if (uri.scheme == "https" && uri.host == "conch.example") {
            onPageFinished()
        }
    }

    private fun localResponse(uri: Uri): WebResourceResponse? {
        if (isYouTubePlayerResource(uri)) return null
        if (!isLocal(uri)) return forbidden()
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

    private fun isLocal(uri: Uri) = uri.scheme == "https" && uri.host == "conch.example"

    private fun isOfficialJingleLink(uri: Uri): Boolean =
        uri.scheme == "https" &&
            uri.host == "www.youtube.com" &&
            uri.path == "/watch" &&
            uri.getQueryParameter("v") == JINGLE_VIDEO_ID

    // Allow the remote scripts, artwork and media used by the embedded player.
    private fun isYouTubePlayerResource(uri: Uri): Boolean {
        if (uri.scheme != "https") return false
        val host = uri.host?.lowercase() ?: return false
        val path = uri.path.orEmpty()
        return when (host) {
            "www.youtube.com" ->
                path == "/embed/$JINGLE_VIDEO_ID" ||
                    path.startsWith("/s/player/") ||
                    path.startsWith("/s/_/") ||
                    path.startsWith("/youtubei/") ||
                    path.startsWith("/api/")
            "youtubei.googleapis.com", "i.ytimg.com", "s.ytimg.com", "yt3.ggpht.com", "www.gstatic.com" -> true
            else -> host == "googlevideo.com" || host.endsWith(".googlevideo.com")
        }
    }

    private companion object {
        const val JINGLE_VIDEO_ID = "f5v2xcBNNic"
    }
}
