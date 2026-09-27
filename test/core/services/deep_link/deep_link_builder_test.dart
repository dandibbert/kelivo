import 'package:Kelivo/core/services/deep_link/deep_link_action.dart';
import 'package:Kelivo/core/services/deep_link/deep_link_builder.dart';
import 'package:Kelivo/core/services/deep_link/deep_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = DeepLinkParser();

  DeepLinkAction roundTrip(DeepLinkAction action) =>
      parser.parse(Uri.parse(DeepLinkBuilder.build(action)))!;

  test('omits default parameters', () {
    expect(
      DeepLinkBuilder.build(const OpenChatDeepLinkAction()),
      'kelivo://v1/chat',
    );
    expect(
      DeepLinkBuilder.build(const NewChatDeepLinkAction()),
      'kelivo://v1/chat/new',
    );
    expect(
      DeepLinkBuilder.build(
        const ComposeDeepLinkAction(
          text: '',
          target: DeepLinkTarget.current(),
          insertMode: DeepLinkInsertMode.replace,
        ),
      ),
      'kelivo://v1/compose',
    );
    expect(
      DeepLinkBuilder.build(const OpenSettingsDeepLinkAction()),
      'kelivo://v1/settings',
    );
  });

  test('percent-encodes text instead of using plus signs', () {
    final link = DeepLinkBuilder.build(
      const SendDeepLinkAction(
        text: 'a+b = c & 你好',
        target: DeepLinkTarget.newConversation(),
        assistantId: 'id 1',
        temporary: true,
      ),
    );
    expect(link, isNot(contains(' ')));
    expect(link, contains('text=a%2Bb%20%3D%20c%20%26%20'));

    final action = roundTrip(
      const SendDeepLinkAction(
        text: 'a+b = c & 你好',
        target: DeepLinkTarget.newConversation(),
        assistantId: 'id 1',
        temporary: true,
      ),
    );
    expect(action, isA<SendDeepLinkAction>());
    final send = action as SendDeepLinkAction;
    expect(send.text, 'a+b = c & 你好');
    expect(send.target.type, DeepLinkTargetType.newConversation);
    expect(send.assistantId, 'id 1');
    expect(send.temporary, isTrue);
  });

  test('round-trips every buildable action', () {
    final newChat =
        roundTrip(
              const NewChatDeepLinkAction(assistantId: 'a1', temporary: true),
            )
            as NewChatDeepLinkAction;
    expect(newChat.assistantId, 'a1');
    expect(newChat.temporary, isTrue);

    final conversation =
        roundTrip(const OpenConversationDeepLinkAction('c/1'))
            as OpenConversationDeepLinkAction;
    expect(conversation.conversationId, 'c/1');

    final compose =
        roundTrip(
              const ComposeDeepLinkAction(
                text: 'line1\nline2',
                target: DeepLinkTarget.conversation('c1'),
                insertMode: DeepLinkInsertMode.append,
              ),
            )
            as ComposeDeepLinkAction;
    expect(compose.text, 'line1\nline2');
    expect(compose.target.type, DeepLinkTargetType.conversation);
    expect(compose.target.conversationId, 'c1');
    expect(compose.insertMode, DeepLinkInsertMode.append);

    for (final section in DeepLinkParser.settingsSections) {
      final settings =
          roundTrip(OpenSettingsDeepLinkAction(section: section))
              as OpenSettingsDeepLinkAction;
      expect(settings.section, section);
    }

    final assistant =
        roundTrip(const OpenAssistantDeepLinkAction('a1'))
            as OpenAssistantDeepLinkAction;
    expect(assistant.assistantId, 'a1');
  });

  test('refuses to build invalid actions', () {
    expect(
      () => DeepLinkBuilder.build(const InvalidDeepLinkAction('x')),
      throwsArgumentError,
    );
  });
}
