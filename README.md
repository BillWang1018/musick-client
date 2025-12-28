# musick

A new Flutter project.

## Setup

### 1) Create `.env`

This app loads Supabase configuration from a local `.env` file (via `flutter_dotenv`).

Create/edit the file at the project root:

`.env`

And set:

- `SUPABASE_URL` (Supabase Project URL)
- `SUPABASE_ANON_KEY` (Supabase anon/public API key)

You can find these in the Supabase Dashboard:

Project Settings → API

Notes:

- `.env` is ignored by git (so keys aren’t committed).
- `.env` is bundled as a Flutter asset for runtime loading.

### 2) Install dependencies

Run:

`flutter pub get`

Notes on media features:

- Uses `youtube_player_iframe` for in-app playback; ensure `flutter pub get` has been run after pulling.

### 3) Run

Run:

`flutter run`

## Source layout (`lib/`)

- `lib/main.dart`
	- App entry point
	- Loads `.env`
	- Initializes Supabase
	- Starts the UI

- `lib/services/socket_service.dart`
	- TCP client for the EasyTCP server
	- Supports sending to arbitrary route IDs (e.g. route `1` for echo, route `10` for login/JWT)

- `lib/pages/connect_page.dart`
	- UI to connect to the TCP server (IP/port)

- `lib/pages/echo_page.dart`
	- Simple echo/chat UI
	- App bar title can be customized (used after login for `welcome! <userid>`)

- `lib/pages/room_chat_page.dart`
	- Room messaging with draggable media pane
	- Sending any YouTube link shows an "Open in player" button; player docks at the top and can be resized/closed
	- Timestamps in messages (e.g., `03:32` or `1:02:05`) add a "Jump" button that seeks the current video without reloading

- `lib/pages/song_list_page.dart`
	- Lists songs for a room (fetch via route `510`), supports manual refresh
	- Add button opens a dialog (default 120 BPM, 20 steps) and creates songs via route `501`
	- Opens the music maker placeholder after creation

- `lib/pages/music_maker_page.dart`
	- Music maker UI: scrollable piano-roll grid (steps x pitches), per-track selection, note toggles
	- Tracks can be added/removed with instrument + color metadata; taps toggle notes per track
	- Song settings (title/BPM/steps) editable via AppBar settings; updates sent on route `511`

- `lib/pages/supabase_auth_page.dart`
	- Supabase sign-in UI
	- Sends JWT to server via route `10`
	- Waits for server login JSON response and navigates to echo page on success

- `lib/pages/supabase_signup_page.dart`
	- Supabase sign-up UI
	- Returns to sign-in page after creating the account
