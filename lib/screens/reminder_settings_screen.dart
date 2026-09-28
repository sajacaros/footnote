import 'package:flutter/material.dart';

import '../models/walk_reminder.dart';
import '../services/walk_reminder_service.dart';
import '../services/walk_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_surfaces.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key});

  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen>
    with WidgetsBindingObserver {
  final WalkRepository _repository = WalkRepository.instance;
  final WalkReminderService _reminders = WalkReminderService.instance;
  List<WalkReminder> _items = [];
  bool _loading = true;
  bool _notificationsEnabled = true;
  bool _exactAlarmsAllowed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 시스템 설정에서 권한을 바꾸고 돌아온 경우.
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions(reschedule: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('기록 알림')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    '정해 둔 시간에 알림을 보내요. 알림의 "기록 시작"을 누르면 바로 경로 기록이 시작됩니다.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 16),
                  if (!_notificationsEnabled) ...[
                    _PermissionNotice(
                      text: '알림 권한이 꺼져 있어 알림이 오지 않습니다.',
                      actionLabel: '알림 허용',
                      onPressed: () async {
                        await _reminders.requestNotificationPermission();
                        await _refreshPermissions();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_exactAlarmsAllowed) ...[
                    _PermissionNotice(
                      text: '"알람 및 리마인더" 권한이 없으면 알림이 몇 분 늦게 올 수 있습니다.',
                      actionLabel: '설정 열기',
                      onPressed: _reminders.requestExactAlarmPermission,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_items.isEmpty)
                    const EmptyStateCard(text: '아직 설정한 알림이 없습니다.')
                  else
                    for (final item in _items) ...[
                      _ReminderTile(
                        reminder: item,
                        onTap: () => _edit(item),
                        onToggle: (enabled) =>
                            _save(item.copyWith(enabled: enabled)),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () => _edit(null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('알림 추가'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _load() async {
    final items = await _repository.loadReminders();
    await _refreshPermissions();
    if (!mounted) {
      return;
    }
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _refreshPermissions({bool reschedule = false}) async {
    final notifications = await _reminders.notificationsEnabled();
    final exact = await _reminders.exactAlarmsAllowed();
    if (reschedule && exact != _exactAlarmsAllowed) {
      // 정확한 알람 허용 여부에 따라 예약 방식이 달라진다.
      await _reminders.reschedule();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationsEnabled = notifications;
      _exactAlarmsAllowed = exact;
    });
  }

  Future<void> _edit(WalkReminder? reminder) async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderEditor(initial: reminder),
    );
    if (result == null) {
      return;
    }
    if (result.deleted) {
      await _repository.deleteReminder(reminder!.id!);
      await _reminders.reschedule();
      await _load();
      return;
    }
    await _save(result.reminder!);
    // 처음 알림을 켤 때 권한을 함께 요청한다.
    if (!_notificationsEnabled) {
      await _reminders.requestNotificationPermission();
      await _refreshPermissions();
    }
  }

  Future<void> _save(WalkReminder reminder) async {
    await _repository.saveReminder(reminder);
    await _reminders.reschedule();
    await _load();
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onTap,
    required this.onToggle,
  });

  final WalkReminder reminder;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = reminder.enabled ? AppColors.ink : AppColors.inkSubtle;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.timeText,
                      style: textTheme.headlineMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        reminder.weekdaysText,
                        if (reminder.label.isNotEmpty) reminder.label,
                      ].join(' · '),
                      style: textTheme.bodyMedium?.copyWith(
                        color: reminder.enabled
                            ? AppColors.inkMuted
                            : AppColors.inkSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: reminder.enabled, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  const _PermissionNotice({
    required this.text,
    required this.actionLabel,
    required this.onPressed,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.warningTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          TextButton(onPressed: onPressed, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _EditResult {
  const _EditResult.saved(WalkReminder this.reminder) : deleted = false;
  const _EditResult.deleted()
      : reminder = null,
        deleted = true;

  final WalkReminder? reminder;
  final bool deleted;
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({this.initial});

  final WalkReminder? initial;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late TimeOfDay _time;
  late Set<int> _weekdays;
  late final TextEditingController _label;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _time = initial == null
        ? const TimeOfDay(hour: 17, minute: 0)
        : TimeOfDay(hour: initial.hour, minute: initial.minute);
    _weekdays = {...?initial?.weekdays};
    if (initial == null) {
      _weekdays.addAll([1, 2, 3, 4, 5, 6, 7]);
    }
    _label = TextEditingController(text: initial?.label ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_isNew ? '알림 추가' : '알림 수정', style: textTheme.titleLarge),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '${_time.hour.toString().padLeft(2, '0')}:'
                '${_time.minute.toString().padLeft(2, '0')}',
                textAlign: TextAlign.center,
                style: textTheme.displaySmall?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('반복', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 1; day <= 7; day += 1)
                _WeekdayToggle(
                  label: WalkReminder.weekdayLabels[day - 1],
                  selected: _weekdays.contains(day),
                  onTap: () => setState(() {
                    if (!_weekdays.remove(day)) {
                      _weekdays.add(day);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _PresetChip(
                label: '매일',
                onTap: () => setState(
                  () => _weekdays = {1, 2, 3, 4, 5, 6, 7},
                ),
              ),
              _PresetChip(
                label: '평일',
                onTap: () => setState(() => _weekdays = {1, 2, 3, 4, 5}),
              ),
              _PresetChip(
                label: '주말',
                onTap: () => setState(() => _weekdays = {6, 7}),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: '이름 (선택)',
              hintText: '예: 저녁 산책, 점심 산책',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _weekdays.isEmpty ? null : _save,
            child: Text(_weekdays.isEmpty ? '요일을 하나 이상 고르세요' : '저장'),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () =>
                  Navigator.of(context).pop(const _EditResult.deleted()),
              child: const Text('이 알림 삭제'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
    }
  }

  void _save() {
    final base = widget.initial ??
        const WalkReminder(label: '', hour: 0, minute: 0, weekdays: {});
    Navigator.of(context).pop(
      _EditResult.saved(
        base.copyWith(
          label: _label.text.trim(),
          hour: _time.hour,
          minute: _time.minute,
          weekdays: _weekdays,
          enabled: true,
        ),
      ),
    );
  }
}

class _WeekdayToggle extends StatelessWidget {
  const _WeekdayToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand : AppColors.surface,
      shape: CircleBorder(
        side: BorderSide(
          color: selected ? AppColors.brand : AppColors.line,
          width: 1.5,
        ),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
