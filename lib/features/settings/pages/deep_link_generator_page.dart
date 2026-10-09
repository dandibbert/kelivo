import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../core/services/deep_link/deep_link_action.dart';
import '../../../core/services/deep_link/deep_link_builder.dart';
import '../../../core/services/deep_link/deep_link_parser.dart';
import '../../../core/services/deep_link/deep_link_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/ios_settings_rows.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/option_sheet.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_semantic_colors.dart';

enum _TargetMode { current, newConversation, conversation }

/// Form that builds `kelivo://v1/...` links covering every route and option
/// understood by [DeepLinkParser].
class DeepLinkGeneratorPage extends StatefulWidget {
  const DeepLinkGeneratorPage({super.key});

  @override
  State<DeepLinkGeneratorPage> createState() => _DeepLinkGeneratorPageState();
}

class _DeepLinkGeneratorPageState extends State<DeepLinkGeneratorPage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _conversationId = TextEditingController();
  final TextEditingController _assistantValue = TextEditingController();

  DeepLinkKind _kind = DeepLinkKind.newChat;
  _TargetMode _targetMode = _TargetMode.current;
  DeepLinkInsertMode _insertMode = DeepLinkInsertMode.replace;
  DeepLinkAssistantRef _assistantRef = DeepLinkAssistantRef.id;
  bool _temporary = false;
  String? _settingsSection;

  @override
  void dispose() {
    _text.dispose();
    _conversationId.dispose();
    _assistantValue.dispose();
    super.dispose();
  }

  bool get _usesMessage =>
      _kind == DeepLinkKind.compose || _kind == DeepLinkKind.send;

  bool get _targetsNewConversation =>
      _kind == DeepLinkKind.newChat ||
      (_usesMessage && _targetMode == _TargetMode.newConversation);

  DeepLinkSpec get _spec {
    final conversationId = _conversationId.text;
    return DeepLinkSpec(
      kind: _kind,
      text: _text.text,
      target: switch (_targetMode) {
        _TargetMode.current => const DeepLinkTarget.current(),
        _TargetMode.newConversation => const DeepLinkTarget.newConversation(),
        _TargetMode.conversation => DeepLinkTarget.conversation(conversationId),
      },
      insertMode: _insertMode,
      assistantRef: _assistantRef,
      assistantValue: _assistantValue.text,
      temporary: _temporary,
      conversationId: conversationId,
      settingsSection: _settingsSection,
    );
  }

  void _update(VoidCallback change) => setState(change);

  String _kindLabel(AppLocalizations l10n, DeepLinkKind kind) => switch (kind) {
    DeepLinkKind.openChat => l10n.aboutPageDeepLinkChat,
    DeepLinkKind.newChat => l10n.aboutPageDeepLinkNewChat,
    DeepLinkKind.openConversation => l10n.aboutPageDeepLinkOpenConversation,
    DeepLinkKind.compose => l10n.aboutPageDeepLinkCompose,
    DeepLinkKind.send => l10n.aboutPageDeepLinkSend,
    DeepLinkKind.settings => l10n.aboutPageDeepLinkSettings,
    DeepLinkKind.assistant => l10n.aboutPageDeepLinkAssistant,
  };

  IconData _kindIcon(DeepLinkKind kind) => switch (kind) {
    DeepLinkKind.openChat => Lucide.MessageSquare,
    DeepLinkKind.newChat => Lucide.MessageCirclePlus,
    DeepLinkKind.openConversation => Lucide.MessagesSquare,
    DeepLinkKind.compose => Lucide.FilePen,
    DeepLinkKind.send => Lucide.Play,
    DeepLinkKind.settings => Lucide.Settings,
    DeepLinkKind.assistant => Lucide.Bot,
  };

  String _sectionLabel(AppLocalizations l10n, String? section) =>
      switch (section) {
        null => l10n.deepLinkGenSettingsHome,
        'display' => l10n.settingsPageDisplay,
        'assistants' => l10n.settingsPageAssistant,
        'models' => l10n.settingsPageDefaultModel,
        'providers' => l10n.settingsPageProviders,
        'search' => l10n.settingsPageSearch,
        'tts' => l10n.settingsPageTts,
        'mcp' => l10n.settingsPageMcp,
        'world-book' => l10n.settingsPageWorldBook,
        'quick-phrases' => l10n.settingsPageQuickPhrase,
        'instruction-injection' => l10n.settingsPageInstructionInjection,
        'network' => l10n.settingsPageNetworkProxy,
        'backup' => l10n.settingsPageBackup,
        'storage' => l10n.settingsPageChatStorage,
        'about' => l10n.settingsPageAbout,
        'stats' => l10n.settingsPageStatistics,
        'logs' => l10n.settingsPageLogs,
        _ => section,
      };

  String _errorMessage(AppLocalizations l10n, String code) => switch (code) {
    'missing_text' => l10n.deepLinkGenNeedText,
    'missing_conversation' => l10n.deepLinkGenNeedConversation,
    'missing_assistant' => l10n.deepLinkGenNeedAssistant,
    'payload_too_large' => l10n.deepLinkPayloadTooLarge,
    'assistant_target_conflict' => l10n.deepLinkAssistantTargetConflict,
    'unsupported_route' => l10n.deepLinkUnsupportedRoute,
    _ => l10n.deepLinkFailed,
  };

  Future<void> _pickKind(AppLocalizations l10n) async {
    final picked = await showOptionSheet<DeepLinkKind>(
      context,
      title: l10n.deepLinkGenSectionAction,
      selected: _kind,
      items: [
        for (final kind in DeepLinkKind.values)
          OptionSheetItem(
            value: kind,
            icon: _kindIcon(kind),
            label: _kindLabel(l10n, kind),
          ),
      ],
    );
    if (picked != null) _update(() => _kind = picked);
  }

  Future<void> _pickTarget(AppLocalizations l10n) async {
    final picked = await showOptionSheet<_TargetMode>(
      context,
      title: l10n.deepLinkGenTarget,
      selected: _targetMode,
      items: [
        OptionSheetItem(
          value: _TargetMode.current,
          label: l10n.deepLinkGenTargetCurrent,
        ),
        OptionSheetItem(
          value: _TargetMode.newConversation,
          label: l10n.deepLinkGenTargetNew,
        ),
        OptionSheetItem(
          value: _TargetMode.conversation,
          label: l10n.deepLinkGenTargetConversation,
        ),
      ],
    );
    if (picked != null) _update(() => _targetMode = picked);
  }

  Future<void> _pickInsertMode(AppLocalizations l10n) async {
    final picked = await showOptionSheet<DeepLinkInsertMode>(
      context,
      title: l10n.deepLinkGenInsertMode,
      selected: _insertMode,
      items: [
        OptionSheetItem(
          value: DeepLinkInsertMode.replace,
          label: l10n.deepLinkGenInsertReplace,
        ),
        OptionSheetItem(
          value: DeepLinkInsertMode.append,
          label: l10n.deepLinkGenInsertAppend,
        ),
      ],
    );
    if (picked != null) _update(() => _insertMode = picked);
  }

  Future<void> _pickAssistantRef(AppLocalizations l10n) async {
    final assistants = context.read<AssistantProvider>();
    final picked = await showOptionSheet<DeepLinkAssistantRef>(
      context,
      title: l10n.deepLinkGenAssistantRef,
      selected: _assistantRef,
      items: [
        OptionSheetItem(
          value: DeepLinkAssistantRef.id,
          label: l10n.deepLinkGenRefId,
        ),
        OptionSheetItem(
          value: DeepLinkAssistantRef.name,
          label: l10n.deepLinkGenRefName,
        ),
      ],
    );
    if (picked == null || picked == _assistantRef) return;
    // The stored value is an ID or a name; switch it with the reference type.
    final current = assistants.getById(_assistantValue.text.trim());
    final byName = assistants.assistants
        .where((a) => a.name == _assistantValue.text.trim())
        .firstOrNull;
    final match = current ?? byName;
    _update(() {
      _assistantRef = picked;
      if (match != null) {
        _assistantValue.text = picked == DeepLinkAssistantRef.id
            ? match.id
            : match.name;
      }
    });
  }

  Future<void> _pickAssistant(
    AppLocalizations l10n, {
    required bool allowDefault,
    required bool forceId,
  }) async {
    final assistants = context.read<AssistantProvider>().assistants;
    const defaultKey = '';
    final picked = await showOptionSheet<String>(
      context,
      title: l10n.deepLinkGenAssistantPick,
      items: [
        if (allowDefault)
          OptionSheetItem(
            value: defaultKey,
            icon: Lucide.Bot,
            label: l10n.deepLinkGenAssistantDefault,
          ),
        for (final a in assistants)
          OptionSheetItem(value: a.id, icon: Lucide.Bot, label: a.name),
      ],
    );
    if (picked == null) return;
    _update(() {
      if (picked == defaultKey) {
        _assistantValue.clear();
        return;
      }
      final assistant = assistants.firstWhere((a) => a.id == picked);
      _assistantValue.text = forceId || _assistantRef == DeepLinkAssistantRef.id
          ? assistant.id
          : assistant.name;
    });
  }

  Future<void> _pickConversation(AppLocalizations l10n) async {
    final conversations = context.read<ChatService>().getAllConversations();
    if (conversations.isEmpty) {
      showAppSnackBar(context, message: l10n.deepLinkGenConversationEmpty);
      return;
    }
    final picked = await showOptionSheet<String>(
      context,
      title: l10n.deepLinkGenConversationPick,
      selected: _conversationId.text.trim(),
      items: [
        for (final c in conversations)
          OptionSheetItem(
            value: c.id,
            label: c.title.trim().isEmpty ? c.id : c.title,
            subtitle: c.id,
          ),
      ],
    );
    if (picked != null) _update(() => _conversationId.text = picked);
  }

  Future<void> _pickSettingsSection(AppLocalizations l10n) async {
    // `null` means the settings home, so wrap the choice to tell it apart
    // from a dismissed sheet.
    final picked = await showOptionSheet<({String? section})>(
      context,
      title: l10n.deepLinkGenSettingsSection,
      selected: (section: _settingsSection),
      items: [
        OptionSheetItem(
          value: (section: null),
          label: l10n.deepLinkGenSettingsHome,
        ),
        for (final section in DeepLinkBuilder.settingsSections)
          OptionSheetItem(
            value: (section: section),
            label: _sectionLabel(l10n, section),
            subtitle: section,
          ),
      ],
    );
    if (picked != null) _update(() => _settingsSection = picked.section);
  }

  Future<void> _copy(String value) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: l10n.deepLinkGenCopied,
      type: NotificationType.success,
    );
  }

  String _markdownLink(AppLocalizations l10n, String url) {
    final label = _kindLabel(l10n, _kind);
    return '[$label]($url)';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final result = DeepLinkBuilder.build(_spec);
    final autoSendOff =
        _kind == DeepLinkKind.send &&
        !context.select<SettingsProvider, bool>((s) => s.allowExternalAutoSend);

    return Scaffold(
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.settingsPageBackButton,
          child: IosIconButton(
            icon: Lucide.ArrowLeft,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.deepLinkGenTitle),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    IosSectionFooter(text: l10n.deepLinkGenSubtitle),
                    IosSectionHeader(text: l10n.deepLinkGenSectionAction),
                    SectionCard(
                      children: [
                        IosNavRow(
                          icon: _kindIcon(_kind),
                          label: _kindLabel(l10n, _kind),
                          onTap: () => _pickKind(l10n),
                        ),
                      ],
                    ),
                    ..._buildMessageSection(l10n),
                    ..._buildTargetSection(l10n),
                    ..._buildOptionsSection(l10n),
                    if (autoSendOff)
                      IosSectionFooter(text: l10n.deepLinkGenAutoSendOff),
                  ],
                ),
              ),
              _ResultBar(
                url: result.url,
                error: result.errorCode == null
                    ? null
                    : _errorMessage(l10n, result.errorCode!),
                title: l10n.deepLinkGenSectionResult,
                copyLabel: l10n.deepLinkGenCopy,
                markdownLabel: l10n.deepLinkGenCopyMarkdown,
                runLabel: l10n.deepLinkGenRun,
                onCopy: () => _copy(result.url!),
                onCopyMarkdown: () => _copy(_markdownLink(l10n, result.url!)),
                onRun: () => DeepLinkService.instance.handleUrl(result.url!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageSection(AppLocalizations l10n) {
    if (!_usesMessage) return const [];
    final bytes = utf8.encode(_text.text).length;
    final tooLarge = bytes > DeepLinkParser.maxTextBytes;
    final cs = Theme.of(context).colorScheme;
    return [
      IosSectionHeader(text: l10n.deepLinkGenSectionMessage),
      SectionCard(
        children: [
          IosFormTextField(
            label: l10n.deepLinkGenText,
            hintText: l10n.deepLinkGenTextHint,
            controller: _text,
            maxLines: 6,
            minLines: 3,
            onChanged: (_) => _update(() {}),
          ),
          if (_kind == DeepLinkKind.compose) ...[
            const IosRowDivider(indent: 12),
            IosNavRow(
              label: l10n.deepLinkGenInsertMode,
              detailText: _insertMode == DeepLinkInsertMode.replace
                  ? l10n.deepLinkGenInsertReplace
                  : l10n.deepLinkGenInsertAppend,
              onTap: () => _pickInsertMode(l10n),
            ),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Text(
          l10n.deepLinkGenTextBytes(bytes, DeepLinkParser.maxTextBytes),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 12,
            color: tooLarge ? cs.error : cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildTargetSection(AppLocalizations l10n) {
    final needsConversation =
        _kind == DeepLinkKind.openConversation ||
        (_usesMessage && _targetMode == _TargetMode.conversation);
    if (!_usesMessage && !needsConversation) return const [];
    return [
      IosSectionHeader(text: l10n.deepLinkGenSectionTarget),
      SectionCard(
        children: [
          if (_usesMessage)
            IosNavRow(
              label: l10n.deepLinkGenTarget,
              detailText: switch (_targetMode) {
                _TargetMode.current => l10n.deepLinkGenTargetCurrent,
                _TargetMode.newConversation => l10n.deepLinkGenTargetNew,
                _TargetMode.conversation => l10n.deepLinkGenTargetConversation,
              },
              onTap: () => _pickTarget(l10n),
            ),
          if (needsConversation) ...[
            if (_usesMessage) const IosRowDivider(indent: 12),
            IosNavRow(
              icon: Lucide.MessagesSquare,
              label: l10n.deepLinkGenConversationPick,
              onTap: () => _pickConversation(l10n),
            ),
            const IosRowDivider(indent: 12),
            IosFormTextField(
              label: l10n.deepLinkGenConversationId,
              hintText: l10n.deepLinkGenConversationIdHint,
              controller: _conversationId,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _update(() {}),
            ),
          ],
        ],
      ),
    ];
  }

  List<Widget> _buildOptionsSection(AppLocalizations l10n) {
    final isAssistantPage = _kind == DeepLinkKind.assistant;
    if (!_targetsNewConversation &&
        !isAssistantPage &&
        _kind != DeepLinkKind.settings) {
      return const [];
    }
    if (_kind == DeepLinkKind.settings) {
      return [
        IosSectionHeader(text: l10n.deepLinkGenSettingsSection),
        SectionCard(
          children: [
            IosNavRow(
              icon: Lucide.Settings,
              label: _sectionLabel(l10n, _settingsSection),
              detailText: _settingsSection,
              onTap: () => _pickSettingsSection(l10n),
            ),
          ],
        ),
      ];
    }
    final byName =
        !isAssistantPage && _assistantRef == DeepLinkAssistantRef.name;
    return [
      IosSectionHeader(
        text: isAssistantPage
            ? l10n.deepLinkGenAssistant
            : l10n.deepLinkGenSectionOptions,
      ),
      SectionCard(
        children: [
          IosNavRow(
            icon: Lucide.Bot,
            label: l10n.deepLinkGenAssistantPick,
            onTap: () => _pickAssistant(
              l10n,
              allowDefault: !isAssistantPage,
              forceId: isAssistantPage,
            ),
          ),
          if (!isAssistantPage) ...[
            const IosRowDivider(indent: 12),
            IosNavRow(
              label: l10n.deepLinkGenAssistantRef,
              detailText: byName
                  ? l10n.deepLinkGenRefName
                  : l10n.deepLinkGenRefId,
              onTap: () => _pickAssistantRef(l10n),
            ),
          ],
          const IosRowDivider(indent: 12),
          IosFormTextField(
            label: byName
                ? l10n.deepLinkGenAssistantName
                : l10n.deepLinkGenAssistantId,
            hintText: isAssistantPage ? null : l10n.deepLinkGenAssistantDefault,
            controller: _assistantValue,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => _update(() {}),
          ),
          if (!isAssistantPage) ...[
            const IosRowDivider(indent: 12),
            IosSwitchRow(
              icon: Lucide.Eye,
              label: l10n.deepLinkGenTemporary,
              subtitle: l10n.deepLinkGenTemporarySubtitle,
              value: _temporary,
              onChanged: (v) => _update(() => _temporary = v),
            ),
          ],
        ],
      ),
      if (_usesMessage) IosSectionFooter(text: l10n.deepLinkGenNewOnlyHint),
    ];
  }
}

/// Pinned at the bottom so the link stays visible while editing the form.
class _ResultBar extends StatelessWidget {
  const _ResultBar({
    required this.url,
    required this.error,
    required this.title,
    required this.copyLabel,
    required this.markdownLabel,
    required this.runLabel,
    required this.onCopy,
    required this.onCopyMarkdown,
    required this.onRun,
  });

  final String? url;
  final String? error;
  final String title;
  final String copyLabel;
  final String markdownLabel;
  final String runLabel;
  final VoidCallback onCopy;
  final VoidCallback onCopyMarkdown;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = url != null;
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surfaceCard,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 96),
                child: SingleChildScrollView(
                  child: SelectableText(
                    ready ? url! : error ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontFamily: ready ? 'monospace' : null,
                      color: ready ? cs.primary : cs.error,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Copy,
                      label: copyLabel,
                      enabled: ready,
                      onTap: onCopy,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.FileText,
                      label: markdownLabel,
                      enabled: ready,
                      onTap: onCopyMarkdown,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Play,
                      label: runLabel,
                      enabled: ready,
                      onTap: onRun,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
