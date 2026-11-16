import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/room_models.dart';
import 'services/lock_wallpaper_service.dart';
import 'services/pairing_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final syncService = PairingSyncService();
  await syncService.init();
  runApp(LoveLockApp(syncService: syncService));
}

class LoveLockApp extends StatelessWidget {
  final PairingSyncService syncService;

  const LoveLockApp({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoveLock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF4D8D),
          brightness: Brightness.dark,
        ),
      ),
      home: LoveLockHomeScreen(syncService: syncService),
    );
  }
}

class LoveLockHomeScreen extends StatefulWidget {
  final PairingSyncService syncService;

  const LoveLockHomeScreen({super.key, required this.syncService});

  @override
  State<LoveLockHomeScreen> createState() => _LoveLockHomeScreenState();
}

class _LoveLockHomeScreenState extends State<LoveLockHomeScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();
  final String _deviceId =
      'user_${DateTime.now().millisecondsSinceEpoch.remainder(100000)}';

  String _roomCode = '842915';
  List<DrawingStroke> _strokes = [];
  List<PlacedSticker> _stickers = [
    PlacedSticker(id: 'st_1', text: '💖', x: 220, y: 120),
    PlacedSticker(
      id: 'st_2',
      text: 'Szeretlek! 💕',
      x: 110,
      y: 360,
      isPill: true,
    ),
  ];
  String? _backgroundBase64;
  Uint8List? _backgroundBytes;
  double _photoDim = 0.30;

  DrawingStroke? _currentStroke;
  BrushMode _selectedMode = BrushMode.neon;
  Color _selectedColor = const Color(0xFFFF4D8D);
  double _strokeSize = 6.0;
  bool _showLockScreenPreview = false;

  final List<Color> _palette = const [
    Color(0xFFFF4D8D),
    Color(0xFFFF2A55),
    Color(0xFFFFB703),
    Color(0xFFA855F7),
    Color(0xFF38BDF8),
    Color(0xFF4ADE80),
    Colors.white,
  ];

  final List<String> _availableStickers = const [
    '💖',
    '🥺',
    '💋',
    '🧸',
    '🌹',
    '☕',
    '✨',
    'Szeretlek! 💕',
    'Hiányzol! 🥺',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedRoomAndConnect();
  }

  Future<void> _loadSavedRoomAndConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('saved_room_code');
    if (savedCode != null && savedCode.isNotEmpty) {
      setState(() => _roomCode = savedCode);
    }
    await _subscribeToRoom(_roomCode);
  }

  Future<void> _subscribeToRoom(String code) async {
    final joined = await widget.syncService.claimRoomSlot(code);
    if (!joined && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Ez a 6 jegyű szoba már betelt (maximum 2 fő csatlakozhat)!',
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_room_code', code);

    // Automatikus figyelés: ha a párod új zárolt képernyőt küld, frissítjük a hátteret!
    widget.syncService.listenForPartnerLockScreenUpdates(
      code,
      onPartnerWallpaperApplied: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '💞 A párod most frissítette a zárolt képernyődet!',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );

    widget.syncService.watchRoom(code).listen((remoteState) {
      if (!mounted) return;
      setState(() {
        _strokes = remoteState.strokes;
        _stickers = remoteState.stickers;
        _photoDim = remoteState.photoDim;
        if (remoteState.backgroundBase64 != _backgroundBase64) {
          _backgroundBase64 = remoteState.backgroundBase64;
          _backgroundBytes = _backgroundBase64 != null
              ? base64Decode(_backgroundBase64!)
              : null;
        }
      });
    });
  }

  void _broadcastState() {
    widget.syncService.syncCanvasState(
      SharedCanvasState(
        roomCode: _roomCode,
        strokes: _strokes,
        stickers: _stickers,
        backgroundBase64: _backgroundBase64,
        photoDim: _photoDim,
      ),
    );
  }

  Future<void> _pickCustomPhoto() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 75,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _backgroundBytes = bytes;
      _backgroundBase64 = base64Encode(bytes);
    });
    _broadcastState();
  }

  void _addSticker(String text) {
    setState(() {
      _stickers.add(
        PlacedSticker(
          id: 'st_${DateTime.now().millisecondsSinceEpoch}',
          text: text,
          x: 110 + math.Random().nextDouble() * 80,
          y: 160 + math.Random().nextDouble() * 140,
          isPill: text.length > 3,
        ),
      );
    });
    _broadcastState();
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _currentStroke = DrawingStroke(
        id: 'stroke_${DateTime.now().millisecondsSinceEpoch}',
        authorId: _deviceId,
        points: [
          StrokePoint(details.localPosition.dx, details.localPosition.dy)
        ],
        color: _selectedColor,
        size: _strokeSize,
        mode: _selectedMode,
      );
      _strokes.add(_currentStroke!);
    });
    _broadcastState();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_currentStroke == null) return;
    setState(() {
      _currentStroke!.points.add(
        StrokePoint(details.localPosition.dx, details.localPosition.dy),
      );
    });
    _broadcastState();
  }

  void _onPanEnd(DragEndDetails details) {
    _currentStroke = null;
    _broadcastState();
  }

  Future<void> _sendToPartnerLockScreen() async {
    final boundary = _repaintKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary != null) {
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        await LockWallpaperService.setLockScreenWallpaper(pngBytes);
        await widget.syncService.publishLockScreenImage(
          roomCode: _roomCode,
          senderId: _deviceId,
          pngBase64: base64Encode(pngBytes),
        );
      }
    }

    if (!mounted) return;
    setState(() => _showLockScreenPreview = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '💞 Közös rajz és fotó frissítve a zárolt képernyőn!',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPairingDialog() {
    final controller = TextEditingController(text: _roomCode);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔗 6 jegyű párosító kód (Közös szoba)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add meg a párod 6 jegyű kódját, vagy generálj egy újat és küldd el neki!',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6 jegyű szobakód',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      controller.text =
                          widget.syncService.generateSixDigitCode();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Új kód'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final newCode = controller.text.trim();
                    if (newCode.isNotEmpty) {
                      setState(() => _roomCode = newCode);
                      _subscribeToRoom(newCode);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Csatlakozás a közös vászonhoz 💕'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showPairingDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('💞 LoveLock '),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.pinkAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '#$_roomCode',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Saját fotó háttérnek',
            onPressed: _pickCustomPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: _showLockScreenPreview
                ? 'Vissza a rajzoláshoz'
                : 'Zárolt képernyő előnézet',
            onPressed: () {
              setState(
                  () => _showLockScreenPreview = !_showLockScreenPreview);
            },
            icon: Icon(
              _showLockScreenPreview ? Icons.brush : Icons.lock_outline,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Közös Vászon (Fotó + Rajz + Húzható Matricák)
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 1. Alap gradiens vagy saját feltöltött fotó
                        if (_backgroundBytes != null)
                          Image.memory(
                            _backgroundBytes!,
                            fit: BoxFit.cover,
                          )
                        else
                          Container(
                            decoration: const BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(-0.5, -0.6),
                                radius: 1.4,
                                colors: [
                                  Color(0xFF3B1D5E),
                                  Color(0xFF17122B),
                                  Color(0xFF090714),
                                ],
                              ),
                            ),
                          ),

                        // Sötétítő réteg a fotón, hogy a neon rajz jól látszódjon
                        if (_backgroundBytes != null && _photoDim > 0)
                          Container(
                            color: Colors.black.withValues(alpha: _photoDim),
                          ),

                        // 2. Rajzoló réteg
                        GestureDetector(
                          onPanStart:
                              _showLockScreenPreview ? null : _onPanStart,
                          onPanUpdate:
                              _showLockScreenPreview ? null : _onPanUpdate,
                          onPanEnd: _showLockScreenPreview ? null : _onPanEnd,
                          child: CustomPaint(
                            painter: LoveLockPainter(strokes: _strokes),
                            size: Size.infinite,
                          ),
                        ),

                        // 3. Mozgatható Matricák (Draggable Stickers)
                        ..._stickers.map((sticker) {
                          return Positioned(
                            left: sticker.x,
                            top: sticker.y,
                            child: GestureDetector(
                              onPanUpdate: _showLockScreenPreview
                                  ? null
                                  : (details) {
                                      setState(() {
                                        sticker.x += details.delta.dx;
                                        sticker.y += details.delta.dy;
                                      });
                                      _broadcastState();
                                    },
                              child: sticker.isPill
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF2A55)
                                            .withValues(alpha: 0.88),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        sticker.text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    )
                                  : Text(
                                      sticker.text,
                                      style: const TextStyle(fontSize: 34),
                                    ),
                            ),
                          );
                        }),

                        // 4. Zárolt képernyő óra szimuláció előnézeti módban
                        if (_showLockScreenPreview)
                          IgnorePointer(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 38),
                                  child: Column(
                                    children: const [
                                      Icon(Icons.lock, color: Colors.white70),
                                      SizedBox(height: 4),
                                      Text(
                                        '19:42',
                                        style: TextStyle(
                                          fontSize: 52,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'Párod zárolt képernyője',
                                        style:
                                            TextStyle(color: Colors.white70),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Container(
                                    width: 110,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: Colors.white54,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Alsó eszköztár: Matricák, Ecsetek, Színek és Küldés
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Matrica sáv
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableStickers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final st = _availableStickers[idx];
                      return ActionChip(
                        label: Text(st),
                        onPressed: () => _addSticker(st),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Ecset választó + Visszavonás/Törlés
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SegmentedButton<BrushMode>(
                      segments: const [
                        ButtonSegment(
                          value: BrushMode.neon,
                          label: Text('✨ Neon'),
                        ),
                        ButtonSegment(
                          value: BrushMode.smooth,
                          label: Text('🖌️ Ecset'),
                        ),
                        ButtonSegment(
                          value: BrushMode.hearts,
                          label: Text('💖 Szív'),
                        ),
                      ],
                      selected: {_selectedMode},
                      onSelectionChanged: (val) {
                        setState(() => _selectedMode = val.first);
                      },
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Visszavonás',
                          onPressed:
                              (_strokes.isEmpty && _stickers.isEmpty)
                                  ? null
                                  : () {
                                      setState(() {
                                        if (_strokes.isNotEmpty) {
                                          _strokes.removeLast();
                                        } else if (_stickers.isNotEmpty) {
                                          _stickers.removeLast();
                                        }
                                      });
                                      _broadcastState();
                                    },
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          tooltip: 'Törlés',
                          onPressed:
                              (_strokes.isEmpty && _stickers.isEmpty)
                                  ? null
                                  : () {
                                      setState(() {
                                        _strokes.clear();
                                        _stickers.clear();
                                      });
                                      _broadcastState();
                                    },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Színpaletta + Küldés gomb
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _palette.map((color) {
                            final isSelected = _selectedColor == color;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedColor = color),
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _sendToPartnerLockScreen,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Zárolt képernyőre'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LoveLockPainter extends CustomPainter {
  final List<DrawingStroke> strokes;

  LoveLockPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;

      if (stroke.mode == BrushMode.hearts) {
        for (int i = 0; i < stroke.points.length; i += 4) {
          _drawHeart(
            canvas,
            stroke.points[i].offset,
            stroke.size * 2.2,
            stroke.color,
          );
        }
        continue;
      }

      final path = Path();
      final pts = stroke.points;
      path.moveTo(pts.first.offset.dx, pts.first.offset.dy);
      for (int i = 1; i < pts.length; i++) {
        final p0 = pts[i - 1].offset;
        final p1 = pts[i].offset;
        path.quadraticBezierTo(
          p0.dx,
          p0.dy,
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
      }

      if (stroke.mode == BrushMode.neon) {
        final glowPaint = Paint()
          ..color = stroke.color.withValues(alpha: 0.65)
          ..strokeWidth = stroke.size * 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawPath(path, glowPaint);
      }

      final mainPaint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, mainPaint);
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final path = Path();
    for (double t = 0; t <= math.pi * 2; t += 0.1) {
      final dx = size * 0.08 * (16 * math.pow(math.sin(t), 3));
      final dy = -size *
          0.08 *
          (13 * math.cos(t) -
              5 * math.cos(2 * t) -
              2 * math.cos(3 * t) -
              math.cos(4 * t));
      if (t == 0) {
        path.moveTo(center.dx + dx, center.dy + dy);
      } else {
        path.lineTo(center.dx + dx, center.dy + dy);
      }
    }
    path.close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LoveLockPainter oldDelegate) => true;
}
