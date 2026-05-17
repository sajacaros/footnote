import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/walk_models.dart';
import '../services/active_walk_service.dart';
import '../services/walk_repository.dart';
import '../widgets/walk_map_preview.dart';
import 'record_walk_screen.dart';
import 'walk_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WalkRepository _repository = WalkRepository.instance;
  final ActiveWalkService _activeWalk = ActiveWalkService.instance;
  final DateFormat _dayHeader = DateFormat('M월 d일');
  final DateFormat _clock = DateFormat('HH:mm');
  List<WalkSession> _sessions = [];
  bool _loading = true;
  int _tabIndex = 0;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _activeWalk.addListener(_refresh);
    _loadSessions();
  }

  @override
  void dispose() {
    _activeWalk.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('풋노트 산책'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadSessions,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                  children: [
                    if (_activeWalk.isActive) ...[
                      _ActiveWalkBanner(onTap: _openRecorder),
                      const SizedBox(height: 14),
                    ],
                    _TodaySummary(sessions: _todaySessions),
                    const SizedBox(height: 16),
                    _HomeTabs(
                      selectedIndex: _tabIndex,
                      onChanged: (index) => setState(() => _tabIndex = index),
                    ),
                    const SizedBox(height: 16),
                    if (_tabIndex == 0)
                      _RecentTimeline(
                        sessions: _sessions,
                        dayHeader: _dayHeader,
                        clock: _clock,
                        onOpen: _openDetail,
                      )
                    else if (_tabIndex == 1)
                      _HistoryCalendar(
                        month: _visibleMonth,
                        sessions: _sessions,
                        onPrevious: () => setState(() {
                          _visibleMonth = DateTime(
                            _visibleMonth.year,
                            _visibleMonth.month - 1,
                          );
                        }),
                        onNext: () => setState(() {
                          _visibleMonth = DateTime(
                            _visibleMonth.year,
                            _visibleMonth.month + 1,
                          );
                        }),
                        onOpen: _openDetail,
                      )
                    else
                      _StatsView(sessions: _sessions),
                  ],
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecorder,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(_activeWalk.isActive ? '산책 열기' : '산책 시작'),
      ),
    );
  }

  List<WalkSession> get _todaySessions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _sessions
        .where((session) => _dayKey(session.startedAt) == today)
        .toList();
  }

  Future<void> _loadSessions() async {
    final sessions = await _repository.loadSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  Future<void> _openDetail(WalkSession session) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WalkDetailScreen(session: session),
      ),
    );

    if (changed == true) {
      await _loadSessions();
    }
  }

  Future<void> _openRecorder() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const RecordWalkScreen(),
      ),
    );

    if (saved == true) {
      await _loadSessions();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  static DateTime _dayKey(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _ActiveWalkBanner extends StatelessWidget {
  const _ActiveWalkBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeWalk = ActiveWalkService.instance;
    return Material(
      color: const Color(0xFFEAF6F1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.directions_walk_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '산책 기록 중 | '
                  '${(activeWalk.distanceMeters / 1000).toStringAsFixed(2)} km | '
                  '사진 ${activeWalk.photos.length}장',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.sessions});

  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final distance = _distance(sessions) / 1000;
    final minutes = _minutes(sessions);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF151713),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '오늘',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _DarkMetric(
                  value: '${sessions.length}',
                  label: '산책',
                ),
              ),
              Expanded(
                child: _DarkMetric(
                  value: distance.toStringAsFixed(1),
                  label: 'km',
                ),
              ),
              Expanded(
                child: _DarkMetric(
                  value: '$minutes',
                  label: '분',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeTabs extends StatelessWidget {
  const _HomeTabs({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<int>(
      segments: const [
        ButtonSegment(value: 0, icon: Icon(Icons.timeline_rounded), label: Text('최근')),
        ButtonSegment(value: 1, icon: Icon(Icons.calendar_month_rounded), label: Text('기록')),
        ButtonSegment(value: 2, icon: Icon(Icons.bar_chart_rounded), label: Text('통계')),
      ],
      selected: {selectedIndex},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class _RecentTimeline extends StatelessWidget {
  const _RecentTimeline({
    required this.sessions,
    required this.dayHeader,
    required this.clock,
    required this.onOpen,
  });

  final List<WalkSession> sessions;
  final DateFormat dayHeader;
  final DateFormat clock;
  final ValueChanged<WalkSession> onOpen;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const _EmptyState(text: '아직 기록된 산책이 없습니다.');
    }

    final groups = <DateTime, List<WalkSession>>{};
    for (final session in sessions) {
      final day = DateTime(
        session.startedAt.year,
        session.startedAt.month,
        session.startedAt.day,
      );
      groups.putIfAbsent(day, () => []).add(session);
    }

    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              dayHeader.format(day),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          ...groups[day]!.map(
            (session) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _WalkListTile(
                session: session,
                clock: clock,
                onTap: () => onOpen(session),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HistoryCalendar extends StatelessWidget {
  const _HistoryCalendar({
    required this.month,
    required this.sessions,
    required this.onPrevious,
    required this.onNext,
    required this.onOpen,
  });

  final DateTime month;
  final List<WalkSession> sessions;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<WalkSession> onOpen;

  @override
  Widget build(BuildContext context) {
    final monthSessions = sessions
        .where((session) =>
            session.startedAt.year == month.year &&
            session.startedAt.month == month.month)
        .toList();
    final selectedDays = _daysWithWalks(monthSessions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('yyyy년 M월').format(month),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _CalendarGrid(month: month, sessions: monthSessions),
        const SizedBox(height: 18),
        Text(
          '산책한 날',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        if (selectedDays.isEmpty)
          const _EmptyState(text: '이번 달 산책 기록이 없습니다.')
        else
          for (final day in selectedDays)
            ...monthSessions
                .where((session) => _dayKey(session.startedAt) == day)
                .map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _WalkListTile(
                      session: session,
                      clock: DateFormat('HH:mm'),
                      onTap: () => onOpen(session),
                    ),
                  ),
                ),
      ],
    );
  }

  List<DateTime> _daysWithWalks(List<WalkSession> sessions) {
    return sessions.map((session) => _dayKey(session.startedAt)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
  }

  static DateTime _dayKey(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({required this.month, required this.sessions});

  final DateTime month;
  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Column(
      children: [
        const Row(
          children: [
            _WeekdayLabel('월'),
            _WeekdayLabel('화'),
            _WeekdayLabel('수'),
            _WeekdayLabel('목'),
            _WeekdayLabel('금'),
            _WeekdayLabel('토'),
            _WeekdayLabel('일'),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.82,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            final dayNumber = index - leading + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }

            final day = DateTime(month.year, month.month, dayNumber);
            final daySessions = sessions
                .where((session) => _dayKey(session.startedAt) == day)
                .toList();
            return _CalendarDay(day: day, sessions: daySessions);
          },
        ),
      ],
    );
  }

  static DateTime _dayKey(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({required this.day, required this.sessions});

  final DateTime day;
  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final hasWalks = sessions.isNotEmpty;
    final distance = _distance(sessions) / 1000;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: hasWalks ? const Color(0xFFEAF6F1) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E0D6)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          if (hasWalks)
            const SizedBox(height: 3),
          if (hasWalks)
            Text(
              '${distance.toStringAsFixed(1)}k',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    height: 1,
                  ),
            ),
        ],
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ),
    );
  }
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.sessions});

  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month);
    final weekSessions = sessions
        .where((session) => session.startedAt.isAfter(weekStart))
        .toList();
    final monthSessions = sessions
        .where((session) => session.startedAt.isAfter(monthStart))
        .toList();

    return Column(
      children: [
        _StatsCard(title: '이번 주', sessions: weekSessions),
        const SizedBox(height: 12),
        _StatsCard(title: '이번 달', sessions: monthSessions),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.sessions});

  final String title;
  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E0D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _LightMetric(value: '${sessions.length}', label: '산책')),
              Expanded(
                child: _LightMetric(
                  value: (_distance(sessions) / 1000).toStringAsFixed(1),
                  label: 'km',
                ),
              ),
              Expanded(
                child: _LightMetric(value: '${_minutes(sessions)}', label: '분'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalkListTile extends StatelessWidget {
  const _WalkListTile({
    required this.session,
    required this.clock,
    required this.onTap,
  });

  final WalkSession session;
  final DateFormat clock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 132,
              child: WalkMapPreview(session: session, height: 132),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${clock.format(session.startedAt)} | '
                      '${session.duration.inMinutes}분 | '
                      '${(session.distanceMeters / 1000).toStringAsFixed(1)} km',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.black54,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.photo_camera_outlined, size: 18),
                        const SizedBox(width: 4),
                        Text('${session.photos.length}'),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
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

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
        ),
      ],
    );
  }
}

class _LightMetric extends StatelessWidget {
  const _LightMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E0D6)),
      ),
      child: Text(text),
    );
  }
}

double _distance(List<WalkSession> sessions) {
  return sessions.fold<double>(
    0,
    (total, session) => total + session.distanceMeters,
  );
}

int _minutes(List<WalkSession> sessions) {
  return sessions.fold<int>(
    0,
    (total, session) => total + session.duration.inMinutes,
  );
}
