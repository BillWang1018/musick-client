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

  // 讓外部判斷是否連線中
  bool get isConnected => _socket != null;

  /// 清除辨識結果
  void clearShazamResult() {
    lastShazamResult = null;
    notifyListeners();
  }

  Future<bool> connect(String ip, int port) async {
    try {
      if (_socket != null) await disconnect();
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _startListening();
      logger.i('Connected to $ip:$port');
      notifyListeners();
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
        logger.i('Socket closed by server');
        _messageStream.add('Disconnected');
        disconnect();
      },
      cancelOnError: true,
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
      
      if (messageId == 401) {
        final response = jsonDecode(jsonStr);
        logger.i('【401】收到辨識結果: $response');
        lastShazamResult = response;
        notifyListeners(); 
      } else {
        _messageStream.add(jsonStr);
      }
    } catch (e) {
      logger.e('解析訊息失敗: $e');
    }
  }

  Future<void> identifyMusic(String base64Audio) async {
    try {
      final requestData = jsonEncode({'audio_data': base64Audio});
      final Uint8List payload = utf8.encode(requestData);
      // 使用 await 確保大型數據發送完成
      await _sendBytes(401, payload);
    } catch (e) {
      logger.e('發送辨識請求失敗: $e');
    }
  }

  Future<void> sendMessage(String message) async {
    final payload = utf8.encode(message);
    await _sendBytes(1, Uint8List.fromList(payload));
  }
  
  Future<void> sendToRoute(int routeId, String message) async {
    final payload = utf8.encode(message);
    await _sendBytes(routeId, Uint8List.fromList(payload));
  }

  // 改為 Future<void> 以便支援 await
  Future<void> _sendBytes(int routeId, Uint8List payload) async {
    if (_socket == null) return;
    try {
      final header = Uint8List(8);
      final view = ByteData.view(header.buffer);
      // 設定數據長度 (Little Endian)
      view.setUint32(0, payload.length, Endian.little);
      // 設定路由 ID (Little Endian)
      view.setUint32(4, routeId, Endian.little);

      // --- 發送數據 ---
      _socket!.add(header);  // 發送檔頭
      _socket!.add(payload); // 發送內容
      
      // --- 關鍵：強制刷新緩衝區，並等待完成 ---
      await _socket!.flush(); 
    } catch (e) {
      logger.e('發送失敗: $e'); 
      disconnect();
    }
  }

  Future<void> disconnect() async {
    try {
      await _socket?.flush();
    } catch (_) {}
    _socket?.destroy();
    _socket = null;
    _buffer = Uint8List(0);
    notifyListeners();
  }
}