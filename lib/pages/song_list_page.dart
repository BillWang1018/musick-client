import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../models/song_model.dart';
import '../services/socket_service.dart';
import 'music_maker_page.dart';

class SongListPage extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String userId;
  final SocketService socketService;

  const SongListPage({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.userId,
    required this.socketService,
  });

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  final Logger _logger = Logger();
  final List<Song> _songs = [];
  bool _isCreating = false;
  bool _isLoadingList = false;

  @override
  void initState() {
    super.initState();
    _logger.i('Opened song list for room ${widget.roomId}');
    _fetchSongs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Songs – ${widget.roomName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh songs',
            onPressed: _isLoadingList ? null : _fetchSongs,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add song',
            onPressed: _isCreating ? null : _onAddSong,
          ),
        ],
      ),
      body: _isLoadingList
          ? const Center(child: CircularProgressIndicator())
          : (_songs.isEmpty ? _buildEmptyState() : _buildSongList()),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.library_music_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No songs yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Collaborate with your group to start a track. Finished songs will show up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongList() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final song = _songs[index];
        return ListTile(
          leading: const Icon(Icons.music_note_outlined),
          title: Text(song.title),
          subtitle: Text('BPM ${song.bpm} • ${song.steps} steps'),
          onTap: () => _openSong(song),
        );
      },
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemCount: _songs.length,
    );
  }

  Future<void> _fetchSongs() async {
    if (_isLoadingList) return;
    setState(() => _isLoadingList = true);

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_id': widget.roomId,
    });

    _logger.i('Fetching songs (route 510): $payload');
    widget.socketService.sendToRoute(510, payload);

    final raw = await _waitForSongListResponse();
    if (!mounted) return;

    if (raw == null) {
      setState(() => _isLoadingList = false);
      _showSnack('Timed out fetching songs');
      return;
    }

    final response = _tryParseSongListResponse(raw);
    if (response == null || !response.success) {
      setState(() => _isLoadingList = false);
      _showSnack(response?.message ?? 'Failed to load songs');
      return;
    }

    setState(() {
      _songs
        ..clear()
        ..addAll(response.songs);
      _isLoadingList = false;
    });
  }

  Future<void> _onAddSong() async {
    final input = await _showCreateSongDialog();
    if (input == null || input.title.isEmpty) return;

    setState(() => _isCreating = true);

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_id': widget.roomId,
      'title': input.title,
      'bpm': input.bpm,
      'steps': input.steps,
    });

    _logger.i('Creating song (route 501): $payload');
    widget.socketService.sendToRoute(501, payload);

    final raw = await _waitForCreateSongResponse();
    if (!mounted) return;

    setState(() => _isCreating = false);

    if (raw == null) {
      _showSnack('Timed out creating song');
      return;
    }

    final response = _tryParseCreateSongResponse(raw);
    if (response == null || !response.success) {
      _showSnack(response?.message ?? 'Failed to create song');
      return;
    }

    final song = response.song;
    if (song != null) {
      setState(() => _songs.add(song));
      _openSong(song);
    } else {
      _showSnack('Song created but missing details');
    }
  }

  Future<CreateSongInput?> _showCreateSongDialog() {
    final titleController = TextEditingController();
    final bpmController = TextEditingController(text: '120');
    final stepsController = TextEditingController(text: '20');

    return showDialog<CreateSongInput>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New song'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bpmController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'BPM',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stepsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Steps (columns)',
                  helperText: 'e.g. 4 beats x 5 measures = 20 steps',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final bpm = int.tryParse(bpmController.text.trim()) ?? 120;
                final steps = int.tryParse(stepsController.text.trim()) ?? 20;
                final title = titleController.text.trim();
                Navigator.of(context).pop(
                  CreateSongInput(title: title, bpm: bpm, steps: steps),
                );
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _waitForCreateSongResponse() async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeCreateSongJson)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      _logger.w('Timed out waiting for create song response: $e');
      return null;
    }
  }

  bool _looksLikeCreateSongJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded.containsKey('success') && decoded.containsKey('message') && decoded.containsKey('song');
    } catch (_) {
      return false;
    }
  }

  CreateSongResponse? _tryParseCreateSongResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final success = decoded['success'];
      final message = decoded['message'];
      final songMap = decoded['song'];

      Song? song;
      if (songMap is Map) {
        song = Song.fromMap(songMap);
      }

      return CreateSongResponse(
        success: success is bool ? success : false,
        message: message is String ? message : '',
        song: song,
      );
    } catch (e) {
      _logger.w('Failed to parse create song response: $e');
      return null;
    }
  }

  Future<void> _openSong(Song song) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MusicMakerPage(
          song: song,
          roomName: widget.roomName,
          roomId: widget.roomId,
          userId: widget.userId,
          socketService: widget.socketService,
        ),
      ),
    );
    if (mounted) {
      _fetchSongs();
    }
  }

  Future<String?> _waitForSongListResponse() async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeSongListJson)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      _logger.w('Timed out waiting for song list response: $e');
      return null;
    }
  }

  bool _looksLikeSongListJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded.containsKey('success') && decoded.containsKey('message');
    } catch (_) {
      return false;
    }
  }

  SongListResponse? _tryParseSongListResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final success = decoded['success'];
      final message = decoded['message'];
      final songsRaw = decoded['songs'];

      final songs = <Song>[];
      if (songsRaw is List) {
        for (final entry in songsRaw) {
          if (entry is Map) {
            songs.add(Song.fromMap(entry));
          }
        }
      }

      return SongListResponse(
        success: success is bool ? success : false,
        message: message is String ? message : '',
        songs: songs,
      );
    } catch (e) {
      _logger.w('Failed to parse song list response: $e');
      return null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class CreateSongInput {
  final String title;
  final int bpm;
  final int steps;

  const CreateSongInput({required this.title, required this.bpm, required this.steps});
}

class CreateSongResponse {
  final bool success;
  final String message;
  final Song? song;

  const CreateSongResponse({required this.success, required this.message, required this.song});
}

class SongListResponse {
  final bool success;
  final String message;
  final List<Song> songs;

  const SongListResponse({
    required this.success,
    required this.message,
    required this.songs,
  });
}
