// lib/pages/market_page.dart
// 行情页：价格头卡（实时）+ 区间统计 + 周期分段控件 + 折线/K线图表。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/services/market_hours.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/utils/formatters.dart';
import 'package:goldpulse/widgets/chart.dart';
import 'package:goldpulse/widgets/empty_state.dart';

/// 行情页黄金类型：Au9999 / 浙商积存金 / 工商积存金。
/// [code] 为历史库（dao.recent）代码；[caption] 为头卡状态行的品种说明。
enum GoldType {
  au9999('Au9999', 'SGE-Au(T+D)', 'Au9999 · 上海金'),
  czb('浙商积存金', 'CZB-JCJ', '浙商积存金'),
  icbc('工商积存金', 'ICBC-JCJ', '工商积存金');

  const GoldType(this.label, this.code, this.caption);
  final String label;
  final String code;
  final String caption;
}

/// 按类型取对应实时行情流（供 ref.watch / ref.listen 取值）。
StreamProvider<GoldPrice?> goldPriceProviderOf(GoldType type) =>
    switch (type) {
      GoldType.au9999 => priceProvider,
      GoldType.czb => accumulationPriceProvider,
      GoldType.icbc => icbcPriceProvider,
    };

/// 区间统计：区间最高 / 区间最低 / 区间涨跌（区间首尾差%）。
/// rows 来自 dao.recent（time DESC，新→旧）；不足 2 条返回 null（无法计算涨跌）。
/// 涨跌基数为区间首端（最早）价格，正向为涨（红）、负向为跌（绿）。
({double high, double low, double changePct})? periodStatsOf(
    List<GoldPrice> rows) {
  if (rows.length < 2) return null;
  var high = rows.first.price;
  var low = rows.first.price;
  GoldPrice newest = rows.first; // 区间末端（最新时间）
  GoldPrice oldest = rows.first; // 区间首端（最早时间）
  for (final r in rows) {
    if (r.price > high) high = r.price;
    if (r.price < low) low = r.price;
    if (r.time > newest.time) newest = r;
    if (r.time < oldest.time) oldest = r;
  }
  final changePct = (newest.price - oldest.price) / oldest.price * 100;
  return (high: high, low: low, changePct: changePct);
}

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  GoldType _type = GoldType.au9999;
  String _period = '7日';
  static const _periods = ['1日', '7日', '30日'];
  bool _showCandles = false;

  List<GoldPrice>? _rows; // null = 尚未成功加载过（首屏加载中）
  bool _loading = true;
  int _loadSeq = 0; // 防竞态：过期请求结果直接丢弃

  int _limitFor() => switch (_period) { '1日' => 240, '7日' => 240, _ => 720 };
  // K 线聚合组大小：各周期都聚合成约 30 根 K 线，保证图形密度一致。
  int _groupSizeFor() => (_limitFor() / 30).ceil();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 按当前周期 + 当前类型从历史库加载走势数据。
  /// 首屏（_rows == null）期间失败按空列表处理，展示空态而非报错。
  Future<void> _load() async {
    final seq = ++_loadSeq;
    final code = _type.code; // 锁定本次请求的类型代码：切换类型后旧请求由 seq 丢弃
    List<GoldPrice> rows;
    try {
      rows = await ref
          .read(priceDaoProvider)
          .recent(code, limit: _limitFor())
          // 本地库读取不应超过数秒；异常卡死时降级为空列表（显示空态而非永久转圈）。
          .timeout(const Duration(seconds: 5), onTimeout: () => const []);
    } catch (_) {
      rows = const [];
    }
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  /// 手动刷新：重启三个行情轮询（流启动即强拉一次最新价）+ 重载历史数据。
  /// 与首页 refreshAllQuotes 同一语义，这里内联以避免页面间循环依赖。
  Future<void> _refresh() async {
    ref.invalidate(priceProvider);
    ref.invalidate(accumulationPriceProvider);
    ref.invalidate(icbcPriceProvider);
    await _load();
  }

  /// 切换黄金类型：切换即重载（清空旧类型走势数据，展示新类型加载态）。
  void _selectType(GoldType t) {
    if (t == _type) return;
    setState(() {
      _type = t;
      _rows = null;
      _loading = true;
    });
    _load();
  }

  void _selectPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  /// 半实时重载：仅当当前类型的实时流出现新时间戳时触发，
  /// 同一条数据（轮询重发）不重复查询。
  void _maybeReload(AsyncValue<GoldPrice?>? prev, AsyncValue<GoldPrice?> next) {
    if (!next.hasValue) return;
    // AsyncData(null)（空库/首拉前）value 为 null，无时间戳可比较 → 跳过。
    final nextTime = next.valueOrNull?.time;
    if (nextTime == null) return;
    final prevTime =
        prev != null && prev.hasValue ? prev.valueOrNull?.time : null;
    if (nextTime == prevTime) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // valueOrNull：AsyncError 状态下访问 .value 会重抛原始异常，这里安全降级为 null。
    final live = ref.watch(goldPriceProviderOf(_type)).valueOrNull; // 当前类型实时流最新价
    // 新价入库后自动重载历史（半实时）：仅在新时间戳出现时触发，避免重复查询。
    // 三个流始终监听、仅对当前激活类型放行，切换类型后无需重挂监听。
    // 用 hasValue 而非 .value：加载中/失败状态不触发重载。
    ref.listen(priceProvider, (prev, next) {
      if (_type != GoldType.au9999) return;
      _maybeReload(prev, next);
    });
    ref.listen(accumulationPriceProvider, (prev, next) {
      if (_type != GoldType.czb) return;
      _maybeReload(prev, next);
    });
    ref.listen(icbcPriceProvider, (prev, next) {
      if (_type != GoldType.icbc) return;
      _maybeReload(prev, next);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('行情'),
        actions: [
          IconButton(
            tooltip: '刷新行情',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeaderCard(context, live),
          const SizedBox(height: 14),
          _buildStatsCard(context),
          const SizedBox(height: 14),
          _buildControls(context),
          const SizedBox(height: 14),
          _buildChartCard(context),
        ],
      ),
    );
  }

  // ---- 价格头卡（实时）----
  Widget _buildHeaderCard(BuildContext context, GoldPrice? live) {
    final now = DateTime.now();
    final trading = MarketHours.isTrading(now);
    final phaseLabel = MarketHours.label(now);
    final resumeHint = MarketHours.resumeHint(now);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.goldSoft.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 顶部：三类型切换分段控件（Au9999 / 浙商积存金 / 工商积存金）
        _buildTypeSwitcher(context),
        const SizedBox(height: 12),
        // 状态行：品种说明 + 交易状态胶囊（复用 GoldCard 语言：交易金点 / 休市灰点）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_type.caption,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 15, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            // Flexible + 省略号（GoldCard 同款）：窄屏（≤320dp）下胶囊收缩，避免 RenderFlex 溢出
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: trading
                      ? AppTheme.gold.withValues(alpha: 0.14)
                      : AppTheme.divider.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: trading ? AppTheme.gold : AppTheme.offline,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(phaseLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                trading ? AppTheme.gold : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (resumeHint != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(resumeHint,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppTheme.textSecondary)),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // 大数字价格（实时流）
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(live == null ? '--' : fmtPrice(live.price),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 6),
            Text('元/g',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15)),
          ],
        ),
        if (live != null) ...[
          const SizedBox(height: 10),
          // 涨跌胶囊（红涨绿跌）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: arrowColor(live.change).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${arrow(live.change)} ${fmtAmount(live.change.abs())}'
              '  (${live.percent >= 0 ? '+' : ''}${live.percent.toStringAsFixed(2)}%)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  color: arrowColor(live.change),
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 8),
          // 数据新鲜度（实时流时间戳）+ 数据源（实时流 source，随类型切换跟随）
          Text(
            '更新于 ${_timeLabel(DateTime.fromMillisecondsSinceEpoch(live.time))}'
            '${live.source.isEmpty ? '' : ' · 数据源：${live.source}'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
          ),
        ],
      ]),
    );
  }

  // ---- 三类型切换分段控件 ----
  /// 与周期分段控件同语言（card 底 + 圆角999 + padding4 + divider 描边），
  /// 字号略小（13）；每段高 44px 保证触控目标；激活段金底 alpha 0.16 + 金字。
  Widget _buildTypeSwitcher(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        for (final t in GoldType.values)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _selectType(t),
              child: Container(
                height: 44, // 触控目标 ≥44px
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _type == t
                      ? AppTheme.gold.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _type == t ? FontWeight.w600 : FontWeight.w400,
                      color: _type == t ? AppTheme.gold : AppTheme.textSecondary,
                    )),
              ),
            ),
          ),
      ]),
    );
  }

  // ---- 区间统计卡 ----
  Widget _buildStatsCard(BuildContext context) {
    final stats = _rows == null ? null : periodStatsOf(_rows!);
    final changeColor = stats == null
        ? AppTheme.textSecondary
        : (stats.changePct >= 0 ? AppTheme.up : AppTheme.down);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Row(children: [
        _statCol(context, '区间最高',
            stats == null ? '--' : fmtPrice(stats.high), AppTheme.textPrimary),
        _statCol(context, '区间最低',
            stats == null ? '--' : fmtPrice(stats.low), AppTheme.textPrimary),
        _statCol(
            context,
            '区间涨跌',
            stats == null
                ? '--'
                : '${stats.changePct >= 0 ? '+' : ''}${stats.changePct.toStringAsFixed(2)}%',
            changeColor),
      ]),
    );
  }

  Widget _statCol(BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Column(children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  // ---- 周期分段控件 + K线切换 ----
  Widget _buildControls(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            for (final p in _periods)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _selectPeriod(p),
                  child: Container(
                    height: 44, // 触控目标 ≥44px
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _period == p
                          ? AppTheme.gold.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(p,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              _period == p ? FontWeight.w600 : FontWeight.w400,
                          color: _period == p
                              ? AppTheme.gold
                              : AppTheme.textSecondary,
                        )),
                  ),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      // K线开关：选中金框金字，未选中 divider 框次级字
      InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _showCandles = !_showCandles),
        child: Container(
          height: 52, // 与分段容器等高，≥44px 触控目标
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _showCandles ? AppTheme.gold : AppTheme.divider,
              width: _showCandles ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.candlestick_chart,
                size: 16,
                color:
                    _showCandles ? AppTheme.gold : AppTheme.textSecondary),
            const SizedBox(width: 5),
            Text('K线',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      _showCandles ? FontWeight.w600 : FontWeight.w400,
                  color:
                      _showCandles ? AppTheme.gold : AppTheme.textSecondary,
                )),
          ]),
        ),
      ),
    ]);
  }

  // ---- 图表卡 ----
  Widget _buildChartCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 280,
        child: _chartBody(context),
      ),
    );
  }

  Widget _chartBody(BuildContext context) {
    // 加载中且尚无任何数据：转圈卡片
    if (_loading && _rows == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
      );
    }
    final rows = _rows ?? const <GoldPrice>[];
    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.show_chart,
        title: '暂无历史数据',
        description: '行情轮询启动后自动积累数据',
      );
    }
    final rowsAsc = rows.reversed.toList(); // 旧 → 新
    if (_showCandles) {
      return CandlestickChart(
        spots: CandlestickChart.aggregateBars(
          prices: rowsAsc.map((e) => e.price).toList(),
          groupSize: _groupSizeFor(),
        ),
      );
    }
    return PriceLineChart(
      spots: rowsAsc.indexed
          .map((e) => FlSpot(e.$1.toDouble(), e.$2.price))
          .toList(),
      times: rowsAsc
          .map((e) => DateTime.fromMillisecondsSinceEpoch(e.time))
          .toList(),
      timeFormatter: _period == '1日' ? _fmtHHmm : _fmtMonthDay,
    );
  }

  static String _timeLabel(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  static String _fmtHHmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
  static String _fmtMonthDay(DateTime t) => '${_two(t.month)}-${_two(t.day)}';
  static String _two(int v) => v.toString().padLeft(2, '0');
}
