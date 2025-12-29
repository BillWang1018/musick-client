import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart'; // 1. 引入這行 (開關箱零件)
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/connect_page.dart';
import 'services/socket_service.dart'; // 2. 引入這行 (冷氣機)

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  // 嘗試初始化 Supabase (如果你的 .env 是假網址，這裡可能會印出錯誤但不會閃退)
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
     try {
       await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
     } catch (e) {
       print("Supabase 初始化警告: $e");
     }
  }

  runApp(
    // 3. 關鍵修改：使用 MultiProvider 把 SocketService (冷氣) 接上總電源
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SocketService()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget { 
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musick Client',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ConnectPage(),
    );
  }
}