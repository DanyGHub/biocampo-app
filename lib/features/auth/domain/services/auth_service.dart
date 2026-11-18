import 'package:shared_preferences/shared_preferences.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import '../models/usuario_model.dart';
import '../models/jwt_token_model.dart';
import '../models/sesion_jwt_model.dart';
import 'jwt_service.dart';

/// Resultado de la operación de autenticación
class AuthResult {
  final bool success;
  final String message;
  final UsuarioModel? usuario;
  final String? token;
  final JwtTokenModel? decodedToken;

  const AuthResult({
    required this.success,
    required this.message,
    this.usuario,
    this.token,
    this.decodedToken,
  });

  @override
  String toString() {
    return 'AuthResult(success: $success, message: $message, usuario: ${usuario?.matricula})';
  }
}

/// Servicio de Autenticación de BioCampo
/// Gestiona credenciales locales, emisión/validación de tokens JWT y persistencia multiplataforma
class AuthService {
  static const String _prefTokenKey = 'biocampo_active_jwt_token';

  final AppDatabase _database;
  final JwtService _jwtService;

  UsuarioModel? _currentUser;
  String? _currentToken;
  JwtTokenModel? _currentDecodedToken;

  AuthService({
    AppDatabase? database,
    JwtService? jwtService,
  })  : _database = database ?? AppDatabase.instance,
        _jwtService = jwtService ?? JwtService();

  UsuarioModel? get currentUser => _currentUser;
  String? get currentToken => _currentToken;
  JwtTokenModel? get currentDecodedToken => _currentDecodedToken;
  bool get isAuthenticated => _currentUser != null && _currentToken != null && !(_currentDecodedToken?.isExpired ?? true);

  /// Restaura la sesión persistida tanto en SQLite como en almacenamiento del navegador/dispositivo
  Future<bool> restoreSession() async {
    String? tokenToRestore;

    // 1. Intentar obtener desde base de datos SQLite
    final activeSession = await _database.getActiveSession();
    if (activeSession != null) {
      tokenToRestore = activeSession.jwtToken;
    }

    // 2. Si no hay en memoria SQLite (ej. recarga F5 en Chrome), consultar SharedPreferences
    if (tokenToRestore == null || tokenToRestore.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        tokenToRestore = prefs.getString(_prefTokenKey);
      } catch (_) {}
    }

    if (tokenToRestore == null || tokenToRestore.isEmpty) {
      return false;
    }

    // 3. Validar firma criptográfica con HMAC-SHA256
    final isValid = _jwtService.verifyToken(tokenToRestore);
    if (!isValid) {
      await logout();
      return false;
    }

    // 4. Decodificar y verificar expiración
    final decoded = _jwtService.decodeToken(tokenToRestore);
    if (decoded == null || decoded.isExpired) {
      await logout();
      return false;
    }

    // 5. Cargar datos del usuario
    var user = await _database.getUsuarioById(decoded.usuarioId);
    if (user == null && decoded.matricula.isNotEmpty) {
      user = await _database.getUsuarioByMatricula(decoded.matricula);
    }

    if (user == null) {
      await logout();
      return false;
    }

    _currentUser = user;
    _currentToken = tokenToRestore;
    _currentDecodedToken = decoded;
    return true;
  }

  /// Inicia sesión mediante credenciales de usuario (matrícula) y contraseña
  Future<AuthResult> login(String matricula, String password) async {
    final cleanMatricula = matricula.trim();
    if (cleanMatricula.isEmpty || password.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'Por favor ingrese matrícula y contraseña.',
      );
    }

    // 1. Buscar usuario en la base de datos relacional
    final usuario = await _database.getUsuarioByMatricula(cleanMatricula);
    if (usuario == null) {
      return const AuthResult(
        success: false,
        message: 'Usuario no registrado en la base local de la expedición.',
      );
    }

    // 2. Verificar hash criptográfico con Salt
    final calculatedHash = AppDatabase.hashPassword(password, usuario.salt);
    if (calculatedHash != usuario.passwordHash) {
      return const AuthResult(
        success: false,
        message: 'Contraseña incorrecta. Verifique sus credenciales.',
      );
    }

    // 3. Generar JSON Web Token (JWT) firmado con HMAC-SHA256
    final token = _jwtService.generateToken(usuario);
    final decoded = _jwtService.decodeToken(token);

    // 4. Actualizar auditoría de último login en BD
    await _database.updateUltimoLogin(usuario.id!);

    // 5. Persistir sesión relacional en SQLite (sesion_jwt)
    if (decoded != null) {
      final sesion = SesionJwtModel(
        usuarioId: usuario.id!,
        jwtToken: token,
        algoritmo: decoded.algorithm,
        emitidoEn: decoded.issuedAt.toIso8601String(),
        expiraEn: decoded.expiresAt.toIso8601String(),
        activo: true,
      );
      await _database.saveActiveSession(sesion);
    }

    // 6. Persistir en SharedPreferences para resistencia a F5 en Chrome y reinicios
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefTokenKey, token);
    } catch (_) {}

    // 7. Guardar sesión en memoria
    _currentUser = usuario;
    _currentToken = token;
    _currentDecodedToken = decoded;

    return AuthResult(
      success: true,
      message: '¡Bienvenido, ${usuario.nombreCompleto}!',
      usuario: usuario,
      token: token,
      decodedToken: decoded,
    );
  }

  /// Cierra la sesión activa en memoria, en SQLite y en almacenamiento local
  Future<void> logout() async {
    await _database.clearActiveSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefTokenKey);
    } catch (_) {}
    _currentUser = null;
    _currentToken = null;
    _currentDecodedToken = null;
  }
}
