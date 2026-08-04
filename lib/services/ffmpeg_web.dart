/// FfmpegWeb — the ffmpeg.wasm bridge used by StoryVideoTrimWebScreen.
///
/// Conditional export rather than a plain import: dart:js_interop's
/// conversion extensions only exist when actually compiling for web, so
/// ffmpeg_web_impl.dart (which uses them) can't be part of the compiled
/// output for Android/iOS/`flutter test` at all — not "won't run there",
/// literally won't compile there. Every OTHER file in the app imports this
/// file, never the two behind it, and gets whichever one actually matches
/// the current build target.
library;

export 'ffmpeg_web_stub.dart'
    if (dart.library.js_interop) 'ffmpeg_web_impl.dart';
