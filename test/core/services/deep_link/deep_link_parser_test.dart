import 'package:Kelivo/core/services/deep_link/deep_link_action.dart';
import 'package:Kelivo/core/services/deep_link/deep_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = DeepLinkParser();

  test('parses chat routes', () {
    expect(
      parser.parse(Uri.parse('kelivo://v1/chat')),
      isA<OpenChatDeepLinkAction>(),
    );

    final newChat = parser.parse(
      Uri.parse('kelivo://v1/chat/new?assistant=a1&temporary=1'),
    );
    expect(newChat, isA<NewChatDeepLinkAction>());
    final action = newChat! as NewChatDeepLinkAction;
    expect(action.assistantId, 'a1');
    expect(action.temporary, isTrue);

    final conversation = parser.parse(Uri.parse('kelivo://v1/chat/c-123'));
    expect(conversation, isA<OpenConversationDeepLinkAction>());
    expect(
      (conversation! as OpenConversationDeepLinkAction).conversationId,
      'c-123',
    );
  });

  test('parses compose query and target', () {
    final parsed = parser.parse(
      Uri.parse(
        'kelivo://v1/compose?target=new&assistant_name=Translator&temporary=1&insert=append&text=Hello%20world',
      ),
    );
    expect(parsed, isA<ComposeDeepLinkAction>());
    final action = parsed! as ComposeDeepLinkAction;
    expect(action.text, 'Hello world');
    expect(action.target.type, DeepLinkTargetType.newConversation);
    expect(action.assistantName, 'Translator');
    expect(action.temporary, isTrue);
    expect(action.insertMode, DeepLinkInsertMode.append);
  });

  test('rejects assistant on an existing target', () {
    final parsed = parser.parse(
      Uri.parse('kelivo://v1/send?target=c-1&assistant=a1&text=hello'),
    );
    expect(parsed, isA<InvalidDeepLinkAction>());
    expect(
      (parsed! as InvalidDeepLinkAction).code,
      'assistant_target_conflict',
    );
  });

  test('send requires text', () {
    final parsed = parser.parse(Uri.parse('kelivo://v1/send?target=new'));
    expect(parsed, isA<InvalidDeepLinkAction>());
    expect((parsed! as InvalidDeepLinkAction).code, 'invalid_parameter');
  });

  test('rejects oversized payloads', () {
    final text = List<String>.filled(
      DeepLinkParser.maxTextBytes + 1,
      'a',
    ).join();
    final uri = Uri(
      scheme: 'kelivo',
      host: 'v1',
      path: '/compose',
      queryParameters: <String, String>{'text': text},
    );
    final parsed = parser.parse(uri);
    expect(parsed, isA<InvalidDeepLinkAction>());
    expect((parsed! as InvalidDeepLinkAction).code, 'payload_too_large');
  });

  test('ignores non-public kelivo callbacks', () {
    expect(parser.parse(Uri.parse('kelivo://oauth-return?code=1')), isNull);
  });

  group('lenient query decoding', () {
    String composeText(String url) =>
        (parser.parse(Uri.parse(url))! as ComposeDeepLinkAction).text;

    test('mixes encoded and raw text', () {
      expect(
        composeText('kelivo://v1/compose?text=hello%20world 你好'),
        'hello world 你好',
      );
      expect(composeText('kelivo://v1/compose?text=%E4%BD%A0好'), '你好');
      expect(composeText('kelivo://v1/compose?text=a b%0Ac'), 'a b\nc');
    });

    test('keeps a raw plus and decodes an escaped one', () {
      expect(
        composeText('kelivo://v1/compose?text=C++ and C%2B%2B'),
        'C++ and C++',
      );
    });

    test('keeps a stray percent literal', () {
      expect(composeText('kelivo://v1/compose?text=100% sure'), '100% sure');
      expect(composeText('kelivo://v1/compose?text=100%'), '100%');
      expect(composeText('kelivo://v1/compose?text=%4'), '%4');
      expect(composeText('kelivo://v1/compose?text=%zz%41'), '%zzA');
    });

    test('invalid utf-8 does not throw', () {
      expect(composeText('kelivo://v1/compose?text=50%E4%BD'), '50\uFFFD');
    });

    test('non-BMP characters survive mixed encoding', () {
      expect(composeText('kelivo://v1/compose?text=😀%20😀'), '😀 😀');
    });

    test('equals signs and empty values', () {
      expect(composeText('kelivo://v1/compose?text=a=b'), 'a=b');
      expect(composeText('kelivo://v1/compose?text='), '');
      expect(
        (parser.parse(Uri.parse('kelivo://v1/compose?text&insert=append'))!
                as ComposeDeepLinkAction)
            .insertMode,
        DeepLinkInsertMode.append,
      );
    });
  });
}
