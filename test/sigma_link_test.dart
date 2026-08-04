import 'package:flutter_test/flutter_test.dart';

import 'package:sigma_social_app/services/sigma_link.dart';

/// The whole point of SigmaLink is that building and parsing can't drift apart,
/// so the central test is the round trip: every link we hand out must be one we
/// can open.
void main() {
  test('every kind round-trips through its own URL', () {
    for (final kind in SigmaLinkKind.values) {
      final built = SigmaLink(kind, 'abc123');
      final parsed = SigmaLink.parse(Uri.parse(built.url));
      expect(parsed, isNotNull, reason: '${kind.name} produced an unparseable URL');
      expect(parsed!.kind, kind);
      expect(parsed.id, 'abc123');
    }
  });

  test('canonical shapes are what we expect', () {
    expect(SigmaLink(SigmaLinkKind.profile, 'aka4').url,
        'https://sigmacta.pages.dev/u/aka4');
    expect(SigmaLink(SigmaLinkKind.post, 'p1').url,
        'https://sigmacta.pages.dev/post/p1');
    expect(SigmaLink(SigmaLinkKind.story, 's1').url,
        'https://sigmacta.pages.dev/story/s1');
    expect(SigmaLink(SigmaLinkKind.group, 'g1').url,
        'https://sigmacta.pages.dev/g/g1');
  });

  test('legacy @username links still resolve', () {
    // Already out in the world inside chat histories — breaking them would
    // silently kill links people have already sent.
    final l = SigmaLink.parse(Uri.parse('https://sigmacta.pages.dev/@aka4'));
    expect(l?.kind, SigmaLinkKind.profile);
    expect(l?.id, 'aka4');
  });

  test('legacy /profile/ and /user/ resolve', () {
    for (final p in ['profile', 'user']) {
      final l = SigmaLink.parse(Uri.parse('https://sigmacta.pages.dev/$p/aka4'));
      expect(l?.kind, SigmaLinkKind.profile, reason: p);
      expect(l?.id, 'aka4');
    }
  });

  test('a raw storage URL is NOT one of ours', () {
    // This is the bug the whole class exists to prevent: a Supabase .mp4 was
    // being shared as if it were a Sigmacta link.
    final l = SigmaLink.parse(
        Uri.parse('https://abc.supabase.co/storage/v1/object/public/x/story.mp4'));
    expect(l, isNull);
  });

  test('junk and incomplete paths are rejected, not guessed', () {
    for (final u in [
      'https://sigmacta.pages.dev/',
      'https://sigmacta.pages.dev/post',
      'https://sigmacta.pages.dev/post/',
      'https://sigmacta.pages.dev/unknown/1',
      'https://sigmacta.pages.dev/@',
    ]) {
      expect(SigmaLink.parse(Uri.parse(u)), isNull, reason: u);
    }
  });

  test('trailing slashes and extra segments do not break parsing', () {
    final l = SigmaLink.parse(Uri.parse('https://sigmacta.pages.dev/post/p1/'));
    expect(l?.kind, SigmaLinkKind.post);
    expect(l?.id, 'p1');
  });
}
