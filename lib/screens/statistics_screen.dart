import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/statistics_service.dart';
import '../widgets/app_ui.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  DailyStats? _todayStats;
  TotalStats? _totalStats;
  List<DailyStats>? _weekHistory;
  int _safeDistanceScore = 100;
  bool _isLoading = true;
  final _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final service = await StatisticsService.getInstance();
      final today = await service.getTodayStats();
      final total = service.getTotalStats();
      final history = await service.getWeekHistory();
      final score = await service.getSafeDistanceScore();
      setState(() {
        _todayStats = today;
        _totalStats = total;
        _weekHistory = history;
        _safeDistanceScore = score;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _shareStats() async {
    try {
      final Uint8List? image = await _screenshotController.capture();
      if (image == null) return;
      final directory = await getTemporaryDirectory();
      final imagePath = '${directory.path}/keepme_away_stats.png';
      await File(imagePath).writeAsBytes(image);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(imagePath)],
          text: 'My KeepMe Away score: $_safeDistanceScore',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t share: $e')),
        );
      }
    }
  }

  String _weekday(String date) {
    try {
      const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return names[DateTime.parse(date).weekday - 1];
    } catch (_) {
      return date.length >= 10 ? date.substring(5) : date;
    }
  }

  Color _scoreColor(int score) {
    if (score >= 80) return const Color(0xFF2FA36B);
    if (score >= 60) return const Color(0xFF7CB342);
    if (score >= 40) return const Color(0xFFE09B2D);
    return const Color(0xFFD64545);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
            onPressed: _shareStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Screenshot(
              controller: _screenshotController,
              child: RefreshIndicator(
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                      child: Column(
                        children: [
                          Text(
                            '$_safeDistanceScore',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: _scoreColor(_safeDistanceScore),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Safe distance score',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Fewer warnings per hour spent protected.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.55),
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Today", style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _StatBox(
                                  value: '${_todayStats?.warnings ?? 0}',
                                  label: 'Warnings',
                                  color: const Color(0xFFE09B2D),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatBox(
                                  value: '${_todayStats?.blocks ?? 0}',
                                  label: 'Blocks',
                                  color: const Color(0xFFD64545),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatBox(
                                  value: '${_todayStats?.sessionMinutes ?? 0}m',
                                  label: 'Protected',
                                  color: const Color(0xFF2FA36B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_weekHistory != null && _weekHistory!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Last 7 days', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 120,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: _weekHistory!.map((day) {
                                  final maxWarnings = _weekHistory!
                                      .map((d) => d.warnings)
                                      .fold<int>(0, (a, b) => a > b ? a : b);
                                  final ratio = maxWarnings > 0 ? day.warnings / maxWarnings : 0.0;
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${day.warnings}',
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            height: 12 + 72 * ratio,
                                            decoration: BoxDecoration(
                                              color: scheme.primary.withValues(alpha: 0.75),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _weekday(day.date),
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        children: [
                          _AllTimeRow(label: 'Total warnings', value: '${_totalStats?.totalWarnings ?? 0}'),
                          const Divider(height: 28),
                          _AllTimeRow(label: 'Total blocks', value: '${_totalStats?.totalBlocks ?? 0}'),
                          const Divider(height: 28),
                          _AllTimeRow(
                            label: 'Time protected',
                            value: _totalStats?.totalSessionTimeFormatted ?? '0h 0m',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatBox({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _AllTimeRow extends StatelessWidget {
  final String label;
  final String value;
  const _AllTimeRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }
}
