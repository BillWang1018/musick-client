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
  bool _loadingRooms = false;

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

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

    widget.socketService.sendToRoute(201, payload);

    final raw = await _waitForCreateRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      _showSnack('No create-room response received.');
      return;
    }

    final resp = _tryParseCreateRoomResponse(raw);
    if (resp == null) {
      _showSnack('Invalid create-room response');
      return;
    }

    if (!resp.success) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Create room failed.');
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _joinRoomDialog,
                  child: const Text('Join room'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _findRoomDialog,
                  child: const Text('Find room'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _createRoomDialog,
                  child: const Text('New room'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loadingRooms
                ? const Center(child: CircularProgressIndicator())
                : (_rooms.isEmpty
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
                            onLongPress: () => _confirmLeaveRoom(room, index),
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
                      )),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchRooms() async {
    if (!mounted) return;

    setState(() {
      _loadingRooms = true;
    });

    final payload = jsonEncode({'user_id': widget.userId});
    _logger.i('Requesting rooms (route 210): $payload');
    widget.socketService.sendToRoute(210, payload);

    final raw = await _waitForListRoomsResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      setState(() {
        _loadingRooms = false;
      });
      _showSnack('No room list response received.');
      return;
    }

    final resp = _tryParseListRoomsResponse(raw);
    if (resp == null) {
      setState(() {
        _loadingRooms = false;
      });
      _showSnack('Invalid room list response');
      return;
    }

    if (!resp.success) {
      setState(() {
        _loadingRooms = false;
      });
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Failed to load rooms.');
      return;
    }

    setState(() {
      _rooms
        ..clear()
        ..addAll(resp.rooms);
      _loadingRooms = false;
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

    widget.socketService.sendToRoute(202, payload);

    final raw = await _waitForJoinRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      _showSnack('No join-room response received.');
      return;
    }

    final resp = _tryParseJoinRoomResponse(raw);
    if (resp == null) {
      _showSnack('Invalid join-room response');
      return;
    }

    if (!resp.success) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Join room failed.');
      return;
    }

    final isDuplicate = _rooms.any(
      (room) =>
          (resp.roomId.isNotEmpty && room.roomId == resp.roomId) ||
          (resp.code.isNotEmpty && room.roomCode == resp.code),
    );

    if (isDuplicate) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Room already in list.');
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

  Future<void> _findRoomDialog() async {
    final controller = TextEditingController();
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Find public room'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Room name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(''),
                child: const Text('Random'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('Find'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _logger.e('Dialog error: $e');
      return;
    }

    if (!mounted || result == null) return;

    await _findPublicRooms(result);
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

  Future<void> _findPublicRooms(String name) async {
    if (!mounted) return;

    final payload = jsonEncode({
      'user_id': widget.userId,
      'name': name,
    });

    _logger.i('Finding public rooms (route 211): $payload');
    widget.socketService.sendToRoute(211, payload);

    final raw = await _waitForFindRoomsResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      _showSnack('No find-room response received.');
      return;
    }

    final resp = _tryParseFindRoomsResponse(raw);
    if (resp == null) {
      _showSnack('Invalid find-room response');
      return;
    }

    if (!resp.success) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Find room failed.');
      return;
    }

    if (resp.rooms.isEmpty) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'No public rooms found.');
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No room found!'),
          content: const Text('No public rooms were returned.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final selected = await _showFoundRoomsDialog(resp.rooms);
    if (!mounted || selected == null) return;

    await _joinFoundRoom(selected);
  }

  Future<String?> _waitForFindRoomsResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeFindRoomsJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for find-rooms response: $e');
      return null;
    }
  }

  Future<String?> _waitForLeaveRoomResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeLeaveRoomJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for leave-room response: $e');
      return null;
    }
  }

  bool _looksLikeFindRoomsJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') && (decoded.containsKey('rooms') || decoded.containsKey('message'));
    } catch (_) {
      return false;
    }
  }

  bool _looksLikeLeaveRoomJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') && decoded.containsKey('message');
    } catch (_) {
      return false;
    }
  }

  FindRoomsResponse? _tryParseFindRoomsResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final roomsRaw = decoded['rooms'];

      final rooms = _parseRooms(roomsRaw);

      return FindRoomsResponse(
        success: success,
        message: message is String ? message : '',
        rooms: rooms,
      );
    } catch (_) {
      return null;
    }
  }

  LeaveRoomResponse? _tryParseLeaveRoomResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];

      return LeaveRoomResponse(
        success: success,
        message: message is String ? message : '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<RoomSummary?> _showFoundRoomsDialog(List<RoomSummary> rooms) {
    return showDialog<RoomSummary>(
      context: context,
      builder: (dialogContext) {
        int? selectedIndex;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Public rooms'),
              content: SizedBox(
                width: 400,
                height: 320,
                child: ListView.separated(
                  itemCount: rooms.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final selected = selectedIndex == index;
                    return ListTile(
                      title: Text(room.name),
                      subtitle: Text(room.roomCode.isNotEmpty ? 'Code: ${room.roomCode}' : 'Room ID: ${room.roomId}'),
                      trailing: selected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                      onTap: () {
                        setStateDialog(() {
                          selectedIndex = index;
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedIndex == null
                      ? null
                      : () => Navigator.of(dialogContext).pop(rooms[selectedIndex!]),
                  child: const Text('Join'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLeaveRoom(RoomSummary room, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Leave room?'),
          content: Text('Leave "${room.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final payload = jsonEncode({
      'room_id': room.roomId,
      'user_id': widget.userId,
    });

    _logger.i('Leaving room (route 203): $payload');
    widget.socketService.sendToRoute(203, payload);

    final raw = await _waitForLeaveRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      _showSnack('No leave-room response received.');
      return;
    }

    final resp = _tryParseLeaveRoomResponse(raw);
    if (resp == null) {
      _showSnack('Invalid leave-room response');
      return;
    }

    if (!resp.success) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Leave room failed.');
      return;
    }

    setState(() {
      _rooms.removeAt(index);
    });
    _showSnack(resp.message.isNotEmpty ? resp.message : 'Left room.');
  }

  Future<void> _joinFoundRoom(RoomSummary room) async {
    if (!mounted) return;

    final payload = jsonEncode({
      'user_id': widget.userId,
      // Prefer code when available, otherwise fall back to room_id for public rooms.
      'code': room.roomCode,
      'room_id': room.roomId,
    });

    _logger.i('Joining found room (route 202): $payload');

    widget.socketService.sendToRoute(202, payload);

    final raw = await _waitForJoinRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      _showSnack('No join-room response received.');
      return;
    }

    final resp = _tryParseJoinRoomResponse(raw);
    if (resp == null) {
      _showSnack('Invalid join-room response');
      return;
    }

    if (!resp.success) {
      _showSnack(resp.message.isNotEmpty ? resp.message : 'Join room failed.');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoomChatPage(
          socketService: widget.socketService,
          roomId: room.roomId.isNotEmpty ? room.roomId : resp.roomId,
          roomName: room.name.isNotEmpty ? room.name : (resp.title.isNotEmpty ? resp.title : 'Room'),
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }

  List<RoomSummary> _parseRooms(dynamic roomsRaw) {
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
    return rooms;
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

      final rooms = _parseRooms(roomsRaw);

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
