enum DeepLinkTargetType { current, newConversation, conversation }

enum DeepLinkInsertMode { replace, append }

class DeepLinkTarget {
  const DeepLinkTarget._(this.type, this.conversationId);

  const DeepLinkTarget.current()
    : this._(DeepLinkTargetType.current, null);

  const DeepLinkTarget.newConversation()
    : this._(DeepLinkTargetType.newConversation, null);

  const DeepLinkTarget.conversation(String conversationId)
    : this._(DeepLinkTargetType.conversation, conversationId);

  final DeepLinkTargetType type;
  final String? conversationId;
}

sealed class DeepLinkAction {
  const DeepLinkAction();
}

class OpenChatDeepLinkAction extends DeepLinkAction {
  const OpenChatDeepLinkAction();
}

class NewChatDeepLinkAction extends DeepLinkAction {
  const NewChatDeepLinkAction({
    this.assistantId,
    this.assistantName,
    this.temporary = false,
  });

  final String? assistantId;
  final String? assistantName;
  final bool temporary;
}

class OpenConversationDeepLinkAction extends DeepLinkAction {
  const OpenConversationDeepLinkAction(this.conversationId);

  final String conversationId;
}

class ComposeDeepLinkAction extends DeepLinkAction {
  const ComposeDeepLinkAction({
    required this.text,
    required this.target,
    required this.insertMode,
    this.assistantId,
    this.assistantName,
    this.temporary = false,
  });

  final String text;
  final DeepLinkTarget target;
  final DeepLinkInsertMode insertMode;
  final String? assistantId;
  final String? assistantName;
  final bool temporary;
}

class SendDeepLinkAction extends DeepLinkAction {
  const SendDeepLinkAction({
    required this.text,
    required this.target,
    this.assistantId,
    this.assistantName,
    this.temporary = false,
  });

  final String text;
  final DeepLinkTarget target;
  final String? assistantId;
  final String? assistantName;
  final bool temporary;
}

class OpenSettingsDeepLinkAction extends DeepLinkAction {
  const OpenSettingsDeepLinkAction({this.section});

  final String? section;
}

class OpenAssistantDeepLinkAction extends DeepLinkAction {
  const OpenAssistantDeepLinkAction(this.assistantId);

  final String assistantId;
}

class InvalidDeepLinkAction extends DeepLinkAction {
  const InvalidDeepLinkAction(this.code);

  final String code;
}
