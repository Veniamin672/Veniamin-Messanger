import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'screens/connect_screen.dart';
import 'screens/chat_screen.dart';
import 'services/connection.dart';
import 'services/device_id.dart';
import 'services/local_labels.dart';
import 'services/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await DeviceId.init();
  await LocalLabels.init();
  await VeniaminNotifications.init();
  runApp(const VeniaminApp());
}

class VeniaminApp extends StatelessWidget {
  const VeniaminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veniamin',
      debugShowCheckedModeBanner: false,
      theme: veniaminTheme,
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  final ConnectionService _conn = ConnectionService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conn.addListener(_onState);
    // автоподключение к последнему серверу, если не жали disconnect
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _conn.tryAutoConnect();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    VeniaminNotifications.lifecycle = state;
    // вернулись в приложение — если сессия должна жить, переподключаемся
    if (state == AppLifecycleState.resumed) {
      if (DeviceId.wantAutoConnect &&
          _conn.state != ConnState.authenticated &&
          _conn.state != ConnState.connecting &&
          _conn.state != ConnState.pending) {
        _conn.tryAutoConnect();
      }
    }
    // при паузе сами сокет НЕ рвём — пусть живёт, пока ОС позволит
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conn.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_conn.state == ConnState.authenticated) {
      return ChatScreen(connection: _conn);
    }
    // пока connecting — тоже connect screen со статусом
    return ConnectScreen(connection: _conn);
  }
}
