// FFmpeg.wasm bridge for the web build.
// ============================================================================
// Video story editing (trim, rotate, speed, mute, overlay-mux) runs through
// ffmpeg_kit_flutter_new natively, which has no web build at all — there is
// no ffmpeg binary to shell out to inside a browser. ffmpeg.wasm is the
// closest equivalent: a real ffmpeg build compiled to WebAssembly, run
// entirely client-side (nothing uploaded anywhere just to be edited).
//
// Loaded lazily — only the first time a web visitor actually edits a video —
// so nobody pays the ~31 MB core download just to browse the feed or chat.
// The single-threaded core is used deliberately: the multi-threaded one needs
// SharedArrayBuffer, which needs Cross-Origin-Opener/Embedder-Policy headers
// on every response from this origin, which Cloudflare Pages doesn't set by
// default. Slower, but it works with zero server config.
//
// Talks to Dart through one function, sigmaFFmpegRun, called via
// dart:js_interop from lib/services/ffmpeg_web.dart. Everything else (module
// loading, the virtual FS, cleanup) is kept on this side so the Dart code
// only ever deals with bytes in, bytes out.
(function () {
  const CORE_VERSION = '0.12.10';
  const UTIL_VERSION = '0.12.1';

  let ffmpegPromise = null;

  async function loadFFmpeg() {
    if (ffmpegPromise) return ffmpegPromise;
    ffmpegPromise = (async () => {
      const [{ FFmpeg }, { toBlobURL }] = await Promise.all([
        import(`https://cdn.jsdelivr.net/npm/@ffmpeg/ffmpeg@${CORE_VERSION}/dist/esm/index.js`),
        import(`https://cdn.jsdelivr.net/npm/@ffmpeg/util@${UTIL_VERSION}/dist/esm/index.js`),
      ]);
      const ffmpeg = new FFmpeg();
      const base = `https://cdn.jsdelivr.net/npm/@ffmpeg/core@${CORE_VERSION}/dist/esm`;
      const loadPromise = ffmpeg.load({
        coreURL: await toBlobURL(`${base}/ffmpeg-core.js`, 'text/javascript'),
        wasmURL: await toBlobURL(`${base}/ffmpeg-core.wasm`, 'application/wasm'),
        // ffmpeg.wasm spawns its own Worker internally, from a URL — browsers
        // refuse `new Worker(crossOriginURL)` outright (this is what actually
        // threw "SecurityError: Failed to construct 'Worker'"), so that
        // script needs the same blob-URL treatment as the core/wasm above.
        classWorkerURL: await toBlobURL(
          `https://cdn.jsdelivr.net/npm/@ffmpeg/ffmpeg@${CORE_VERSION}/dist/esm/worker.js`,
          'text/javascript'
        ),
      });
      // A 31 MB wasm core plus its own worker spinning up can legitimately
      // take a while on a slow connection — but if the worker never answers
      // at all (blocked by an extension, an embedder that restricts nested
      // workers, whatever), load() hangs forever with no error and no way
      // for the caller to know. Bound it, and reset ffmpegPromise on timeout
      // so a retry (e.g. the visitor reopening the trim screen) gets a fresh
      // attempt instead of an already-poisoned promise.
      const timeout = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('ffmpeg.wasm load timed out')), 90000)
      );
      try {
        await Promise.race([loadPromise, timeout]);
      } catch (e) {
        ffmpegPromise = null;
        throw e;
      }
      return ffmpeg;
    })();
    return ffmpegPromise;
  }

  // fileEntries: [[name, Uint8Array], ...] — everything ffmpeg needs to read
  //   (the source clip, an overlay PNG, a music track — whatever this
  //   particular command takes as -i inputs).
  // argsJson: JSON-encoded array of CLI args, e.g. '["-i","in.mp4","-t","5","out.mp4"]'
  //   — a plain array survives the Dart↔JS boundary far more predictably than
  //   trying to interop a real JS array of strings from Dart.
  // outputName: the file ffmpeg was told to produce, read back after exec().
  window.sigmaFFmpegRun = async function (fileEntries, argsJson, outputName) {
    const ffmpeg = await loadFFmpeg();
    const args = JSON.parse(argsJson);
    const written = [];
    try {
      for (const [name, bytes] of fileEntries) {
        await ffmpeg.writeFile(name, bytes);
        written.push(name);
      }
      await ffmpeg.exec(args);
      const data = await ffmpeg.readFile(outputName);
      // readFile can return a string for text output; ffmpeg's media outputs
      // are always binary, so this is just defensive.
      return data instanceof Uint8Array ? data : new Uint8Array(0);
    } finally {
      // The virtual FS persists across calls (one FFmpeg instance is reused
      // for the whole session) — clean up so a long editing session doesn't
      // slowly fill it with every intermediate file.
      for (const name of written) {
        try { await ffmpeg.deleteFile(name); } catch (_) {}
      }
      try { await ffmpeg.deleteFile(outputName); } catch (_) {}
    }
  };

  // Lets a picked/recorded clip preview instantly in a <video> element (via
  // video_player_web) without ever touching ffmpeg — a blob: URL over the
  // bytes already held in memory, zero-copy, no base64 round trip.
  window.sigmaBytesToObjectURL = function (bytes, mimeType) {
    const blob = new Blob([bytes], { type: mimeType || 'video/mp4' });
    return URL.createObjectURL(blob);
  };
  window.sigmaRevokeObjectURL = function (url) {
    try { URL.revokeObjectURL(url); } catch (_) {}
  };
})();
