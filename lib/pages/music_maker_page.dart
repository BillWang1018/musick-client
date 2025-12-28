import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/song_model.dart';
import '../models/track_model.dart';
import '../services/socket_service.dart';
import '../services/track_repository.dart';

class MusicMakerPage extends StatefulWidget {
  final Song song;
  final String roomName;
  final String roomId;
  final String userId;
  final SocketService socketService;

  const MusicMakerPage({
    super.key,
    required this.song,
    required this.roomName,
    required this.roomId,
    required this.userId,
    required this.socketService,
  });

  @override
  State<MusicMakerPage> createState() => _MusicMakerPageState();
}

class _MusicMakerPageState extends State<MusicMakerPage> {
  // Piano-roll defaults.
  static const int _octaveSpan = 12;
  static const int _defaultBeatsPerMeasure = 4;
  static const int _defaultBasePitch = 24; // C2
  static const int _defaultOctaveCount = 2;
  static const double _cellSize = 44;
  static const int _defaultVelocity = 100;
  static const int _defaultLengthSteps = 1;

  int _beatsPerMeasure = _defaultBeatsPerMeasure;
  int _basePitch = _defaultBasePitch;
  int _octaveCount = _defaultOctaveCount;
  ScaleType _scale = ScaleType.major;

  final List<Track> _tracks = [];

  final Map<String, Map<String, Note>> _notesByTrackId = {};
  late Song _currentSong;
  late final TrackRepository _trackRepo;
  int _selectedTrack = 0;
  String _lastTapInfo = 'Tap a note to debug.';
  StreamSubscription<String>? _trackSub;
  StreamSubscription<NoteBroadcast>? _noteBroadcastSub;

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _trackRepo = TrackRepository(widget.socketService);
    _trackSub = widget.socketService.messages.listen(_handleIncomingTrackMessage);
    _noteBroadcastSub = _trackRepo.noteBroadcasts(songId: widget.song.id).listen(_handleNoteBroadcast);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialNotesAndTracks());
  }

  @override
  void dispose() {
    _noteBroadcastSub?.cancel();
    _trackSub?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialNotesAndTracks() async {
    final response = await _trackRepo.listNotes(
      userId: widget.userId,
      roomId: widget.roomId,
      songId: _currentSong.id,
      trackId: '',
    );
    if (!mounted) return;
    if (response == null) {
      _showSnack('Timed out loading notes');
      return;
    }
    if (!response.success) {
      _showSnack(response.message.isNotEmpty ? response.message : 'Failed to load notes');
    }
    setState(() {
      if (response.tracks.isNotEmpty) {
        _tracks
          ..clear()
          ..addAll(response.tracks);
        if (_selectedTrack >= _tracks.length) {
          _selectedTrack = _tracks.isEmpty ? 0 : _tracks.length - 1;
        }
      }
      _notesByTrackId.clear();
      for (final note in response.notes) {
        final noteMap = _notesByTrackId.putIfAbsent(note.trackId, () => <String, Note>{});
        noteMap[_noteKey(note.step, note.pitch)] = note;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTrack >= _tracks.length) {
      _selectedTrack = _tracks.isEmpty ? 0 : _tracks.length - 1;
    }
    final pitches = List<int>.generate(_octaveSpan * _octaveCount, (i) => _basePitch + i);
    final steps = _currentSong.steps;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentSong.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Grid settings',
            onPressed: _onEditGrid,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Edit song',
            onPressed: _onEditSong,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(
              children: [
                Text('Room: ${widget.roomName}'),
                const SizedBox(width: 12),
                Text('BPM ${_currentSong.bpm}'),
                const SizedBox(width: 12),
                Text('Steps $steps'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _tracks.isEmpty
                ? _buildEmptyTracksPlaceholder()
                : InteractiveViewer(
                    minScale: 0.6,
                    maxScale: 2.0,
                    constrained: false,
                    child: SizedBox(
                      width: steps * _cellSize,
                      height: pitches.length * _cellSize,
                      child: _buildGrid(pitches, steps),
                    ),
                  ),
          ),
          const Divider(height: 1),
          _buildTracks(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(_lastTapInfo)),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Return'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<int> pitches, int steps) {
    if (_tracks.isEmpty) {
      return const SizedBox.shrink();
    }
    final trackIndex = _selectedTrack.clamp(0, _tracks.length - 1);
    final track = _tracks[trackIndex];
    final notes = _notesByTrackId.putIfAbsent(track.id, () => <String, Note>{});
    int beatLength = _beatsPerMeasure <= 0 ? _currentSong.steps : (_currentSong.steps / _beatsPerMeasure).round();
    if (beatLength < 1) beatLength = 1;
    if (beatLength > _currentSong.steps) beatLength = _currentSong.steps;
    return Column(
      children: List.generate(pitches.length, (rowIdx) {
        final pitch = pitches[pitches.length - 1 - rowIdx]; // top is highest pitch
        final isSharp = _isSharp(pitch);
        final isScaleTone = _isScaleTone(pitch);
        final octaveBoundary = pitch % _octaveSpan == 0; // C boundary
        return Row(
          children: List.generate(steps, (colIdx) {
            final key = _noteKey(colIdx, pitch);
            final isActive = notes.containsKey(key);
            final beatBoundary = colIdx % beatLength == 0;
            final trackColor = colorForName(track.color);
            final baseColor = isActive
              ? trackColor.withValues(alpha: (trackColor.a * 0.65).clamp(0.0, 1.0))
              : (isScaleTone
                ? Colors.amber.shade50
                : (isSharp ? Colors.blueGrey.shade50 : Colors.white));
            return GestureDetector(
              onTap: () => _handleTap(step: colIdx, pitch: pitch),
              child: Container(
                width: _cellSize,
                height: _cellSize,
                decoration: BoxDecoration(
                  color: baseColor,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: octaveBoundary ? 1.2 : 0.5),
                    left: BorderSide(color: Colors.grey.shade400, width: beatBoundary ? 1.5 : 0.5),
                    right: BorderSide(color: Colors.grey.shade200, width: 0.3),
                    bottom: BorderSide(color: Colors.grey.shade200, width: 0.3),
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  Widget _buildTracks() {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemBuilder: (context, index) {
          if (index == _tracks.length) {
            return _buildAddTrackButton();
          }
          final track = _tracks[index];
          final selected = index == _selectedTrack;
          return GestureDetector(
            onTap: () => setState(() => _selectedTrack = index),
            onLongPress: () => _confirmDeleteTrack(index),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 26,
                          backgroundColor:
                              selected ? colorForName(track.color).withValues(alpha: 0.25) : Colors.grey.shade200,
                  child: Icon(
                            iconForInstrument(track.instrument),
                            color: selected ? colorForName(track.color) : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(track.name, style: const TextStyle(fontSize: 12)),
              ],
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemCount: _tracks.length + 1,
      ),
    );
  }

  Widget _buildAddTrackButton() {
    return GestureDetector(
      onTap: _showAddTrackDialog,
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.green.shade100,
            child: const Icon(Icons.add, color: Colors.green),
          ),
          const SizedBox(height: 8),
          const Text('Add', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _handleTap({required int step, required int pitch}) async {
    if (_tracks.isEmpty) return;
    if (_selectedTrack >= _tracks.length) {
      _selectedTrack = _tracks.length - 1;
    }
    final track = _tracks[_selectedTrack];
    final notes = _notesByTrackId.putIfAbsent(track.id, () => <String, Note>{});
    final key = _noteKey(step, pitch);
    final existing = notes[key];
    if (existing == null) {
      final optimistic = Note(
        id: 'local_$key',
        trackId: track.id,
        step: step,
        pitch: pitch,
        velocity: _defaultVelocity,
        lengthSteps: _defaultLengthSteps,
      );
      setState(() {
        notes[key] = optimistic;
        _lastTapInfo = 'On step ${step + 1}, pitch $pitch on track ${track.name}';
      });
      final response = await _trackRepo.createNote(
        userId: widget.userId,
        roomId: widget.roomId,
        songId: _currentSong.id,
        trackId: track.id,
        step: step,
        pitch: pitch,
        velocity: _defaultVelocity,
        lengthSteps: _defaultLengthSteps,
      );
      if (!mounted) return;
      if (response == null || !response.success || response.note == null) {
        setState(() {
          notes.remove(key);
        });
        _showSnack(response?.message.isNotEmpty == true ? response!.message : 'Failed to add note');
        return;
      }
      setState(() {
        notes[key] = response.note!;
      });
    } else {
      setState(() {
        notes.remove(key);
        _lastTapInfo = 'Off step ${step + 1}, pitch $pitch on track ${track.name}';
      });
      final response = await _trackRepo.deleteNote(
        userId: widget.userId,
        roomId: widget.roomId,
        songId: _currentSong.id,
        trackId: track.id,
        step: step,
        pitch: pitch,
      );
      if (!mounted) return;
      if (response == null || !response.success) {
        setState(() {
          notes[key] = existing;
        });
        _showSnack(response?.message.isNotEmpty == true ? response!.message : 'Failed to delete note');
      }
    }
  }

  bool _isSharp(int pitch) {
    // pitch 1 = C0, so mod 12 gives chroma; sharps at 2,4,7,9,11.
    final chroma = pitch % 12;
    return chroma == 2 || chroma == 4 || chroma == 7 || chroma == 9 || chroma == 11;
  }

  bool _isScaleTone(int pitch) {
    final chroma = pitch % 12;
    return _scale == ScaleType.major ? _majorScale.contains(chroma) : _minorScale.contains(chroma);
  }

  String _noteKey(int step, int pitch) => '$step:$pitch';

  Widget _buildEmptyTracksPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.playlist_add, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text('Add a track to start editing'),
        ],
      ),
    );
  }

  Future<void> _showAddTrackDialog() async {
    final nameController = TextEditingController();
    String selectedInstrument = instrumentChoices.first.instrument;
    String selectedColor = trackColors.first.colorName;
    final channelController = TextEditingController();

    final result = await showDialog<CreateTrackInput>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('New track'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Track name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedInstrument,
                    decoration: const InputDecoration(
                      labelText: 'Instrument',
                      border: OutlineInputBorder(),
                    ),
                    items: instrumentChoices
                        .map((e) => DropdownMenuItem(
                              value: e.instrument,
                              child: Row(
                                children: [
                                  Icon(iconForInstrument(e.instrument)),
                                  const SizedBox(width: 8),
                                  Text(e.label),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (instrument) {
                      setStateDialog(() {
                        selectedInstrument = instrument ?? selectedInstrument;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedColor,
                    decoration: const InputDecoration(
                      labelText: 'Color',
                      border: OutlineInputBorder(),
                    ),
                    items: trackColors
                        .map((e) => DropdownMenuItem(
                              value: e.colorName,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: colorForName(e.colorName),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(e.label),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (color) {
                      setStateDialog(() {
                        selectedColor = color ?? selectedColor;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: channelController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Channel (optional)',
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
                    final name = nameController.text.trim();
                    final channel = int.tryParse(channelController.text.trim());
                    Navigator.of(context).pop(CreateTrackInput(
                      name: name.isNotEmpty ? name : selectedInstrument,
                      instrument: selectedInstrument,
                      color: selectedColor,
                      channel: channel,
                    ));
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;
    await _createTrackOnServer(result);
  }

  Future<void> _confirmDeleteTrack(int index) async {
    if (_tracks.isEmpty || index < 0 || index >= _tracks.length) return;
    final track = _tracks[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete track?'),
          content: Text('Remove "${track.name}" and its notes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await _deleteTrackOnServer(track);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _onEditSong() async {
    final result = await _showEditSongDialog();
    if (result == null) return;

    final updates = <String, dynamic>{
      'user_id': widget.userId,
      'room_id': widget.roomId,
      'song_id': _currentSong.id,
    };

    if (result.title != null && result.title!.trim().isNotEmpty && result.title != _currentSong.title) {
      updates['title'] = result.title;
    }
    if (result.bpm != null && result.bpm != _currentSong.bpm) {
      updates['bpm'] = result.bpm;
    }
    if (result.steps != null && result.steps != _currentSong.steps) {
      updates['steps'] = result.steps;
    }

    if (updates.length <= 3) {
      return; // nothing to update
    }

    final response = await _trackRepo.updateSong(updates: updates);
    if (!mounted) return;
    if (response == null) {
      _showSnack('Timed out updating song');
      return;
    }
    if (!response.success) {
      _showSnack(response.message.isNotEmpty ? response.message : 'Failed to update song');
      return;
    }

    if (response.song != null) {
      setState(() {
        _currentSong = response.song!;
      });
    } else {
      setState(() {
        _currentSong = Song(
          id: _currentSong.id,
          title: result.title?.isNotEmpty == true ? result.title! : _currentSong.title,
          bpm: result.bpm ?? _currentSong.bpm,
          steps: result.steps ?? _currentSong.steps,
        );
      });
    }
  }

  Future<UpdateSongInput?> _showEditSongDialog() {
    final titleController = TextEditingController(text: _currentSong.title);
    final bpmController = TextEditingController(text: _currentSong.bpm.toString());
    final stepsController = TextEditingController(text: _currentSong.steps.toString());

    return showDialog<UpdateSongInput>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit song'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
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
                  labelText: 'Steps',
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
                final title = titleController.text.trim();
                final bpm = int.tryParse(bpmController.text.trim());
                final steps = int.tryParse(stepsController.text.trim());
                Navigator.of(context).pop(UpdateSongInput(title: title, bpm: bpm, steps: steps));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onEditGrid() async {
    final result = await _showGridSettingsDialog();
    if (result == null) return;
    setState(() {
      _beatsPerMeasure = result.beats;
      _scale = result.scale;
      _basePitch = result.startFrom;
      _octaveCount = result.octaveCount;
    });
  }

  Future<_GridSettings?> _showGridSettingsDialog() {
    final beatsController = TextEditingController(text: _beatsPerMeasure.toString());
    final startController = TextEditingController(text: _basePitch.toString());
    final octavesController = TextEditingController(text: _octaveCount.toString());
    ScaleType scale = _scale;

    return showDialog<_GridSettings>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Grid settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: beatsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Beats per measure', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ScaleType>(
                initialValue: scale,
                decoration: const InputDecoration(labelText: 'Scale', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: ScaleType.major, child: Text('Major')),
                  DropdownMenuItem(value: ScaleType.minor, child: Text('Minor')),
                ],
                onChanged: (value) {
                  scale = value ?? scale;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: startController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Start pitch (MIDI)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: octavesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Octave range', border: OutlineInputBorder()),
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
                final beats = int.tryParse(beatsController.text.trim()) ?? _beatsPerMeasure;
                final start = int.tryParse(startController.text.trim()) ?? _basePitch;
                final octaves = int.tryParse(octavesController.text.trim()) ?? _octaveCount;
                Navigator.of(context).pop(_GridSettings(
                  beats: beats > 0 ? beats : _beatsPerMeasure,
                  scale: scale,
                  startFrom: start.clamp(0, 127),
                  octaveCount: octaves.clamp(1, 6),
                ));
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createTrackOnServer(CreateTrackInput input) async {
    final response = await _trackRepo.createTrack(
      userId: widget.userId,
      roomId: widget.roomId,
      songId: _currentSong.id,
      input: input,
    );
    if (!mounted) return;
    if (response == null) {
      _showSnack('Timed out creating track');
      return;
    }
    if (!response.success || response.track == null) {
      _showSnack(response.message.isNotEmpty ? response.message : 'Failed to create track');
      return;
    }
    setState(() => _insertOrUpdateTrack(response.track!));
  }

  Future<void> _deleteTrackOnServer(Track track) async {
    if (track.id.isEmpty) {
      setState(() {
        _tracks.remove(track);
        _notesByTrackId.remove(track.id);
        if (_selectedTrack >= _tracks.length) {
          _selectedTrack = _tracks.isEmpty ? 0 : _tracks.length - 1;
        }
      });
      return;
    }
    final response = await _trackRepo.deleteTrack(
      userId: widget.userId,
      roomId: widget.roomId,
      songId: _currentSong.id,
      trackId: track.id,
    );
    if (!mounted) return;
    if (response == null) {
      _showSnack('Timed out deleting track');
      return;
    }
    if (!response.success) {
      _showSnack(response.message.isNotEmpty ? response.message : 'Failed to delete track');
      return;
    }
    setState(() => _removeTrackById(track.id));
  }

  void _handleIncomingTrackMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      if (_looksLikeNoteBroadcast(decoded)) {
        return; // handled by note broadcast stream
      }

      // Broadcasts
      if (_looksLikeTrackBroadcast(decoded)) {
        final songId = decoded['song_id'];
        if (songId is String && songId != _currentSong.id) return;
        final action = decoded['action'];
        if (action == 'on') {
          final trackMap = decoded['track'];
          if (trackMap is Map) {
            final track = Track.tryFromMap(trackMap);
            if (track != null) {
              setState(() => _insertOrUpdateTrack(track));
            }
          }
        } else if (action == 'off') {
          final trackId = decoded['track_id'];
          if (trackId is String && trackId.isNotEmpty) {
            setState(() => _removeTrackById(trackId));
          }
        }
        return;
      }
    } catch (_) {
      // ignore non-JSON
    }
  }

  bool _looksLikeTrackBroadcast(Map decoded) {
    return decoded.containsKey('action') && (decoded.containsKey('track') || decoded.containsKey('track_id'));
  }

  bool _looksLikeNoteBroadcast(Map decoded) {
    return decoded.containsKey('action') && decoded.containsKey('track_id') && decoded.containsKey('step') && decoded.containsKey('pitch');
  }

  void _insertOrUpdateTrack(Track track) {
    final idx = _tracks.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      _tracks[idx] = track;
    } else {
      _tracks.add(track);
    }
    _notesByTrackId.putIfAbsent(track.id, () => <String, Note>{});
    _selectedTrack = _tracks.indexWhere((t) => t.id == track.id);
  }

  void _removeTrackById(String trackId) {
    _tracks.removeWhere((t) => t.id == trackId);
    _notesByTrackId.remove(trackId);
    if (_selectedTrack >= _tracks.length) {
      _selectedTrack = _tracks.isEmpty ? 0 : _tracks.length - 1;
    }
  }

  void _handleNoteBroadcast(NoteBroadcast broadcast) {
    if (broadcast.songId != _currentSong.id) return;
    final noteMap = _notesByTrackId.putIfAbsent(broadcast.trackId, () => <String, Note>{});
    final key = _noteKey(broadcast.step, broadcast.pitch);
    if (broadcast.action == 'on') {
      final note = broadcast.note ??
          Note(
            id: 'broadcast_$key',
            trackId: broadcast.trackId,
            step: broadcast.step,
            pitch: broadcast.pitch,
            velocity: _defaultVelocity,
            lengthSteps: _defaultLengthSteps,
          );
      setState(() => noteMap[key] = note);
    } else if (broadcast.action == 'off') {
      setState(() => noteMap.remove(key));
    }
  }
}

enum ScaleType { major, minor }

const Set<int> _majorScale = {0, 2, 4, 5, 7, 9, 11};
const Set<int> _minorScale = {0, 2, 3, 5, 7, 8, 10};

class _GridSettings {
  final int beats;
  final ScaleType scale;
  final int startFrom;
  final int octaveCount;

  const _GridSettings({
    required this.beats,
    required this.scale,
    required this.startFrom,
    required this.octaveCount,
  });
}

