import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

class SocketService with ChangeNotifier {
  final logger = Logger();
  Socket? _socket;
  final StreamController<String> _messageStream = StreamController<String>.broadcast();
  Uint8List _buffer = Uint8List(0);
  
  // 儲存辨識結果
  Map<String, dynamic>? lastShazamResult;

  Stream<String> get messages => _messageStream.stream;

  Future<bool> connect(String ip, int port) async {
    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _startListening();
      return true;
    } catch (e) {
      logger.e('Connection error: $e');
      return false;
    }
  }

  void _startListening() {
    _socket?.listen(
      (Uint8List data) {
        _handleIncomingData(data);
      },
      onError: (error) {
        logger.e('Socket error: $error');
        _messageStream.add('Error: $error');
        disconnect();
      },
      onDone: () {
        logger.i('Socket closed');
        _messageStream.add('Disconnected');
        disconnect();
      },
    );
  }

  void _handleIncomingData(Uint8List data) {
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setRange(0, _buffer.length, _buffer);
    newBuffer.setRange(_buffer.length, newBuffer.length, data);
    _buffer = newBuffer;

    while (_buffer.length >= 8) {
      final headerData = ByteData.view(_buffer.buffer);
      final dataSize = headerData.getUint32(0, Endian.little);
      final messageId = headerData.getUint32(4, Endian.little);

      if (_buffer.length < 8 + dataSize) break;

      final payload = _buffer.sublist(8, 8 + dataSize);
      _buffer = _buffer.sublist(8 + dataSize);

      _processMessage(messageId, payload);
    }
  }

  void _processMessage(int messageId, Uint8List payload) {
    try {
      final String jsonStr = utf8.decode(payload);
      
      // 處理 401 Shazam 辨識結果
      if (messageId == 401) {
        // --- 這裡就是證據！直接把原始資料印出來 ---
        print("\n\n🔥🔥🔥 [SHAZAM 原始證據] 🔥🔥🔥");
        print(jsonStr);
        print("🔥🔥🔥 [證據結束] 🔥🔥🔥\n\n");
        // -------------------------------------

        final response = jsonDecode(jsonStr);
        logger.i('【401】收到辨識結果: $response');
        lastShazamResult = response;
        notifyListeners(); 
      } 
      // 處理一般訊息
      else {
        _messageStream.add(jsonStr);
        logger.i('收到 MessageID $messageId: $jsonStr');
      }
    } catch (e) {
      logger.e('解析訊息失敗: $e');
    }
  }

  // 發送 Shazam 辨識請求
  Future<void> identifyMusic(String base64Audio) async {
    if (_socket == null) return;
    try {
      final requestData = jsonEncode({'audio_data': base64Audio});
      final Uint8List payload = utf8.encode(requestData);
      _sendBytes(401, payload); // 使用 helper 發送
      logger.i('【401】已發送辨識請求');
    } catch (e) {
      logger.e('發送請求失敗: $e');
    }
  }

  // --- 補回：舊頁面需要的聊天發送功能 ---
  Future<void> sendMessage(String message) async {
    if (_socket == null) return;
    // 這裡假設舊的 EchoPage 只需要發送純文字，通常是用 Route 1
    // 如果你的 EchoPage 需要特定 JSON 格式，請根據需求調整
    final payload = utf8.encode(message);
    _sendBytes(1, Uint8List.fromList(payload));
  }
  
  // 用來給 sendMessage 調用的通用發送方法 (Route 10 登入等也可以用)
  Future<void> sendToRoute(int routeId, String message) async {
      final payload = utf8.encode(message);
      _sendBytes(routeId, Uint8List.fromList(payload));
  }

  // 底層發送 bytes 方法
  void _sendBytes(int routeId, Uint8List payload) {
    if (_socket == null) return;
    final header = Uint8List(8);
    final view = ByteData.view(header.buffer);
    view.setUint32(0, payload.length, Endian.little);
    view.setUint32(4, routeId, Endian.little);
    _socket?.add(header);
    _socket?.add(payload);
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _buffer = Uint8List(0);
  }
}