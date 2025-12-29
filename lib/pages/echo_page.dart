import 'dart:async';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import 'connect_page.dart';
import 'room_list_page.dart';

class EchoPage extends StatefulWidget {
  final SocketService socketService;
  final String title;
  final String? userId;
  final String? userName;

  const EchoPage({
    super.key,
    required this.socketService,
    this.title = 'Echo Test',
    this.userId,
    this.userName,
  });

  @override
  State<EchoPage> createState() => _EchoPageState();
}

class _EchoPageState extends State<EchoPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  late ScrollController _scrollController;
  StreamSubscription<String>? _messageSub;
  bool _connected = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _connected = widget.socketService.isConnected();
    _listenToMessages();
  }

  void _listenToMessages() {
    _messageSub = widget.socketService.messages.listen((message) {
      if (!mounted) return;
      final isError = message.startsWith('Error:');
      final isDisconnect = message == 'Disconnected';
      setState(() {
        _messages.add({
          'text': message,
          'isReceived': !message.startsWith('[SEND]'),
          'timestamp': DateTime.now(),
        });
        if (isError || isDisconnect) {
          _connected = false;
        }
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      return;
    }

    widget.socketService.sendMessage(message);
    
    setState(() {
      _messages.add({
        'text': message,
        'isReceived': false,
        'timestamp': DateTime.now(),
      });
    });

    _messageController.clear();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSub?.cancel();
    widget.socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          widget.socketService.disconnect();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (widget.userId != null && widget.userId!.isNotEmpty)
              IconButton(
                tooltip: 'Rooms',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RoomListPage(
                        socketService: widget.socketService,
                        userId: widget.userId!,
                        userName: widget.userName,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.meeting_room),
              ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: InkWell(
                  onTap: _handleConnectionTap,
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 12,
                        color: _connected ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(_connected ? 'Connected' : 'Disconnected'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _buildMessageBubble(msg);
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _sendMessage,
                    mini: true,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleConnectionTap() {
    widget.socketService.disconnect();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ConnectPage()),
      (route) => false,
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isReceived = message['isReceived'] as bool;
    final text = message['text'] as String;

    return Align(
      alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isReceived ? Colors.grey[300] : Colors.blue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isReceived ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
