import 'package:flutter/material.dart';
import 'package:biocampo_app/core/theme/app_theme.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/auth/presentation/screens/login_screen.dart';
import 'package:biocampo_app/features/home/presentation/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar Base de Datos Relacional SQLite WAL y Cargar Semillas
  final database = AppDatabase.instance;
  await database.initialize();

  final authService = AuthService(database: database);

  // Intentar restaurar sesión activa desde la tabla 'sesion_jwt' en SQLite
  final hasSession = await authService.restoreSession();

  runApp(BioCampoApp(
    authService: authService,
    initialLoggedIn: hasSession,
  ));
}

class BioCampoApp extends StatelessWidget {
  final AuthService authService;
  final bool initialLoggedIn;

  const BioCampoApp({
    super.key,
    required this.authService,
    this.initialLoggedIn = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BioCampo Móvil',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.solarLightTheme,
      darkTheme: AppTheme.solarDarkTheme,
      themeMode: ThemeMode.system,
      home: initialLoggedIn
          ? HomeScreen(authService: authService)
          : LoginScreen(authService: authService),
    );
  }
}
