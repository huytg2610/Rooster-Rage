/// Little-endian byte writer/reader for the binary wire format.
library;

import 'dart:math' as math;
import 'dart:typed_data';

class ByteWriter {
  Uint8List _buf;
  late ByteData _view;
  int length = 0;

  ByteWriter([int capacity = 512]) : _buf = Uint8List(capacity) {
    _view = ByteData.sublistView(_buf);
  }

  void _ensure(int n) {
    if (length + n <= _buf.length) return;
    final next = Uint8List(math.max(_buf.length * 2, length + n));
    next.setRange(0, length, _buf);
    _buf = next;
    _view = ByteData.sublistView(_buf);
  }

  void u8(int v) {
    _ensure(1);
    _buf[length++] = v.clamp(0, 255);
  }

  void i8(int v) {
    _ensure(1);
    _view.setInt8(length++, v.clamp(-128, 127));
  }

  void u16(int v) {
    _ensure(2);
    _view.setUint16(length, v.clamp(0, 65535), Endian.little);
    length += 2;
  }

  void i16(int v) {
    _ensure(2);
    _view.setInt16(length, v.clamp(-32768, 32767), Endian.little);
    length += 2;
  }

  void u24(int v) {
    _ensure(3);
    final x = v.clamp(0, 0xFFFFFF);
    _buf[length++] = x & 0xFF;
    _buf[length++] = (x >> 8) & 0xFF;
    _buf[length++] = (x >> 16) & 0xFF;
  }

  void u32(int v) {
    _ensure(4);
    _view.setUint32(length, v & 0xFFFFFFFF, Endian.little);
    length += 4;
  }

  /// Patches a previously written byte (e.g. a count known only later).
  void setU8(int at, int v) => _buf[at] = v.clamp(0, 255);

  Uint8List takeBytes() => Uint8List.fromList(Uint8List.sublistView(_buf, 0, length));
}

class ByteReader {
  final ByteData _view;
  int pos = 0;

  ByteReader(Uint8List bytes) : _view = ByteData.sublistView(bytes);

  int get remaining => _view.lengthInBytes - pos;

  void _need(int n) {
    if (pos + n > _view.lengthInBytes) throw const FormatException('truncated');
  }

  int u8() {
    _need(1);
    return _view.getUint8(pos++);
  }

  int i8() {
    _need(1);
    return _view.getInt8(pos++);
  }

  int u16() {
    _need(2);
    final v = _view.getUint16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int i16() {
    _need(2);
    final v = _view.getInt16(pos, Endian.little);
    pos += 2;
    return v;
  }

  int u24() {
    _need(3);
    final v = _view.getUint8(pos) | _view.getUint8(pos + 1) << 8 | _view.getUint8(pos + 2) << 16;
    pos += 3;
    return v;
  }

  int u32() {
    _need(4);
    final v = _view.getUint32(pos, Endian.little);
    pos += 4;
    return v;
  }
}
