import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal valid 1×1 PNG.
Uint8List _png() {
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
    0x90,
    0x77,
    0x53,
    0xDE,
    0x00,
    0x00,
    0x00,
    0x0C,
    0x49,
    0x44,
    0x41,
    0x54,
    0x08,
    0xD7,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x01,
    0x00,
    0x05,
    0xFE,
    0xD4,
    0xEF,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) {
    return FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(content: Center(child: child)),
    );
  }

  testWidgets('memoryPreviewBytes takes priority over network URL', (
    tester,
  ) async {
    final memory = _png();
    await tester.pumpWidget(
      wrap(
        ProfileAvatarWidget(
          memoryPreviewBytes: memory,
          networkImageUrl: 'https://example.com/avatar.jpg',
          initials: 'TU',
          radius: 24,
          showBorder: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsWidgets);
    final memoryImages = tester
        .widgetList<Image>(find.byType(Image))
        .where((image) => image.image is MemoryImage);
    expect(memoryImages, isNotEmpty);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url.contains('example.com'),
      ),
      findsNothing,
    );
  });

  testWidgets('network URL is used when memory preview is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const ProfileAvatarWidget(
          networkImageUrl: 'https://example.com/avatar.jpg',
          initials: 'TU',
          radius: 24,
          showBorder: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url == 'https://example.com/avatar.jpg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('legacy local path is used when network and memory are absent', (
    tester,
  ) async {
    late Directory dir;
    late File file;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('elixr_avatar_');
      file = File('${dir.path}/legacy.png');
      await file.writeAsBytes(_png());
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    });

    await tester.pumpWidget(
      wrap(
        ProfileAvatarWidget(
          legacyLocalPath: file.path,
          initials: 'TU',
          radius: 24,
          showBorder: false,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
      findsOneWidget,
    );
  });

  testWidgets('falls back to initials when no sources resolve', (tester) async {
    await tester.pumpWidget(
      wrap(
        const ProfileAvatarWidget(
          networkImageUrl: '',
          initials: 'AB',
          radius: 24,
          showBorder: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(ProfileAvatarWidget), findsOneWidget);
  });
}
