import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controls/input_controller.dart';
import '../game/rooster_game.dart';
import '../net/session.dart';
import '../platform/web_helpers.dart';
import '../ui/theme.dart';
import '../audio/sound_fx.dart';
import '../main.dart' show musicMutedPref, soundMutedPref;
import '../widgets/chicken_info_card.dart';
import '../widgets/close_room.dart';
import '../widgets/controls_help.dart';

/// Match screen: Flame world + HUD, with one raw [Listener] for multi-touch
/// controls; keyboard (desktop browsers) goes through the game's focus.
class MatchView extends StatefulWidget {
  final Session session;
  final VoidCallback onLeave;
  const MatchView({super.key, required this.session, required this.onLeave});

  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  final _input = InputController(
    keyboardState: () => HardwareKeyboard.instance.logicalKeysPressed,
  );
  // Keys go straight to the game whatever has focus (a tapped HUD button
  // used to swallow key-ups → stuck keys, and Space could press it).
  bool _onKey(KeyEvent e) => _input.handleKey(e);
  late final AppLifecycleListener _life;
  late final RoosterGame _game;
  bool _askedFullscreen = false;
  bool _showHelp = true;
  bool _showInfo = false;
  late bool _touch = _mobilePlatform;
  static const _helpPref = 'show_controls_help';

  static bool get _mobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _game = RoosterGame(
      session: widget.session,
      input: _input,
      showTouchControls: _mobilePlatform,
    );
    _input.onHelpToggle = _toggleHelp;
    HardwareKeyboard.instance.addHandler(_onKey);
    // Leaving the tab / window: release everything that was held.
    _life = AppLifecycleListener(
      onInactive: _input.reset,
      onHide: _input.reset,
    );
    WebHelpers.keepScreenOn();
    _loadHelpPref();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _life.dispose();
    _game.stats.dispose();
    super.dispose();
  }

  Future<void> _loadHelpPref() async {
    try {
      final v = (await SharedPreferences.getInstance()).getBool(_helpPref);
      if (v != null && mounted) setState(() => _showHelp = v);
    } on Object {
      // Storage unavailable (private mode) — keep the default.
    }
  }

  /// Cycles: everything on → music off (effects on) → all off.
  void _toggleSound() {
    final fx = SoundFx.instance;
    setState(() {
      if (fx.muted) {
        fx.muted = false;
        fx.musicMuted = false;
      } else if (fx.musicMuted) {
        fx.muted = true;
      } else {
        fx.musicMuted = true;
      }
    });
    SharedPreferences.getInstance()
        .then((p) {
          p.setBool(soundMutedPref, fx.muted);
          p.setBool(musicMutedPref, fx.musicMuted);
        })
        .ignore(); // storage blocked — the toggle still works this session
  }

  /// "My chicken" sheet — the reveal is too quick to read, so it's here too.
  void _toggleInfo() => setState(() {
    _showInfo = !_showInfo;
    if (_showInfo) _showHelp = false;
  });

  void _toggleHelp() {
    setState(() {
      _showHelp = !_showHelp;
      if (_showHelp) _showInfo = false;
    });
    SharedPreferences.getInstance()
        .then((p) => p.setBool(_helpPref, _showHelp))
        .catchError((Object _) => false);
  }

  FighterInfo? get _myInfo {
    final you = widget.session.match?.you;
    return you == null ? null : widget.session.match?.fighters[you];
  }

  String get _skillName {
    final you = widget.session.match?.you;
    final info = you == null ? null : widget.session.match?.fighters[you];
    return info == null
        ? 'kỹ năng riêng'
        : ChickenClasses.byId(info.classId).skillName;
  }

  Future<void> _confirmLeave() async {
    final s = widget.session;
    final canClose = s.isOwner && !s.isLocal;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời trận?'),
        content: Text(
          canClose
              ? 'Rời trận: gà của bạn được bot điều khiển tiếp.\n'
                    'Đóng phòng: kết thúc trận và đưa mọi người ra ngoài.'
              : 'Gà của bạn sẽ được bot điều khiển tiếp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ở lại'),
          ),
          if (canClose)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: RC.red),
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: const Text('Đóng phòng'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'leave'),
            child: const Text('Rời'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'leave') widget.onLeave();
    if (choice == 'close') await confirmCloseRoom(context, s);
  }

  void _down(PointerDownEvent e) {
    final touch = e.kind == PointerDeviceKind.touch;
    // First touch on a phone browser: go fullscreen (needs a user gesture).
    if (touch &&
        WebHelpers.isWeb &&
        !WebHelpers.isFullscreen &&
        !_askedFullscreen) {
      _askedFullscreen = true;
      WebHelpers.enterFullscreen();
    }
    if (touch && !_game.showTouchControls) {
      _game.showTouchControls = true;
      setState(() => _touch = true);
    }
    _input.pointerDown(
      e.pointer,
      e.localPosition,
      touch ? PointerDeviceKindLike.touch : PointerDeviceKindLike.mouse,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GameWidget(game: _game)),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: (e) =>
                _input.pointerMove(e.pointer, e.localPosition),
            onPointerUp: (e) => _input.pointerUp(e.pointer),
            onPointerCancel: (e) => _input.pointerUp(e.pointer),
          ),
        ),
        Positioned(
          top: 6,
          left: 6,
          child: SafeArea(
            child: Column(
              children: [
                _RoundButton(icon: Icons.close, onTap: _confirmLeave),
                if (WebHelpers.isWeb) ...[
                  const SizedBox(height: 6),
                  _RoundButton(
                    icon: Icons.fullscreen,
                    onTap: WebHelpers.enterFullscreen,
                  ),
                ],
                const SizedBox(height: 6),
                _RoundButton(
                  icon: _touch ? Icons.help_outline : Icons.keyboard,
                  onTap: _toggleHelp,
                  active: _showHelp,
                  tooltip: _touch ? 'Hướng dẫn' : 'Hướng dẫn phím (H)',
                ),
                const SizedBox(height: 6),
                _RoundButton(
                  icon: SoundFx.instance.muted
                      ? Icons.volume_off
                      : (SoundFx.instance.musicMuted
                            ? Icons.music_off
                            : Icons.volume_up),
                  onTap: _toggleSound,
                  tooltip: SoundFx.instance.muted
                      ? 'Đang tắt hết — bấm để bật'
                      : (SoundFx.instance.musicMuted
                            ? 'Đang tắt nhạc — bấm để tắt hết'
                            : 'Bấm để tắt nhạc'),
                ),
                if (_myInfo != null) ...[
                  const SizedBox(height: 6),
                  _RoundButton(
                    icon: Icons.info_outline,
                    onTap: _toggleInfo,
                    active: _showInfo,
                    tooltip: 'Thông tin chiến kê của bạn',
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_showInfo && _myInfo != null)
          Positioned(
            top: 44,
            left: 56,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Align(
                alignment: _touch ? Alignment.topCenter : Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Stack(
                    children: [
                      SingleChildScrollView(
                        child: ChickenInfoCard(
                          def: ChickenClasses.byId(_myInfo!.classId),
                          variant: _myInfo!.variant,
                          rarity: _myInfo!.rarity,
                          slotColor: Color(
                            slotColors[_myInfo!.slot % slotColors.length],
                          ),
                          compact: true,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: _toggleInfo,
                          icon: const Icon(
                            Icons.close,
                            size: 18,
                            color: RC.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_showHelp)
          // Touch: under the timer (thumbs own the bottom); desktop: bottom-left.
          Positioned(
            top: _touch ? 44 : null,
            bottom: _touch ? null : 12,
            left: _touch ? 0 : 56,
            right: _touch ? 0 : 12,
            child: IgnorePointer(
              child: SafeArea(
                child: Align(
                  alignment: _touch
                      ? Alignment.topCenter
                      : Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: _touch
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      ControlsHelp(touch: _touch, skillName: _skillName),
                      const SizedBox(height: 4),
                      ValueListenableBuilder<String>(
                        valueListenable: _game.stats,
                        builder: (_, v, _) => v.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xD91B100A),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  v,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: RC.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final String? tooltip;
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: active ? RC.gold : const Color(0xAA1B100A),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, color: active ? RC.ink : RC.cream, size: 20),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
