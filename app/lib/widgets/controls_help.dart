import 'package:flutter/material.dart';

import '../ui/theme.dart';

/// In-match controls cheat sheet: keyboard on desktop, gestures on touch.
class ControlsHelp extends StatelessWidget {
  final bool touch;
  final String skillName;
  const ControlsHelp({super.key, required this.touch, required this.skillName});

  @override
  Widget build(BuildContext context) {
    final rows = touch
        ? <(List<String>, String)>[
            (['Kéo trái'], 'Chạy'),
            (['Chạm phải'], 'Đánh thường (chạm liên tục = combo)'),
            (['Giữ phải'], 'Đánh mạnh (giữ lâu = mạnh hơn)'),
            (['THỦ'], 'Giữ để đỡ: giảm sát thương; khiên có máu, vỡ thì chờ hồi'),
            (['Vuốt xuống'], 'Lướt'),
            (['Vuốt lên'], 'Nhảy đánh'),
            (['CHIÊU'], 'Đầy Nộ: bật Nộ + tung $skillName luôn'),
            (['GÁY'], 'Đẩy lùi, tăng nộ'),
          ]
        : <(List<String>, String)>[
            (['W', 'A', 'S', 'D'], 'Di chuyển (hoặc phím mũi tên)'),
            (['J'], 'Đánh thường (bấm liên tục = combo)'),
            (['Giữ J'], 'Đánh mạnh — nhả ra để đánh'),
            (['Giữ K'], 'Đỡ đòn: giảm sát thương; khiên có máu, vỡ thì chờ hồi'),
            (['L', 'Shift'], 'Lướt'),
            (['Space'], 'Nhảy đánh'),
            (['U'], 'Đầy Nộ: bật Nộ + tung $skillName luôn'),
            (['O'], 'Gáy: đẩy lùi, tăng nộ'),
            (['H'], 'Ẩn / hiện bảng này'),
          ];

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xD91B100A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RC.panelHi, width: 2),
      ),
      // Clips instead of overflowing on short screens (the sheet ignores
      // touches, so it never needs to actually scroll).
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ĐIỀU KHIỂN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: RC.gold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Góc trái: MÁU (đỏ) · THỂ LỰC (vàng, đánh/né tốn) · THĂNG BẰNG '
              '(xanh, về 0 là choáng) · NỘ (cam, đầy thì bấm Nộ).\n'
              'Trên đầu gà: đỏ = máu, vạch xanh = thăng bằng, chấm cam = Nộ sẵn sàng.\n'
              'Màu: cam/đỏ = đánh (! = đòn mạnh sắp ra) · xanh = đỡ · vàng = gáy đẩy.',
              style: TextStyle(fontSize: 11, color: RC.muted, height: 1.3),
            ),
            const SizedBox(height: 6),
            for (final (keys, action) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: touch ? 84 : 104,
                      child: Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: [for (final k in keys) _KeyCap(k)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        action,
                        style: const TextStyle(fontSize: 12, color: RC.cream),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  final String label;
  const _KeyCap(this.label);

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 20),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: RC.cream,
      borderRadius: BorderRadius.circular(5),
      boxShadow: const [BoxShadow(color: RC.muted, offset: Offset(0, 2))],
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: RC.ink,
      ),
    ),
  );
}
