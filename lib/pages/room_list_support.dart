import 'package:flutter/material.dart';

class RoomSummary {
  final String name;
  final bool isPrivate;
  final String roomId;
  final String roomCode;
  final String ownerId;
  final String createdAt;

  const RoomSummary({
    required this.name,
    required this.isPrivate,
    this.roomId = '',
    this.roomCode = '',
    this.ownerId = '',
    this.createdAt = '',
  });
}

class CreateRoomResult {
  final String name;
  final bool isPrivate;

  const CreateRoomResult({required this.name, required this.isPrivate});
}

class CreateRoomResponse {
  final bool success;
  final String message;
  final String roomId;
  final String roomCode;
  final String roomName;
  final bool? isPrivate;

  const CreateRoomResponse({
    required this.success,
    required this.message,
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.isPrivate,
  });
}

class ListRoomsResponse {
  final bool success;
  final String message;
  final List<RoomSummary> rooms;

  const ListRoomsResponse({
    required this.success,
    required this.message,
    required this.rooms,
  });
}

class JoinRoomResponse {
  final bool success;
  final String message;
  final String roomId;
  final String code;
  final String title;
  final String ownerId;
  final bool? isPrivate;
  final String createdAt;

  const JoinRoomResponse({
    required this.success,
    required this.message,
    required this.roomId,
    required this.code,
    required this.title,
    required this.ownerId,
    required this.isPrivate,
    required this.createdAt,
  });
}

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({super.key});

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  final _nameController = TextEditingController();
  bool _isPrivate = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      CreateRoomResult(name: name, isPrivate: _isPrivate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Room name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private room'),
            value: _isPrivate,
            onChanged: (value) {
              setState(() => _isPrivate = value ?? false);
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
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class JoinRoomDialog extends StatefulWidget {
  const JoinRoomDialog({super.key});

  @override
  State<JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<JoinRoomDialog> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join room'),
      content: TextField(
        controller: _codeController,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Room code',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Join'),
        ),
      ],
    );
  }
}
