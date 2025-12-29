class Song {
  final String id;
  final String roomId;
  final String title;
  final int bpm;
  final int steps;
  final int beatsPerMeasure;
  final String scale;
  final int startPitch;
  final int octaveRange;
  final String createdBy;
  final DateTime? createdAt;

  const Song({
    required this.id,
    required this.roomId,
    required this.title,
    required this.bpm,
    required this.steps,
    required this.beatsPerMeasure,
    required this.scale,
    required this.startPitch,
    required this.octaveRange,
    required this.createdBy,
    required this.createdAt,
  });

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'] ?? map['song_id'];
    final roomId = map['room_id'];
    final title = map['title'];
    final bpm = map['bpm'];
    final steps = map['steps'];
    final beatsPerMeasure = map['beats_per_measure'];
    final scale = map['scale'];
    final startPitch = map['start_pitch'];
    final octaveRange = map['octave_range'];
    final createdBy = map['created_by'];
    final createdAtRaw = map['created_at'];

    return Song(
      id: id is String ? id : (id is int ? id.toString() : ''),
      roomId: roomId is String ? roomId : '',
      title: title is String && title.isNotEmpty ? title : 'Untitled',
      bpm: bpm is int ? bpm : (bpm is String ? int.tryParse(bpm) ?? 120 : 120),
      steps: steps is int ? steps : (steps is String ? int.tryParse(steps) ?? 20 : 20),
      beatsPerMeasure: beatsPerMeasure is int
          ? beatsPerMeasure
          : (beatsPerMeasure is String ? int.tryParse(beatsPerMeasure) ?? 4 : 4),
      scale: scale is String && scale.isNotEmpty ? scale : 'major',
      startPitch: startPitch is int
          ? startPitch
          : (startPitch is String ? int.tryParse(startPitch) ?? 24 : 24),
      octaveRange: octaveRange is int
          ? octaveRange
          : (octaveRange is String ? int.tryParse(octaveRange) ?? 2 : 2),
      createdBy: createdBy is String ? createdBy : '',
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)
          : (createdAtRaw is DateTime ? createdAtRaw : null),
    );
  }
}
