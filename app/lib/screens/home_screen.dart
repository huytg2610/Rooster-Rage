import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_core/rooster_core.dart';

import '../app/profile.dart';
import '../app/providers.dart';
import '../platform/web_helpers.dart';
import '../ui/theme.dart';
import '../widgets/chicken_avatar.dart';
import 'roster_screen.dart';

class RoomDefaults {
  static const port = 8080;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _name = TextEditingController();
  final _server = TextEditingController();
  bool _loadedName = false;
  String? _error;

  bool _hostDetected = false;

  @override
  void initState() {
    super.initState();
    _server.text = _servedByHost
        ? WebHelpers.defaultServerUri().toString()
        : 'ws://localhost:${RoomDefaults.port}/ws';
    // Served by a LAN host on a non-default port? Ask the origin.
    WebHelpers.probeHost().then((isHost) {
      if (!isHost || !mounted) return;
      setState(() {
        _hostDetected = true;
        _server.text = WebHelpers.defaultServerUri().toString();
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    super.dispose();
  }

  /// Page was served by a LAN host (not the `flutter run` dev server) →
  /// joining is the main action.
  bool get _servedByHost {
    if (_hostDetected) return true;
    final u = WebHelpers.defaultServerUri();
    if (u == null) return false;
    final loopback = u.host == 'localhost' || u.host == '127.0.0.1';
    return !loopback || u.port == RoomDefaults.port;
  }

  Future<Profile?> _profile() async {
    final p = await ref.read(profileProvider.future);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nhập tên chiến kê của bạn trước đã!');
      return null;
    }
    final updated = p.copyWith(
      name: name.length > 16 ? name.substring(0, 16) : name,
    );
    await ProfileStore.save(updated);
    ref.invalidate(profileProvider); // home shows the saved name next time
    return updated;
  }

  Future<void> _playOffline() async {
    final p = await _profile();
    if (p == null || !mounted) return;
    ref.read(sessionProvider.notifier).startLocal(p);
    context.go('/room');
  }

  Future<void> _joinLan() async {
    final p = await _profile();
    if (p == null || !mounted) return;
    final uri = Uri.tryParse(_server.text.trim());
    if (uri == null ||
        !(uri.scheme == 'ws' || uri.scheme == 'wss') ||
        uri.host.isEmpty) {
      setState(() => _error = 'Địa chỉ host phải dạng ws://IP:8080/ws');
      return;
    }
    WebHelpers.keepScreenOn();
    ref.read(sessionProvider.notifier).join(p, uri);
    context.go('/room');
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    if (!_loadedName && profile.hasValue) {
      _loadedName = true;
      _name.text = profile.value!.name;
    }
    final lanFirst = _servedByHost;
    final wide = MediaQuery.sizeOf(context).width > 720;

    final title = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'ROOSTER RAGE',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w900,
            color: RC.gold,
            height: 1,
            shadows: [Shadow(color: RC.red, offset: Offset(3, 3))],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ĐẠI CHIẾN GÀ ĐÁ',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final (i, c) in ChickenClasses.all.indexed)
              ChickenAvatar(
                chicken: ChickenInstance(
                  c.id,
                  Variant.values[i % Variant.values.length],
                  Rarity.values[i % Rarity.values.length],
                ),
                slotColor: Color(slotColors[i % slotColors.length]),
                size: wide ? 84 : 60,
                state: i.isEven ? FState.idle : FState.run,
                faceRight: i < 3,
              ),
          ],
        ),
      ],
    );

    final form = WoodPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: 16,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Tên chiến kê',
              counterText: '',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          if (lanFirst) ...[
            FilledButton.icon(
              onPressed: _joinLan,
              icon: const Icon(Icons.wifi),
              label: const Text('VÀO PHÒNG LAN'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _playOffline,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('Luyện với bot (offline)'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _playOffline,
              icon: const Icon(Icons.smart_toy_outlined),
              label: const Text('CHƠI VỚI BOT'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _joinLan,
              icon: const Icon(Icons.wifi),
              label: const Text('Vào phòng LAN'),
            ),
          ],
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => RosterScreen.open(context),
            icon: const Icon(Icons.menu_book, color: RC.gold),
            label: const Text(
              'Xem thông tin 8 chiến kê',
              style: TextStyle(color: RC.gold, fontWeight: FontWeight.w800),
            ),
          ),
          if (WebHelpers.isWeb)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Đồ họa:',
                    style: TextStyle(fontSize: 13, color: RC.muted),
                  ),
                  for (final (q, label) in const [
                    ('auto', 'Tự động'),
                    ('low', 'Tiết kiệm'),
                    ('high', 'Sắc nét'),
                  ])
                    ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: WebHelpers.quality == q,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        if (WebHelpers.quality != q) WebHelpers.setQuality(q);
                      },
                    ),
                ],
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: false,
            title: const Text(
              'Địa chỉ host LAN',
              style: TextStyle(fontSize: 13, color: RC.muted),
            ),
            children: [
              TextField(
                controller: _server,
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'ws://IP-máy-host:8080/ws',
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: RC.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    const howTo = WoodPanel(
      child: Text(
        'Điện thoại: kéo trái để chạy · chạm phải = đánh, giữ = đánh mạnh, '
        'vuốt xuống = lướt, vuốt lên = nhảy · giữ THỦ để đỡ.\n'
        'Máy tính: WASD chạy · J đánh (giữ J = mạnh) · giữ K đỡ · L lướt · '
        'Space nhảy · U Nộ + chiêu cuối · O gáy.\n'
        'Đánh trúng/bị đánh sẽ tích Nộ. Đầy Nộ thì bấm U (nút CHIÊU): vừa Nộ vừa tung chiêu cuối. '
        'Mỗi đòn tốn thể lực — hất đối thủ ra khỏi sân để hạ gục nhanh!',
        style: TextStyle(fontSize: 13, height: 1.4, color: RC.cream),
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [RC.bg2, RC.bg],
                ),
              ),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: wide ? 900 : 440),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: title),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      form,
                                      const SizedBox(height: 12),
                                      howTo,
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                title,
                                const SizedBox(height: 16),
                                form,
                                const SizedBox(height: 12),
                                howTo,
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton.filled(
                tooltip: 'Thông tin các chiến kê',
                style: IconButton.styleFrom(
                  backgroundColor: RC.panel,
                  foregroundColor: RC.gold,
                ),
                onPressed: () => RosterScreen.open(context),
                icon: const Icon(Icons.menu_book),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
