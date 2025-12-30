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
  SocketService? _socketService; // Make nullable to handle cases where provider fails

  @override
  void initState() {
    super.initState();
    // Safely get the service
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _socketService = context.read<SocketService>();
        _socketService?.addListener(_handleShazamResult);
      }
    });
  }

  @override
  void dispose() {
    // FIX: Wrap listener removal in try-catch. 
    // If the Page/Provider disposes the Service BEFORE this widget disposes,
    // calling removeListener on a disposed ChangeNotifier causes a crash.
    try {
      _socketService?.removeListener(_handleShazamResult);
    } catch (e) {
      // Ignore errors if service is already disposed
    }
    
    // Dispose recorder safely
    try {
      _audioRecorder.dispose();
    } catch (e) {
      // Ignore recorder dispose errors
    }
    
    super.dispose();
  }

  void _handleShazamResult() {
    // FIX: Strict mounted check
    if (!mounted || _socketService == null) return;

    final result = _socketService!.lastShazamResult;

    if (result != null && result['success'] == true) {
      final track = result['result']['track'];
      if (track != null) {
        final title = track['title'] ?? 'Unknown Title';
        final artist = track['subtitle'] ?? 'Unknown Artist';
        final String messageText = "🎵 I just identified this song:\n$title - $artist";

        if (mounted) {
          widget.textController.text = messageText;
          widget.onSend();
        }
      }
      // Check mounted before clearing if needed, though clearing is usually safe
      _socketService!.clearShazamResult();
      
    } else if (result != null && result['success'] == false) {
      if (mounted) {
        _showSnackBar('Identification failed: ${result['message']}');
      }
      _socketService!.clearShazamResult();
    }
  }

  Future<void> _handleFilePickAndIdentify(BuildContext context) async {
    final socketService = context.read<SocketService>();
    if (!socketService.isConnected()) {
      _showSnackBar('Not connected to server');
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
          _showSnackBar('Format error: Only WAV files supported');
          return;
        }

        final int sizeInBytes = await file.length();
        const int maxSizeBytes = 2 * 1024 * 1024; // 2MB

        if (sizeInBytes > maxSizeBytes) {
          _showSnackBar('File too large: Please upload WAV under 2MB');
          return;
        }

        if (mounted) setState(() => _isRecognizing = true);
        final bytes = await file.readAsBytes();
        String base64Audio = base64Encode(bytes);
        
        await socketService.identifyMusic(base64Audio);
        _showSnackBar('File sent for identification...');
      }
    } catch (e) {
      _showSnackBar('File read error: $e');
    } finally {
      if (mounted) setState(() => _isRecognizing = false);
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatTs(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
              final message = widget.messages[index];
              final tsSeconds = widget.extractTimestampSeconds?.call(message.content);
              final canJump = widget.youtubeUrl != null && widget.onJumpToTimestamp != null && tsSeconds != null;
              
              return Column(
                crossAxisAlignment:
                    message.isFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // if (!message.isFromUser) ...[
                  //   Padding(
                  //     padding: const EdgeInsets.only(left: 4, bottom: 2),
                  //     child: Text(
                  //       message.senderName,
                  //       style: const TextStyle(fontSize: 12, color: Colors.grey),
                  //     ),
                  //   ),
                  // ],
                  Row(
                     mainAxisAlignment: message.isFromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                     crossAxisAlignment: CrossAxisAlignment.end,
                     children: [
                       if (!message.isFromUser) _buildTimeText(message),
                       Flexible(
                         child: Column(
                           crossAxisAlignment: message.isFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                           children: [
                             MessageBubble(message: message),
                             if (canJump)
                               Padding(
                                 padding: const EdgeInsets.only(top: 4, bottom: 8),
                                 child: InkWell(
                                   onTap: () => widget.onJumpToTimestamp?.call(tsSeconds),
                                   child: Container(
                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                     decoration: BoxDecoration(
                                       color: Colors.red.shade50,
                                       borderRadius: BorderRadius.circular(12),
                                       border: Border.all(color: Colors.red.shade100),
                                     ),
                                     child: Row(
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                         const Icon(Icons.play_arrow, size: 16, color: Colors.red),
                                         Text('Jump to ${_formatTs(tsSeconds)}', 
                                            style: const TextStyle(color: Colors.red, fontSize: 12)),
                                       ],
                                     ),
                                   ),
                                 ),
                               ),
                           ],
                         ),
                       ),
                       if (message.isFromUser) _buildTimeText(message),
                     ],
                  ),
                ],
              );
            },
          ),
        ),
        
        // --- YouTube Frame ---
        if (widget.youtubeUrl != null)
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'YouTube Link: ${widget.youtubeUrl}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.blue),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onOpenYoutube,
                  icon: const Icon(Icons.ondemand_video),
                  label: const Text('Open Player'),
                ),
              ],
            ),
          ),
          
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.orange),
                  onPressed: _isRecognizing ? null : () => _handleFilePickAndIdentify(context),
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
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeText(Message message) {
    // Placeholder for time display logic
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            "${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}",
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          if (message.isFromUser)
             const Icon(Icons.check, size: 12, color: Colors.blue),
        ],
      ),
    );
  }
}