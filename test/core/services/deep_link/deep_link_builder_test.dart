import 'package:Kelivo/core/services/deep_link/deep_link_action.dart';
import 'package:Kelivo/core/services/deep_link/deep_link_builder.dart';
import 'package:Kelivo/core/services/deep_link/deep_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = DeepLinkParser();

  String urlOf(DeepLinkSpec spec) {
    final result = DeepLinkBuilder.build(spec);
    expect(result.errorCode, isNull);
    return result.url!;
  }

  DeepLinkAction parsed(String url) => parser.parse(Uri.parse(url))!;

  test('simple routes', () {
    expect(
      urlOf(const DeepLinkSpec(kind: DeepLinkKind.openChat)),
      'kelivo://v1/chat',
    );
    expect(
      urlOf(const DeepLinkSpec(kind: DeepLinkKind.newChat)),
      'kelivo://v1/chat/new',
    );
    expect(
      urlOf(const DeepLinkSpec(kind: DeepLinkKind.settings)),
      'kelivo://v1/settings',
    );
    expect(
      urlOf(
        const DeepLinkSpec(kind: DeepLinkKind.settings, settingsSection: 'mcp'),
      ),
      'kelivo://v1/settings/mcp',
    );
  });

  test('every settings section round-trips', () {
    for (final section in DeepLinkBuilder.settingsSections) {
      final action = parsed(
        urlOf(
          DeepLinkSpec(kind: DeepLinkKind.settings, settingsSection: section),
        ),
      );
      expect((action as OpenSettingsDeepLinkAction).section, section);
    }
  });

  test('new chat options', () {
    final byId =
        parsed(
              urlOf(
                const DeepLinkSpec(
                  kind: DeepLinkKind.newChat,
                  assistantValue: 'a 1',
                  temporary: true,
                ),
              ),
            )
            as NewChatDeepLinkAction;
    expect(byId.assistantId, 'a 1');
    expect(byId.temporary, isTrue);

    final byName =
        parsed(
              urlOf(
                const DeepLinkSpec(
                  kind: DeepLinkKind.newChat,
                  assistantRef: DeepLinkAssistantRef.name,
                  assistantValue: '翻译 & 润色',
                ),
              ),
            )
            as NewChatDeepLinkAction;
    expect(byName.assistantName, '翻译 & 润色');
    expect(byName.assistantId, isNull);
  });

  test('open conversation and assistant encode path segments', () {
    final conversation =
        parsed(
              urlOf(
                const DeepLinkSpec(
                  kind: DeepLinkKind.openConversation,
                  conversationId: 'c/1 ?',
                ),
              ),
            )
            as OpenConversationDeepLinkAction;
    expect(conversation.conversationId, 'c/1 ?');

    final assistant =
        parsed(
              urlOf(
                const DeepLinkSpec(
                  kind: DeepLinkKind.assistant,
                  assistantValue: 'x y',
                ),
              ),
            )
            as OpenAssistantDeepLinkAction;
    expect(assistant.assistantId, 'x y');
  });

  test('compose keeps text, unicode and reserved characters', () {
    const text = 'Hi there\n你好 & 100% = ok? #1';
    final url = urlOf(
      const DeepLinkSpec(
        kind: DeepLinkKind.compose,
        text: text,
        insertMode: DeepLinkInsertMode.append,
        target: DeepLinkTarget.newConversation(),
        assistantValue: 'Translator',
        assistantRef: DeepLinkAssistantRef.name,
        temporary: true,
      ),
    );
    expect(url, isNot(contains('+')));
    final action = parsed(url) as ComposeDeepLinkAction;
    expect(action.text, text);
    expect(action.insertMode, DeepLinkInsertMode.append);
    expect(action.target.type, DeepLinkTargetType.newConversation);
    expect(action.assistantName, 'Translator');
    expect(action.temporary, isTrue);
  });

  test('compose may be empty, send may not', () {
    expect(
      urlOf(const DeepLinkSpec(kind: DeepLinkKind.compose)),
      'kelivo://v1/compose',
    );
    expect(
      DeepLinkBuilder.build(
        const DeepLinkSpec(kind: DeepLinkKind.send, text: '  '),
      ).errorCode,
      'missing_text',
    );
  });

  test('send to a specific conversation', () {
    final action =
        parsed(
              urlOf(
                const DeepLinkSpec(
                  kind: DeepLinkKind.send,
                  text: 'go',
                  target: DeepLinkTarget.conversation('c-9'),
                  // Ignored: new-conversation-only options.
                  assistantValue: 'a1',
                  temporary: true,
                ),
              ),
            )
            as SendDeepLinkAction;
    expect(action.target.conversationId, 'c-9');
    expect(action.assistantId, isNull);
    expect(action.temporary, isFalse);
  });

  test('missing required fields', () {
    expect(
      DeepLinkBuilder.build(
        const DeepLinkSpec(kind: DeepLinkKind.openConversation),
      ).errorCode,
      'missing_conversation',
    );
    expect(
      DeepLinkBuilder.build(
        const DeepLinkSpec(kind: DeepLinkKind.assistant),
      ).errorCode,
      'missing_assistant',
    );
    expect(
      DeepLinkBuilder.build(
        const DeepLinkSpec(
          kind: DeepLinkKind.compose,
          target: DeepLinkTarget.conversation(' '),
        ),
      ).errorCode,
      'missing_conversation',
    );
  });

  test('oversized text is rejected by the parser', () {
    final result = DeepLinkBuilder.build(
      DeepLinkSpec(
        kind: DeepLinkKind.compose,
        text: 'a' * (DeepLinkParser.maxTextBytes + 1),
      ),
    );
    expect(result.errorCode, 'payload_too_large');
  });
}
