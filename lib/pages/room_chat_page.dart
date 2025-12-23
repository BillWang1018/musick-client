import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ytp;

import '../models/message_model.dart';
import '../services/socket_service.dart';
import '../widgets/room_chat_content.dart';

class RoomChatPage extends StatefulWidget {
  final SocketService socketService;
  final String roomId;
  final String roomName;
  final String userId;
  final String? userName;

  const RoomChatPage({
    super.key,
    required this.socketService,
    required this.roomId,
    required this.roomName,
    required this.userId,
    this.userName,
  });

  @override
  State<RoomChatPage> createState() => _RoomChatPageState();
}

class _RoomChatPageState extends State<RoomChatPage> {
  final Logger _logger = Logger();
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  late final ScrollController _scrollController;
  late final String _selfName;
  ytp.YoutubePlayerController? _ytController;
  StreamSubscription<String>? _sub;
  bool _sending = false;
  String _status = '';
  bool _isLoading = false;
  bool _hasMore = true;
  String _nextBeforeId = '';
  static const double _minWebviewHeight = 100;
  double _webviewHeight = 0;
  String? _pendingYoutubeUrl;

  @override
  void initState() {
    super.initState();
    _selfName = (widget.userName != null && widget.userName!.isNotEmpty)
        ? widget.userName!
        : widget.userId;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _sub = widget.socketService.messages.listen(_handleIncoming);
    _loadInitialMessages();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ytController?.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 80 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  void _handleIncoming(String raw) {
    // Ignore non-JSON messages that clearly aren't about this room.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final roomId = decoded['room_id'];
      if (roomId is String && roomId == widget.roomId) {
        final body = decoded['body'];
        final senderId = decoded['sender_id'];
        final success = decoded['success'];
        final id = decoded['id'];
        final sentAt = decoded['sent_at'] ?? decoded['created_at'];

        // Mark our own message as delivered when success comes back.
        if (senderId is String && senderId == widget.userId && success is bool && success) {
          setState(() {
            for (var i = _messages.length - 1; i >= 0; i--) {
              final msg = _messages[i];
              if (msg.isFromUser && !msg.delivered &&
                  (id is int && msg.id == id.toString() || id is String && id.isNotEmpty && msg.id == id || msg.content == (body ?? ''))) {
                _messages[i] = Message(
                  content: msg.content,
                  isFromUser: true,
                  senderName: msg.senderName,
                  senderId: msg.senderId,
                  delivered: true,
                  id: id is int ? id.toString() : (id is String ? id : msg.id),
                  timestamp: _parseTime(sentAt) ?? msg.timestamp,
                );
                break;
              }
            }
            _status = '';
          });
          return;
        }

        // Messages from others (or from server broadcast).
        if (body is String && body.isNotEmpty) {
          final senderName = senderId is String && senderId.isNotEmpty ? senderId : 'Server';
          setState(() {
            final already = _messages.any((m) => m.id.isNotEmpty && m.id == (id is int ? id.toString() : (id is String ? id : '')));
            if (!already) {
              final isSelf = senderId is String && senderId == widget.userId;
              _messages.add(
                Message(
                  content: body,
                  isFromUser: isSelf,
                  senderName: isSelf ? _selfName : senderName,
                  senderId: senderId is String ? senderId : '',
                  delivered: true,
                  id: id is int ? id.toString() : (id is String ? id : ''),
                  timestamp: _parseTime(sentAt),
                ),
              );
              final youtubeLink = _extractYoutubeUrl(body);
              if (youtubeLink != null) {
                _pendingYoutubeUrl = youtubeLink;
              }
            }
            _status = '';
          });
        }
        return;
      }
    } catch (_) {
      // Non-JSON payload; ignore.
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final youtubeLink = _extractYoutubeUrl(text);

    setState(() {
      _sending = true;
      _status = '';
      if (youtubeLink != null) {
        _pendingYoutubeUrl = youtubeLink;
      }
      _messages.add(
        Message(
          content: text,
          isFromUser: true,
          senderName: _selfName,
          senderId: widget.userId,
          delivered: false,
          id: '',
        ),
      );
    });

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_id': widget.roomId,
      'body': text,
    });

    _logger.i('Sending room message (route 301): $payload');
    widget.socketService.sendToRoute(301, payload);

    _controller.clear();

    // Optionally wait briefly for a response to surface errors; not required.
    Future.delayed(const Duration(milliseconds: 200)).then((_) {
      if (mounted) {
        setState(() => _sending = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxWebHeight = MediaQuery.of(context).size.height * 0.55;
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomName}'),
      ),
      body: Column(
        children: [
          _buildWebViewPane(maxWebHeight),
          Expanded(
            child: RoomChatContent(
              messages: _messages,
              scrollController: _scrollController,
              textController: _controller,
              sending: _sending,
              status: _status,
              youtubeUrl: _pendingYoutubeUrl,
              onOpenYoutube: _pendingYoutubeUrl != null
                  ? () => _openYoutubeInPlayer(_pendingYoutubeUrl!, maxWebHeight)
                  : null,
              onJumpToTimestamp: _pendingYoutubeUrl != null
                  ? (seconds) => _jumpToTimestamp(seconds, maxWebHeight)
                  : null,
              extractTimestampSeconds: _extractTimestampSeconds,
              onSend: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewPane(double maxHeight) {
    if (_webviewHeight <= 0 || _ytController == null) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: _webviewHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  child: ytp.YoutubePlayerScaffold(
                    controller: _ytController!,
                    builder: (context, player) => player,
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (details) {
              setState(() {
                _webviewHeight = (_webviewHeight + details.delta.dy)
                    .clamp(_minWebviewHeight, maxHeight);
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 36,
              child: Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 64,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade500,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close player',
                    onPressed: () => setState(() => _webviewHeight = 0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialMessages() async {
    if (_isLoading) return;
    _isLoading = true;
    setState(() => _status = 'Loading messages...');
    await _fetchMessages(limit: 30, beforeId: '');
    if (mounted) setState(() => _status = '');
    _isLoading = false;
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    await _fetchMessages(limit: 30, beforeId: _nextBeforeId);
    _isLoading = false;
  }

  Future<void> _fetchMessages({required int limit, required String beforeId}) async {
    final payload = jsonEncode({
      'room_id': widget.roomId,
      'user_id': widget.userId,
      'limit': limit,
      'before_id': beforeId,
      'include_system': false,
    });

    _logger.i('Fetching messages (route 310): $payload');
    widget.socketService.sendToRoute(310, payload);

    final raw = await _waitForFetchMessagesResponse(timeout: const Duration(seconds: 8));
    if (!mounted || raw == null) return;

    final parsed = _tryParseFetchMessagesResponse(raw);
    if (parsed == null) return;

    setState(() {
      _hasMore = parsed.hasMore;
      _nextBeforeId = parsed.nextBeforeId;
      if (parsed.messages.isNotEmpty) {
        // Prepend older messages
        _messages.insertAll(0, parsed.messages);
      }
    });
  }

  Future<String?> _waitForFetchMessagesResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeFetchMessagesJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for fetch messages response: $e');
      return null;
    }
  }

  bool _looksLikeFetchMessagesJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('messages') || decoded.containsKey('has_more'));
    } catch (_) {
      return false;
    }
  }

  _FetchMessagesResponse? _tryParseFetchMessagesResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final success = decoded['success'];
      if (success is! bool || !success) return null;

      final messagesRaw = decoded['messages'];
      final hasMore = decoded['has_more'];
      final nextBeforeId = decoded['next_before_id'];

      final parsed = <Message>[];
      if (messagesRaw is List) {
        for (final entry in messagesRaw) {
          if (entry is! Map) continue;
          final body = entry['body'];
          final senderId = entry['sender_id'];
          final senderName = entry['sender_name'];
          final id = entry['id'];
          final createdAt = entry['created_at'];

          if (body is! String) continue;

          final senderIdStr = senderId is String ? senderId : '';
          final isSelf = senderIdStr == widget.userId;
          parsed.add(
            Message(
              content: body,
              isFromUser: isSelf,
              senderName: isSelf
                  ? _selfName
                  : (senderName is String && senderName.isNotEmpty
                      ? senderName
                      : (senderIdStr.isNotEmpty ? senderIdStr : 'Server')),
              senderId: senderIdStr,
              delivered: true,
              id: id is int ? id.toString() : (id is String ? id : ''),
              timestamp: _parseTime(createdAt),
            ),
          );
        }
      }

      // Oldest first expected; ensure list is chronological.
      parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return _FetchMessagesResponse(
        messages: parsed,
        hasMore: hasMore is bool ? hasMore : false,
        nextBeforeId: nextBeforeId is String ? nextBeforeId : '',
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractYoutubeUrl(String text) {
    final regex = RegExp(
      r'(https?:\/\/(?:www\.)?(?:youtube\.com\/(?:watch\?v=|embed\/)[\w-]{11}|youtu\.be\/[\w-]{11})(?:[\w\-?&=%.]*)?)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(text);
    return match?.group(0);
  }

  void _jumpToTimestamp(int seconds, double maxHeight) {
    if (_ytController == null) {
      final url = _pendingYoutubeUrl;
      if (url != null) {
        _openYoutubeInPlayer(url, maxHeight);
      }
    }
    _ytController?.seekTo(
      seconds: seconds.toDouble(),
      allowSeekAhead: true,
    );
    _ytController?.playVideo();
    setState(() {
      if (_webviewHeight < _minWebviewHeight) {
        _webviewHeight = _minWebviewHeight;
      }
    });
  }

  int? _extractTimestampSeconds(String text) {
    final regex = RegExp(r'\b(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b');
    final match = regex.firstMatch(text);
    if (match == null) return null;
    final hStr = match.group(1);
    final mStr = match.group(2);
    final sStr = match.group(3);
    if (mStr == null || sStr == null) return null;
    final hours = hStr != null ? int.tryParse(hStr) ?? 0 : 0;
    final minutes = int.tryParse(mStr) ?? 0;
    final seconds = int.tryParse(sStr) ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  void _openYoutubeInPlayer(String url, double maxHeight) {
    final videoId = ytp.YoutubePlayerController.convertUrlToId(url);
    if (videoId == null || videoId.isEmpty) {
      _logger.w('Could not parse YouTube video ID from: $url');
      return;
    }

    if (_ytController == null) {
      _ytController = ytp.YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const ytp.YoutubePlayerParams(
          mute: false,
          showFullscreenButton: true,
          showControls: true,
          playsInline: true,
          origin: 'https://www.youtube-nocookie.com',
        ),
      );
    } else {
      _ytController!.loadVideoById(videoId: videoId, startSeconds: 0);
      _ytController!.playVideo();
    }

    setState(() {
      _pendingYoutubeUrl = url;
      _webviewHeight = _webviewHeight > 0
          ? (_webviewHeight < _minWebviewHeight ? _minWebviewHeight : _webviewHeight)
          : (maxHeight * 0.5 < _minWebviewHeight ? _minWebviewHeight : maxHeight * 0.5);
    });
  }

  DateTime? _parseTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class _FetchMessagesResponse {
  final List<Message> messages;
  final bool hasMore;
  final String nextBeforeId;

  _FetchMessagesResponse({
    required this.messages,
    required this.hasMore,
    required this.nextBeforeId,
  });
}
