class Song {
  final String id;
  final String title;
  final int bpm;
  final int steps;

  const Song({
    required this.id,
    required this.title,
    required this.bpm,
    required this.steps,
  });

  factory Song.fromMap(Map<dynamic, dynamic> map) {
    final id = map['id'] ?? map['song_id'];
    final title = map['title'];
    final bpm = map['bpm'];
    final steps = map['steps'];

    return Song(
      id: id is String ? id : (id is int ? id.toString() : ''),
      title: title is String && title.isNotEmpty ? title : 'Untitled',
      bpm: bpm is int ? bpm : (bpm is String ? int.tryParse(bpm) ?? 120 : 120),
      steps: steps is int ? steps : (steps is String ? int.tryParse(steps) ?? 20 : 20),
    );
  }
}
