import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/deep_link/deep_link_action.dart';
import '../../../core/services/deep_link/deep_link_builder.dart';
import '../../../core/services/deep_link/deep_link_parser.dart';
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

/// Copies the link for [action] and confirms it with a snackbar.
Future<void> copyDeepLink(BuildContext context, DeepLinkAction action) async {
  final l10n = AppLocalizations.of(context)!;
  await Clipboard.setData(ClipboardData(text: DeepLinkBuilder.build(action)));
  if (!context.mounted) return;
  showAppSnackBar(
    context,
    message: l10n.deepLinkLinkCopied,
    type: NotificationType.success,
  );
}

enum _LinkKind { openChat, newChat, compose, send, settings, assistant }

/// iOS-only: other platforms do not register the `kelivo` URL scheme.
class DeepLinkSettingsPage extends StatefulWidget {
  const DeepLinkSettingsPage({super.key});

  @override
  State<DeepLinkSettingsPage> createState() => _DeepLinkSettingsPageState();
}

class _DeepLinkSettingsPageState extends State<DeepLinkSettingsPage> {
  final TextEditingController _text = TextEditingController();

  _LinkKind _kind = _LinkKind.newChat;
  bool _newTarget = false;
  String? _assistantId;
  bool _temporary = false;
  DeepLinkInsertMode _insertMode = DeepLinkInsertMode.replace;
  String? _section;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _hasText => _kind == _LinkKind.compose || _kind == _LinkKind.send;

  /// Assistant and temporary options only apply to a newly created chat.
  bool get _opensNewChat =>
      _kind == _LinkKind.newChat || (_hasText && _newTarget);

  DeepLinkAction? _action(String? currentAssistantId) {
    final target = _newTarget
        ? const DeepLinkTarget.newConversation()
        : const DeepLinkTarget.current();
    final assistantId = _opensNewChat ? _assistantId : null;
    final temporary = _opensNewChat && _temporary;
    switch (_kind) {
      case _LinkKind.openChat:
        return const OpenChatDeepLinkAction();
      case _LinkKind.newChat:
        return NewChatDeepLinkAction(
          assistantId: assistantId,
          temporary: temporary,
        );
      case _LinkKind.compose:
        return ComposeDeepLinkAction(
          text: _text.text,
          target: target,
          insertMode: _insertMode,
          assistantId: assistantId,
          temporary: temporary,
        );
      case _LinkKind.send:
        if (_text.text.trim().isEmpty) return null;
        return SendDeepLinkAction(
          text: _text.text,
          target: target,
          assistantId: assistantId,
          temporary: temporary,
        );
      case _LinkKind.settings:
        return OpenSettingsDeepLinkAction(section: _section);
      case _LinkKind.assistant:
        final id = _assistantId ?? currentAssistantId;
        return id == null ? null : OpenAssistantDeepLinkAction(id);
    }
  }

  String _kindLabel(AppLocalizations l10n, _LinkKind kind) => switch (kind) {
    _LinkKind.openChat => l10n.deepLinkPageActionOpenChat,
    _LinkKind.newChat => l10n.deepLinkPageActionNewChat,
    _LinkKind.compose => l10n.deepLinkPageActionCompose,
    _LinkKind.send => l10n.deepLinkPageActionSend,
    _LinkKind.settings => l10n.deepLinkPageActionSettings,
    _LinkKind.assistant => l10n.deepLinkPageActionAssistant,
  };

  IconData _kindIcon(_LinkKind kind) => switch (kind) {
    _LinkKind.openChat => Lucide.MessageCircle,
    _LinkKind.newChat => Lucide.MessageCirclePlus,
    _LinkKind.compose => LucideIcons.textCursorInput,
    _LinkKind.send => LucideIcons.send,
    _LinkKind.settings => Lucide.Settings,
    _LinkKind.assistant => Lucide.Bot,
  };

  String _sectionLabel(AppLocalizations l10n, String? section) =>
      switch (section) {
        null => l10n.settingsPageTitle,
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

  Future<void> _pickKind() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showOptionSheet<_LinkKind>(
      context,
      title: l10n.deepLinkPageAction,
      selected: _kind,
      items: [
        for (final kind in _LinkKind.values)
          OptionSheetItem(
            value: kind,
            icon: _kindIcon(kind),
            label: _kindLabel(l10n, kind),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() {
      // "Current assistant" is meaningless for an assistant settings link.
      if (picked == _LinkKind.assistant) {
        _assistantId ??= context.read<AssistantProvider>().currentAssistantId;
      }
      _kind = picked;
    });
  }

  Future<void> _pickTarget() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showOptionSheet<bool>(
      context,
      title: l10n.deepLinkPageTarget,
      selected: _newTarget,
      items: [
        OptionSheetItem(
          value: false,
          icon: Lucide.MessageCircle,
          label: l10n.deepLinkPageTargetCurrent,
        ),
        OptionSheetItem(
          value: true,
          icon: Lucide.MessageCirclePlus,
          label: l10n.deepLinkPageTargetNew,
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _newTarget = picked);
  }

  Future<void> _pickAssistant({required bool allowCurrent}) async {
    final l10n = AppLocalizations.of(context)!;
    final assistants = context.read<AssistantProvider>().assistants;
    // An empty id stands for "no assistant parameter" in the option list.
    final picked = await showOptionSheet<String>(
      context,
      title: l10n.deepLinkPageAssistant,
      selected: _assistantId ?? '',
      items: [
        if (allowCurrent)
          OptionSheetItem(
            value: '',
            icon: Lucide.Bot,
            label: l10n.deepLinkPageAssistantCurrent,
          ),
        for (final assistant in assistants)
          OptionSheetItem(value: assistant.id, label: assistant.name),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _assistantId = picked.isEmpty ? null : picked);
  }

  Future<void> _pickInsertMode() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showOptionSheet<DeepLinkInsertMode>(
      context,
      title: l10n.deepLinkPageInsertMode,
      selected: _insertMode,
      items: [
        OptionSheetItem(
          value: DeepLinkInsertMode.replace,
          label: l10n.deepLinkPageInsertReplace,
        ),
        OptionSheetItem(
          value: DeepLinkInsertMode.append,
          label: l10n.deepLinkPageInsertAppend,
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _insertMode = picked);
  }

  Future<void> _pickSection() async {
    final l10n = AppLocalizations.of(context)!;
    // An empty section stands for the settings home page.
    final picked = await showOptionSheet<String>(
      context,
      title: l10n.deepLinkPageSettingsSection,
      selected: _section ?? '',
      items: [
        OptionSheetItem(value: '', label: _sectionLabel(l10n, null)),
        for (final section in DeepLinkParser.settingsSections)
          OptionSheetItem(value: section, label: _sectionLabel(l10n, section)),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _section = picked.isEmpty ? null : picked);
  }

  Future<void> _tryLink(String link) async {
    final opened = await launchUrl(Uri.parse(link));
    if (!opened && mounted) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(context)!.deepLinkFailed,
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final assistantProvider = context.watch<AssistantProvider>();
    final action = _action(assistantProvider.currentAssistantId);
    final link = action == null ? null : DeepLinkBuilder.build(action);

    String assistantLabel() {
      final id = _assistantId;
      if (id == null) return l10n.deepLinkPageAssistantCurrent;
      return assistantProvider.getById(id)?.name ??
          l10n.deepLinkAssistantNotFound;
    }

    final optionRows = <Widget>[
      IosNavRow(
        icon: _kindIcon(_kind),
        label: l10n.deepLinkPageAction,
        detailText: _kindLabel(l10n, _kind),
        onTap: _pickKind,
      ),
      if (_hasText)
        IosNavRow(
          icon: Lucide.MessagesSquare,
          label: l10n.deepLinkPageTarget,
          detailText: _newTarget
              ? l10n.deepLinkPageTargetNew
              : l10n.deepLinkPageTargetCurrent,
          onTap: _pickTarget,
        ),
      if (_kind == _LinkKind.compose)
        IosNavRow(
          icon: LucideIcons.replace,
          label: l10n.deepLinkPageInsertMode,
          detailText: _insertMode == DeepLinkInsertMode.append
              ? l10n.deepLinkPageInsertAppend
              : l10n.deepLinkPageInsertReplace,
          onTap: _pickInsertMode,
        ),
      if (_opensNewChat || _kind == _LinkKind.assistant)
        IosNavRow(
          icon: Lucide.Bot,
          label: l10n.deepLinkPageAssistant,
          detailText: assistantLabel(),
          onTap: () =>
              _pickAssistant(allowCurrent: _kind != _LinkKind.assistant),
        ),
      if (_opensNewChat)
        IosSwitchRow(
          icon: Lucide.MessageCircleDashed,
          label: l10n.temporaryChatTitle,
          value: _temporary,
          onChanged: (v) => setState(() => _temporary = v),
        ),
      if (_kind == _LinkKind.settings)
        IosNavRow(
          icon: LucideIcons.panelsTopLeft,
          label: l10n.deepLinkPageSettingsSection,
          detailText: _sectionLabel(l10n, _section),
          onTap: _pickSection,
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deepLinkPageTitle),
        leading: IosIconButton(
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.settingsPageBackButton,
          tooltip: l10n.settingsPageBackButton,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                IosSectionHeader(
                  text: l10n.deepLinkPagePermissionSection,
                  first: true,
                ),
                SectionCard(
                  children: [
                    IosSwitchRow(
                      icon: LucideIcons.send,
                      label: l10n.deepLinkPageAutoSend,
                      value: settings.allowExternalAutoSend,
                      onChanged: settings.setAllowExternalAutoSend,
                    ),
                  ],
                ),
                IosSectionFooter(text: l10n.deepLinkPageAutoSendFooter),

                IosSectionHeader(text: l10n.deepLinkPageBuilderSection),
                SectionCard(
                  children: [
                    for (int i = 0; i < optionRows.length; i++) ...[
                      if (i > 0) const IosRowDivider(),
                      optionRows[i],
                    ],
                  ],
                ),
                if (_hasText) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    children: [
                      IosFormTextField(
                        label: l10n.deepLinkPageMessage,
                        hintText: _kind == _LinkKind.send
                            ? l10n.deepLinkPageMessageRequiredHint
                            : l10n.deepLinkPageMessageOptionalHint,
                        controller: _text,
                        maxLines: 6,
                        minLines: 3,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ],

                IosSectionHeader(text: l10n.deepLinkPageLinkSection),
                SectionCard(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: context.appColors.surfaceCardFill,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SelectableText(
                              link ?? l10n.deepLinkPageLinkIncomplete,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                fontFamily: 'monospace',
                                color: link == null
                                    ? cs.onSurface.withValues(alpha: 0.5)
                                    : cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: IosTileButton(
                                  icon: Lucide.Copy,
                                  label: l10n.deepLinkCopyLink,
                                  backgroundColor: cs.primary,
                                  enabled: action != null,
                                  onTap: () {
                                    if (action == null) return;
                                    unawaited(copyDeepLink(context, action));
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: IosTileButton(
                                  icon: Lucide.ExternalLink,
                                  label: l10n.deepLinkPageTryLink,
                                  enabled: link != null,
                                  onTap: () {
                                    if (link == null) return;
                                    unawaited(_tryLink(link));
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_kind == _LinkKind.send && !settings.allowExternalAutoSend)
                  IosSectionFooter(text: l10n.deepLinkPageSendNeedsPermission),
                IosSectionFooter(text: l10n.deepLinkPageShortcutFooter),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
