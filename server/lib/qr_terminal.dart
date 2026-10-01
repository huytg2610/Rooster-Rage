import 'package:qr/qr.dart';

/// Renders [data] as a QR code using half-block characters (2 rows per
/// line) so phones can scan it straight from the terminal.
String qrForTerminal(String data) {
  final image = QrImage(QrCode(
    payload: QrPayload.fromString(data),
    errorCorrectLevel: QrErrorCorrectLevel.low,
  ));
  final n = image.moduleCount;
  const quiet = 2;
  bool dark(int x, int y) =>
      x >= 0 && y >= 0 && x < n && y < n && image.isDark(y, x);

  final sb = StringBuffer();
  for (var y = -quiet; y < n + quiet; y += 2) {
    for (var x = -quiet; x < n + quiet; x++) {
      final top = dark(x, y), bottom = dark(x, y + 1);
      // Light modules are drawn as filled blocks (works on dark terminals).
      sb.write(switch ((top, bottom)) {
        (false, false) => '█',
        (true, false) => '▄',
        (false, true) => '▀',
        (true, true) => ' ',
      });
    }
    sb.writeln();
  }
  return sb.toString();
}
