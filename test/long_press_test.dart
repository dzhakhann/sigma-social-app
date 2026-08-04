import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sigma_social_app/theme/brutal_theme.dart';
import 'package:sigma_social_app/widgets/chat_context_menu.dart';

/// Pins down the long-press-to-open-menu path, which regressed twice.
void main() {
  testWidgets('MessageLongPress fires with the bubble rect', (tester) async {
    Offset? origin;
    Size? size;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: MessageLongPress(
            onMenu: (o, s) {
              origin = o;
              size = s;
            },
            child: Container(width: 200, height: 60, color: Colors.blue),
          ),
        ),
      ),
    ));

    await tester.longPress(find.byType(Container));
    await tester.pumpAndSettle();

    expect(origin, isNotNull, reason: 'onMenu never fired');
    expect(size, isNotNull);
    // The rect must be the bubble's, not the whole screen — that's the whole
    // point of measuring the widget's own RenderBox.
    expect(size!.width, 200);
    expect(size!.height, 60);
  });

  testWidgets('long-press still fires inside a scrollable list',
      (tester) async {
    var fired = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView.builder(
          itemCount: 10,
          itemBuilder: (_, i) => MessageLongPress(
            onMenu: (_, __) => fired++,
            child: SizedBox(
              height: 60,
              child: Text('msg $i'),
            ),
          ),
        ),
      ),
    ));

    await tester.longPress(find.text('msg 3'));
    await tester.pumpAndSettle();
    expect(fired, 1, reason: 'scroll gesture swallowed the long press');
  });


  testWidgets('showChatContextMenu actually renders its actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildBrutalTheme(kThemes[0]),
      home: AppScope(
        config: const AppConfig(),
        child: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showChatContextMenu(
                  ctx,
                  origin: const Offset(20, 200),
                  size: const Size(180, 50),
                  isOwn: true,
                  c: kThemes[0].c,
                  bubble: const SizedBox(width: 180, height: 50),
                  actions: [
                    MenuAction(Icons.reply_rounded, 'Reply',
                        kThemes[0].c.ink, () {}),
                  ],
                  quickReactions: const ['👍'],
                  onReact: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget, reason: 'menu did not render');
  });

  testWidgets('long-press wins over nested tap targets inside the bubble',
      (tester) async {
    var menu = 0, innerTap = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MessageLongPress(
          onMenu: (_, __) => menu++,
          // Mirrors a real bubble: link text, a reaction chip and a quote tap
          // all sit inside and each registers its own recognizer.
          child: Column(children: [
            GestureDetector(
                onTap: () => innerTap++, child: const Text('quote')),
            InkWell(onTap: () => innerTap++, child: const Text('reaction')),
            const Text('body'),
          ]),
        ),
      ),
    ));

    await tester.longPress(find.text('reaction'));
    await tester.pumpAndSettle();
    expect(menu, 1, reason: 'nested tap target swallowed the long press');
    expect(innerTap, 0, reason: 'long press must not also fire the tap');
  });
}
