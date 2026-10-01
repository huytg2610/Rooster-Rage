import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rooster_core/rooster_core.dart';

import '../ui/theme.dart';
import '../widgets/chicken_info_card.dart';

/// All chickens with stats, rage skill and tips — read at your own pace.
class RosterScreen extends StatelessWidget {
  const RosterScreen({super.key});

  static void open(BuildContext context) => context.push('/chickens');

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1100 ? 3 : (width > 700 ? 2 : 1);
    const rules = WoodPanel(
      child: Text(
        'Mỗi trận mỗi người là 1 chiến kê khác nhau (tối đa 8).\n'
        '• Thể lực (vàng): mỗi đòn tốn thể lực, thể lực thấp đánh yếu, cạn thì thở dốc.\n'
        '• Thăng bằng (xanh): bị đánh nhiều sẽ tụt, về 0 thì choáng và bị hất văng xa hơn.\n'
        '• Nộ (cam): đánh trúng/bị đánh sẽ tích Nộ. Đầy Nộ thì bấm U (nút CHIÊU): '
        'bật Nộ (đánh mạnh +30%, nhanh hơn, không bị choáng) và tung chiêu cuối luôn; '
        'trong lúc Nộ bấm U lại để dùng chiêu khi hồi xong.\n'
        '• Đỡ (giữ K / nút THỦ): giảm 60% sát thương. Khiên có máu riêng (thanh KHIÊN): '
        'đỡ nhiều thì vỡ khiên và bị choáng; khiên tự hồi, hồi được 1/4 là giơ lại được. '
        'Gà thăng bằng cao, giáp dày hồi khiên nhanh hơn (xem "Hồi khiên").\n'
        '• Gà gục rơi ra cục máu (trái tim đỏ): ăn vào hồi 30% máu (đầy máu thì không ăn được).\n'
        '• Chết càng nhiều hồi sinh càng lâu (3 giây, mỗi lần thêm 1 giây, tối đa 8 giây).\n'
        '• Luật Sinh tồn (chọn ở phòng chờ): không hồi sinh, gục là bị loại — con gà cuối cùng còn đứng thắng.\n'
        '• Hất đối thủ ra khỏi sân là cách hạ gục nhanh nhất — rớt sân tính cho người đánh trúng cuối!',
        style: TextStyle(fontSize: 13, height: 1.45),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: RC.bg2,
        title: Text(
          'Các chiến kê (${ChickenClasses.all.length})',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            rules,
            const SizedBox(height: 12),
            for (var i = 0; i < ChickenClasses.all.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: 12),
                        Expanded(
                          child: j < ChickenClasses.all.length
                              ? ChickenInfoCard(
                                  def: ChickenClasses.all[j],
                                  slotColor: Color(
                                    slotColors[j % slotColors.length],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
