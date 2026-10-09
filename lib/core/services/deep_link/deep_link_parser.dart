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
    final query = _queryOf(uri);
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

    final temporary = _parseBool(query['temporary']);
    if (temporary == null && query.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    return NewChatDeepLinkAction(
      assistantId: _clean(query['assistant']),
      assistantName: _clean(query['assistant_name']),
      temporary: temporary ?? false,
    );
  }

  DeepLinkAction _parseCompose(Uri uri) {
    final query = _queryOf(uri);
    final target = _parseTarget(query['target']);
    if (target == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final temporary = _parseBool(query['temporary']);
    if (temporary == null && query.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final assistantId = _clean(query['assistant']);
    final assistantName = _clean(query['assistant_name']);
    final conflict = _validateNewTargetOnlyOptions(
      target,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
    if (conflict != null) return conflict;

    final insert = switch (query['insert']?.toLowerCase()) {
      null || '' || 'replace' => DeepLinkInsertMode.replace,
      'append' => DeepLinkInsertMode.append,
      _ => null,
    };
    if (insert == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }

    final text = query['text'] ?? '';
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
    final query = _queryOf(uri);
    final target = _parseTarget(query['target']);
    if (target == null) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final temporary = _parseBool(query['temporary']);
    if (temporary == null && query.containsKey('temporary')) {
      return const InvalidDeepLinkAction('invalid_parameter');
    }
    final assistantId = _clean(query['assistant']);
    final assistantName = _clean(query['assistant_name']);
    final conflict = _validateNewTargetOnlyOptions(
      target,
      assistantId: assistantId,
      assistantName: assistantName,
      temporary: temporary ?? false,
    );
    if (conflict != null) return conflict;

    final text = query['text'];
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

  /// Reads the query leniently so hand-written links that mix encoded and raw
  /// text still work. Unlike [Uri.queryParameters]:
  ///  * `+` stays a literal plus (RFC 3986). Spaces are `%20` or raw spaces.
  ///  * A `%` that does not start a valid escape stays literal, and invalid
  ///    UTF-8 is replaced instead of throwing.
  static Map<String, String> _queryOf(Uri uri) {
    final result = <String, String>{};
    final raw = uri.query;
    if (raw.isEmpty) return result;
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = _decode(eq < 0 ? pair : pair.substring(0, eq));
      final value = eq < 0 ? '' : _decode(pair.substring(eq + 1));
      result[key] = value;
    }
    return result;
  }

  static String _decode(String input) {
    if (!input.contains('%')) return input;
    final bytes = <int>[];
    var literalStart = 0;
    var i = 0;
    while (i < input.length) {
      if (input.codeUnitAt(i) == 0x25) {
        final hi = i + 1 < input.length ? _hex(input.codeUnitAt(i + 1)) : -1;
        final lo = i + 2 < input.length ? _hex(input.codeUnitAt(i + 2)) : -1;
        if (hi >= 0 && lo >= 0) {
          bytes.addAll(utf8.encode(input.substring(literalStart, i)));
          bytes.add(hi * 16 + lo);
          i += 3;
          literalStart = i;
          continue;
        }
      }
      i++;
    }
    bytes.addAll(utf8.encode(input.substring(literalStart)));
    return utf8.decode(bytes, allowMalformed: true);
  }

  static int _hex(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  bool _textFits(String text) => utf8.encode(text).length <= maxTextBytes;
}
