import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/features/auth/domain/models/usuario_model.dart';
import 'package:biocampo_app/features/auth/domain/services/jwt_service.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';

void main() {
  group('Paso 1: Pruebas Unitarias de Base de Datos Relacional y Modelos', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.instance;
      db.clearForTesting();
      await db.initialize();
    });

    test('CP-01.1: Inicialización de BD y Carga de Datos Semilla de Biólogos', () async {
      final biologo1 = await db.getUsuarioByMatricula('biologo1');
      expect(biologo1, isNotNull);
      expect(biologo1!.nombreCompleto, contains('Carlos Gómez'));
      expect(biologo1.rol, equals('Investigador Titular'));
      expect(biologo1.passwordHash, isNotEmpty);

      final investigador2 = await db.getUsuarioByMatricula('investigador2');
      expect(investigador2, isNotNull);
      expect(investigador2!.nombreCompleto, contains('Elena Ramos'));
    });

    test('CP-01.2: Integridad Relacional 1:N entre Usuario y Reportes', () async {
      final biologo = (await db.getUsuarioByMatricula('biologo1'))!;

      final nuevoReporte = ReporteModel(
        usuarioId: biologo.id!,
        fechaHora: DateTime.now().toIso8601String(),
        latitud: 21.8853,
        longitud: -102.2916,
        altitud: 1880.5,
        precisionGps: 3.2,
        nombreComun: 'Jaguarundi (Herpailurus yagouaroundi)',
        notas: 'Avistamiento en sendero rocoso bajo dosel.',
      );

      final idInsertado = await db.insertReporte(nuevoReporte);
      expect(idInsertado, isPositive);

      final reportesBiologo = await db.getReportes(usuarioId: biologo.id);
      expect(reportesBiologo.length, equals(1));
      expect(reportesBiologo.first.nombreComun, contains('Jaguarundi'));
      expect(reportesBiologo.first.latitud, closeTo(21.8853, 0.001));
      expect(reportesBiologo.first.usuarioId, equals(biologo.id));
    });

    test('CP-01.3: Violación de Clave Foránea lanza Excepción', () async {
      const idInexistente = 9999;
      final reporteInvalido = ReporteModel(
        usuarioId: idInexistente,
        fechaHora: DateTime.now().toIso8601String(),
        latitud: 19.4326,
        longitud: -99.1332,
        nombreComun: 'Especie Huérfana',
      );

      expect(
        () async => await db.insertReporte(reporteInvalido),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CP-01.4: Edición / Modificación de Reporte en Base de Datos', () async {
      final biologo = (await db.getUsuarioByMatricula('biologo1'))!;

      final reporte = ReporteModel(
        usuarioId: biologo.id!,
        fechaHora: DateTime.now().toIso8601String(),
        latitud: 21.8853,
        longitud: -102.2916,
        altitud: 1880.5,
        precisionGps: 3.2,
        nombreComun: 'Jaguarundi Original',
        notas: 'Notas iniciales',
      );

      final insertId = await db.insertReporte(reporte);
      final reporteGuardado = (await db.getReportes()).firstWhere((r) => r.id == insertId);

      final modificado = reporteGuardado.copyWith(
        nombreComun: 'Jaguarundi (Modificado)',
        notas: 'Observación corregida con ejemplar adulto.',
      );

      final updateOk = await db.updateReporte(modificado);
      expect(updateOk, isTrue);

      final reporteConsultado = (await db.getReportes()).firstWhere((r) => r.id == insertId);
      expect(reporteConsultado.nombreComun, equals('Jaguarundi (Modificado)'));
      expect(reporteConsultado.notas, contains('Observación corregida'));
    });

    test('CP-01.5: Eliminación de Reporte en Base de Datos', () async {
      final biologo = (await db.getUsuarioByMatricula('biologo1'))!;

      final reporte = ReporteModel(
        usuarioId: biologo.id!,
        fechaHora: DateTime.now().toIso8601String(),
        latitud: 21.8853,
        longitud: -102.2916,
        nombreComun: 'Especie para Borrar',
      );

      final insertId = await db.insertReporte(reporte);
      expect((await db.getReportes()).any((r) => r.id == insertId), isTrue);

      final deleteOk = await db.deleteReporte(insertId);
      expect(deleteOk, isTrue);

      expect((await db.getReportes()).any((r) => r.id == insertId), isFalse);
    });
  });

  group('Paso 1: Pruebas Unitarias del Servicio JWT (RFC 7519)', () {
    late JwtService jwtService;
    late UsuarioModel usuarioPrueba;

    setUp(() {
      jwtService = JwtService(secretKey: 'Secret_Test_Key_123');
      usuarioPrueba = const UsuarioModel(
        id: 42,
        matricula: 'BIO-042',
        nombreCompleto: 'Biólogo de Prueba',
        passwordHash: 'hash123',
        salt: 'salt123',
        rol: 'Investigador de Campo',
      );
    });

    test('CP-02.1: Generación y Firma Determinista de Token JWT (HS256)', () {
      final token = jwtService.generateToken(usuarioPrueba);
      expect(token, isNotEmpty);
      final partes = token.split('.');
      expect(partes.length, equals(3), reason: 'Un JWT válido debe tener Header.Payload.Signature');

      final esValido = jwtService.verifyToken(token);
      expect(esValido, isTrue);
    });

    test('CP-02.2: Decodificación y Extracción de Claims del JWT', () {
      final token = jwtService.generateToken(usuarioPrueba);
      final decoded = jwtService.decodeToken(token);

      expect(decoded, isNotNull);
      expect(decoded!.usuarioId, equals(42));
      expect(decoded.matricula, equals('BIO-042'));
      expect(decoded.nombre, equals('Biólogo de Prueba'));
      expect(decoded.rol, equals('Investigador de Campo'));
      expect(decoded.algorithm, equals('HS256'));
      expect(decoded.isExpired, isFalse);
    });

    test('CP-02.3: Detección Inmediata de Adulteración en Firma o Payload', () {
      final token = jwtService.generateToken(usuarioPrueba);
      final partes = token.split('.');

      // Alterar un solo carácter de la firma
      final firmaBase = partes[2].substring(0, partes[2].length - 1);
      final firmaAlterada = '${firmaBase}X';
      final tokenAdulterado = '${partes[0]}.${partes[1]}.$firmaAlterada';

      expect(jwtService.verifyToken(tokenAdulterado), isFalse);
      expect(jwtService.decodeToken(tokenAdulterado), isNull);
    });
  });

  group('Paso 1: Pruebas Unitarias de Autenticación con Credenciales', () {
    late AuthService authService;
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.instance;
      db.clearForTesting();
      await db.initialize();
      authService = AuthService(database: db);
    });

    test('CP-03.1: Login Exitoso con Credenciales de Biólogo y Emisión de JWT', () async {
      final resultado = await authService.login('biologo1', 'BioCampo2026!');

      expect(resultado.success, isTrue);
      expect(resultado.usuario, isNotNull);
      expect(resultado.token, isNotNull);
      expect(resultado.decodedToken, isNotNull);
      expect(resultado.decodedToken!.matricula, equals('biologo1'));
      expect(authService.isAuthenticated, isTrue);
    });

    test('CP-03.2: Login Rechazado por Contraseña Incorrecta', () async {
      final resultado = await authService.login('biologo1', 'PasswordEquivocada!');

      expect(resultado.success, isFalse);
      expect(resultado.message, contains('Contraseña incorrecta'));
      expect(authService.isAuthenticated, isFalse);
    });

    test('CP-03.3: Login Rechazado por Usuario Inexistente', () async {
      final resultado = await authService.login('usuario_fantasma', '123456');

      expect(resultado.success, isFalse);
      expect(resultado.message, contains('Usuario no registrado'));
      expect(authService.isAuthenticated, isFalse);
    });

    test('CP-03.4: Persistencia Relacional de Sesión JWT en SQLite y Restauración Automática', () async {
      // 1. Iniciar sesión para generar y persistir sesión en SQLite
      final loginRes = await authService.login('biologo1', 'BioCampo2026!');
      expect(loginRes.success, isTrue);

      // 2. Simular reinicio de la aplicación creando una nueva instancia del servicio
      final nuevoAuthService = AuthService(database: db);
      expect(nuevoAuthService.isAuthenticated, isFalse);

      // 3. Restaurar sesión desde SQLite
      final restaurado = await nuevoAuthService.restoreSession();
      expect(restaurado, isTrue);
      expect(nuevoAuthService.isAuthenticated, isTrue);
      expect(nuevoAuthService.currentUser?.matricula, equals('biologo1'));
      expect(nuevoAuthService.currentToken, equals(loginRes.token));
    });

    test('CP-03.5: Cierre de Sesión Desactiva Registro en SQLite', () async {
      await authService.login('biologo1', 'BioCampo2026!');
      expect(authService.isAuthenticated, isTrue);

      // Cerrar sesión
      await authService.logout();
      expect(authService.isAuthenticated, isFalse);

      // Verificar que restoreSession() ya no permite auto-login
      final nuevoAuthService = AuthService(database: db);
      final restaurado = await nuevoAuthService.restoreSession();
      expect(restaurado, isFalse);
      expect(nuevoAuthService.isAuthenticated, isFalse);
    });
  });
}
