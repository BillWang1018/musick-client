import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/socket_service.dart';
import '../models/message_model.dart';
import 'message_bubble.dart';

class RoomChatContent extends StatefulWidget {
  final List<Message> messages;
  final ScrollController scrollController;
  final TextEditingController textController;
  final bool sending;
  final String status;
  final VoidCallback onSend;
  final String? youtubeUrl;
  final VoidCallback? onOpenYoutube;
  final void Function(int seconds)? onJumpToTimestamp;
  final int? Function(String text)? extractTimestampSeconds;

  const RoomChatContent({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.textController,
    required this.sending,
    required this.status,
    required this.onSend,
    this.youtubeUrl,
    this.onOpenYoutube,
    this.onJumpToTimestamp,
    this.extractTimestampSeconds,
  });

  @override
  State<RoomChatContent> createState() => _RoomChatContentState();
}

class _RoomChatContentState extends State<RoomChatContent> {
  bool _isRecognizing = false;

  Future<void> _handleMusicIdentify(BuildContext context) async {
    setState(() => _isRecognizing = true);
    try {
      // 這裡發送假數據測試通道
      // 實際使用時請接上 record 套件錄製的 Base64
      String mockBase64 = "MOCK_AUDIO_DATA"; 
      await context.read<SocketService>().identifyMusic(mockBase64);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已發送辨識請求...')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRecognizing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 監聽 SocketService 的結果變數
    final lastResult = context.watch<SocketService>().lastShazamResult;

    return Column(
      children: [
        // 顯示辨識結果的頂部橫條
        if (lastResult != null)
          Container(
            color: Colors.indigo.shade50,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lastResult['success'] == true
                        ? "辨識成功: ${lastResult['message']}" 
                        : "辨識失敗: ${lastResult['message']}",
                    style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    context.read<SocketService>().lastShazamResult = null;
                    context.read<SocketService>().notifyListeners();
                  },
                )
              ],
            ),
          ),
        
        if (widget.status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(widget.status, textAlign: TextAlign.center),
          ),
        
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            controller: widget.scrollController,
            itemCount: widget.messages.length,
            itemBuilder: (context, index) {
              return MessageBubble(
                message: widget.messages[index],
                onJumpToTimestamp: widget.onJumpToTimestamp,
                extractTimestampSeconds: widget.extractTimestampSeconds,
              );
            },
          ),
        ),
        
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                // 辨識按鈕
                IconButton(
                  icon: _isRecognizing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mic, color: Colors.blue),
                  onPressed: _isRecognizing ? null : () => _handleMusicIdentify(context),
                ),
                Expanded(
                  child: TextField(
                    controller: widget.textController,
                    enabled: !widget.sending,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: widget.sending ? null : widget.onSend,
                  mini: true,
                  child: widget.sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}