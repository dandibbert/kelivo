import 'package:Kelivo/core/providers/assistant_provider.dart';
import 'package:Kelivo/core/providers/settings_provider.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/features/settings/pages/deep_link_generator_page.dart';
import 'package:Kelivo/l10n/app_localizations.dart';
import 'package:Kelivo/shared/widgets/snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/business_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppLocalizations> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = SettingsProvider(createBusinessTestPreferences());
    final assistants = AssistantProvider(
      preferences: createBusinessTestPreferences(),
    );
    await settings.loaded;
    await assistants.loaded;
    final chat = ChatService();
    addTearDown(chat.close);
    addTearDown(settings.dispose);
    addTearDown(assistants.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<AssistantProvider>.value(value: assistants),
          ChangeNotifierProvider<ChatService>.value(value: chat),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AppSnackBarOverlay(child: DeepLinkGeneratorPage()),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
  }

  testWidgets('builds links live and reports missing input', (tester) async {
    final l10n = await pumpPage(tester);
    expect(find.text('kelivo://v1/chat/new'), findsOneWidget);

    // Switch the action to "send".
    await tester.tap(find.text(l10n.aboutPageDeepLinkNewChat));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.aboutPageDeepLinkSend).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.deepLinkGenNeedText), findsOneWidget);
    expect(find.text(l10n.deepLinkGenAutoSendOff), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Hello world');
    await tester.pump();
    expect(find.text('kelivo://v1/send?text=Hello%20world'), findsOneWidget);

    // Target a new conversation: assistant / temporary options appear.
    await tester.tap(find.text(l10n.deepLinkGenTargetCurrent));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.deepLinkGenTargetNew).last);
    await tester.pumpAndSettle();
    expect(
      find.text('kelivo://v1/send?text=Hello%20world&target=new'),
      findsOneWidget,
    );
    expect(find.text(l10n.deepLinkGenTemporary), findsOneWidget);
  });

  testWidgets('copy puts the link on the clipboard', (tester) async {
    final l10n = await pumpPage(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.tap(find.text(l10n.deepLinkGenCopy));
    await tester.pump();
    expect(copied, 'kelivo://v1/chat/new');
    expect(find.text(l10n.deepLinkGenCopied), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.deepLinkGenCopyMarkdown));
    await tester.pump();
    expect(copied, '[${l10n.aboutPageDeepLinkNewChat}](kelivo://v1/chat/new)');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
