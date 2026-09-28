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
                  // 아래 떠 있는 시작 버튼에 마지막 카드가 가리지 않게 띄운다.
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                  children: [
                    if (_activeWalk.isActive) ...[
                      _ActiveWalkBanner(onTap: _openRecorder),
                      const SizedBox(height: 14),
                    ],
                    _GreetingCard(
                      today: _todaySessions,
                      sessions: _sessions,
                    ),
                    const SizedBox(height: 20),
                    _HomeTabs(
                      selectedIndex: _tabIndex,
                      onChanged: (index) => setState(() => _tabIndex = index),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.03),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_tabIndex),
                        child: _tabView(),
                      ),
                    ),
                  ],
                ),
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _StartWalkButton(
        isActive: _activeWalk.isActive,
        onPressed: _openRecorder,
      ),
    );
  }

  Widget _tabView() {
    if (_tabIndex == 0) {
      return _RecentTimeline(
        sessions: _sessions,
        dayHeader: _dayHeader,
        clock: _clock,
        onOpen: _openDetail,
      );
    }
    if (_tabIndex == 1) {
      return _HistoryCalendar(
        month: _visibleMonth,
        sessions: _sessions,
        onPrevious: () => setState(() {
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
        }),
        onNext: () => setState(() {
          _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
        }),
        onOpen: _openDetail,
      );
    }
    return _StatsView(sessions: _sessions);
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
      color: AppColors.pawTint,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '산책 기록 중 · '
                  '${(activeWalk.distanceMeters / 1000).toStringAsFixed(2)} km · '
                  '사진 ${activeWalk.photos.length}장',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
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

/// 기록 중임을 알리는, 숨 쉬듯 커졌다 작아지는 점.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + 12 * t,
                height: 10 + 12 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.paw.withValues(alpha: 0.5 * (1 - t)),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.pawStrong,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 오늘 요약. 산책 전에는 0 대신 한마디와 이번 주 발자국을 보여 준다.
class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.today, required this.sessions});

  final List<WalkSession> today;
  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final walkedToday = today.isNotEmpty;
    final streak = _streakDays(sessions);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandLight, AppColors.brandStrong],
        ),
        boxShadow: kCardShadow,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 배경에 크게 깔리는 발바닥.
          Positioned(
            right: -18,
            top: -14,
            child: Transform.rotate(
              angle: 0.35,
              child: Icon(
                Icons.pets,
                size: 120,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      walkedToday ? '오늘 ${today.length}번 걸었어요' : '오늘도 걸어볼까요?',
                      style: const TextStyle(
                        fontFamily: kDisplayFont,
                        fontSize: 26,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (streak >= 2) _StreakChip(days: streak),
                ],
              ),
              const SizedBox(height: 6),
              if (walkedToday)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: MetricRow(
                    metrics: [
                      MetricValue(
                        value: (_distance(today) / 1000).toStringAsFixed(1),
                        label: 'km',
                        onDark: true,
                      ),
                      MetricValue(
                        value: '${_minutes(today)}',
                        label: '분',
                        onDark: true,
                      ),
                      MetricValue(
                        value: _steps(today),
                        label: '걸음',
                        onDark: true,
                      ),
                    ],
                  ),
                )
              else
                Text(
                  _sinceLastWalk(sessions),
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              const SizedBox(height: 18),
              _WeekPaws(sessions: sessions),
            ],
          ),
        ],
      ),
    );
  }

  static String _steps(List<WalkSession> sessions) {
    final known = sessions.where((s) => s.steps != null).toList();
    if (known.isEmpty) {
      return '-';
    }
    return formatSteps(known.fold<int>(0, (sum, s) => sum + s.steps!));
  }

  static String _sinceLastWalk(List<WalkSession> sessions) {
    if (sessions.isEmpty) {
      return '첫 산책을 기록해 보세요.';
    }
    final last =
        sessions.map((s) => s.startedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    if (days <= 1) {
      return '어제도 걸었어요. 오늘도 이어가 볼까요?';
    }
    return '마지막 산책은 $days일 전이에요.';
  }

  /// 오늘(또는 어제)까지 하루도 빠지지 않고 걸은 날 수.
  static int _streakDays(List<WalkSession> sessions) {
    final days = sessions
        .map((s) =>
            DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day))
        .toSet();
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(day)) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (days.contains(day)) {
      count += 1;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.paw,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '연속 $days일',
        style: const TextStyle(
          fontFamily: kDisplayFont,
          color: Colors.white,
          fontSize: 14,
        ),
      ),
    );
  }
}

/// 이번 주 월~일. 걸은 날은 발바닥 도장이 찍힌다.
class _WeekPaws extends StatelessWidget {
  const _WeekPaws({required this.sessions});

  final List<WalkSession> sessions;

  static const _labels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final walked = sessions
        .map((s) =>
            DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day))
        .toSet();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i += 1)
          _dayMark(
            _labels[i],
            walked: walked
                .contains(DateTime(monday.year, monday.month, monday.day + i)),
            isToday: i == today.weekday - 1,
            isFuture: i > today.weekday - 1,
          ),
      ],
    );
  }

  Widget _dayMark(
    String label, {
    required bool walked,
    required bool isToday,
    required bool isFuture,
  }) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: walked
                ? Colors.white
                : Colors.white.withValues(alpha: isFuture ? 0.06 : 0.14),
            border: isToday && !walked
                ? Border.all(color: Colors.white, width: 1.5)
                : null,
          ),
          child: walked
              ? const Icon(Icons.pets, size: 18, color: AppColors.pawStrong)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: isToday ? 1 : 0.7),
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// 화면 아래에 떠 있는 산책 시작 버튼.
class _StartWalkButton extends StatelessWidget {
  const _StartWalkButton({
    required this.isActive,
    required this.onPressed,
  });

  final bool isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x551F8A70),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(200, 60),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          backgroundColor: isActive ? AppColors.pawStrong : AppColors.brand,
          textStyle: const TextStyle(fontFamily: kDisplayFont, fontSize: 20),
        ),
        onPressed: onPressed,
        icon: Icon(isActive ? Icons.route_rounded : Icons.pets, size: 24),
        label: Text(isActive ? '산책 이어서 보기' : '산책 시작'),
      ),
    );
  }
}

/// 알약 모양 탭. 선택된 탭 뒤로 흰 알약이 미끄러진다.
class _HomeTabs extends StatelessWidget {
  const _HomeTabs({required this.selectedIndex, required this.onChanged});

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  static const _tabs = [
    (Icons.auto_awesome_rounded, '최근'),
    (Icons.calendar_month_rounded, '기록'),
    (Icons.insights_rounded, '통계'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.brandTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / _tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                left: width * selectedIndex,
                top: 0,
                bottom: 0,
                width: width,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: kCardShadow,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _tabs.length; i += 1)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _tabs[i].$1,
                                size: 18,
                                color: i == selectedIndex
                                    ? AppColors.brand
                                    : AppColors.inkMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _tabs[i].$2,
                                style: TextStyle(
                                  fontFamily: kDisplayFont,
                                  fontSize: 16,
                                  color: i == selectedIndex
                                      ? AppColors.ink
                                      : AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
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
    // 산책한 날은 분홍 발바닥 도장, 오늘은 초록 테두리.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hasWalks ? AppColors.pawTint : null,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: isToday ? Border.all(color: AppColors.brand, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (hasWalks)
            const Icon(Icons.pets, size: 16, color: AppColors.pawStrong)
          else
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: AppColors.ink,
                height: 1,
              ),
            ),
          if (hasWalks) ...[
            const SizedBox(height: 3),
            Text(
              '${day.day}',
              style: const TextStyle(
                fontFamily: kDisplayFont,
                fontSize: 13,
                color: AppColors.pawStrong,
                height: 1,
              ),
            ),
            Text(
              '${distance.toStringAsFixed(1)}k',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 9,
                height: 1.2,
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
        _WeeklyBars(sessions: sessions),
        const SizedBox(height: 14),
        _SummaryCard(title: '이번 주', sessions: weekSessions),
        const SizedBox(height: 14),
        _SummaryCard(title: '이번 달', sessions: monthSessions),
      ],
    );
  }
}

const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// 최근 7일 거리 막대그래프. 막대가 아래에서 자라 오른다.
class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.sessions});

  final List<WalkSession> sessions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 6; i >= 0; i -= 1)
        DateTime(today.year, today.month, today.day - i),
    ];
    final km = [
      for (final day in days)
        _distance(sessions
                .where((s) =>
                    s.startedAt.year == day.year &&
                    s.startedAt.month == day.month &&
                    s.startedAt.day == day.day)
                .toList()) /
            1000,
    ];
    final maxKm = km.fold<double>(0, (a, b) => a > b ? a : b);
    final total = km.fold<double>(0, (a, b) => a + b);

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '최근 7일',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${total.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontFamily: kDisplayFont,
                  fontSize: 20,
                  color: AppColors.brand,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i += 1)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: maxKm == 0 ? 0 : km[i] / maxKm,
                            ),
                            duration: Duration(milliseconds: 500 + i * 60),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, _) => Container(
                              height: 8 + 82 * t,
                              decoration: BoxDecoration(
                                color: km[i] == 0
                                    ? AppColors.line
                                    : i == 6
                                        ? AppColors.paw
                                        : AppColors.brandLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            i == 6 ? '오늘' : _weekdayLabels[days[i].weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  i == 6 ? AppColors.ink : AppColors.inkMuted,
                              fontWeight:
                                  i == 6 ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
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
              height: 150,
              child: featuredPhoto == null
                  ? IgnorePointer(
                      child: WalkMapPreview(
                        session: session,
                        height: 150,
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
                              height: 150,
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
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
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
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MetaPill(
                              icon: Icons.schedule_rounded,
                              text: '${clock.format(session.startedAt)} · '
                                  '${session.duration.inMinutes}분',
                            ),
                            _MetaPill(
                              icon: Icons.route_rounded,
                              text:
                                  '${(session.distanceMeters / 1000).toStringAsFixed(1)} km',
                            ),
                            if (session.steps != null)
                              _MetaPill(
                                icon: Icons.pets,
                                text: '${formatSteps(session.steps!)}걸음',
                                accent: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (session.photos.isNotEmpty) ...[
                    const Icon(
                      Icons.photo_camera_rounded,
                      size: 18,
                      color: AppColors.inkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${session.photos.length}',
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                  ],
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.inkSubtle,
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.text,
    this.accent = false,
  });

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AppColors.pawStrong : AppColors.brandText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? AppColors.pawTint : AppColors.brandTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
                color: AppColors.paw,
                borderRadius: BorderRadius.circular(AppRadius.sm),
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
