import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// QR code for the join URL so friends on the same WiFi scan & play.
class QrView extends StatelessWidget {
  final String data;
  final double size;
  const QrView({super.key, required this.data, this.size = 150});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: CustomPaint(size: Size.square(size), painter: _QrPainter(data)),
  );
}

class _QrPainter extends CustomPainter {
  final String data;
  _QrPainter(this.data);

  // Module grid as one path per URL (the lobby rebuilds on every update).
  static final _paths = <String, (int, Path)>{};
  static final _ink = Paint()..color = Colors.black;

  static (int, Path) _pathFor(String data) => _paths[data] ??= () {
    final img = QrImage(
      QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    final n = img.moduleCount;
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (img.isDark(y, x)) {
          path.addRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.02, 1.02));
        }
      }
    }
    return (n, path);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final (n, path) = _pathFor(data);
    canvas.save();
    canvas.scale(size.width / n);
    canvas.drawPath(path, _ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
