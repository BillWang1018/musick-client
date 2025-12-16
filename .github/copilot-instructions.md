# Copilot Instructions for musick

- **Project type**: Flutter client that talks to an EasyTCP server and Supabase auth. Key flows: connect to TCP server, sign in via Supabase, send JWT to server, echo messages, create rooms.
- **Runtime config**: Requires a `.env` at repo root with `SUPABASE_URL` and `SUPABASE_ANON_KEY`. `main.dart` loads it via `flutter_dotenv` and throws if missing. `.env` is bundled as an asset and gitignored.
- **Build/run**: `flutter pub get`, `flutter analyze`, `flutter run`. No custom scripts. Use the `.env` approach (not `--dart-define`).
- **Logging**: Use the `logger` package (see `lib/services/socket_service.dart`); avoid `print`.
- **TCP protocol (EasyTCP)**: Frame is `Size(4)|ID(4)|Data(n)` in **little-endian**. Payload is UTF-8. `SocketService.sendToRoute(routeId, message)` wraps payload; `messages` stream emits only the decoded body string (no route info). Disconnect adds `"Disconnected"`, errors add `"Error: ..."` to the stream.
- **Core pages**:
  - `lib/pages/connect_page.dart`: IP/port entry, constructs a shared `SocketService`, navigates onward.
  - `lib/pages/echo_page.dart`: Simple echo/chat UI; title can be customized (e.g., `welcome! <userid>`).
  - `lib/pages/supabase_auth_page.dart`: Supabase sign-in; sends `{"token": <jwt>}` to route **10**; waits for next socket message, parses JSON (`success`, `message`/`message_text`, `user_id` variants, `user_name`), then navigates to EchoPage with user info.
  - `lib/pages/supabase_signup_page.dart`: Supabase sign-up; captures `user_name` and stores it in Supabase user metadata (`data: {'user_name': ...}`); returns to sign-in without sending JWT.
  - `lib/pages/room_list_page.dart`: Shows in-memory room list; dialog creates room and sends route **201** JSON with snake_case keys (`user_id`, `room_name`, `is_private`). Waits for a server response shaped like `CreateRoomResponse` (`success`, `message`, optional `room_id`, `room_code`, `room_name`, `is_private`) before updating UI.
- **Socket parsing**: `SocketService` buffers partial frames and supports multiple messages per read. It logs `Received - ID: <id> ...` but emits only the message body to listeners. Keep handlers tolerant to extra stream events like `Error:` and `Disconnected`.
- **JSON conventions**: Use camelCase in Dart, snake_case in payloads sent to server (e.g., room creation). Login response parser tolerates multiple key spellings; match that style when adding new routes.
- **Navigation/state**: Pages pass the same `SocketService` instance through constructors. Use `mounted` checks around async UI updates. PopScope is already used in other screens (keep to modern Flutter APIs).
- **Extending network features**: For new routes, reuse `sendToRoute`/`sendBytes` and remember the little-endian header. If you need to correlate responses, filter the `messages` stream for JSON shape or a distinguishing key, as done in room creation.
- **Tests**: None present. If adding, keep lightweight and prefer integration with current TCP framing and Supabase mocks/stubs.

Ask for clarification if adding new routes, response shapes, or Supabase flows that aren’t defined in the current code.
