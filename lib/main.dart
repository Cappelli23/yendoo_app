import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
      initialRoute: '/login',
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
