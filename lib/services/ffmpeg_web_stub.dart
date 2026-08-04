import 'dart:typed_data';

/// Native-target stand-in for ffmpeg_web_impl.dart — see ffmpeg_web.dart for
/// why this exists. dart:js_interop's conversion extensions (String.toJS
/// etc.) don't exist outside a web compilation, so the real implementation
/// can't even be IN the compiled output for Android/iOS/tests, regardless of
/// the kIsWeb check every caller already has. This file is what conditional
/// export swaps in there instead: same API, never actually reachable at
/// runtime (StoryVideoTrimWebScreen is only ever pushed behind `if (kIsWeb)`
/// in home_screen.dart), so throwing is fine — it documents "this should be
/// unreachable" better than a silent no-op would.
class FfmpegWeb {
  FfmpegWeb._();

  static Future<Uint8List?> run({
    required Map<String, Uint8List> files,
    required List<String> args,
    required String outputName,
  }) async =>
      throw UnsupportedError('FfmpegWeb is web-only');

  static String bytesToObjectUrl(Uint8List bytes, {String mimeType = 'video/mp4'}) =>
      throw UnsupportedError('FfmpegWeb is web-only');

  static void revokeObjectUrl(String url) =>
      throw UnsupportedError('FfmpegWeb is web-only');
}
