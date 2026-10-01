import 'dart:io';

/// IPv4 addresses other devices on the same WiFi can reach, private LAN
/// ranges first.
Future<List<String>> lanAddresses() async {
  final out = <String>[];
  try {
    final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.isLinkLocal) out.add(a.address);
      }
    }
  } on SocketException {
    // No interfaces — fall through to empty list.
  }
  int rank(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    if (m != null) {
      final b = int.parse(m.group(1)!);
      if (b >= 16 && b <= 31) return 2;
    }
    return 3;
  }

  out.sort((a, b) => rank(a).compareTo(rank(b)));
  return out;
}
