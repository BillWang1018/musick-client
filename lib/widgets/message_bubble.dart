import 'package:flutter/material.dart';
import '../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  // 配合聊天室功能的參數
  final void Function(int seconds)? onJumpToTimestamp;
  final int? Function(String text)? extractTimestampSeconds;

  const MessageBubble({
    super.key,
    required this.message,
    this.onJumpToTimestamp,
    this.extractTimestampSeconds,
  });

  @override
  Widget build(BuildContext context) {
    // --- 這裡改回使用原本的變數名稱 ---
    final isUser = message.isFromUser; // 改用 isFromUser
    final isShazam = message.senderName == 'Shazam'; // 改用 senderName

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isShazam 
              ? Colors.indigo.shade100 // Shazam 訊息顯示靛藍色
              : (isUser ? Colors.blue.shade100 : Colors.grey.shade300),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
            bottomRight: isUser ? Radius.zero : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              Text(
                message.senderName, // 改用 senderName
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!isUser) const SizedBox(height: 4),
            Text(
              message.content,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}