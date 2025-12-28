import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // 1. 記得引入 provider
import '../services/socket_service.dart';
import 'supabase_auth_page.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final TextEditingController _ipController = TextEditingController(text: '10.0.2.2');
  final TextEditingController _portController = TextEditingController(text: '5896');
  bool _isConnecting = false;
  String _statusMessage = '';

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();

    if (ip.isEmpty || portText.isEmpty) {
      _showError('Please enter both IP and port');
      return;
    }

    int? port;
    try {
      port = int.parse(portText);
    } catch (e) {
      _showError('Invalid port number');
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connecting...';
    });

    // --- 關鍵修改開始 ---
    // 原本：final socketService = SocketService(); // 這是錯的，會創造分身
    // 修改為：直接從 Provider 獲取全域唯一的那個實體
    final socketService = context.read<SocketService>(); 
    // --- 關鍵修改結束 ---

    final connected = await socketService.connect(ip, port);

    if (mounted) {
      if (connected) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            // 這裡依然把 socketService 傳下去，保持相容性
            builder: (context) => SupabaseAuthPage(socketService: socketService),
          ),
        );
      } else {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Connection failed';
        });
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipController,
              enabled: !_isConnecting,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              enabled: !_isConnecting,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isConnecting ? null : _handleConnect,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
              child: _isConnecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 16),
            if (_statusMessage.isNotEmpty)
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusMessage.contains('failed')
                      ? Colors.red
                      : Colors.green,
                ),
              ),
          ],
        ),
      ),
    );
  }
}