import 'package:flutter/material.dart';

import '../models/message_model.dart';
import 'message_bubble.dart';

class RoomChatContent extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(status, textAlign: TextAlign.center),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            controller: scrollController,
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final tsSeconds = extractTimestampSeconds?.call(message.content);
              final canJump = youtubeUrl != null && onJumpToTimestamp != null;
              return Column(
                crossAxisAlignment:
                    message.isFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  MessageBubble(message: message),
                  if (canJump && tsSeconds != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextButton.icon(
                        onPressed: () => onJumpToTimestamp?.call(tsSeconds),
                        icon: const Icon(Icons.fast_forward),
                        label: Text('Jump to ${_formatTs(tsSeconds)}'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (youtubeUrl != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Open YouTube: $youtubeUrl',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: onOpenYoutube,
                  icon: const Icon(Icons.ondemand_video),
                  label: const Text('Open in player'),
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
                Expanded(
                  child: TextField(
                    controller: textController,
                    enabled: !sending,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: sending ? null : onSend,
                  mini: true,
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
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

String _formatTs(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}
