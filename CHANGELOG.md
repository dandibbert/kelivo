# Changelog

All notable changes to this project will be documented in this file.

## [1.2.4] - 2026-08-21

### Fixed
- Preserve widget lifecycle safety while processing external deep links.
- Localize external deep-link warnings and errors in English, Simplified Chinese, and Traditional Chinese.
- Correct the About page settings deep-link example.

## [1.1.18] - 2026-08-07

### Added
- **External Deep Links (iOS)**: support the `kelivo://v1/...` URL scheme so other apps can open chats, compose or send messages:
  - `kelivo://v1/chat` — open the chat page
  - `kelivo://v1/chat/new` — start a new conversation (optional `assistant`, `assistant_name`, `temporary`)
  - `kelivo://v1/chat/<conversationId>` — open an existing conversation
  - `kelivo://v1/compose?text=...&insert=replace|append` — fill the message box
  - `kelivo://v1/send?text=...&target=...` — send a message directly
  - `kelivo://v1/settings/<section>` — jump to a settings page
  - `kelivo://v1/assistant/<assistantId>` — open an assistant settings page
- **Settings → Allow External Auto-Send** toggle (off by default for security): enables links to send messages without confirmation.
- **About page** now documents the supported deep link formats.
- Unit tests for the deep link parser (`test/core/services/deep_link/`).
- README (EN/ZH) deep link documentation section.

### Changed
- Bump version to 1.1.18+62.
