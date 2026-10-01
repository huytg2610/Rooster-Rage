import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_server/host_server.dart';
import 'package:rooster_server/lan_info.dart';
import 'package:rooster_server/qr_terminal.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addOption('address', defaultsTo: '0.0.0.0', help: 'Bind address')
    ..addOption('web',
        defaultsTo: p.normalize(p.join(p.dirname(Platform.script.toFilePath()), '..', '..',
            'app', 'build', 'web')),
        help: 'Flutter web build directory')
    ..addFlag('qr', defaultsTo: true, help: 'Print a join QR code')
    ..addFlag('help', abbr: 'h', negatable: false);
  final opts = parser.parse(args);
  if (opts['help'] as bool) {
    stdout.writeln('Rooster Rage LAN host\n\n${parser.usage}');
    return;
  }

  final port = int.tryParse(opts['port'] as String) ?? 8080;
  final ips = await lanAddresses();
  final urls = [for (final ip in ips) 'http://$ip:$port'];
  final room = RoomHost(joinUrls: urls);
  final server = HostServer(room);
  try {
    await server.start(
        webDir: opts['web'] as String, address: opts['address'] as String, port: port);
  } on SocketException catch (e) {
    stderr.writeln('Không mở được cổng $port: ${e.message}');
    exitCode = 1;
    return;
  }

  stdout.writeln('🐓 Rooster Rage host đang chạy (web: ${opts['web']})');
  stdout.writeln('   Máy này:  http://localhost:$port');
  for (final u in urls) {
    stdout.writeln('   Cùng WiFi: $u');
  }
  if (urls.isNotEmpty && (opts['qr'] as bool)) {
    stdout.writeln('\nQuét để vào phòng (${urls.first}):\n');
    stdout.write(qrForTerminal(urls.first));
  }
  stdout.writeln('\nCtrl+C để tắt.');

  ProcessSignal.sigint.watch().listen((_) async {
    await server.stop();
    exit(0);
  });
}
