package com.rekindle.app.core.readaloud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat
import com.rekindle.app.R
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Keeps a book reading aloud with the screen off or the app in the background.
 * Android stops a background app's work, so while [ReadAloud] is active this runs
 * in the foreground, with a notification and lock-screen controls (play, pause and
 * stop) through a media session. It also holds audio focus, pausing for a call or
 * other audio and when headphones are unplugged.
 */
@AndroidEntryPoint
class ReadAloudService : Service() {

    @Inject lateinit var readAloud: ReadAloud

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var session: MediaSession
    private lateinit var audio: AudioManager
    private var focus: AudioFocusRequest? = null

    /** Paused for a short interruption, such as a notification sound, to resume after. */
    private var pausedForInterruption = false
    private var noisyRegistered = false

    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) readAloud.pause()
        }
    }

    override fun onCreate() {
        super.onCreate()
        audio = getSystemService(AudioManager::class.java)
        createChannel()
        session = MediaSession(this, "Rekindle read aloud").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = readAloud.resume()
                override fun onPause() = readAloud.pause()
                override fun onStop() = readAloud.stop()
            })
            setSessionActivity(openApp())
            isActive = true
        }
        // Foreground at once: Android allows a few seconds from starting the service.
        goForeground(notification(readAloud.state.value))
        scope.launch {
            readAloud.state.collect { state ->
                if (!state.active) {
                    stopSelf()
                    return@collect
                }
                update(state)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> readAloud.togglePause()
            ACTION_STOP -> readAloud.stop()
        }
        return START_NOT_STICKY
    }

    /** Swiping the app away stops reading. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        readAloud.stop()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        scope.cancel()
        abandonFocus()
        setNoisy(false)
        session.isActive = false
        session.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun update(state: ReadAloud.State) {
        val playing = state.status == ReadAloud.Status.PLAYING || state.status == ReadAloud.Status.STARTING
        if (playing) {
            requestFocus()
            setNoisy(true)
        } else {
            setNoisy(false)
        }
        val book = readAloud.book
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, chapterTitle(state))
                .putString(MediaMetadata.METADATA_KEY_ARTIST, book?.title.orEmpty())
                .build(),
        )
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                    PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    1f,
                )
                .build(),
        )
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(state))
    }

    private fun chapterTitle(state: ReadAloud.State): String {
        val book = readAloud.book ?: return "Reading aloud"
        return if (state.chapter in 0 until book.chapterCount) book.chapterTitle(state.chapter) else book.title
    }

    private fun notification(state: ReadAloud.State): Notification {
        val playing = state.status != ReadAloud.Status.PAUSED
        val toggle = Notification.Action.Builder(
            Icon.createWithResource(this, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play),
            if (playing) "Pause" else "Play",
            serviceIntent(ACTION_TOGGLE, 1),
        ).build()
        val stop = Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
            "Stop",
            serviceIntent(ACTION_STOP, 2),
        ).build()
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_read_aloud)
            .setContentTitle(chapterTitle(state))
            .setContentText(readAloud.book?.title.orEmpty())
            .setContentIntent(openApp())
            .setOngoing(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(toggle)
            .addAction(stop)
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1))
            .build()
    }

    private fun goForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        val channel = NotificationChannel(CHANNEL, "Reading aloud", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Controls for a book being read aloud"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** Back to the app as it was left, rather than a new copy of it. */
    private fun openApp(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun serviceIntent(action: String, code: Int): PendingIntent = PendingIntent.getService(
        this,
        code,
        Intent(this, ReadAloudService::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    // ── Audio focus ──────────────────────────────────────────────────────────

    private fun requestFocus() {
        if (focus != null) return
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            // Speech under other audio is hard to follow, so it pauses rather than ducks.
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener { change ->
                when (change) {
                    AudioManager.AUDIOFOCUS_LOSS -> {
                        pausedForInterruption = false
                        readAloud.pause()
                        abandonFocus()
                    }
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                        if (readAloud.state.value.status == ReadAloud.Status.PLAYING) {
                            pausedForInterruption = true
                            readAloud.pause()
                        }
                    }
                    AudioManager.AUDIOFOCUS_GAIN -> {
                        if (pausedForInterruption) readAloud.resume()
                        pausedForInterruption = false
                    }
                }
            }
            .build()
        if (audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) focus = request
    }

    private fun abandonFocus() {
        focus?.let { audio.abandonAudioFocusRequest(it) }
        focus = null
    }

    private fun setNoisy(on: Boolean) {
        if (on == noisyRegistered) return
        noisyRegistered = on
        if (on) {
            ContextCompat.registerReceiver(
                this, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } else {
            unregisterReceiver(noisy)
        }
    }

    private companion object {
        const val CHANNEL = "read_aloud"
        const val NOTIFICATION_ID = 0x5241
        const val ACTION_TOGGLE = "com.rekindle.app.readaloud.TOGGLE"
        const val ACTION_STOP = "com.rekindle.app.readaloud.STOP"
    }
}
