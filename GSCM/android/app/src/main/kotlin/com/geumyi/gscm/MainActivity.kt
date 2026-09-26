package com.geumyi.gscm

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val channelName = "com.geumyi.gscm/secure_storage"
    private val prefsName = "gscm_local_v2"
    private val keyAlias = "gscm_device_token_aes_v2"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "deviceId" -> result.success(deviceId())
                    "deviceName" -> result.success(deviceName())
                    "loadConnection" -> result.success(loadConnection())
                    "saveConnection" -> {
                        val host = call.argument<String>("host")?.trim().orEmpty()
                        val token = call.argument<String>("token")?.trim().orEmpty()
                        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
                        val deviceName = call.argument<String>("deviceName")?.trim().orEmpty()
                        require(host.isNotEmpty() && token.isNotEmpty() && deviceId.isNotEmpty())
                        saveConnection(host, token, deviceId, deviceName.ifEmpty { deviceName() })
                        result.success(null)
                    }
                    "clearConnection" -> {
                        prefs().edit().remove("host").remove("token_enc").remove("device_name").apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("SECURE_STORE", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun prefs() = getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun deviceId(): String {
        val p = prefs()
        val existing = p.getString("device_id", null)
        if (!existing.isNullOrBlank()) return existing
        val created = "android-" + UUID.randomUUID().toString()
        p.edit().putString("device_id", created).apply()
        return created
    }

    private fun deviceName(): String {
        val manufacturer = Build.MANUFACTURER?.trim().orEmpty()
        val model = Build.MODEL?.trim().orEmpty()
        return listOf(manufacturer, model).filter { it.isNotBlank() }.distinct().joinToString(" ").ifBlank { "Android" }
    }

    private fun saveConnection(host: String, token: String, deviceId: String, deviceName: String) {
        prefs().edit()
            .putString("host", host)
            .putString("device_id", deviceId)
            .putString("device_name", deviceName)
            .putString("token_enc", encrypt(token))
            .apply()
    }

    private fun loadConnection(): Map<String, String>? {
        val p = prefs()
        val host = p.getString("host", null)?.trim().orEmpty()
        val encrypted = p.getString("token_enc", null)?.trim().orEmpty()
        if (host.isEmpty() || encrypted.isEmpty()) return null
        val token = decrypt(encrypted)
        if (token.isBlank()) return null
        return mapOf(
            "host" to host,
            "token" to token,
            "deviceId" to deviceId(),
            "deviceName" to (p.getString("device_name", null)?.trim().orEmpty().ifEmpty { deviceName() })
        )
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(keyAlias, null) as? SecretKey
        if (existing != null) return existing
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        keyGenerator.init(
            KeyGenParameterSpec.Builder(keyAlias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return keyGenerator.generateKey()
    }

    private fun encrypt(value: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val encrypted = cipher.doFinal(value.toByteArray(StandardCharsets.UTF_8))
        return Base64.encodeToString(iv, Base64.NO_WRAP) + "." + Base64.encodeToString(encrypted, Base64.NO_WRAP)
    }

    private fun decrypt(value: String): String {
        val parts = value.split('.', limit = 2)
        require(parts.size == 2) { "Invalid encrypted token" }
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val encrypted = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return String(cipher.doFinal(encrypted), StandardCharsets.UTF_8)
    }
}
