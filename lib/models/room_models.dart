import 'package:flutter/material.dart';

enum BrushMode { neon, smooth, hearts, sparkles }

class StrokePoint {
  final double x;
  final double y;

  const StrokePoint(this.x, this.y);

  Offset get offset => Offset(x, y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory StrokePoint.fromJson(Map<dynamic, dynamic> json) {
    return StrokePoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }
}

class DrawingStroke {
  final String id;
  final String authorId;
  final List<StrokePoint> points;
  final Color color;
  final double size;
  final BrushMode mode;

  DrawingStroke({
    required this.id,
    required this.authorId,
    required this.points,
    required this.color,
    required this.size,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'points': points.map((p) => p.toJson()).toList(),
        'color': color.value,
        'size': size,
        'mode': mode.name,
      };

  factory DrawingStroke.fromJson(Map<dynamic, dynamic> json) {
    final ptsRaw = (json['points'] as List<dynamic>? ?? []);
    return DrawingStroke(
      id: json['id'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      points: ptsRaw
          .map((e) => StrokePoint.fromJson(Map<dynamic, dynamic>.from(e)))
          .toList(),
      color: Color(json['color'] as int? ?? 0xFFFF4D8D),
      size: (json['size'] as num? ?? 6.0).toDouble(),
      mode: BrushMode.values.firstWhere(
        (m) => m.name == (json['mode'] as String? ?? 'neon'),
        orElse: () => BrushMode.neon,
      ),
    );
  }
}

class PlacedSticker {
  final String id;
  final String text;
  double x;
  double y;
  final bool isPill;

  PlacedSticker({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    this.isPill = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'x': x,
        'y': y,
        'isPill': isPill,
      };

  factory PlacedSticker.fromJson(Map<dynamic, dynamic> json) {
    return PlacedSticker(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '💖',
      x: (json['x'] as num? ?? 140.0).toDouble(),
      y: (json['y'] as num? ?? 220.0).toDouble(),
      isPill: json['isPill'] as bool? ?? false,
    );
  }
}

class SharedCanvasState {
  final String roomCode;
  final List<DrawingStroke> strokes;
  final List<PlacedSticker> stickers;
  final String? backgroundBase64;
  final double photoDim;

  const SharedCanvasState({
    required this.roomCode,
    required this.strokes,
    required this.stickers,
    this.backgroundBase64,
    this.photoDim = 0.3,
  });

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'stickers': stickers.map((st) => st.toJson()).toList(),
        'backgroundBase64': backgroundBase64,
        'photoDim': photoDim,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  factory SharedCanvasState.fromJson(Map<dynamic, dynamic> json) {
    final strokesRaw = (json['strokes'] as List<dynamic>? ?? []);
    final stickersRaw = (json['stickers'] as List<dynamic>? ?? []);
    return SharedCanvasState(
      roomCode: json['roomCode'] as String? ?? '',
      strokes: strokesRaw
          .map((s) => DrawingStroke.fromJson(Map<dynamic, dynamic>.from(s)))
          .toList(),
      stickers: stickersRaw
          .map((st) => PlacedSticker.fromJson(Map<dynamic, dynamic>.from(st)))
          .toList(),
      backgroundBase64: json['backgroundBase64'] as String?,
      photoDim: (json['photoDim'] as num? ?? 0.3).toDouble(),
    );
  }
}
