package dev.flowmoney.flowmoney

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class VoiceWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            val openVoiceIntent = Intent(context, MainActivity::class.java).apply {
                action = MainActivity.ACTION_OPEN_VOICE
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetId,
                openVoiceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val views = RemoteViews(context.packageName, R.layout.voice_widget)
            views.setOnClickPendingIntent(R.id.voice_widget_root, pendingIntent)
            views.setOnClickPendingIntent(R.id.voice_widget_mic, pendingIntent)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
