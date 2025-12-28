import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/song_model.dart';
import '../services/socket_service.dart';

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
  // Piano-roll defaults: bottom row starts at C3 (pitch=37), show 2 octaves.
  static const int _basePitch = 37;
  static const int _octaveSpan = 12;
  static const int _octaveCount = 2;
  static const double _cellSize = 44;

  final List<Track> _tracks = [
    // const Track(name: 'Drums', instrument: 'drums', color: 'blue'),
    // const Track(name: 'Bass', instrument: 'bass', color: 'teal'),
    // const Track(name: 'Lead', instrument: 'lead', color: 'purple'),
    // const Track(name: 'Pad', instrument: 'pad', color: 'pink'),
  ];

  late List<Set<String>> _notesPerTrack;
  late Song _currentSong;
  int _selectedTrack = 0;
  String _lastTapInfo = 'Tap a note to debug.';

  @override
  void initState() {
    super.initState();
    _currentSong = widget.song;
    _notesPerTrack = List.generate(_tracks.length, (_) => <String>{});
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
    return Column(
      children: List.generate(pitches.length, (rowIdx) {
        final pitch = pitches[pitches.length - 1 - rowIdx]; // top is highest pitch
        final isSharp = _isSharp(pitch);
        return Row(
          children: List.generate(steps, (colIdx) {
            final key = _noteKey(colIdx, pitch);
            final isActive = _notesPerTrack[trackIndex].contains(key);
            return GestureDetector(
              onTap: () => _handleTap(step: colIdx, pitch: pitch),
              child: Container(
                width: _cellSize,
                height: _cellSize,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.lightBlue.shade200
                      : (isSharp ? Colors.blueGrey.shade50 : Colors.white),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 0.5),
                    left: BorderSide(color: Colors.grey.shade300, width: 0.5),
                    right: BorderSide(color: Colors.grey.shade200, width: 0.25),
                    bottom: BorderSide(color: Colors.grey.shade200, width: 0.25),
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
                  backgroundColor: selected
                      ? _colorForName(track.color).withValues(alpha: 0.25)
                      : Colors.grey.shade200,
                  child: Icon(
                    _iconForInstrument(track.instrument),
                    color: selected ? _colorForName(track.color) : Colors.grey.shade700,
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

  void _handleTap({required int step, required int pitch}) {
    if (_tracks.isEmpty) return;
    final track = _tracks[_selectedTrack];
    final set = _notesPerTrack[_selectedTrack];
    final key = _noteKey(step, pitch);
    final turnedOn = set.contains(key) ? false : true;

    setState(() {
      if (turnedOn) {
        set.add(key);
      } else {
        set.remove(key);
      }
      _lastTapInfo = '${turnedOn ? 'On' : 'Off'} step ${step + 1}, pitch $pitch on track ${track.name}';
    });
    // Future: send to server; for now we just log/debug.
  }

  bool _isSharp(int pitch) {
    // pitch 1 = C0, so mod 12 gives chroma; sharps at 2,4,7,9,11.
    final chroma = pitch % 12;
    return chroma == 2 || chroma == 4 || chroma == 7 || chroma == 9 || chroma == 11;
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
    String selectedInstrument = _instrumentChoices.first.instrument;
    String selectedColor = _trackColors.first.colorName;

    final result = await showDialog<Track>(
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
                    items: _instrumentChoices
                        .map((e) => DropdownMenuItem(
                              value: e.instrument,
                              child: Row(
                                children: [
                                  Icon(_iconForInstrument(e.instrument)),
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
                    items: _trackColors
                        .map((e) => DropdownMenuItem(
                              value: e.colorName,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: _colorForName(e.colorName),
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
                    Navigator.of(context).pop(
                      Track(
                        name: name.isNotEmpty ? name : selectedInstrument,
                        instrument: selectedInstrument,
                        color: selectedColor,
                        channel: null,
                      ),
                    );
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

    setState(() {
      _tracks.add(result);
      _notesPerTrack.add(<String>{});
      _selectedTrack = _tracks.length - 1;
    });
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

    setState(() {
      _tracks.removeAt(index);
      _notesPerTrack.removeAt(index);
      if (_selectedTrack >= _tracks.length) {
        _selectedTrack = _tracks.isEmpty ? 0 : _tracks.length - 1;
      }
    });
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

    final payload = jsonEncode(updates);
    widget.socketService.sendToRoute(511, payload);

    final raw = await _waitForUpdateSongResponse();
    if (!mounted) return;
    if (raw == null) {
      _showSnack('Timed out updating song');
      return;
    }

    final response = _tryParseUpdateSongResponse(raw);
    if (response == null || !response.success) {
      _showSnack(response?.message ?? 'Failed to update song');
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

  Future<String?> _waitForUpdateSongResponse() async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeUpdateSongJson)
          .first
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeUpdateSongJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded.containsKey('success') && decoded.containsKey('message');
    } catch (_) {
      return false;
    }
  }

  UpdateSongResponse? _tryParseUpdateSongResponse(String raw) {
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
      return UpdateSongResponse(
        success: success is bool ? success : false,
        message: message is String ? message : '',
        song: song,
      );
    } catch (_) {
      return null;
    }
  }
}

class TrackIconChoice {
  final String label;
  final String instrument;
  const TrackIconChoice(this.label, this.instrument);
}

const List<TrackIconChoice> _instrumentChoices = [
  TrackIconChoice('Drums', 'drums'),
  TrackIconChoice('Bass', 'bass'),
  TrackIconChoice('Lead', 'lead'),
  TrackIconChoice('Pad', 'pad'),
  TrackIconChoice('Pluck', 'pluck'),
  TrackIconChoice('Keys', 'keys'),
];

class TrackColorChoice {
  final String label;
  final String colorName;
  const TrackColorChoice(this.label, this.colorName);
}

const List<TrackColorChoice> _trackColors = [
  TrackColorChoice('Blue', 'blue'),
  TrackColorChoice('Teal', 'teal'),
  TrackColorChoice('Purple', 'purple'),
  TrackColorChoice('Pink', 'pink'),
  TrackColorChoice('Orange', 'orange'),
  TrackColorChoice('Green', 'green'),
];

IconData _iconForInstrument(String instrument) {
  switch (instrument) {
    case 'drums':
      return Icons.music_note;
    case 'bass':
      return Icons.piano;
    case 'lead':
      return Icons.audiotrack;
    case 'pad':
      return Icons.graphic_eq;
    case 'pluck':
      return Icons.queue_music;
    case 'keys':
      return Icons.keyboard;
    default:
      return Icons.music_video;
  }
}

class Track {
  final String name;
  final String instrument;
  final String color; // stored as a text-friendly name for persistence
  final int? channel;
  const Track({required this.name, required this.instrument, required this.color, this.channel});
}

class UpdateSongInput {
  final String? title;
  final int? bpm;
  final int? steps;

  const UpdateSongInput({this.title, this.bpm, this.steps});
}

class UpdateSongResponse {
  final bool success;
  final String message;
  final Song? song;

  const UpdateSongResponse({required this.success, required this.message, required this.song});
}

Color _colorForName(String name) {
  switch (name) {
    case 'blue':
      return Colors.blue;
    case 'teal':
      return Colors.teal;
    case 'purple':
      return Colors.purple;
    case 'pink':
      return Colors.pink;
    case 'orange':
      return Colors.orange;
    case 'green':
      return Colors.green;
    default:
      return Colors.grey;
  }
}
