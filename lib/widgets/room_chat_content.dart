import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
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
  final AudioRecorder _audioRecorder = AudioRecorder();
  late SocketService _socketService; 

  @override
  void initState() {
    super.initState();
    _socketService = context.read<SocketService>();
    _socketService.addListener(_handleShazamResult);
  }

  @override
  void dispose() {
    _socketService.removeListener(_handleShazamResult);
    _audioRecorder.dispose();
    super.dispose();
  }

  // --- 核心邏輯：收到辨識結果後，模擬使用者發送訊息 ---
  void _handleShazamResult() {
    final result = _socketService.lastShazamResult;

    if (result != null && result['success'] == true) {
      final track = result['result']['track'];

      if (track != null) {
        final title = track['title'] ?? '未知歌名';
        final artist = track['subtitle'] ?? '未知歌手';
        
        final String messageText = "🎵 我剛剛辨識到了這首歌：\n$title - $artist";

        if (mounted) {
          widget.textController.text = messageText;
          widget.onSend();
        }
      }
      _socketService.clearShazamResult();
      
    } else if (result != null && result['success'] == false) {
       if (mounted) {
         _showSnackBar('辨識失敗: ${result['message']}');
       }
       _socketService.clearShazamResult();
    }
  }

  // --- 功能 A: 檔案選取辨識 (保留此功能) ---
  Future<void> _handleFilePickAndIdentify(BuildContext context) async {
    final socketService = context.read<SocketService>();
    if (!(socketService.isConnected())) {
      _showSnackBar('尚未連線到伺服器');
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, 
        allowedExtensions: ['wav'], 
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        
        if (!file.path.toLowerCase().endsWith('.wav')) {
          _showSnackBar('格式錯誤：僅支援 WAV 檔案');
          return;
        }

        final int sizeInBytes = await file.length();
        const int maxSizeBytes = 2 * 1024 * 1024; // 2MB

        if (sizeInBytes > maxSizeBytes) {
          _showSnackBar('檔案過大：請上傳小於 2MB 的 WAV 檔案');
          return;
        }

        setState(() => _isRecognizing = true);
        final bytes = await file.readAsBytes();
        String base64Audio = base64Encode(bytes);
        
        await socketService.identifyMusic(base64Audio);
        _showSnackBar('檔案已送出辨識...');
      }
    } catch (e) {
      _showSnackBar('讀取檔案失敗: $e');
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }


  void _showSnackBar(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                // 檔案選取按鈕 (保留)
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.orange),
                  onPressed: _isRecognizing ? null : () => _handleFilePickAndIdentify(context),
                ),
                
                // --- 錄音按鈕已隱藏 (邏輯保留) ---
                /*
                IconButton(
                  icon: _isRecognizing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.mic, color: Colors.blue),
                  onPressed: _isRecognizing ? null : () => _handleMusicIdentify(context),
                ),
                */
                
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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