import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

class SocketService with ChangeNotifier {
  final logger = Logger();
  Socket? _socket;
  final StreamController<String> _messageStream = StreamController<String>.broadcast();
  String? _lastIp;
  int? _lastPort;
  Timer? _reconnectTimer;
  bool _manuallyDisconnected = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  int? _authRouteId;
  String? _authPayload;
  Uint8List _buffer = Uint8List(0);
  
  // 儲存辨識結果
  Map<String, dynamic>? lastShazamResult;

  Stream<String> get messages => _messageStream.stream;


  /// 清除辨識結果
  void clearShazamResult() {
    lastShazamResult = null;
    notifyListeners();
  }

  Future<bool> connect(String ip, int port) async {
    _manuallyDisconnected = false;
    _lastIp = ip;
    _lastPort = port;
    return _openSocket(ip, port);
  }

  Future<bool> _openSocket(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true);

      _socket = socket;
      _resetReconnectState();
      _startListening();
      _sendPersistedAuthPayload();
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
        _handleSocketClosure('Disconnected');
      },
      onDone: () {
        logger.i('Socket closed');
        _handleSocketClosure('Disconnected');
      },
      cancelOnError: true,
    );
  }

  void _handleSocketClosure(String? notice) {
    _tearDownSocket();
    if (notice != null && !_manuallyDisconnected) {
      _messageStream.add(notice);
    }
    if (_manuallyDisconnected) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final ip = _lastIp;
    final port = _lastPort;
    if (ip == null || port == null) return;
    if (_isReconnecting) return;

    final delaySeconds = [1, 2, 4, 8, 16][_reconnectAttempts.clamp(0, 4)];
    _isReconnecting = true;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_manuallyDisconnected) {
        _isReconnecting = false;
        return;
      }

      final ok = await _openSocket(ip, port);
      if (ok) {
        logger.i('Reconnected to $ip:$port');
        _messageStream.add('Reconnected');
      } else {
        _isReconnecting = false;
        _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 4);
        _scheduleReconnect();
      }
    });
  }

  void _resetReconnectState() {
    _reconnectAttempts = 0;
    _isReconnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _handleIncomingData(Uint8List data) {
    // Append incoming data to buffer by creating a new buffer
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setRange(0, _buffer.length, _buffer);
    newBuffer.setRange(_buffer.length, newBuffer.length, data);
    _buffer = newBuffer; // Reassign buffer

    // Process complete messages from buffer
    int offset = 0;
    while (offset + 8 <= _buffer.length) {
      final byteData = ByteData.view(_buffer.buffer, _buffer.offsetInBytes + offset, _buffer.length - offset);
      final size = byteData.getInt32(0, Endian.little);
      
      // Check if we have a complete message
      if (offset + 8 + size > _buffer.length) {
        break; // Wait for more data
      }

      final id = byteData.getInt32(4, Endian.little);
      final messageData = _buffer.sublist(offset + 8, offset + 8 + size);
      final messageText = utf8.decode(messageData);

      logger.d('Received - ID: $id, Size: $size, Data: $messageText');
      _messageStream.add(messageText);

      offset += 8 + size;

      _processMessage(id, messageData);
    }

    // Remove processed data from buffer
    if (offset > 0) {
      if (offset < _buffer.length) {
        _buffer = _buffer.sublist(offset);
      } else {
        _buffer = Uint8List(0); // All processed, reset buffer
      }
    }
  }

  /// Sends a UTF-8 message to the default echo route (ID=1).
  void sendMessage(String message) => sendToRoute(1, message);

  /// Sends a UTF-8 message to an arbitrary EasyTCP route ID.
  /// Example: sendToRoute(10, 'abc')
  void sendToRoute(int routeId, String message) {
    sendBytes(routeId, Uint8List.fromList(utf8.encode(message)));
  }

  /// Stores a payload that should be re-sent automatically after reconnect.
  void rememberAuthPayload(int routeId, String payload) {
    _authRouteId = routeId;
    _authPayload = payload;
  }

  /// Sends raw bytes to an arbitrary EasyTCP route ID.
  /// Packet format: Size(4)|ID(4)|Data(n) in little-endian.
  void sendBytes(int routeId, Uint8List payload) {
    final socket = _socket;
    if (socket == null) {
      logger.w('Not connected');
      return;
    }

    if (routeId < 0 || routeId > 0x7fffffff) {
      logger.e('Invalid routeId (must fit int32): $routeId');
      return;
    }

    if (payload.length > 0x7fffffff) {
      logger.e('Payload too large: ${payload.length}');
      return;
    }

    try {
      final size = payload.length;

      final buffer = Uint8List(8 + size);
      final byteData = ByteData.view(buffer.buffer);
      byteData.setInt32(0, size, Endian.little);
      byteData.setInt32(4, routeId, Endian.little);
      buffer.setRange(8, 8 + size, payload);

      socket.add(buffer);
      socket.flush();
    } catch (e) {
      logger.e('Send error: $e');
    }
  }

  void disconnect() {
    _manuallyDisconnected = true;
    _resetReconnectState();
    _tearDownSocket();
    _authRouteId = null;
    _authPayload = null;
    _messageStream.add('Disconnected');
  }

  bool isConnected() {
    return _socket != null && !_isReconnecting;
  }

  @override
  void dispose() {
    super.dispose();
    disconnect();
    _messageStream.close();
  }

  void _tearDownSocket() {
    _socket?.destroy();
    _socket = null;
    _buffer = Uint8List(0);
  }

  void _sendPersistedAuthPayload() {
    final routeId = _authRouteId;
    final payload = _authPayload;
    if (routeId == null || payload == null) return;

    try {
      sendToRoute(routeId, payload);
      logger.i('Re-sent auth payload on route $routeId after reconnect');
    } catch (e) {
      logger.w('Failed to resend auth payload: $e');
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
}
