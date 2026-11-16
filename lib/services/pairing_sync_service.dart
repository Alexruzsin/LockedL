import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/room_models.dart';
import 'lock_wallpaper_service.dart';

/// Éles (Production) biztonságos 6 jegyű párosítás és valós idejű szinkronizáció
/// a `lockedl` (europe-west1) Firebase projekthez bekötve.
class PairingSyncService {
  static const String _databaseUrl =
      'https://lockedl-default-rtdb.europe-west1.firebasedatabase.app';

  static const FirebaseOptions _firebaseOptions = FirebaseOptions(
    apiKey: 'AIzaSyChozQSFt_ViJgd1HuzfyAraGuEX81_k6c',
    appId: '1:1031313204593:android:3b7d496f8271709ab782d0',
    messagingSenderId: '1031313204593',
    projectId: 'lockedl',
    databaseURL: _databaseUrl,
    storageBucket: 'lockedl.firebasestorage.app',
  );

  bool _firebaseReady = false;
  String _currentUid = 'local_user';
  final StreamController<SharedCanvasState> _localController =
      StreamController<SharedCanvasState>.broadcast();
  StreamSubscription<DatabaseEvent>? _lockScreenSub;
  int _lastAppliedTimestamp = 0;

  bool get isFirebaseReady => _firebaseReady;
  String get currentUid => _currentUid;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );

  Future<void> init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _firebaseOptions);
      }
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      _currentUid = userCredential.user?.uid ?? 'anon_user';
      _firebaseReady = true;
    } catch (_) {
      _currentUid =
          'local_${DateTime.now().millisecondsSinceEpoch.remainder(100000)}';
      _firebaseReady = false;
    }
  }

  /// Véletlenszerű 6 jegyű párosító kód generálása (pl. "842915")
  String generateSixDigitCode() {
    final rnd = Random();
    final part1 = 100 + rnd.nextInt(900);
    final part2 = 100 + rnd.nextInt(900);
    return '$part1$part2';
  }

  /// Lefoglalja az 1. vagy 2. helyet (`member1` / `member2`) a szobában.
  Future<bool> claimRoomSlot(String roomCode) async {
    if (!_firebaseReady) return true;

    final normalized = roomCode.replaceAll('-', '').trim();
    final membersRef = _db.ref('rooms/$normalized/members');
    final snapshot = await membersRef.get();

    String? member1;
    String? member2;
    if (snapshot.exists && snapshot.value is Map) {
      final map = Map<dynamic, dynamic>.from(snapshot.value as Map);
      member1 = map['member1'] as String?;
      member2 = map['member2'] as String?;
    }

    if (member1 == _currentUid || member2 == _currentUid) {
      return true;
    }
    if (member1 == null) {
      await membersRef.child('member1').set(_currentUid);
      return true;
    }
    if (member2 == null) {
      await membersRef.child('member2').set(_currentUid);
      return true;
    }
    return false;
  }

  /// Feliratkozás a közös szoba élő változásaira (vonások, matricák, közös fotó)
  Stream<SharedCanvasState> watchRoom(String roomCode) {
    final normalized = roomCode.replaceAll('-', '').trim();
    if (!_firebaseReady) {
      return _localController.stream;
    }

    final ref = _db.ref('rooms/$normalized/canvas');
    return ref.onValue.map((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        return SharedCanvasState.fromJson(Map<dynamic, dynamic>.from(data));
      }
      return SharedCanvasState(
        roomCode: normalized,
        strokes: const [],
        stickers: const [],
      );
    });
  }

  /// Figyeli, ha a párod új kész zárolt képernyőt küldött, és automatikusan
  /// lecseréli a telefonod zárolt képernyőjének hátterét!
  void listenForPartnerLockScreenUpdates(
    String roomCode, {
    void Function()? onPartnerWallpaperApplied,
  }) {
    _lockScreenSub?.cancel();
    if (!_firebaseReady) return;

    final normalized = roomCode.replaceAll('-', '').trim();
    final ref = _db.ref('rooms/$normalized/latestLockScreen');

    _lockScreenSub = ref.onValue.listen((event) async {
      final data = event.snapshot.value;
      if (data is! Map) return;
      final map = Map<dynamic, dynamic>.from(data);
      final senderId = map['senderId'] as String?;
      final pngBase64 = map['pngBase64'] as String?;
      final timestamp = (map['timestamp'] as num?)?.toInt() ?? 0;

      if (senderId != null &&
          senderId != _currentUid &&
          pngBase64 != null &&
          timestamp > _lastAppliedTimestamp) {
        _lastAppliedTimestamp = timestamp;
        final Uint8List pngBytes = base64Decode(pngBase64);
        await LockWallpaperService.setLockScreenWallpaper(pngBytes);
        onPartnerWallpaperApplied?.call();
      }
    });
  }

  /// Közös vászon állapotának azonnali küldése a szobába
  Future<void> syncCanvasState(SharedCanvasState state) async {
    final normalized = state.roomCode.replaceAll('-', '').trim();
    if (!_firebaseReady) {
      _localController.add(state);
      return;
    }

    final ref = _db.ref('rooms/$normalized/canvas');
    await ref.set(state.toJson());
  }

  /// A kész, kirenderelt zárolt képernyő kép (PNG base64) feltöltése a párodnak
  Future<void> publishLockScreenImage({
    required String roomCode,
    required String senderId,
    required String pngBase64,
  }) async {
    if (!_firebaseReady) return;
    final normalized = roomCode.replaceAll('-', '').trim();
    final ref = _db.ref('rooms/$normalized/latestLockScreen');
    await ref.set({
      'senderId': senderId,
      'pngBase64': pngBase64,
      'timestamp': ServerValue.timestamp,
    });
  }
}
