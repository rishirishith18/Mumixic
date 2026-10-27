package com.music.bitchord.desktop

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.system.exitProcess

/**
 * Looks at the repo's "latest release" on GitHub once per launch and says whether it is newer
 * than the running build. It can download the platform-specific installer over-the-air (OTA)
 * and launch it to automatically update the application.
 */
internal object DesktopUpdateChecker {

    data class UpdateInfo(
        val version: String,
        val releaseUrl: String,
        /** The installer for this platform, or null when the release has none. */
        val downloadUrl: String?,
        val fileName: String?,
        val notes: String?,
    )

    private const val LATEST_RELEASE_URL =
        "https://api.github.com/repos/rishirishith18/Mumixic-Windows/releases/latest"

    val currentVersion: String =
        System.getProperty("mumixic.version")
            ?: System.getProperty("bitchord.version")
            ?: "1.8-beta1"

    private val json = Json { ignoreUnknownKeys = true }

    private val http = HttpClient(CIO) {
        install(HttpTimeout) {
            requestTimeoutMillis = 15_000
            connectTimeoutMillis = 10_000
        }
    }

    suspend fun check(): UpdateInfo? = runCatching {
        val response = http.get(LATEST_RELEASE_URL) {
            header("Accept", "application/vnd.github+json")
        }
        if (!response.status.isSuccess()) return@runCatching null
        val release = json.parseToJsonElement(response.bodyAsText()) as? JsonObject
            ?: return@runCatching null
        val tag = release["tag_name"]?.jsonPrimitive?.contentOrNull ?: return@runCatching null
        val url = release["html_url"]?.jsonPrimitive?.contentOrNull ?: return@runCatching null
        val latest = tag.removePrefix("v")
        if (!isNewer(latest, currentVersion)) return@runCatching null
        val installerAsset = findInstallerAsset(release)
        UpdateInfo(
            version = latest,
            releaseUrl = url,
            downloadUrl = installerAsset?.first,
            fileName = installerAsset?.second,
            notes = release["body"]?.jsonPrimitive?.contentOrNull,
        )
    }.getOrNull()

    /**
     * Matches platform installer packages from the release assets:
     * - Windows: .exe, -setup.exe, .msi
     * - Linux: .AppImage, .deb
     * - macOS: .dmg, .pkg
     */
    private fun findInstallerAsset(release: JsonObject): Pair<String, String>? {
        val suffixes = when {
            DesktopPlatform.isWindows -> listOf("-windows-x64-setup.exe", ".exe", ".msi")
            DesktopPlatform.isLinux -> listOf(".AppImage", "-linux-amd64.deb")
            DesktopPlatform.isMac -> listOf(".dmg", ".pkg")
            else -> return null
        }
        val assets = release["assets"]?.jsonArray?.mapNotNull { it as? JsonObject }.orEmpty()
        for (suffix in suffixes) {
            val hit = assets.firstOrNull { asset ->
                asset["name"]?.jsonPrimitive?.contentOrNull?.endsWith(suffix, ignoreCase = true) == true &&
                    asset["state"]?.jsonPrimitive?.contentOrNull == "uploaded"
            }
            if (hit != null) {
                val url = hit["browser_download_url"]?.jsonPrimitive?.contentOrNull
                val name = hit["name"]?.jsonPrimitive?.contentOrNull
                if (url != null && name != null) {
                    return url to name
                }
            }
        }
        return null
    }

    /**
     * Streams the installer file directly with progress callback.
     */
    suspend fun downloadInstaller(
        url: String,
        fileName: String,
        onProgress: (Float) -> Unit,
    ): File = withContext(Dispatchers.IO) {
        val targetDir = File(System.getProperty("java.io.tmpdir"), "MumixicUpdates").apply { mkdirs() }
        val targetFile = File(targetDir, fileName)

        var currentUrl = url
        var connection: HttpURLConnection
        var redirects = 0
        while (true) {
            val u = java.net.URI.create(currentUrl).toURL()
            connection = u.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", "Mumixic-Desktop")
            val status = connection.responseCode
            if (status in 300..399) {
                val newUrl = connection.getHeaderField("Location") ?: break
                currentUrl = newUrl
                redirects++
                if (redirects > 8) error("Too many redirects: $redirects")
                continue
            }
            break
        }

        val contentLength = connection.contentLengthLong
        var downloadedBytes = 0L

        connection.inputStream.use { input ->
            FileOutputStream(targetFile).use { output ->
                val buffer = ByteArray(32 * 1024)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    output.write(buffer, 0, read)
                    downloadedBytes += read
                    if (contentLength > 0) {
                        onProgress((downloadedBytes.toFloat() / contentLength).coerceIn(0f, 1f))
                    } else {
                        onProgress(-1f)
                    }
                }
            }
        }
        targetFile
    }

    /**
     * Launches the installer process and terminates the current instance so files can be updated cleanly.
     */
    fun launchInstaller(file: File) {
        try {
            when {
                DesktopPlatform.isWindows -> {
                    if (file.name.endsWith(".msi", ignoreCase = true)) {
                        ProcessBuilder("msiexec", "/i", file.absolutePath).start()
                    } else {
                        ProcessBuilder(file.absolutePath).start()
                    }
                }
                DesktopPlatform.isMac -> {
                    ProcessBuilder("open", file.absolutePath).start()
                }
                DesktopPlatform.isLinux -> {
                    file.setExecutable(true, false)
                    if (file.name.endsWith(".AppImage", ignoreCase = true)) {
                        ProcessBuilder(file.absolutePath).start()
                    } else if (file.name.endsWith(".deb", ignoreCase = true)) {
                        ProcessBuilder("xdg-open", file.absolutePath).start()
                    } else {
                        ProcessBuilder("xdg-open", file.parentFile.absolutePath).start()
                    }
                }
                else -> {
                    DesktopExternalLinks.open(file.toURI().toString())
                }
            }
        } finally {
            exitProcess(0)
        }
    }

    private class Parsed(val parts: List<Int>, val preRelease: Boolean)

    private fun parse(raw: String): Parsed {
        val dash = raw.indexOf('-')
        val base = if (dash >= 0) raw.substring(0, dash) else raw
        return Parsed(base.split('.').map { it.toIntOrNull() ?: 0 }, dash >= 0)
    }

    /** Numeric comparison, with a `-betaN` build counted as older than the plain release it leads up to. */
    internal fun isNewer(latest: String, current: String): Boolean {
        val l = parse(latest)
        val c = parse(current)
        for (i in 0 until maxOf(l.parts.size, c.parts.size)) {
            val a = l.parts.getOrElse(i) { 0 }
            val b = c.parts.getOrElse(i) { 0 }
            if (a != b) return a > b
        }
        return c.preRelease && !l.preRelease
    }
}
