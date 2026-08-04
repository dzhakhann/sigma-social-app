/// Canonical Sigmacta links — ONE place that both builds and parses them.
///
/// Sharing and routing used to be unrelated code: share produced whatever URL
/// was handy (including raw Supabase `.mp4` links, which open a bare video in a
/// browser), while the router understood only two shapes. Anything either side
/// learned, the other didn't. Keeping construction and parsing in one file makes
/// "we can share a link we can't open" impossible by construction.
library;

enum SigmaLinkKind { profile, post, story, reel, music, podcast, group }

class SigmaLink {
  final SigmaLinkKind kind;

  /// Username for [SigmaLinkKind.profile], otherwise the entity id.
  final String id;

  const SigmaLink(this.kind, this.id);

  /// The public host. Everything canonical lives under this one origin so a
  /// single Android App Links / iOS Universal Links association covers the lot.
  static const host = 'sigmacta.pages.dev';

  static const _path = {
    SigmaLinkKind.profile: 'u',
    SigmaLinkKind.post: 'post',
    SigmaLinkKind.story: 'story',
    SigmaLinkKind.reel: 'reel',
    SigmaLinkKind.music: 'music',
    SigmaLinkKind.podcast: 'podcast',
    SigmaLinkKind.group: 'g',
  };

  /// The URL to share. Always https and always this host — never a storage URL:
  /// a direct media link bypasses the app entirely, can't show a caption or an
  /// author, and stops working when the object is moved.
  String get url => 'https://$host/${_path[kind]}/$id';

  @override
  String toString() => url;

  /// Parses an incoming link, or null if it isn't one of ours.
  ///
  /// Accepts `/@username` as well as `/u/username` — the older share format is
  /// already out in the world in chat histories and must keep working.
  static SigmaLink? parse(Uri uri) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;

    if (segs[0].startsWith('@') && segs[0].length > 1) {
      return SigmaLink(SigmaLinkKind.profile, segs[0].substring(1));
    }
    if (segs.length < 2) return null;

    final id = segs[1];
    if (id.isEmpty) return null;
    for (final e in _path.entries) {
      if (e.value == segs[0]) return SigmaLink(e.key, id);
    }
    // Legacy: /profile/<username> and /user/<username> were both used before
    // /u/ settled.
    if (segs[0] == 'profile' || segs[0] == 'user') {
      return SigmaLink(SigmaLinkKind.profile, id);
    }
    return null;
  }
}
