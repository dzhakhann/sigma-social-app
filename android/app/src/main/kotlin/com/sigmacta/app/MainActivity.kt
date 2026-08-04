package com.sigmacta.app

import android.content.ComponentName
import android.content.pm.PackageManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// just_audio_background requires the activity to be an AudioServiceActivity,
// otherwise playback silently fails on Android (stuck at 00:00).
class MainActivity : AudioServiceActivity() {

    companion object {
        private const val CHANNEL = "com.sigmacta.app/launcher_icon"

        /// Alias suffix per variant. Must match the activity-alias names in
        /// AndroidManifest.xml.
        private val VARIANTS = mapOf(
            "default" to ".MainActivityIconDefault",
            "boys" to ".MainActivityIconBoy",
            "girls" to ".MainActivityIconGirl",
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        val variant = call.argument<String>("variant") ?: "default"
                        result.success(setLauncherIcon(variant))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Switches the launcher icon by enabling one activity-alias and disabling
     * the others. Android offers no way to change an activity's icon directly.
     *
     * Order matters: the target is enabled FIRST, then the others are disabled.
     * Disabling every alias before enabling one — even for an instant — can
     * leave the app with no launcher entry at all, and some launchers cache that
     * and drop the app from the home screen.
     *
     * DONT_KILL_APP keeps the current process alive. Without it Android tears
     * the app down mid-switch, which the user experiences as a crash right after
     * picking a theme.
     */
    private fun setLauncherIcon(variant: String): Boolean {
        val target = VARIANTS[variant] ?: return false
        return try {
            val pm = packageManager
            enable(pm, target, true)
            VARIANTS.values.filter { it != target }.forEach { enable(pm, it, false) }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun enable(pm: PackageManager, alias: String, on: Boolean) {
        pm.setComponentEnabledSetting(
            ComponentName(packageName, packageName + alias),
            if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }
}
