import 'dart:async';

import 'package:flutter/services.dart';

import 'deep_link_action.dart';
import 'deep_link_parser.dart';

class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();

  static const MethodChannel _channel = MethodChannel('app.deep_link');
  static const Duration _dedupeWindow = Duration(seconds: 1);

  final DeepLinkParser _parser = const DeepLinkParser();
  final StreamController<DeepLinkAction> _controller =
      StreamController<DeepLinkAction>.broadcast();
  final List<DeepLinkAction> _pending = <DeepLinkAction>[];

  bool _initialized = false;
  String? _lastRawUrl;
  DateTime? _lastReceivedAt;

  Stream<DeepLinkAction> get actions => _controller.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onUrl') return;
      final raw = call.arguments?.toString();
      if (raw != null) _handleRawUrl(raw);
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitialUrl');
      if (initial != null) _handleRawUrl(initial);
    } on MissingPluginException {
      // Deep links currently use the native iOS bridge. Other platforms can
      // add the same channel without changing the Dart parser/consumer.
    } on PlatformException {
      // A native bridge failure should never prevent the app from starting.
    }
  }

  List<DeepLinkAction> drainPendingActions() {
    if (_pending.isEmpty) return const <DeepLinkAction>[];
    final actions = List<DeepLinkAction>.of(_pending);
    _pending.clear();
    return actions;
  }

  void _handleRawUrl(String raw) {
    final now = DateTime.now();
    if (_lastRawUrl == raw &&
        _lastReceivedAt != null &&
        now.difference(_lastReceivedAt!) <= _dedupeWindow) {
      return;
    }
    _lastRawUrl = raw;
    _lastReceivedAt = now;

    final uri = Uri.tryParse(raw);
    if (uri == null) {
      _emit(const InvalidDeepLinkAction('invalid_parameter'));
      return;
    }
    final action = _parser.parse(uri);
    if (action != null) _emit(action);
  }

  void _emit(DeepLinkAction action) {
    if (_controller.hasListener) {
      _controller.add(action);
    } else {
      _pending.add(action);
    }
  }
}
