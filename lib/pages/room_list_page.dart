import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../services/socket_service.dart';
import 'room_chat_page.dart';
import 'room_list_support.dart';

class RoomListPage extends StatefulWidget {
  final SocketService socketService;
  final String userId;
  final String? userName;

  const RoomListPage({
    super.key,
    required this.socketService,
    required this.userId,
    this.userName,
  });

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  final Logger _logger = Logger();
  final List<RoomSummary> _rooms = [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _createRoomDialog() async {
    CreateRoomResult? result;
    try {
      result = await showDialog<CreateRoomResult>(
        context: context,
        builder: (dialogContext) => const CreateRoomDialog(),
      );
    } catch (e) {
      _logger.e('Dialog error: $e');
      return;
    }

    if (!mounted || result == null) return;

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_name': result.name,
      'is_private': result.isPrivate,
    });

    _logger.i('Creating room (route 201): $payload');

    setState(() {
      _status = 'Creating room...';
    });

    widget.socketService.sendToRoute(201, payload);

    final raw = await _waitForCreateRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      setState(() => _status = 'No create-room response received.');
      return;
    }

    final resp = _tryParseCreateRoomResponse(raw);
    if (resp == null) {
      setState(() => _status = 'Invalid create-room response: $raw');
      return;
    }

    if (!resp.success) {
      setState(() => _status = resp.message.isEmpty ? 'Create room failed.' : resp.message);
      return;
    }

    setState(() {
      _rooms.add(
        RoomSummary(
          name: resp.roomName.isNotEmpty ? resp.roomName : result!.name,
          isPrivate: resp.isPrivate ?? result!.isPrivate,
          roomId: resp.roomId,
          roomCode: resp.roomCode,
        ),
      );
      _status = resp.message.isNotEmpty ? resp.message : 'Room created.';
    });
  }

  Future<String?> _waitForCreateRoomResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeCreateRoomJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for create-room response: $e');
      return null;
    }
  }

  bool _looksLikeCreateRoomJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('room_id') ||
              decoded.containsKey('room_name') ||
              decoded.containsKey('room_code') ||
              decoded.containsKey('is_private') ||
              decoded.containsKey('message'));
    } catch (_) {
      return false;
    }
  }

  CreateRoomResponse? _tryParseCreateRoomResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final roomId = decoded['room_id'];
      final roomCode = decoded['room_code'];
      final roomName = decoded['room_name'];
      final isPrivate = decoded['is_private'];

      return CreateRoomResponse(
        success: success,
        message: message is String ? message : '',
        roomId: roomId is String ? roomId : '',
        roomCode: roomCode is String ? roomCode : '',
        roomName: roomName is String ? roomName : '',
        isPrivate: isPrivate is bool ? isPrivate : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          IconButton(
            tooltip: 'Refresh rooms',
            onPressed: _fetchRooms,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _joinRoomDialog,
            child: const Text('Join room'),
          ),
          TextButton(
            onPressed: _createRoomDialog,
            child: const Text('New room'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _status,
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _rooms.isEmpty
                ? const Center(child: Text('No rooms yet'))
                : ListView.separated(
                    itemCount: _rooms.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      final privacyText = room.isPrivate ? 'Private' : 'Public';
                      final codePrefix = room.roomCode.isNotEmpty ? 'Code: ${room.roomCode} • ' : '';
                      return ListTile(
                        leading: Icon(room.isPrivate ? Icons.lock : Icons.group),
                        title: Text(room.name),
                        subtitle: Text('$codePrefix$privacyText'),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RoomChatPage(
                                socketService: widget.socketService,
                                roomId: room.roomId,
                                roomName: room.name,
                                userId: widget.userId,
                                userName: widget.userName,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRooms() async {
    if (!mounted) return;

    setState(() {
      _status = 'Loading rooms...';
    });

    final payload = jsonEncode({'user_id': widget.userId});
    _logger.i('Requesting rooms (route 210): $payload');
    widget.socketService.sendToRoute(210, payload);

    final raw = await _waitForListRoomsResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      setState(() => _status = 'No room list response received.');
      return;
    }

    final resp = _tryParseListRoomsResponse(raw);
    if (resp == null) {
      setState(() => _status = 'Invalid room list response: $raw');
      return;
    }

    if (!resp.success) {
      setState(() => _status = resp.message.isNotEmpty ? resp.message : 'Failed to load rooms.');
      return;
    }

    setState(() {
      _rooms
        ..clear()
        ..addAll(resp.rooms);
      _status = resp.message.isNotEmpty ? resp.message : 'Rooms loaded.';
    });
  }

  Future<void> _joinRoomDialog() async {
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => const JoinRoomDialog(),
      );
    } catch (e) {
      _logger.e('Dialog error: $e');
      return;
    }

    if (!mounted || result == null || result.isEmpty) return;

    final payload = jsonEncode({
      'code': result,
      'user_id': widget.userId,
    });

    _logger.i('Joining room (route 202): $payload');
    setState(() => _status = 'Joining room...');

    widget.socketService.sendToRoute(202, payload);

    final raw = await _waitForJoinRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      setState(() => _status = 'No join-room response received.');
      return;
    }

    final resp = _tryParseJoinRoomResponse(raw);
    if (resp == null) {
      setState(() => _status = 'Invalid join-room response: $raw');
      return;
    }

    if (!resp.success) {
      setState(() => _status = resp.message.isNotEmpty ? resp.message : 'Join room failed.');
      return;
    }

    final isDuplicate = _rooms.any(
      (room) =>
          (resp.roomId.isNotEmpty && room.roomId == resp.roomId) ||
          (resp.code.isNotEmpty && room.roomCode == resp.code),
    );

    if (isDuplicate) {
      setState(() {
        _status = resp.message.isNotEmpty ? resp.message : 'Room already in list.';
      });
      return;
    }

    setState(() {
      final roomName = resp.title.isNotEmpty
          ? resp.title
          : (resp.roomId.isNotEmpty ? 'Room ${resp.roomId}' : 'Joined room');
      _rooms.add(
        RoomSummary(
          name: roomName,
          isPrivate: resp.isPrivate ?? false,
          roomId: resp.roomId,
          roomCode: resp.code,
          ownerId: resp.ownerId,
          createdAt: resp.createdAt,
        ),
      );
      _status = resp.message.isNotEmpty ? resp.message : 'Room joined.';
    });
  }

  Future<String?> _waitForJoinRoomResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeJoinRoomJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for join-room response: $e');
      return null;
    }
  }

  bool _looksLikeJoinRoomJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('room_id') ||
              decoded.containsKey('code') ||
              decoded.containsKey('title') ||
              decoded.containsKey('message'));
    } catch (_) {
      return false;
    }
  }

  JoinRoomResponse? _tryParseJoinRoomResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final roomId = decoded['room_id'];
      final code = decoded['code'];
      final title = decoded['title'];
      final ownerId = decoded['owner_id'];
      final isPrivate = decoded['is_private'];
      final createdAt = decoded['created_at'];

      return JoinRoomResponse(
        success: success,
        message: message is String ? message : '',
        roomId: roomId is String ? roomId : '',
        code: code is String ? code : '',
        title: title is String ? title : '',
        ownerId: ownerId is String ? ownerId : '',
        isPrivate: isPrivate is bool ? isPrivate : null,
        createdAt: createdAt is String ? createdAt : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _waitForListRoomsResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeListRoomsJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for room list response: $e');
      return null;
    }
  }

  bool _looksLikeListRoomsJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('rooms') || decoded.containsKey('message'));
    } catch (_) {
      return false;
    }
  }

  ListRoomsResponse? _tryParseListRoomsResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final roomsRaw = decoded['rooms'];

      final rooms = <RoomSummary>[];
      if (roomsRaw is List) {
        for (final entry in roomsRaw) {
          if (entry is! Map) continue;
          final roomName = entry['room_name'] ?? entry['title'];
          final roomId = entry['room_id'] ?? entry['id'];
          final roomCode = entry['room_code'] ?? entry['code'];
          final isPrivate = entry['is_private'];
          final ownerId = entry['owner_id'];
          final createdAt = entry['created_at'];

          rooms.add(
            RoomSummary(
              name: roomName is String && roomName.isNotEmpty ? roomName : 'Unnamed room',
              isPrivate: isPrivate is bool ? isPrivate : false,
              roomId: roomId is String ? roomId : '',
              roomCode: roomCode is String ? roomCode : '',
              ownerId: ownerId is String ? ownerId : '',
              createdAt: createdAt is String ? createdAt : '',
            ),
          );
        }
      }

      return ListRoomsResponse(
        success: success,
        message: message is String ? message : '',
        rooms: rooms,
      );
    } catch (_) {
      return null;
    }
  }

}
