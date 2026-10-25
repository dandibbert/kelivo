import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final services = <ChatService>[];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_new_entry_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SandboxPathResolver.debugSetDirs(
      docsDir: tempDir.path,
      supportDir: tempDir.path,
    );
  });

  tearDown(() async {
    for (final service in services) {
      await service.close();
    }
    services.clear();
    await Hive.close();
    SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<ChatService> open() async {
    final service = ChatService();
    services.add(service);
    await service.init();
    return service;
  }

  test('an unsent new chat is reused by the next new chat', () async {
    final service = await open();
    final first = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    await service.discardUsedNewEntry('default', presetMessageCount: 0);
    final second = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    expect(second.id, first.id);
  });

  test('a new chat that already has messages is not reused', () async {
    final service = await open();
    final first = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    // A message sent without a composer submission (external link, share).
    await service.addMessage(
      conversationId: first.id,
      role: 'user',
      content: 'hello',
    );
    await service.addMessage(
      conversationId: first.id,
      role: 'assistant',
      content: 'hi',
      modelId: 'm',
    );

    await service.discardUsedNewEntry('default', presetMessageCount: 0);
    final next = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    expect(next.id, isNot(first.id));
  });

  test('assistant preset messages do not count as use', () async {
    final service = await open();
    final first = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    for (final role in ['user', 'assistant']) {
      await service.addMessage(
        conversationId: first.id,
        role: role,
        content: 'preset',
      );
    }
    await service.discardUsedNewEntry('default', presetMessageCount: 2);
    final again = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    expect(again.id, first.id);

    await service.addMessage(
      conversationId: first.id,
      role: 'user',
      content: 'a real message',
    );
    await service.discardUsedNewEntry('default', presetMessageCount: 2);
    await service.discardUsedNewEntry('default', presetMessageCount: 0);
    final next = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    expect(next.id, isNot(first.id));
  });

  test('a used entry left in the database is dropped after restart', () async {
    var service = await open();
    final used = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    await service.addMessage(
      conversationId: used.id,
      role: 'user',
      content: 'hello',
    );
    await service.composerDrafts!.flush();
    expect(service.composerDrafts!.newEntry('default')?.id, used.id);

    await service.close();
    services.remove(service);
    await Hive.close();

    service = await open();
    // The stale registration is still loaded from the database.
    expect(service.composerDrafts!.newEntry('default')?.id, used.id);

    await service.discardUsedNewEntry('default', presetMessageCount: 0);
    final next = await service.createDraftConversation(
      title: 'Chat',
      assistantId: 'default',
      reuseNewEntry: true,
    );
    expect(next.id, isNot(used.id));
    // The used conversation itself is untouched and no longer registered.
    expect(service.getConversation(used.id), isNotNull);
    expect(service.composerDrafts!.isNewEntry(used.id), isFalse);
    expect(service.composerDrafts!.newEntry('default')?.id, next.id);
  });
}
