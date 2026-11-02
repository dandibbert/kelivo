import 'dart:io';

import 'package:Kelivo/core/services/diagnostics/breadcrumbs.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

Future<void> _pumpApp(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(navigatorKey: rootNavigatorKey, home: const Scaffold()),
);

void main() {
  late Directory dir;
  late File log;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('breadcrumbs');
    log = File(p.join(dir.path, 'breadcrumbs.log'));
    PathProviderPlatform.instance = _Paths(dir.path);
  });
  tearDown(() {
    Breadcrumbs.stopForTest();
    dir.deleteSync(recursive: true);
  });

  testWidgets('shows the last steps after an unclean exit', (tester) async {
    log.writeAsStringSync(
      '10:00:00.000 START\n10:00:01.000 ca:generate begin\n',
    );
    await _pumpApp(tester);
    await tester.runAsync(Breadcrumbs.start);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('上次异常退出前的最后步骤'), findsOneWidget);
    expect(find.textContaining('ca:generate begin'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(log.readAsStringSync(), contains('START'));
  });

  testWidgets('stays quiet after a clean pause', (tester) async {
    log.writeAsStringSync('10:00:00.000 START\n10:00:01.000 PAUSED\n');
    await _pumpApp(tester);
    await tester.runAsync(Breadcrumbs.start);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1300)),
    );
    await tester.pump();
    expect(find.text('上次异常退出前的最后步骤'), findsNothing);
  });

  testWidgets('marks are written through immediately', (tester) async {
    await tester.runAsync(Breadcrumbs.start);
    Breadcrumbs.mark('step one');
    Breadcrumbs.markSampled('k', 'sampled', first: 1, every: 1000);
    Breadcrumbs.markSampled('k', 'sampled', first: 1, every: 1000);
    final text = log.readAsStringSync();
    expect(text, contains('step one'));
    expect('sampled'.allMatches(text).length, 1);
  });
}
