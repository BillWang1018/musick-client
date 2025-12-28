import 'package:flutter/material.dart';

import 'song_model.dart';

class Note {
  final String id;
  final String trackId;
  final int step;
  final int pitch;
  final int velocity;
  final int lengthSteps;

  const Note({
    required this.id,
    required this.trackId,
    required this.step,
    required this.pitch,
    required this.velocity,
    required this.lengthSteps,
  });

  static Note? tryFromMap(Map<dynamic, dynamic> map) {
    final idRaw = map['id'] ?? map['note_id'];
    final trackId = map['track_id'];
    final step = map['step'];
    final pitch = map['pitch'];
    final velocity = map['velocity'];
    final lengthSteps = map['length_steps'] ?? map['length'];
    final id = idRaw is String ? idRaw : (idRaw is int ? idRaw.toString() : '');
    if (trackId is! String || trackId.isEmpty || step is! int || pitch is! int) {
      return null;
    }
    return Note(
      id: id.isEmpty ? '${trackId}_${step}_$pitch' : id,
      trackId: trackId,
      step: step,
      pitch: pitch,
      velocity: velocity is int ? velocity : 100,
      lengthSteps: lengthSteps is int ? lengthSteps : 1,
    );
  }
}

class Track {
  final String id;
  final String name;
  final String instrument;
  final String color;
  final int? channel;

  const Track({
    required this.id,
    required this.name,
    required this.instrument,
    required this.color,
    this.channel,
  });

  static Track? tryFromMap(Map<dynamic, dynamic> map) {
    final idRaw = map['id'] ?? map['track_id'];
    final name = map['name'] ?? map['title'];
    final instrument = map['instrument'];
    final color = map['color'];
    final channel = map['channel'];
    final id = idRaw is String ? idRaw : (idRaw is int ? idRaw.toString() : '');
    if (id.isEmpty || instrument is! String || name is! String || name.isEmpty || color is! String || color.isEmpty) {
      return null;
    }
    return Track(
      id: id,
      name: name,
      instrument: instrument,
      color: color,
      channel: channel is int ? channel : (channel is String ? int.tryParse(channel) : null),
    );
  }
}

class CreateTrackInput {
  final String name;
  final String instrument;
  final String color;
  final int? channel;

  const CreateTrackInput({
    required this.name,
    required this.instrument,
    required this.color,
    this.channel,
  });
}

class CreateTrackResponse {
  final bool success;
  final String message;
  final Track? track;

  const CreateTrackResponse({required this.success, required this.message, required this.track});

  factory CreateTrackResponse.fromJson(Map<String, dynamic> json) {
    final track = json['track'];
    return CreateTrackResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
      track: track is Map ? Track.tryFromMap(track) : null,
    );
  }
}

class DeleteTrackResponse {
  final bool success;
  final String message;

  const DeleteTrackResponse({required this.success, required this.message});

  factory DeleteTrackResponse.fromJson(Map<String, dynamic> json) {
    return DeleteTrackResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
    );
  }
}

class CreateNoteResponse {
  final bool success;
  final String message;
  final Note? note;

  const CreateNoteResponse({required this.success, required this.message, required this.note});

  factory CreateNoteResponse.fromJson(Map<String, dynamic> json) {
    final noteMap = json['note'];
    return CreateNoteResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
      note: noteMap is Map ? Note.tryFromMap(noteMap) : null,
    );
  }
}

class DeleteNoteResponse {
  final bool success;
  final String message;

  const DeleteNoteResponse({required this.success, required this.message});

  factory DeleteNoteResponse.fromJson(Map<String, dynamic> json) {
    return DeleteNoteResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
    );
  }
}

class ListNotesResponse {
  final bool success;
  final String message;
  final List<Note> notes;
  final List<Track> tracks;

  const ListNotesResponse({
    required this.success,
    required this.message,
    required this.notes,
    required this.tracks,
  });

  factory ListNotesResponse.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'];
    final rawTracks = json['tracks'];
    return ListNotesResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
      notes: rawNotes is List
          ? rawNotes.map((e) => e is Map ? Note.tryFromMap(e) : null).whereType<Note>().toList()
          : const [],
      tracks: rawTracks is List
          ? rawTracks.map((e) => e is Map ? Track.tryFromMap(e) : null).whereType<Track>().toList()
          : const [],
    );
  }
}

class NoteBroadcast {
  final String action; // "on" | "off"
  final String songId;
  final String trackId;
  final int step;
  final int pitch;
  final Note? note;

  const NoteBroadcast({
    required this.action,
    required this.songId,
    required this.trackId,
    required this.step,
    required this.pitch,
    this.note,
  });

  static NoteBroadcast? tryFromMap(Map<String, dynamic> map) {
    final action = map['action'];
    final songId = map['song_id'];
    final trackId = map['track_id'];
    final step = map['step'];
    final pitch = map['pitch'];
    if (action is! String || songId is! String || trackId is! String || step is! int || pitch is! int) {
      return null;
    }
    final noteMap = map['note'];
    return NoteBroadcast(
      action: action,
      songId: songId,
      trackId: trackId,
      step: step,
      pitch: pitch,
      note: noteMap is Map ? Note.tryFromMap(noteMap) : null,
    );
  }
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

  factory UpdateSongResponse.fromJson(Map<String, dynamic> json) {
    final songMap = json['song'];
    return UpdateSongResponse(
      success: json['success'] == true,
      message: json['message'] is String ? json['message'] as String : '',
      song: songMap is Map ? Song.fromMap(songMap) : null,
    );
  }
}

class TrackIconChoice {
  final String label;
  final String instrument;
  const TrackIconChoice(this.label, this.instrument);
}

const List<TrackIconChoice> instrumentChoices = [
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

const List<TrackColorChoice> trackColors = [
  TrackColorChoice('Blue', 'blue'),
  TrackColorChoice('Teal', 'teal'),
  TrackColorChoice('Purple', 'purple'),
  TrackColorChoice('Pink', 'pink'),
  TrackColorChoice('Orange', 'orange'),
  TrackColorChoice('Green', 'green'),
];

IconData iconForInstrument(String instrument) {
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

Color colorForName(String name) {
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
