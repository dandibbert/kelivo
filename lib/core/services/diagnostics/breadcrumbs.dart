import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/widgets/snackbar.dart';

/// Crash breadcrumbs: every step is appended and flushed synchronously, so the
/// last lines survive a native crash or a kill by the system. After an
/// unclean exit the next launch shows them in a dialog.
class Breadcrumbs with WidgetsBindingObserver {
  Breadcrumbs._();

  static const _maxBytes = 512 * 1024;
  static final Breadcrumbs _instance = Breadcrumbs._();
  static RandomAccessFile? _file;
  static int _written = 0;
  static List<String>? _previous;
  static final Map<String, int> _counters = {};
  static Timer? _heartbeat;

  /// Call once, right after the binding is initialized.
  static Future<void> start() async {
    _previous = null;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'breadcrumbs.log'));
      if (await file.exists()) {
        final lines = await file.readAsLines();
        final clean =
            lines.isNotEmpty &&
            (lines.last.endsWith(' PAUSED') || lines.last.endsWith(' EXIT'));
        if (lines.isNotEmpty && !clean) {
          _previous = lines.length > 60
              ? lines.sublist(lines.length - 60)
              : lines;
        }
      }
      _file = await file.open(mode: FileMode.write);
    } catch (_) {
      return;
    }
    mark('START');
    WidgetsBinding.instance.addObserver(_instance);
    _startHeartbeat();
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      mark(
        'FLUTTER_ERROR ${_clip(details.exceptionAsString())} '
        '| ${_clip(details.stack?.toString().split('\n').take(4).join(' / '))}',
      );
      if (previousOnError != null) {
        previousOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      mark(
        'ASYNC_ERROR ${_clip(error.toString())} '
        '| ${_clip(stack.toString().split('\n').take(4).join(' / '))}',
      );
      return previousPlatform?.call(error, stack) ?? false;
    };
    _scheduleReport();
  }

  @visibleForTesting
  static void stopForTest() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(_instance);
    _file?.closeSync();
    _file = null;
    _counters.clear();
  }

  /// Appends a line. Never throws.
  static void mark(String text) {
    final file = _file;
    if (file == null || _written > _maxBytes) return;
    try {
      final now = DateTime.now().toIso8601String().substring(11, 23);
      final line = '$now $text\n';
      file.writeStringSync(line);
      file.flushSync();
      _written += line.length;
    } catch (_) {}
  }

  /// Marks the first [first] calls for [key], then every [every]th.
  static void markSampled(
    String key,
    String text, {
    int first = 3,
    int every = 50,
  }) {
    final count = _counters.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (count <= first || count % every == 0) mark('$text #$count');
  }

  static String _clip(String? text) {
    if (text == null) return '';
    final flat = text.replaceAll('\n', ' ');
    return flat.length > 240 ? flat.substring(0, 240) : flat;
  }

  static void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 1), (_) {
      mark('tick rss=${(ProcessInfo.currentRss / 1048576).round()}MB');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      mark('RESUMED');
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _heartbeat?.cancel();
      mark('PAUSED');
    }
  }

  static void _scheduleReport() {
    final lines = _previous;
    if (lines == null) return;
    var attempts = 0;
    Timer.periodic(const Duration(seconds: 1), (timer) {
      final context = rootNavigatorKey.currentContext;
      if (context == null || !context.mounted) {
        if (++attempts > 60) timer.cancel();
        return;
      }
      timer.cancel();
      final text = lines.join('\n');
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('上次异常退出前的最后步骤'),
          content: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontSize: 10, fontFamily: 'Menlo'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
              child: const Text('复制'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }
}
