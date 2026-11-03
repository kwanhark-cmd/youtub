import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../services/sale_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../widgets/celebrate.dart';
import '../../services/market_links.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// 판매 도우미 목록
class SellScreen extends StatelessWidget {
  const SellScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.palette;
    final list = s.items.where((i) => i.decision == Decision.sell).toList()
      ..sort((a, b) => (a.saleStatus == SaleStatus.sold ? 1 : 0).compareTo(b.saleStatus == SaleStatus.sold ? 1 : 0));
    return AppPage(
      title: '판매 도우미',
      body: list.isEmpty
          ? const Center(
              child: SingleChildScrollView(
                child: EmptyState(message: '판매로 정한 물건이 아직 없어요.\n"정리하기"에서 판매를 골라 보세요.', mood: MascotMood.thinking),
              ),
            )
          : ItemGrid(
              storageKey: 'sell_1',
              items: list,
              header: const FirstTimeTip(id: 'sell', text: '판매글을 만들어 "복사"한 뒤, 당근마켓이나 번개장터 앱에 직접 붙여넣어 올리세요. 이 앱은 대신 올리지 않아요.'),
              onTap: (it) => go(context, SellDetailScreen(itemId: it.id!)),
              trailing: (it) => s.sales.suggestedDrop(it, s.user, at: s.now) != null ? Chip3('인하 추천', p.attention, textColor: p.onAttention) : null,
            ),
    );
  }
}

class SellDetailScreen extends StatefulWidget {
  final int itemId;
  const SellDetailScreen({super.key, required this.itemId});
  @override
  State<SellDetailScreen> createState() => _SellDetailScreenState();
}

class _SellDetailScreenState extends State<SellDetailScreen> {
  Item? item;
  final title = TextEditingController();
  final body = TextEditingController();
  final category = TextEditingController();
  final price = TextEditingController();
  bool writing = false;
  bool showShipping = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final it = await s.repo.item(s.uid, widget.itemId);
    if (!mounted || it == null) return;
    setState(() {
      item = it;
      title.text = it.listingTitle;
      body.text = it.listingBody;
      category.text = it.listingCategory;
      price.text = it.price?.toString() ?? '';
      showShipping = it.shipping;
    });
    if (it.listingTitle.isEmpty) _write();
  }

  Future<void> _write() async {
    final s = context.read<AppState>();
    final it = item!;
    setState(() => writing = true);
    var jpeg = it.photoPath == null ? null : await s.images.readPhoto(it.photoPath!).catchError((_) => Uint8List(0));
    if (jpeg != null && jpeg.isEmpty) jpeg = null;
    var w = 0, h = 0;
    if (jpeg != null && it.photoPath != null) (w, h) = await s.images.sizeOf(it.photoPath!);
    final r = await s.ai.writeListing(s.uid, s.user, it, jpeg: jpeg, width: w, height: h);
    if (!mounted) return;
    final d = r.value;
    it.listingTitle = d.title;
    it.listingBody = d.body;
    it.listingCategory = d.category;
    it.priceLow = d.priceLow;
    it.priceHigh = d.priceHigh;
    await s.saveItem(it);
    setState(() {
      writing = false;
      title.text = d.title;
      body.text = d.body;
      category.text = d.category;
    });
    if (r.message != null && mounted) toast(context, r.message!);
  }

  Future<void> _saveFields() async {
    final it = item!;
    it.listingTitle = title.text;
    it.listingBody = body.text;
    it.listingCategory = category.text;
    it.shipping = showShipping;
    final pr = int.tryParse(price.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final s = context.read<AppState>();
    if (pr != null && pr != it.price) {
      await s.sales.startSelling(it, price: pr);
    }
    await s.saveItem(it);
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, '$what을(를) 복사했어요. 당근마켓·번개장터 앱에 붙여넣으세요.');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final it = item;
    if (it == null) {
      return const AppPage(
        title: '판매',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final s = context.watch<AppState>();
    final drop = s.sales.suggestedDrop(it, s.user, at: s.now);
    final days = s.sales.daysListed(it, s.now);
    final all = '${title.text}\n\n${body.text}\n\n가격: ${won(int.tryParse(price.text))}';
    return AppPage(
      title: '판매: ${it.name}',
      body: ListView(
        key: const PageStorageKey('sell_2'),
        padding: const EdgeInsets.all(AppSizes.page),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radius),
            child: SizedBox(height: 200, child: ItemPhoto(it, height: 200, full: true)),
          ),
          const SectionTitle('판매 상태'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final st in SaleStatus.values)
                BigButton(
                  label: '${it.saleStatus == st ? '✓ ' : ''}${st.label}',
                  expand: false,
                  color: it.saleStatus == st ? p.progress : p.muted,
                  onTap: () async {
                    int? sold;
                    if (st == SaleStatus.sold) {
                      final t = await askText(context, title: '얼마에 팔았나요?', initial: price.text, hint: '숫자만');
                      if (t == null) return;
                      sold = int.tryParse(t.replaceAll(RegExp(r'[^0-9]'), ''));
                    }
                    await s.sales.setStatus(it, st, soldPrice: sold);
                    await s.refresh();
                    if (!context.mounted) return;
                    if (st == SaleStatus.sold) {
                      celebrate(context, decision: Decision.sell, message: '판매 완료!');
                      s.say('${it.name} 판매 완료! 집이 한결 가벼워졌어요.');
                    }
                    setState(() {});
                  },
                ),
            ],
          ),
          if (it.listedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '판매 시작 $days일째 · ${SaleService.oneYearDays - days > 0 ? '${SaleService.oneYearDays - days}일 뒤 안 팔리면 폐기 목록으로 옮겨요' : ''}',
                style: TextStyle(color: p.muted, fontSize: 16),
              ),
            ),
          if (drop != null)
            Panel(
              border: p.attention,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Emoji3D('idea', size: 36),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$days일째 안 팔렸어요. ${won(it.price)} → ${won(drop)}(으)로 내려 볼까요?',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '${won(drop)}(으)로 내리기',
                    color: p.sell,
                    onTap: () async {
                      await s.sales.applyPriceDrop(it, drop);
                      price.text = '$drop';
                      await s.refresh();
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          const SectionTitle('가격'),
          Panel(child: Text('예상 시세: ${wonRange(it.priceLow, it.priceHigh)}\n(AI 추정이에요. 최종 가격은 직접 정해 주세요)', style: const TextStyle(fontSize: 17))),
          TextField(
            controller: price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '내가 정한 가격 (원)'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: '가격 저장',
            emoji: 'check',
            color: p.primary,
            onTap: () async {
              await _saveFields();
              if (context.mounted) toast(context, '가격을 저장했어요');
              setState(() {});
            },
          ),
          const SectionTitle('판매글'),
          if (writing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: Column(children: [Mascot(MascotMood.thinking, size: 80), Text('판매글을 쓰고 있어요…')])),
            ),
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: '제목'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: category,
            decoration: const InputDecoration(labelText: '카테고리'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: body,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(labelText: '설명'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSizes.gap),
          // 행동형 카드: 크게 복사 → 바로 앱 열기
          Panel(
            fill: Color.alphaBlend(p.sell.withValues(alpha: 0.12), p.surface),
            border: p.sell,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('1. 판매글 복사하기', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                BigButton(
                  label: '판매글 전체 복사',
                  emoji: 'clipboard',
                  color: p.sell,
                  onTap: () {
                    _saveFields();
                    _copy(all, '판매글');
                  },
                ),
                const SizedBox(height: AppSizes.gap),
                Text('2. 앱을 열고 붙여넣기', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final m in Market.values) ...[
                      if (m != Market.values.first) const SizedBox(width: 8),
                      Expanded(
                        child: BigButton(
                          label: '${m.label} 열기',
                          emoji: 'link',
                          color: m == Market.daangn ? const Color(0xFFB34700) : const Color(0xFFB71C1C),
                          onTap: () async {
                            final ok = await openMarket(m);
                            if (!ok) await showFailure(null, stage: '판매', message: '${m.label}을(를) 열지 못했어요. 앱이나 인터넷 연결을 확인해 주세요.');
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text('이 앱은 글을 대신 올리지 않아요. 열린 앱에서 직접 붙여넣어 올려 주세요.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: BigButton(label: '제목만 복사', color: p.primary, onTap: () => _copy(title.text, '제목')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BigButton(label: '설명만 복사', color: p.primary, onTap: () => _copy(body.text, '설명')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          BigButton(label: writing ? '쓰는 중…' : '판매글 다시 만들기', emoji: 'speech', color: p.muted, onTap: writing ? null : _write),
          const SizedBox(height: 8),
          Text('글을 복사한 뒤 당근마켓·번개장터 앱을 직접 열어 붙여넣으세요. 연락이 오면 각 앱의 알림으로 알 수 있어요.', style: TextStyle(color: p.muted, fontSize: 15)),
          const SectionTitle('택배로 보낼 때'),
          SwitchListTile(
            value: showShipping,
            title: const Text('번개장터 택배 판매 안내 보기', style: TextStyle(fontSize: 17)),
            onChanged: (v) {
              setState(() => showShipping = v);
              _saveFields();
            },
          ),
          if (showShipping) Panel(child: StepList(splitSteps(shippingGuide).skip(1).toList(), color: p.sell)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

const shippingGuide =
    '포장·발송 방법\n'
    '1. 물건을 깨끗이 닦고, 사진을 한 장 더 찍어 두세요(발송 전 상태 기록).\n'
    '2. 깨지는 물건은 뽁뽁이(에어캡)로 두세 겹 싸고, 상자 빈 곳은 신문지로 채워요.\n'
    '3. 상자는 테이프로 "H" 모양으로 단단히 붙여요.\n'
    '4. 번개장터 앱의 거래 화면에서 안내하는 택배 방법(편의점 택배 등)으로 접수해요.\n'
    '5. 받은 운송장 번호를 번개장터 앱에 입력해요.\n'
    '※ 자세한 택배 방법과 요금은 번개장터 앱 안내를 따라 주세요.';
