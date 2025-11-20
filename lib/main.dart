// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ✅ En Web, aseguramos persistencia local (mantiene la sesión tras recargar)
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
      // Usamos un gate que observa el authState y redirige solo
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

/// Observa el estado de autenticación y decide adónde ir.
/// Si no hay sesión → Login.
/// Si hay sesión → lee el rol en Firestore y envía al dashboard correcto.
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

        // 🔴 No logueado
        if (!authSnap.hasData) {
          return const LoginScreen();
        }

        // 🟢 Logueado: resolvemos rol
        final uid = authSnap.data!.uid;
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future:
              FirebaseFirestore.instance.collection('usuarios').doc(uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (!userSnap.hasData || !userSnap.data!.exists) {
              // Si no existe el doc, mandamos a login (o podrías crear el doc aquí)
              return const LoginScreen();
            }

            final data = userSnap.data!.data() ?? {};
            final rol = (data['rol'] ?? '').toString().toLowerCase();

            switch (rol) {
              case 'cadete':
                return const CadeteDashboardScreen();
              case 'local':
                return const LocalDashboard();
              case 'admin':
                return const AdminDashboardScreen();
              default:
                // Rol desconocido → volver a login
                return const LoginScreen();
            }
          },
        );
      },
    );
  }
}
