import 'dart:convert';

import 'deep_link_action.dart';

class DeepLinkParser {
  const DeepLinkParser();

  static const int maxTextBytes = 16 * 1024;

  DeepLinkAction? parse(Uri uri) {
    if (uri.scheme.toLowerCase() != 'kelivo') return null;
    if (uri.host.toLowerCase() != 'v1') return null;

    final segments = uri.pathSegments.where((e) => e.isNotEmpty).toList();
    if (segments.isEmpty) {
      return const InvalidDeepLinkAction('unsupported_route');
    }

    switch (segments.first) {
      case 'chat':
        return _parseChat(uri, segments);
      case 'compose':
        if (segments.length != 1) {
          return const InvalidDeepLinkAction('unsupported_route');
        }
        return _parseCompose(uri);
      case 'send':
        if (segments.length != 1) {
          return const InvalidDeepLinkAction('unsupported_route');
        }
        return _parseSend(uri);
      case 'settings':
        return _parseSettings(segments);
      case 'assistant':
        return _parseAssistant(segments);
      default:
        return const InvalidDeepLinkAction('unsupported_route');
    }
  }

  DeepLinkAction _parseChat(Uri uri, List<String> segments) {
    if (segments.length == 1) return const OpenChatDeepLinkAction();
    if (segments.length != 2) {
      return const InvalidDeepLinkAction('unsupported_route');
    }

    final second = segments[1];
    if (second != 'new') {
      return second.trim().isEmpty
          ? const InvalidDeepLinkAction('invalid_parameter')
          : OpenConversationDeepLinkAction(second);
    }

    final temporary = _parseBool(uri.queryParameters['temporary']);
    if (temporary == null && uri.queryParameters.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    return NewChatDeepLinkAction(
      assistantId: _clean(uri.queryParameters['assistant']),
      assistantName: _clean(uri.queryParameters['assistant_name']),
      temporary: temporary ?? false,
    );
  }

  DeepLinkAction _parseCompose(Uri uri) {
    final target = _parseTarget(uri.queryParameters['target']);
    if (target == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final temporary = _parseBool(uri.queryParameters['temporary']);
    if (temporary == null && uri.queryParameters.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final assistantId = _clean(uri.queryParameters['assistant']);
    final assistantName = _clean(uri.queryParameters['assistant_name']);
    final conflict = _validateNewTargetOnlyOptions(
      target,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
    if (conflict != null) return conflict;

    final insert = switch (uri.queryParameters['insert']?.toLowerCase()) {
      null || '' || 'replace' => DeepLinkInsertMode.replace,
      'append' => DeepLinkInsertMode.append,
      _ => null,
    };
    if (insert == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }

    final text = uri.queryParameters['text'] ?? '';
    if (!_textFits(text)) {
      return const InvalidDeepLinkAction('payload_too_large');
    }
    return ComposeDeepLinkAction(
      text: text,
      target: target,
      insertMode: insert,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
  }

  DeepLinkAction _parseSend(Uri uri) {
    final target = _parseTarget(uri.queryParameters['target']);
    if (target == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final temporary = _parseBool(uri.queryParameters['temporary']);
    if (temporary == null && uri.queryParameters.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final assistantId = _clean(uri.queryParameters['assistant']);
    final assistantName = _clean(uri.queryParameters['assistant_name']);
    final conflict = _validateNewTargetOnlyOptions(
      target,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
    if (conflict != null) return conflict;

    final text = uri.queryParameters['text'];
    if (text == null || text.trim().isEmpty) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    if (!_textFits(text)) {
      return const InvalidDeepLinkAction('payload_too_large');
    }
    return SendDeepLinkAction(
      text: text,
      target: target,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
  }

  DeepLinkAction _parseSettings(List<String> segments) {
    if (segments.length == 1) {
      return const OpenSettingsDeepLinkAction();
    }
    if (segments.length != 2) {
      return const InvalidDeepLinkAction('unsupported_route');
    }
    const supported = <String>{
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
    };
    final section = segments[1];
    return supported.contains(section)
        ? OpenSettingsDeepLinkAction(section: section)
        : const InvalidDeepLinkAction('unsupported_route');
  }

  DeepLinkAction _parseAssistant(List<String> segments) {
    if (segments.length != 2 || segments[1].trim().isEmpty) {
      return const InvalidDeepLinkAction('unsupported_route');
    }
    return OpenAssistantDeepLinkAction(segments[1]);
  }

  InvalidDeepLinkAction? _validateNewTargetOnlyOptions(
    DeepLinkTarget target, {
    required String? assistantId,
    required String? assistantName,
    required bool temporary,
  }) {
    if (target.type == DeepLinkTargetType.newConversation) return null;
    if (assistantId != null || assistantName != null) {
      return const InvalidDeepLinkAction('assistant_target_conflict');
    }
    if (temporary) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    return null;
  }

  DeepLinkTarget? _parseTarget(String? raw) {
    final value = _clean(raw);
    if (value == null || value == 'current') {
      return const DeepLinkTarget.current();
    }
    if (value == 'new') return const DeepLinkTarget.newConversation();
    return DeepLinkTarget.conversation(value);
  }

  bool? _parseBool(String? raw) {
    if (raw == null) return false;
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
        return true;
      case '0':
      case 'false':
      case '':
        return false;
      default:
        return null;
    }
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _textFits(String text) => utf8.encode(text).length <= maxTextBytes;
}
