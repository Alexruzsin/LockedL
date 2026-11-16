import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Natív híd (MethodChannel) a zárolt képernyő háttérképének frissítéséhez.
///
/// - Androidon: `WallpaperManager.getInstance(context).setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)`
///   közvetlenül a háttérből lecseréli a zárolt képernyő hátterét a kapott rajzra.
/// - iOS-en: Az Apple biztonsági korlátai miatt a háttérképet App Group + WidgetKit
///   (Lock Screen Widget) vagy Shortcuts automatizációval frissítjük.
class LockWallpaperService {
  static const MethodChannel _channel = MethodChannel('com.lovelock/wallpaper');

  /// Elmenti és beállítja a renderelt PNG képet a zárolt képernyő háttereként.
  static Future<bool> setLockScreenWallpaper(Uint8List pngBytes) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'setLockWallpaper',
        {'imageBytes': pngBytes},
      );
      return result ?? false;
    } on PlatformException {
      // Helyi / szimulált prototípus módban nem dobunk hibát, ha a natív csatorna nincs bekötve
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
