import 'dart:async';
import 'dart:convert';

import 'package:logger/logger.dart';

import '../models/track_model.dart';
import '../services/socket_service.dart';

class TrackRepository {
  TrackRepository(this._socketService, {Logger? logger}) : _logger = logger ?? Logger();

  final SocketService _socketService;
  final Logger _logger;

  static const _routeCreateTrack = 604;
  static const _routeDeleteTrack = 605;
  static const _routeUpdateSong = 511;
  static const _routeCreateNote = 601;
  static const _routeDeleteNote = 602;
  static const _routeListNotes = 610;

  Future<CreateTrackResponse?> createTrack({
    required String userId,
    required String roomId,
    required String songId,
    required CreateTrackInput input,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'room_id': roomId,
      'song_id': songId,
      'name': input.name,
      'instrument': input.instrument,
      'channel': input.channel,
      'color': input.color,
    });

    _socketService.sendToRoute(_routeCreateTrack, payload);
    final json = await _waitForJson(_looksLikeCreateTrackJson, timeout: timeout);
    if (json == null) return null;
    return CreateTrackResponse.fromJson(json);
  }

  Future<DeleteTrackResponse?> deleteTrack({
    required String userId,
    required String roomId,
    required String songId,
    required String trackId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'room_id': roomId,
      'song_id': songId,
      'track_id': trackId,
    });

    _socketService.sendToRoute(_routeDeleteTrack, payload);
    final json = await _waitForJson(_looksLikeDeleteTrackJson, timeout: timeout);
    if (json == null) return null;
    return DeleteTrackResponse.fromJson(json);
  }

  Future<UpdateSongResponse?> updateSong({
    required Map<String, dynamic> updates,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    _socketService.sendToRoute(_routeUpdateSong, jsonEncode(updates));
    final json = await _waitForJson(_looksLikeUpdateSongJson, timeout: timeout);
    if (json == null) return null;
    return UpdateSongResponse.fromJson(json);
  }

  Future<CreateNoteResponse?> createNote({
    required String userId,
    required String roomId,
    required String songId,
    required String trackId,
    required int step,
    required int pitch,
    int velocity = 100,
    int lengthSteps = 1,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'room_id': roomId,
      'song_id': songId,
      'track_id': trackId,
      'step': step,
      'pitch': pitch,
      'velocity': velocity,
      'length_steps': lengthSteps,
    });

    _socketService.sendToRoute(_routeCreateNote, payload);
    final json = await _waitForJson(_looksLikeCreateNoteJson, timeout: timeout);
    if (json == null) return null;
    return CreateNoteResponse.fromJson(json);
  }

  Future<DeleteNoteResponse?> deleteNote({
    required String userId,
    required String roomId,
    required String songId,
    required String trackId,
    required int step,
    required int pitch,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'room_id': roomId,
      'song_id': songId,
      'track_id': trackId,
      'step': step,
      'pitch': pitch,
    });

    _socketService.sendToRoute(_routeDeleteNote, payload);
    final json = await _waitForJson(_looksLikeDeleteNoteJson, timeout: timeout);
    if (json == null) return null;
    return DeleteNoteResponse.fromJson(json);
  }

  Future<ListNotesResponse?> listNotes({
    required String userId,
    required String roomId,
    required String songId,
    required String trackId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final payload = jsonEncode({
      'user_id': userId,
      'room_id': roomId,
      'song_id': songId,
      'track_id': trackId,
    });

    _socketService.sendToRoute(_routeListNotes, payload);
    final json = await _waitForJson(_looksLikeListNotesJson, timeout: timeout);
    if (json == null) return null;
    return ListNotesResponse.fromJson(json);
  }

  Stream<NoteBroadcast> noteBroadcasts({String? songId}) {
    return _jsonMessageStream()
      .where(_looksLikeNoteBroadcastJson)
      .map(NoteBroadcast.tryFromMap)
        .where((b) => b != null && (songId == null || b.songId == songId))
        .map((b) => b as NoteBroadcast);
  }

  Stream<Map<String, dynamic>> _jsonMessageStream() {
    return _socketService.messages
        .where((m) => m.isNotEmpty && !m.startsWith('Error:') && m != 'Disconnected')
        .map((raw) {
          try {
            final decoded = jsonDecode(raw);
            return decoded is Map<String, dynamic> ? decoded : null;
          } catch (e) {
            _logger.w('Non-JSON socket message skipped: $e');
            return null;
          }
        })
        .where((m) => m != null)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> _waitForJson(
    bool Function(Map<String, dynamic>) matcher, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await _jsonMessageStream().where(matcher).first.timeout(timeout);
    } catch (e) {
      _logger.w('Timed out or failed waiting for socket response: $e');
      return null;
    }
  }

  bool _looksLikeCreateTrackJson(Map<String, dynamic> json) {
    return json.containsKey('success') && json.containsKey('track');
  }

  bool _looksLikeCreateNoteJson(Map<String, dynamic> json) {
    return json.containsKey('success') && json.containsKey('note');
  }

  bool _looksLikeDeleteNoteJson(Map<String, dynamic> json) {
    return json.containsKey('success') && json.containsKey('message') && !json.containsKey('track');
  }

  bool _looksLikeListNotesJson(Map<String, dynamic> json) {
    return json.containsKey('success') && json.containsKey('message') && (json.containsKey('notes') || json.containsKey('tracks'));
  }

  bool _looksLikeDeleteTrackJson(Map<String, dynamic> json) {
    final message = json['message'];
    final messageStr = message is String ? message.toLowerCase() : '';
    return json.containsKey('success') &&
        json.containsKey('message') &&
        !json.containsKey('track') &&
        !json.containsKey('song') &&
        (json.containsKey('track_id') || messageStr.contains('track'));
  }

  bool _looksLikeUpdateSongJson(Map<String, dynamic> json) {
    return json.containsKey('success') && json.containsKey('message');
  }

  bool _looksLikeNoteBroadcastJson(Map<String, dynamic> json) {
    return json.containsKey('action') && json.containsKey('track_id') && json.containsKey('step') && json.containsKey('pitch');
  }
}
