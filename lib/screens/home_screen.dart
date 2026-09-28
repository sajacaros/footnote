import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/walk_models.dart';
import '../services/active_walk_service.dart';
import '../services/step_service.dart';
import '../services/sync_service.dart';
import '../services/walk_reminder_service.dart';
import '../services/walk_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_surfaces.dart';
import '../widgets/walk_map_preview.dart';
import '../widgets/walk_photo_image.dart';
import 'account_screen.dart';
import 'record_walk_screen.dart';
import 'reminder_settings_screen.dart';
import 'walk_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WalkRepository _repository = WalkRepository.instance;
  final ActiveWalkService _activeWalk = ActiveWalkService.instance;
  final WalkReminderService _reminders = WalkReminderService.instance;
  final DateFormat _dayHeader = DateFormat('M월 d일');
  final DateFormat _clock = DateFormat('HH:mm');
  List<WalkSession> _sessions = [];
  late bool _walkWasActive = _activeWalk.isActive;
  bool _loading = true;
  int _tabIndex = 0;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _activeWalk.addListener(_refresh);
    _reminders.addListener(_handleReminderStart);
    _loadSessions();
    // 앱이 꺼져 있다가 알림으로 실행된 경우 요청이 이미 들어와 있다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleReminderStart());
  }

  @override
  void dispose() {
    _activeWalk.removeListener(_refresh);
    _reminders.removeListener(_handleReminderStart);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('풋노트 산책'),
        actions: [
          IconButton(
            tooltip: '기록 알림',
            onPressed: _openReminderSettings,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          _AccountButton(onPressed: _openAccount),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadSessions,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  children: [
                    if (_activeWalk.isActive) ...[
                      _ActiveWalkBanner(onTap: _openRecorder),
                      const SizedBox(height: 14),
                    ],
                    _SummaryCard(title: '오늘', sessions: _todaySessions),
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
      bottomNavigationBar: _StartWalkBar(
        isActive: _activeWalk.isActive,
        onPressed: _openRecorder,
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
    // 만보기 앱이 늦게 쓴 걸음 수를 반영한다. 바뀌면 sync_rev가 올라 함께 올라간다.
    final refreshed = await StepService.instance.refreshRecent(sessions);
    if (refreshed != null && mounted) {
      setState(() => _sessions = refreshed);
    }
    // 기록이 바뀌었을 수 있는 시점마다 불린다. 보낼 게 없으면 네트워크를 쓰지 않는다.
    SyncService.instance.sync();
  }

  Future<void> _openDetail(WalkSession session) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => WalkDetailScreen(session: session),
      ),
    );

    if (mounted) {
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

  Future<void> _openAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
    );
  }

  Future<void> _openReminderSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ReminderSettingsScreen()),
    );
  }

  /// 기록 알림을 눌러 앱이 열리면 다른 화면을 닫고 기록 화면으로 간다.
  void _handleReminderStart() {
    if (!mounted || !_reminders.startRequested) {
      return;
    }
    _reminders.consumeStartRequest();
    Navigator.of(context).popUntil((route) => route.isFirst);
    _openRecorder();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }
    // 멈춤 알림 등으로 기록 화면 밖에서 산책이 끝나면 새 기록을 목록에 올린다.
    final active = _activeWalk.isActive;
    if (_walkWasActive && !active) {
      _loadSessions();
    }
    _walkWasActive = active;
    setState(() {});
  }

  static DateTime _dayKey(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

/// 계정 화면으로 가는 버튼. 서버로 못 보낸 기록이 있으면 점을 찍는다.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final sync = SyncService.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final showDot = sync.error != null && sync.pendingCount > 0;
        return IconButton(
          tooltip: '계정',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: showDot,
            smallSize: 8,
            backgroundColor: AppColors.routeEnd,
            child: sync.isRunning
                ? const Icon(Icons.cloud_sync_outlined)
                : const Icon(Icons.account_circle_outlined),
          ),
        );
      },
    );
  }
}

class _ActiveWalkBanner extends StatelessWidget {
  const _ActiveWalkBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeWalk = ActiveWalkService.instance;
    return Material(
      color: AppColors.brandTint,
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

class _StartWalkBar extends StatelessWidget {
  const _StartWalkBar({
    required this.isActive,
    required this.onPressed,
  });

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(
                isActive ? Icons.route_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(isActive ? '진행 중인 산책 열기' : '산책 시작'),
            ),
          ),
        ),
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
        ButtonSegment(
            value: 0, icon: Icon(Icons.timeline_rounded), label: Text('최근')),
        ButtonSegment(
            value: 1,
            icon: Icon(Icons.calendar_month_rounded),
            label: Text('기록')),
        ButtonSegment(
            value: 2, icon: Icon(Icons.bar_chart_rounded), label: Text('통계')),
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
      return const EmptyStateCard(text: '아직 기록된 산책이 없습니다.');
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
              style: Theme.of(context).textTheme.titleMedium,
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
                  style: Theme.of(context).textTheme.titleMedium,
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
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        if (selectedDays.isEmpty)
          const EmptyStateCard(text: '이번 달 산책 기록이 없습니다.')
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
    return sessions
        .map((session) => _dayKey(session.startedAt))
        .toSet()
        .toList()
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
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.9,
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
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    final distance = _distance(sessions) / 1000;
    // 산책한 날만 면을 채우고, 오늘은 테두리로만 표시한다.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasWalks ? AppColors.brandTint : null,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: AppColors.brand, width: 1.5) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  hasWalks || isToday ? FontWeight.w800 : FontWeight.w500,
              color: hasWalks ? AppColors.brandText : AppColors.ink,
              height: 1,
            ),
          ),
          if (hasWalks) ...[
            const SizedBox(height: 4),
            Text(
              '${distance.toStringAsFixed(1)}k',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.brandText,
                    fontSize: 10,
                    height: 1,
                  ),
            ),
          ],
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
                color: AppColors.inkMuted,
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
        _SummaryCard(title: '이번 주', sessions: weekSessions),
        const SizedBox(height: 12),
        _SummaryCard(title: '이번 달', sessions: monthSessions),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.sessions});

  final String title;
  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          MetricRow(
            metrics: [
              MetricValue(value: '${sessions.length}', label: '산책'),
              MetricValue(
                value: (_distance(sessions) / 1000).toStringAsFixed(1),
                label: 'km',
              ),
              MetricValue(value: '${_minutes(sessions)}', label: '분'),
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
    final featuredPhoto = session.featuredPhoto;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            SizedBox(
              height: 142,
              child: featuredPhoto == null
                  ? IgnorePointer(
                      child: WalkMapPreview(
                        session: session,
                        height: 142,
                        compactAttribution: true,
                        showPhotoMarkers: false,
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: IgnorePointer(
                            child: WalkMapPreview(
                              session: session,
                              height: 142,
                              compactAttribution: true,
                              showPhotoMarkers: false,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _FeaturedPhotoPreview(photo: featuredPhoto),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${clock.format(session.startedAt)} | '
                          '${session.duration.inMinutes}분 | '
                          '${(session.distanceMeters / 1000).toStringAsFixed(1)} km'
                          '${session.steps == null ? '' : ' | ${formatSteps(session.steps!)}걸음'}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.inkMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      const Icon(Icons.photo_camera_outlined, size: 18),
                      const SizedBox(width: 4),
                      Text('${session.photos.length}'),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded),
                    ],
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

class _FeaturedPhotoPreview extends StatelessWidget {
  const _FeaturedPhotoPreview({required this.photo});

  final WalkPhoto? photo;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo == null)
          const ColoredBox(
            color: AppColors.line,
            child: Center(
              child: Icon(Icons.photo_outlined, color: AppColors.inkSubtle),
            ),
          )
        else
          WalkPhotoImage(imageUrl: photo.imageUrl, fit: BoxFit.cover),
        if (photo != null)
          Positioned(
            left: 8,
            top: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.photoScrim,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Text(
                  '대표',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
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
