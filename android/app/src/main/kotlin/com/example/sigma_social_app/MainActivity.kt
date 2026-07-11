package com.example.sigma_social_app

import com.ryanheise.audioservice.AudioServiceActivity

// just_audio_background requires the activity to be an AudioServiceActivity,
// otherwise playback silently fails on Android (stuck at 00:00).
class MainActivity: AudioServiceActivity()
