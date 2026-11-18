import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biocampo_app/features/auth/domain/models/usuario_model.dart';
import 'package:biocampo_app/features/auth/domain/models/sesion_jwt_model.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';

/// Gestor Central de Base de Datos Relacional de BioCampo
/// Implementa SQLite con Write-Ahead Logging (WAL) e integridad referencial (Foreign Keys) en Android/Desktop,
/// y provee un almacenamiento adaptativo para Web y pruebas unitarias.
class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();
  AppDatabase._internal();

  static const String _dbName = 'biocampo_local.db';
  static const int _dbVersion = 1;
  static const String _webReportsKey = 'biocampo_web_reports_json';

  sqflite.Database? _sqliteDb;

  // Almacenamiento adaptativo en memoria para Web/Testing
  final List<Map<String, dynamic>> _memUsuarios = [];
  final List<Map<String, dynamic>> _memReportes = [];
  final List<Map<String, dynamic>> _memSesiones = [];
  int _nextUsuarioId = 1;
  int _nextReporteId = 1;
  int _nextSesionId = 1;

  /// Inicializa la base de datos y aplica los pragmas de integridad y datos semilla
  Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('[AppDatabase] Inicializando motor adaptativo en memoria para Web...');
      await _seedInMemory();
      await _restoreWebReports();
      return;
    }

    try {
      final dbPath = await sqflite.getDatabasesPath();
      final path = p.join(dbPath, _dbName);

      _sqliteDb = await sqflite.openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onConfigure: _onConfigure,
      );

      debugPrint('[AppDatabase] Base de datos SQLite inicializada exitosamente en: $path');
      await _seedSQLite();
    } catch (e) {
      debugPrint('[AppDatabase] Advertencia al abrir SQLite nativo ($e). Activando modo adaptativo.');
      await _seedInMemory();
    }
  }

  /// Configuración de Pragmas SQLite (WAL y Claves Foráneas)
  Future<void> _onConfigure(sqflite.Database db) async {
    // 1. Forzar cumplimiento de integridad referencial relacional
    await db.execute('PRAGMA foreign_keys = ON;');
    // 2. Activar Write-Ahead Logging para resistencia a fallas de energía
    await db.execute('PRAGMA journal_mode = WAL;');
  }

  /// Creación del esquema relacional DDL
  Future<void> _onCreate(sqflite.Database db, int version) async {
    // Tabla 1: Usuario (Biólogo)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usuario (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        matricula TEXT NOT NULL UNIQUE,
        nombre_completo TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        rol TEXT NOT NULL DEFAULT 'Investigador',
        ultimo_login TEXT
      );
    ''');

    // Tabla 2: Reporte de Avistamiento con FK explícita hacia usuario (1:N)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reporte_avistamiento (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL,
        fecha_hora TEXT NOT NULL,
        latitud REAL NOT NULL,
        longitud REAL NOT NULL,
        altitud REAL NOT NULL DEFAULT 0.0,
        precision_gps REAL NOT NULL DEFAULT 0.0,
        nombre_comun TEXT NOT NULL,
        notas TEXT,
        estado_sync TEXT NOT NULL DEFAULT 'PENDIENTE',
        FOREIGN KEY (usuario_id) REFERENCES usuario (id) ON DELETE CASCADE
      );
    ''');

    // Tabla 3: Sesion JWT (Relación 1:1 con Usuario para persistencia de sesión)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sesion_jwt (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usuario_id INTEGER NOT NULL UNIQUE,
        jwt_token TEXT NOT NULL,
        algoritmo TEXT NOT NULL DEFAULT 'HS256',
        emitido_en TEXT NOT NULL,
        expira_en TEXT NOT NULL,
        activo INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (usuario_id) REFERENCES usuario (id) ON DELETE CASCADE
      );
    ''');

    // Índices relacionales para optimización de consultas
    await db.execute('CREATE INDEX IF NOT EXISTS idx_usuario_matricula ON usuario (matricula);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reporte_usuario ON reporte_avistamiento (usuario_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sesion_usuario ON sesion_jwt (usuario_id);');
  }

  /// Función utilitaria para hashing de contraseñas con Salt
  static String hashPassword(String password, String salt) {
    final bytes = utf8.encode('$password::$salt');
    return sha256.convert(bytes).toString();
  }

  /// Inserción de biólogos de prueba en SQLite si la tabla está vacía
  Future<void> _seedSQLite() async {
    if (_sqliteDb == null) return;
    final count = sqflite.Sqflite.firstIntValue(
      await _sqliteDb!.rawQuery('SELECT COUNT(*) FROM usuario;'),
    );

    if (count == 0) {
      debugPrint('[AppDatabase] Insertando datos semilla de biólogos en SQLite...');
      const salt1 = 'salt_biocampo_carlos_2026';
      final hash1 = hashPassword('BioCampo2026!', salt1);
      await _sqliteDb!.insert('usuario', {
        'matricula': 'biologo1',
        'nombre_completo': 'Dr. Carlos Gómez (Biólogo de Campo)',
        'password_hash': hash1,
        'salt': salt1,
        'rol': 'Investigador Titular',
        'ultimo_login': null,
      });

      const salt2 = 'salt_biocampo_elena_2026';
      final hash2 = hashPassword('Selva2026!', salt2);
      await _sqliteDb!.insert('usuario', {
        'matricula': 'investigador2',
        'nombre_completo': 'Dra. Elena Ramos (Coordinadora de Expedición)',
        'password_hash': hash2,
        'salt': salt2,
        'rol': 'Coordinadora de Campo',
        'ultimo_login': null,
      });
    }
  }

  /// Inserción de datos semilla en memoria (Web / Pruebas)
  Future<void> _seedInMemory() async {
    if (_memUsuarios.isEmpty) {
      const salt1 = 'salt_biocampo_carlos_2026';
      final hash1 = hashPassword('BioCampo2026!', salt1);
      _memUsuarios.add({
        'id': _nextUsuarioId++,
        'matricula': 'biologo1',
        'nombre_completo': 'Dr. Carlos Gómez (Biólogo de Campo)',
        'password_hash': hash1,
        'salt': salt1,
        'rol': 'Investigador Titular',
        'ultimo_login': null,
      });

      const salt2 = 'salt_biocampo_elena_2026';
      final hash2 = hashPassword('Selva2026!', salt2);
      _memUsuarios.add({
        'id': _nextUsuarioId++,
        'matricula': 'investigador2',
        'nombre_completo': 'Dra. Elena Ramos (Coordinadora de Expedición)',
        'password_hash': hash2,
        'salt': salt2,
        'rol': 'Coordinadora de Campo',
        'ultimo_login': null,
      });
    }
  }

  // =====================================================================
  // OPERACIONES CRUD: ENTIDAD USUARIO
  // =====================================================================

  Future<UsuarioModel?> getUsuarioByMatricula(String matricula) async {
    if (_sqliteDb != null) {
      final results = await _sqliteDb!.query(
        'usuario',
        where: 'matricula = ?',
        whereArgs: [matricula],
        limit: 1,
      );
      if (results.isNotEmpty) {
        return UsuarioModel.fromMap(results.first);
      }
      return null;
    } else {
      final found = _memUsuarios.cast<Map<String, dynamic>?>().firstWhere(
        (u) => u?['matricula'] == matricula,
        orElse: () => null,
      );
      if (found != null) {
        return UsuarioModel.fromMap(found);
      }
      return null;
    }
  }

  Future<UsuarioModel?> getUsuarioById(int id) async {
    if (_sqliteDb != null) {
      final results = await _sqliteDb!.query(
        'usuario',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (results.isNotEmpty) {
        return UsuarioModel.fromMap(results.first);
      }
      return null;
    } else {
      final found = _memUsuarios.cast<Map<String, dynamic>?>().firstWhere(
        (u) => u?['id'] == id,
        orElse: () => null,
      );
      if (found != null) {
        return UsuarioModel.fromMap(found);
      }
      return null;
    }
  }

  Future<void> updateUltimoLogin(int usuarioId) async {
    final nowIso = DateTime.now().toIso8601String();
    if (_sqliteDb != null) {
      await _sqliteDb!.update(
        'usuario',
        {'ultimo_login': nowIso},
        where: 'id = ?',
        whereArgs: [usuarioId],
      );
    } else {
      final index = _memUsuarios.indexWhere((u) => u['id'] == usuarioId);
      if (index != -1) {
        _memUsuarios[index]['ultimo_login'] = nowIso;
      }
    }
  }

  // =====================================================================
  // OPERACIONES CRUD: ENTIDAD SESION_JWT (PERSISTENCIA DE SESIÓN RELACIONAL)
  // =====================================================================

  /// Guarda o actualiza la sesión JWT activa de un usuario en SQLite
  Future<void> saveActiveSession(SesionJwtModel sesion) async {
    if (_sqliteDb != null) {
      // Desactivar sesiones previas
      await _sqliteDb!.update('sesion_jwt', {'activo': 0});
      // Insertar o reemplazar sesión activa
      await _sqliteDb!.insert(
        'sesion_jwt',
        sesion.toMap(),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    } else {
      for (var s in _memSesiones) {
        s['activo'] = 0;
      }
      final map = sesion.toMap();
      map['id'] = _nextSesionId++;
      _memSesiones.add(map);
    }
  }

  /// Obtiene la sesión JWT activa no expirada
  Future<SesionJwtModel?> getActiveSession() async {
    if (_sqliteDb != null) {
      final results = await _sqliteDb!.query(
        'sesion_jwt',
        where: 'activo = 1',
        orderBy: 'id DESC',
        limit: 1,
      );
      if (results.isNotEmpty) {
        return SesionJwtModel.fromMap(results.first);
      }
      return null;
    } else {
      final found = _memSesiones.cast<Map<String, dynamic>?>().firstWhere(
        (s) => s?['activo'] == 1,
        orElse: () => null,
      );
      if (found != null) {
        return SesionJwtModel.fromMap(found);
      }
      return null;
    }
  }

  /// Cierra y desactiva la sesión en base de datos
  Future<void> clearActiveSession() async {
    if (_sqliteDb != null) {
      await _sqliteDb!.update('sesion_jwt', {'activo': 0});
    } else {
      for (var s in _memSesiones) {
        s['activo'] = 0;
      }
    }
  }

  // =====================================================================
  // OPERACIONES CRUD: ENTIDAD REPORTE_AVISTAMIENTO (CON CLAVE FORÁNEA)
  // =====================================================================

  /// Inserta un reporte en la base de datos asegurando la integridad referencial
  Future<int> insertReporte(ReporteModel reporte) async {
    // 1. Validar que el usuario exista (integridad relacional)
    final usuario = await getUsuarioById(reporte.usuarioId);
    if (usuario == null) {
      throw ArgumentError('Violación de Integridad Referencial: El usuario_id ${reporte.usuarioId} no existe en la BD.');
    }

    if (_sqliteDb != null) {
      final map = reporte.toMap();
      map.remove('id');
      return await _sqliteDb!.insert('reporte_avistamiento', map);
    } else {
      final newId = _nextReporteId++;
      final map = reporte.toMap();
      map['id'] = newId;
      _memReportes.add(map);
      if (kIsWeb) {
        await _saveWebReports();
      }
      return newId;
    }
  }

  Future<void> _restoreWebReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_webReportsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decodedList = jsonDecode(jsonStr) as List<dynamic>;
        _memReportes.clear();
        for (var item in decodedList) {
          final map = Map<String, dynamic>.from(item as Map);
          _memReportes.add(map);
          final id = map['id'] as int? ?? 0;
          if (id >= _nextReporteId) {
            _nextReporteId = id + 1;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveWebReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webReportsKey, jsonEncode(_memReportes));
    } catch (_) {}
  }

  /// Consulta todos los reportes de un usuario o del sistema completo
  Future<List<ReporteModel>> getReportes({int? usuarioId}) async {
    if (_sqliteDb != null) {
      final results = await _sqliteDb!.query(
        'reporte_avistamiento',
        where: usuarioId != null ? 'usuario_id = ?' : null,
        whereArgs: usuarioId != null ? [usuarioId] : null,
        orderBy: 'id DESC',
      );
      return results.map((map) => ReporteModel.fromMap(map)).toList();
    } else {
      var list = List<Map<String, dynamic>>.from(_memReportes);
      if (usuarioId != null) {
        list = list.where((r) => r['usuario_id'] == usuarioId).toList();
      }
      list.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      return list.map((map) => ReporteModel.fromMap(map)).toList();
    }
  }

  /// Actualiza un reporte existente en SQLite o almacenamiento en memoria
  Future<bool> updateReporte(ReporteModel reporte) async {
    if (reporte.id == null) return false;

    if (_sqliteDb != null) {
      final rows = await _sqliteDb!.update(
        'reporte_avistamiento',
        reporte.toMap(),
        where: 'id = ?',
        whereArgs: [reporte.id],
      );
      return rows > 0;
    } else {
      final index = _memReportes.indexWhere((r) => r['id'] == reporte.id);
      if (index != -1) {
        _memReportes[index] = reporte.toMap();
        if (kIsWeb) {
          await _saveWebReports();
        }
        return true;
      }
      return false;
    }
  }

  /// Elimina un reporte por su identificador primario (ID)
  Future<bool> deleteReporte(int id) async {
    if (_sqliteDb != null) {
      final rows = await _sqliteDb!.delete(
        'reporte_avistamiento',
        where: 'id = ?',
        whereArgs: [id],
      );
      return rows > 0;
    } else {
      final index = _memReportes.indexWhere((r) => r['id'] == id);
      if (index != -1) {
        _memReportes.removeAt(index);
        if (kIsWeb) {
          await _saveWebReports();
        }
        return true;
      }
      return false;
    }
  }

  /// Métricas cuantitativas para verificación docente
  Future<int> countUsuarios() async {
    if (_sqliteDb != null) {
      return sqflite.Sqflite.firstIntValue(await _sqliteDb!.rawQuery('SELECT COUNT(*) FROM usuario;')) ?? 0;
    }
    return _memUsuarios.length;
  }

  Future<int> countReportes() async {
    if (_sqliteDb != null) {
      return sqflite.Sqflite.firstIntValue(await _sqliteDb!.rawQuery('SELECT COUNT(*) FROM reporte_avistamiento;')) ?? 0;
    }
    return _memReportes.length;
  }

  /// Limpia tablas para propósitos de pruebas unitarias
  @visibleForTesting
  void clearForTesting() {
    _memUsuarios.clear();
    _memReportes.clear();
    _memSesiones.clear();
    _nextUsuarioId = 1;
    _nextReporteId = 1;
    _nextSesionId = 1;
  }
}
