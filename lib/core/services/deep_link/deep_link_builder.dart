import 'deep_link_action.dart';
import 'deep_link_parser.dart';

enum DeepLinkKind {
  openChat,
  newChat,
  openConversation,
  compose,
  send,
  settings,
  assistant,
}

enum DeepLinkAssistantRef { id, name }

/// Everything the generator form can express. Fields that the selected
/// [kind] does not use are ignored by [DeepLinkBuilder.build].
class DeepLinkSpec {
  const DeepLinkSpec({
    this.kind = DeepLinkKind.newChat,
    this.text = '',
    this.target = const DeepLinkTarget.current(),
    this.insertMode = DeepLinkInsertMode.replace,
    this.assistantRef = DeepLinkAssistantRef.id,
    this.assistantValue = '',
    this.temporary = false,
    this.conversationId = '',
    this.settingsSection,
  });

  final DeepLinkKind kind;
  final String text;
  final DeepLinkTarget target;
  final DeepLinkInsertMode insertMode;
  final DeepLinkAssistantRef assistantRef;
  final String assistantValue;
  final bool temporary;

  /// Only for [DeepLinkKind.openConversation].
  final String conversationId;

  /// Only for [DeepLinkKind.settings]; `null` opens the settings home.
  final String? settingsSection;
}

class DeepLinkBuildResult {
  const DeepLinkBuildResult.ok(String this.url) : errorCode = null;
  const DeepLinkBuildResult.error(String this.errorCode) : url = null;

  final String? url;

  /// A parser error code, or `missing_text` / `missing_conversation` /
  /// `missing_assistant` when a required field is empty.
  final String? errorCode;
}

class DeepLinkBuilder {
  const DeepLinkBuilder._();

  static const DeepLinkParser _parser = DeepLinkParser();

  /// Settings sections understood by [DeepLinkParser], in display order.
  static const List<String> settingsSections = <String>[
    'display',
    'assistants',
    'models',
    'providers',
    'search',
    'tts',
    'mcp',
    'world-book',
    'quick-phrases',
    'instruction-injection',
    'network',
    'backup',
    'storage',
    'about',
    'stats',
    'logs',
  ];

  /// Builds the URL and round-trips it through [DeepLinkParser], so a link
  /// that the app would reject is never offered to the user.
  static DeepLinkBuildResult build(DeepLinkSpec spec) {
    final assistant = spec.assistantValue.trim();
    final conversationId = spec.conversationId.trim();
    final targetId = spec.target.conversationId?.trim() ?? '';

    final String path;
    final query = <String, String>{};
    switch (spec.kind) {
      case DeepLinkKind.openChat:
        path = 'chat';
      case DeepLinkKind.newChat:
        path = 'chat/new';
        _putNewChatOptions(query, spec, assistant);
      case DeepLinkKind.openConversation:
        if (conversationId.isEmpty) {
          return const DeepLinkBuildResult.error('missing_conversation');
        }
        path = 'chat/${Uri.encodeComponent(conversationId)}';
      case DeepLinkKind.compose:
      case DeepLinkKind.send:
        final isSend = spec.kind == DeepLinkKind.send;
        if (isSend && spec.text.trim().isEmpty) {
          return const DeepLinkBuildResult.error('missing_text');
        }
        path = isSend ? 'send' : 'compose';
        if (spec.text.isNotEmpty) query['text'] = spec.text;
        switch (spec.target.type) {
          case DeepLinkTargetType.current:
            break;
          case DeepLinkTargetType.newConversation:
            query['target'] = 'new';
            _putNewChatOptions(query, spec, assistant);
          case DeepLinkTargetType.conversation:
            if (targetId.isEmpty) {
              return const DeepLinkBuildResult.error('missing_conversation');
            }
            query['target'] = targetId;
        }
        if (!isSend && spec.insertMode == DeepLinkInsertMode.append) {
          query['insert'] = 'append';
        }
      case DeepLinkKind.settings:
        final section = spec.settingsSection;
        path = section == null ? 'settings' : 'settings/$section';
      case DeepLinkKind.assistant:
        if (assistant.isEmpty) {
          return const DeepLinkBuildResult.error('missing_assistant');
        }
        path = 'assistant/${Uri.encodeComponent(assistant)}';
    }

    final url = StringBuffer('kelivo://v1/$path');
    var separator = '?';
    query.forEach((key, value) {
      // `+` is not decoded as a space by every consumer; %20 always is.
      final encoded = Uri.encodeQueryComponent(value).replaceAll('+', '%20');
      url.write('$separator$key=$encoded');
      separator = '&';
    });

    final built = url.toString();
    final action = _parser.parse(Uri.parse(built));
    if (action == null) {
      return const DeepLinkBuildResult.error('unsupported_route');
    }
    if (action is InvalidDeepLinkAction) {
      return DeepLinkBuildResult.error(action.code);
    }
    return DeepLinkBuildResult.ok(built);
  }

  static void _putNewChatOptions(
    Map<String, String> query,
    DeepLinkSpec spec,
    String assistant,
  ) {
    if (assistant.isNotEmpty) {
      query[spec.assistantRef == DeepLinkAssistantRef.id
              ? 'assistant'
              : 'assistant_name'] =
          assistant;
    }
    if (spec.temporary) query['temporary'] = '1';
  }
}
