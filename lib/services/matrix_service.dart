import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../constants.dart';

/// Matrix client singleton — E2EE chat on a separate homeserver.
class MatrixService {
  MatrixService._();
  static final MatrixService instance = MatrixService._();

  Client? _client;
  bool _ready = false;

  Client get client {
    final c = _client;
    if (c == null) {
      throw StateError('MatrixService not initialized. Call init() first.');
    }
    return c;
  }

  bool get isReady => _ready;
  bool get isLoggedIn => _client?.isLogged() ?? false;

  Stream<void> get onSync => client.onSync.stream;
  Stream<LoginState> get onLoginStateChanged => client.onLoginStateChanged.stream;

  /// Call once from main() before runApp.
  Future<void> init() async {
    if (_ready) return;

    await vod.init();

    final db = await MatrixSdkDatabase.init(
      'sigma_matrix',
      database: kIsWeb
          ? null
          : await sqflite.openDatabase(
              p.join(
                (await getApplicationSupportDirectory()).path,
                'sigma_matrix.db',
              ),
            ),
    );

    _client = Client(
      'Sigmacta',
      database: db,
      nativeImplementations: NativeImplementationsIsolate(
        compute,
        vodozemacInit: () => vod.init(),
      ),
    );

    await _client!.init();
    _ready = true;
  }

  /// After Sigma login: connect the same username/password to Matrix.
  /// Returns null on success, or an error message string.
  Future<String?> loginOrRegister(String username, String password) async {
    await init();
    final c = client;

    if (c.isLogged()) {
      final saved = await _loadSavedMxid();
      if (saved != null && c.userID == saved) return null;
      await c.logout();
    }

    final cleanUser = username.trim().toLowerCase();
    if (cleanUser.isEmpty || password.isEmpty) {
      return 'Matrix: empty credentials';
    }

    try {
      await c.checkHomeserver(Uri.parse(kMatrixHomeserver));
    } catch (e) {
      return 'Homeserver unreachable: $e';
    }

    try {
      await c.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: cleanUser),
        password: password,
        initialDeviceDisplayName: 'Sigmacta',
      );
      await _saveMxid(c.userID!);
      return null;
    } catch (_) {
      if (!kMatrixAutoRegister) {
        return 'Matrix login failed. Create @$cleanUser:$kMatrixServerName '
            'on the homeserver or enable auto-register.';
      }
    }

    try {
      await c.register(
        username: cleanUser,
        password: password,
        deviceId: c.deviceID,
        initialDeviceDisplayName: 'Sigmacta',
      );
      await _saveMxid(c.userID!);
      return null;
    } catch (e) {
      return 'Matrix register failed: $e';
    }
  }

  /// Build a Matrix user id from a Sigma username (same homeserver).
  String mxidFromUsername(String username) {
    final local = username.trim().toLowerCase();
    return '@$local:$kMatrixServerName';
  }

  /// Direct chats only, most recent activity first.
  List<Room> get directRooms {
    final rooms = client.rooms.where((r) => r.isDirectChat).toList();
    rooms.sort((a, b) {
      final ta = a.lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.lastEvent?.originServerTs ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return rooms;
  }

  Future<Room> openDirectChat(String mxid) async {
    final roomId = await client.startDirectChat(mxid, enableEncryption: true);
    final room = client.getRoomById(roomId);
    if (room == null) throw Exception('Room not found after create');
    return room;
  }

  Future<void> logout() async {
    if (_client?.isLogged() == true) {
      await _client!.logout();
    }
    final p = await SharedPreferences.getInstance();
    await p.remove(_kMxid);
  }

  static const _kMxid = 'matrix_user_id';

  Future<void> _saveMxid(String mxid) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMxid, mxid);
  }

  Future<String?> _loadSavedMxid() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kMxid);
  }
}
