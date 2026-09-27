import 'deep_link_action.dart';

/// Builds `kelivo://v1/...` links that [DeepLinkParser] parses back into the
/// same action. Default values are omitted so links stay short.
class DeepLinkBuilder {
  const DeepLinkBuilder._();

  static String build(DeepLinkAction action) {
    return switch (action) {
      OpenChatDeepLinkAction() => _link(['chat']),
      NewChatDeepLinkAction() => _link(
        ['chat', 'new'],
        {
          'assistant': action.assistantId,
          'assistant_name': action.assistantName,
          'temporary': action.temporary ? '1' : null,
        },
      ),
      OpenConversationDeepLinkAction() => _link([
        'chat',
        action.conversationId,
      ]),
      ComposeDeepLinkAction() => _link(
        ['compose'],
        {
          'text': action.text.isEmpty ? null : action.text,
          'insert': action.insertMode == DeepLinkInsertMode.append
              ? 'append'
              : null,
          ..._targetParams(
            action.target,
            assistantId: action.assistantId,
            assistantName: action.assistantName,
            temporary: action.temporary,
          ),
        },
      ),
      SendDeepLinkAction() => _link(
        ['send'],
        {
          'text': action.text,
          ..._targetParams(
            action.target,
            assistantId: action.assistantId,
            assistantName: action.assistantName,
            temporary: action.temporary,
          ),
        },
      ),
      OpenSettingsDeepLinkAction() => _link([
        'settings',
        if (action.section != null) action.section!,
      ]),
      OpenAssistantDeepLinkAction() => _link(['assistant', action.assistantId]),
      InvalidDeepLinkAction() => throw ArgumentError.value(
        action,
        'action',
        'Invalid deep link actions cannot be built',
      ),
    };
  }

  static Map<String, String?> _targetParams(
    DeepLinkTarget target, {
    required String? assistantId,
    required String? assistantName,
    required bool temporary,
  }) {
    return {
      'target': switch (target.type) {
        DeepLinkTargetType.current => null,
        DeepLinkTargetType.newConversation => 'new',
        DeepLinkTargetType.conversation => target.conversationId,
      },
      'assistant': assistantId,
      'assistant_name': assistantName,
      'temporary': temporary ? '1' : null,
    };
  }

  // Uri(queryParameters:) encodes spaces as '+', which some launchers pass
  // through literally; percent-encoding every component is unambiguous.
  static String _link(
    List<String> segments, [
    Map<String, String?> query = const {},
  ]) {
    final path = segments.map(Uri.encodeComponent).join('/');
    final params = query.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value!)}')
        .join('&');
    return params.isEmpty ? 'kelivo://v1/$path' : 'kelivo://v1/$path?$params';
  }
}
