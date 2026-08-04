import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

/// Dart side of the ffmpeg.wasm bridge — see web/ffmpeg_bridge.js for why
/// this exists (ffmpeg_kit_flutter_new has no web build at all) and how the
/// JS side works. This file only ever deals in bytes; the video/overlay
/// filesystem, the wasm core, all of it stays on the JS side.
@JS('sigmaFFmpegRun')
external JSPromise _sigmaFFmpegRun(
  JSArray<JSArray<JSAny?>> fileEntries,
  JSString argsJson,
  JSString outputName,
);

@JS('sigmaBytesToObjectURL')
external JSString _bytesToObjectURL(JSUint8Array bytes, JSString mimeType);

@JS('sigmaRevokeObjectURL')
external void _revokeObjectURL(JSString url);

class FfmpegWeb {
  FfmpegWeb._();

  /// Runs one ffmpeg command against in-memory files. [files] are written to
  /// ffmpeg's virtual filesystem under their map key before [args] (a normal
  /// ffmpeg CLI argument list, e.g. `['-i','in.mp4','-t','5','out.mp4']`)
  /// executes; the file named [outputName] is read back afterward. Returns
  /// null on any failure — the wasm core failing to load, a bad command, an
  /// unsupported codec — so callers can fall back the same way the native
  /// path already falls back when FFmpegKit's return code isn't success.
  static Future<Uint8List?> run({
    required Map<String, Uint8List> files,
    required List<String> args,
    required String outputName,
  }) async {
    try {
      final entries = files.entries
          .map((e) => <JSAny?>[e.key.toJS, e.value.toJS].toJS)
          .toList()
          .toJS;
      final promise = _sigmaFFmpegRun(
        entries,
        jsonEncode(args).toJS,
        outputName.toJS,
      );
      final result = await promise.toDart;
      final bytes = (result as JSUint8Array?)?.toDart;
      return (bytes == null || bytes.isEmpty) ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// A blob: URL over [bytes] — for previewing a picked/trimmed clip in a
  /// video_player controller without writing anything to ffmpeg's (or any)
  /// filesystem. Caller owns the URL and should [revokeObjectUrl] it once the
  /// controller is disposed, or the browser keeps the backing memory alive.
  static String bytesToObjectUrl(Uint8List bytes, {String mimeType = 'video/mp4'}) =>
      _bytesToObjectURL(bytes.toJS, mimeType.toJS).toDart;

  static void revokeObjectUrl(String url) => _revokeObjectURL(url.toJS);
}
