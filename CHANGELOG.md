# Changelog

All notable changes to this project will be documented in this file.

## [1.3.5] - 2026-10-24

### Changed
- Rebase onto upstream Kelivo: integrated browser and browser agent tools, per-conversation tool permissions, password-encrypted backups, grouped MCP management, iOS native selection menus, world book entry copy and batch transfer, Windows restore recovery, and more. The iOS `kelivo://v1` deep links are kept.
- Bump version to 1.3.5+89.

### Fixed
- The iOS Share extension no longer shows one generic "could not save" message for every failure. It now says when Kelivo's shared storage (App Group) is unavailable, and otherwise shows the underlying error.
- The iOS Share extension and the app now also try the App Groups declared by the build's embedded provisioning profile when `group.psyche.kelivo` is unavailable. An App Group ID belongs to the team that registered it, so a build re-signed under another team carries a different one. An extension signed without its own profile reads the host app's.
- The "new chat" button no longer returns to the current conversation. A new chat that already held messages stayed registered as the assistant's reusable unsent chat (external-link sends left it behind, persisted across restarts), so every new chat went back to it. It is now dropped once it holds more than the assistant's preset messages, which also heals registrations already on disk.

## [1.3.4] - 2026-10-23

### Changed
- Rebase onto upstream Kelivo (Markstream message renderer, storage and backup recovery fixes, Exa / DeepSeek search, Groq / Mistral transcription, and more) and keep the iOS `kelivo://v1` deep links.
- Bump version to 1.3.4+83.

### Fixed
- The About page test no longer assumes the debug Markdown Playground row is already built; the URL generator button made the page longer.

## [1.3.3] - 2026-10-22

### Fixed
- `kelivo://v1/send` and `compose` with `target=new` now always start a fresh conversation. Previously a second link for the same assistant was appended to the previous conversation, because the conversation stayed registered as that assistant's reusable unsent chat after an external send.

### Changed
- Bump version to 1.3.3+82.

## [1.3.2] - 2026-10-17

### Added
- **URL Scheme Generator** (Settings → URL Scheme Generator, also linked from About): build `kelivo://v1/...` links for every supported route with text, insert mode, target conversation, assistant by ID or name, temporary chat and settings page options. Copy the link, copy it as Markdown, or run it in the app. Links are validated with the same parser the app uses.

### Fixed
- Deep-link text that mixes percent-encoded and raw characters is decoded leniently: a raw `+` stays a plus (use `%20` for spaces), a stray `%` stays literal, and malformed UTF-8 or path escapes no longer drop the link silently.

### Changed
- Rebase onto upstream Kelivo 1.3.1 (Flutter 3.47) and keep the iOS `kelivo://v1` deep links.
- Bump version to 1.3.2+81.

## [1.3.1] - 2026-09-22

### Changed
- Rebase onto upstream Kelivo 1.3.0 and keep the iOS `kelivo://v1` deep links.
- Bump version to 1.3.1+80.

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
