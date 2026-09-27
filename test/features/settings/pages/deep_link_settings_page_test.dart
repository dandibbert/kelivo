import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/features/settings/pages/deep_link_settings_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';

import '../../../support/business_test_harness.dart';

void main() {
  late SettingsProvider settings;
  late AssistantProvider assistants;
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // Created inside the test zone so their async loads finish during pumps.
    settings = SettingsProvider(createBusinessTestPreferences());
    assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    addTearDown(settings.dispose);
    addTearDown(assistants.dispose);
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: assistants),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DeepLinkSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('builds and copies a new-conversation link', (tester) async {
    await pumpPage(tester);
    expect(find.text('kelivo://v1/chat/new'), findsOneWidget);

    await tester.tap(find.text('Temporary Chat'));
    await tester.pumpAndSettle();
    expect(find.text('kelivo://v1/chat/new?temporary=1'), findsOneWidget);

    await tester.tap(find.text('Copy Link'));
    await tester.pumpAndSettle();
    expect(clipboard, 'kelivo://v1/chat/new?temporary=1');
    // Let the confirmation snackbar expire.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('send links need a message', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send Message').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter a message to generate the link.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hi there');
    await tester.pumpAndSettle();
    expect(find.text('kelivo://v1/send?text=hi%20there'), findsOneWidget);
    // Auto-send is off by default, so the page warns that it only fills text.
    expect(
      find.text('Auto-send is off, so this link will only fill the input box.'),
      findsOneWidget,
    );
  });
}
