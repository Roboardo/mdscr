package com.example.mdscr

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val backgroundConnectionChannel = "com.example.mdscr/background_connection"
	private val incomingMessages = mutableListOf<IncomingMessage>()

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, backgroundConnectionChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"start" -> {
						val graceSeconds = call.argument<Int>("graceSeconds") ?: 120
						val intent = Intent(this, ConnectionKeepAliveService::class.java)
							.putExtra(ConnectionKeepAliveService.graceSecondsExtra, graceSeconds)
						if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
							startForegroundService(intent)
						} else {
							startService(intent)
						}
						result.success(null)
					}
					"stop" -> {
						stopService(Intent(this, ConnectionKeepAliveService::class.java))
						result.success(null)
					}
					"requestNotificationPermission" -> {
						requestNotificationPermission()
						result.success(null)
					}
					"showIncomingMessageNotification" -> {
						val callSign = call.argument<String>("callSign")
						val message = call.argument<String>("message")
						if (callSign == null || message == null) {
							result.error("invalid_arguments", "A callsign and message are required.", null)
						} else {
							showIncomingMessageNotification(callSign, message)
							result.success(null)
						}
					}
					else -> result.notImplemented()
				}
			}
	}

	private fun requestNotificationPermission() {
		if (
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
			checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
		) {
			requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequestCode)
		}
	}

	private fun showIncomingMessageNotification(callSign: String, message: String) {
		if (
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
			checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
		) {
			return
		}
		createIncomingMessageNotificationChannel()
		incomingMessages.add(IncomingMessage(callSign, message))
		if (incomingMessages.size > maxIncomingMessages) {
			incomingMessages.removeAt(0)
		}
		val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
			?.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
		val contentIntent = launchIntent?.let {
			PendingIntent.getActivity(
				this,
				0,
				it,
				PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
			)
		}
		val inboxStyle = NotificationCompat.InboxStyle()
		for (incomingMessage in incomingMessages) {
			inboxStyle.addLine("${incomingMessage.callSign}: ${incomingMessage.message}")
		}
		val notification = NotificationCompat.Builder(this, incomingMessageNotificationChannelId)
			.setSmallIcon(android.R.drawable.stat_notify_chat)
			.setContentTitle(
				if (incomingMessages.size == 1) {
					"MESSAGE FROM $callSign"
				} else {
					"${incomingMessages.size} NEW MESSAGES"
				},
			)
			.setContentText("$callSign: $message")
			.setStyle(inboxStyle)
			.setNumber(incomingMessages.size)
			.setOnlyAlertOnce(true)
			.setAutoCancel(true)
			.setContentIntent(contentIntent)
			.build()
		getSystemService(NotificationManager::class.java)
			.notify(incomingMessageNotificationId, notification)
	}

	private fun createIncomingMessageNotificationChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			return
		}
		val channel = NotificationChannel(
			incomingMessageNotificationChannelId,
			"Incoming messages",
			NotificationManager.IMPORTANCE_DEFAULT,
		)
		getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
	}

	companion object {
		private const val incomingMessageNotificationChannelId = "incoming_messages"
		private const val incomingMessageNotificationId = 2000
		private const val maxIncomingMessages = 5
		private const val notificationPermissionRequestCode = 1002
	}

	private data class IncomingMessage(val callSign: String, val message: String)
}
