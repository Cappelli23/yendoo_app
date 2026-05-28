// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// 👇 IMPORTANTE: tu archivo de opciones de Firebase
import 'firebase_options.dart';

// ✅ Push service
import 'services/push_notification_service.dart';

// Screens
import 'login_screen.dart';
import 'local_dashboard.dart';
import 'screens/cadete/cadete_dashboard.dart';
import 'screens/cadete/perfil_screen.dart';
import 'screens/cadete/historial_pedidos_cadete_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/admin_locales_screen.dart';
import 'screens/admin/admin_cadetes_screen.dart';
import 'screens/local/generar_pedido_screen.dart';
import 'screens/local/personalizar_pedido_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Para recibir la notificación alcanza con registrar el handler.
  // Si luego querés lógica extra acá, la agregamos.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ usar las opciones por plataforma
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Registrar background handler (Android/iOS)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // ✅ En Web, persistencia local
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yendo App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const _RootGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/localDashboard': (context) => const LocalDashboard(),
        '/cadeteDashboard': (context) => const CadeteDashboardScreen(),
        '/perfilCadete': (context) => const PerfilScreen(),
        '/historialPedidosCadete': (context) =>
            const HistorialPedidosCadeteScreen(),
        '/adminDashboard': (context) => const AdminDashboardScreen(),
        '/verLocalesAdmin': (context) => const AdminLocalesScreen(),
        '/verCadetesAdmin': (context) => const AdminCadetesScreen(),
        '/generarPedido': (context) => const GenerarPedidoScreen(),
        '/personalizarPedido': (context) => const PersonalizarPedidoScreen(),
      },
    );
  }
}

class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!authSnap.hasData) {
          return const LoginScreen();
        }

        final uid = authSnap.data!.uid;
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('usuarios').doc(uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnap.hasData || !userSnap.data!.exists) {
              return const LoginScreen();
            }

            final data = userSnap.data!.data() ?? {};
            final rol = (data['rol'] ?? '').toString().toLowerCase();

            switch (rol) {
              case 'cadete':
                // ✅ Registrar token + topic al entrar como cadete
                return const _CadeteGate();
              case 'local':
                return const LocalDashboard();
              case 'admin':
                return const AdminDashboardScreen();
              default:
                return const LoginScreen();
            }
          },
        );
      },
    );
  }
}

/// ✅ Gate para registrar FCM del cadete UNA VEZ antes de entrar al dashboard
class _CadeteGate extends StatefulWidget {
  const _CadeteGate();

  @override
  State<_CadeteGate> createState() => _CadeteGateState();
}

class _CadeteGateState extends State<_CadeteGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _initCadete();
  }

  Future<void> _initCadete() async {
    try {
      await PushNotificationService.instance.registerCadeteActive();
    } catch (_) {
      // Si falla, igual dejamos entrar al dashboard
    }

    if (!mounted) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return const CadeteDashboardScreen();
  }
}
