/// Port of Truver/Sources/Features/Practice/PracticeScreen.swift
///
/// «Занятия» in v1 (canvas «Занятия — журнал», PL-0): summary on top, days below; a tap on a metronome row opens
/// the metronome with that tempo.
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'play_check_charts.dart';
import 'practice_links.dart';
import 'practice_session_controller.dart';
import '../tour/coach_marks.dart';

class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.practice, app.session, app.trainer, app.playCheck]),
      builder: (context, _) => _body(context, app),
    );
  }

  Widget _body(BuildContext context, AppModel app) {
    final history = app.practice.demoHistory ?? PracticeLinks.playCheckHistory(app);
    final journal = PracticeJournalData(app.practice.entries, DateTime.now());
    final isEmpty = journal.days.isEmpty && history.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader(title: 'Занятия'),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EntryCard(
                icon: AppIcon.timer,
                title: 'Занятие',
                subtitle: isEmpty ? 'составьте план из упражнений' : _sessionSubtitle(app.session.plan),
                onTap: () => app.showSession = true,
              ),
              const SizedBox(height: 10),
              CoachAnchor(
                id: CoachAnchors.trainer,
                child: _EntryCard(
                  icon: AppIcon.fretboard,
                  title: 'Тренажёр грифа',
                  subtitle: 'Назови или сыграй ноту',
                  onTap: () => app.showTrainer = true,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: isEmpty
              ? _EmptyJournal(onStart: () => app.showSession = true)
              : _UnderInsetScroll(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20, right: 20, top: 10, bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: PracticeStat(caption: 'За неделю', value: duration(journal.weekSeconds))),
                            const SizedBox(width: 10),
                            Expanded(child: PracticeStat(caption: 'Дней подряд', value: '${journal.streak}')),
                          ],
                        ),
                        if (history.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SectionCaption(text: 'Проверка игры'),
                                PlayCheckCharts(history: history),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        ..._spaced(16, [
                          for (final group in journal.days)
                            CardGroup(
                              title: '${dayTitle(group.day, DateTime.now())} · ${duration(group.items.fold(0.0, (s, e) => s + e.seconds))}',
                              // One row per instrument and tuning in a day, the metronome by preset under it.
                              children: _rows(app, merged(group.items)),
                            ),
                          SwiftText(
                            'Считаются занятия от 30 секунд: время, пока играет метроном или тюнер слышит инструмент',
                            textAlign: TextAlign.center,
                            style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  static String _sessionSubtitle(PracticePlan plan) {
    final minutes = plan.steps.fold(0, (s, e) => s + e.minutes);
    final n = plan.steps.length;
    return '$n ${PracticeSessionController.plural(n, 'упражнение', 'упражнения', 'упражнений')} · $minutes мин';
  }

  List<Widget> _rows(AppModel app, List<JournalSession> sessions) {
    final rows = <Widget>[];
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final last = i == sessions.length - 1;
      final time = '${clock(session.first)}–${clock(session.last)}';
      rows.add(
        CardRow(
          title: session.title,
          subtitle: session.tuned ? '$time · инструмент настроен ✓' : time,
          showsDivider: !last || session.metronome.isNotEmpty,
          trailing: Text(duration(session.seconds)),
        ),
      );
      for (var j = 0; j < session.metronome.length; j++) {
        final m = session.metronome[j];
        final tempo = m.minBPM.toInt() == m.maxBPM.toInt() ? '${m.maxBPM.toInt()}' : '${m.minBPM.toInt()}–${m.maxBPM.toInt()}';
        rows.add(
          Pressable(
            scale: 1,
            onTap: () {
              // Canvas «Пресет метронома · тап — открыть»: the preset if it still exists, else just the tempo.
              final preset = PracticeLinks.presets(app).where((p) => p.name == m.name).firstOrNull;
              if (preset != null && m.name.isNotEmpty) {
                PracticeLinks.loadPreset(app, preset);
              } else {
                PracticeLinks.setBPM(app, m.maxBPM);
              }
              app.tab = AppTab.metronome;
            },
            child: CardRow(
              title: m.name.isEmpty ? 'Метроном' : m.name,
              subtitle: m.name.isEmpty ? 'тап — открыть с этим темпом' : 'Пресет метронома · тап — открыть',
              showsDivider: !last || j < session.metronome.length - 1,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tempo),
                  const SizedBox(width: 8),
                  const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
                ],
              ),
            ),
          ),
        );
      }
    }
    return rows;
  }

  // MARK: Formatting

  /// «5 мин», «2 ч 10 мин» (canvas).
  static String duration(double seconds) {
    final minutes = seconds ~/ 60;
    return minutes >= 60 ? '${minutes ~/ 60} ч ${minutes % 60} мин' : '${minutes < 1 ? 1 : minutes} мин';
  }

  /// `formatted(date: .omitted, time: .shortened)` in Russian: «16:47».
  static String clock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static const _months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  static const _weekdays = ['понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота', 'воскресенье'];

  /// «Сегодня», «Вчера», «пятница, 21 ноября» (`.dateTime.day().month(.wide).weekday(.wide)`, ru).
  static String dayTitle(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Сегодня';
    if (day == DateTime(today.year, today.month, today.day - 1)) return 'Вчера';
    return '${_weekdays[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}';
  }
}

List<Widget> _spaced(double spacing, List<Widget> children) => [
  for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: spacing), children[i]],
];

/// A day's practice on one instrument and tuning.
class JournalSession {
  JournalSession({required this.title, required this.first, required this.last});
  final String title;
  DateTime first;
  DateTime last;
  double seconds = 0;
  bool tuned = false;
  final List<({String name, double minBPM, double maxBPM})> metronome = [];
}

/// One row per instrument and tuning, newest first; the metronome by preset with its tempo range.
List<JournalSession> merged(List<PracticeEntry> items) {
  final order = <String>[];
  final byKey = <String, JournalSession>{};
  final sorted = [...items]..sort((a, b) => a.start.compareTo(b.start));
  for (final e in sorted) {
    final title = '${AppModel.shortInstrumentName(e.instrumentName)} · ${e.tuningName}';
    final end = e.start.add(Duration(microseconds: (e.seconds * 1e6).round()));
    final s = byKey[title] ?? JournalSession(title: title, first: e.start, last: end);
    if (e.start.isBefore(s.first)) s.first = e.start;
    if (end.isAfter(s.last)) s.last = end;
    s.seconds += e.seconds;
    s.tuned = s.tuned || e.tuned;
    if (e.usedMetronome) {
      final name = e.presetName;
      final low = e.minBPM > 0 ? e.minBPM : e.lastBPM;
      final i = s.metronome.indexWhere((m) => m.name == name);
      if (i >= 0) {
        final m = s.metronome[i];
        s.metronome[i] = (name: name, minBPM: m.minBPM < low ? m.minBPM : low, maxBPM: m.maxBPM > e.lastBPM ? m.maxBPM : e.lastBPM);
      } else {
        s.metronome.add((name: name, minBPM: low, maxBPM: e.lastBPM));
      }
    }
    if (!byKey.containsKey(title)) order.add(title);
    byKey[title] = s;
  }
  return [for (final k in order) byKey[k]!].reversed.toList();
}

/// The journal's days, week total and streak (PracticeScreen.swift «Data»).
class PracticeJournalData {
  PracticeJournalData(List<PracticeEntry> entries, this.now) : meaningful = entries.where((e) => e.seconds >= 30).toList() {
    final groups = <DateTime, List<PracticeEntry>>{};
    for (final e in meaningful) {
      groups.putIfAbsent(DateTime(e.start.year, e.start.month, e.start.day), () => []).add(e);
    }
    days = [for (final d in groups.keys) (day: d, items: groups[d]!)]..sort((a, b) => b.day.compareTo(a.day));
  }

  final DateTime now;
  final List<PracticeEntry> meaningful;
  late final List<({DateTime day, List<PracticeEntry> items})> days;

  double get weekSeconds {
    final from = DateTime(now.year, now.month, now.day - 7, now.hour, now.minute, now.second, now.millisecond);
    return meaningful.where((e) => !e.start.isBefore(from)).fold(0.0, (s, e) => s + e.seconds);
  }

  int get streak {
    final set = {for (final d in days) d.day};
    var day = DateTime(now.year, now.month, now.day);
    if (!set.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
    var count = 0;
    while (set.contains(day)) {
      count += 1;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return count;
  }
}

/// Canvas entry card: 64 high + the 1 pt border outside (CSS content box), radius 16, icon in a 40 pt circle
/// (white 6 %), title 15 medium, subtitle 12.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final AppIcon icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: SizedBox(
      height: 66,
      child: PracticeCard(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: ShapeBox(
                shape: SwiftShape.circle,
                fills: [SwiftFill(TruverColors.white(0.06))],
                child: Center(child: AppIconView(icon, size: 20, color: TruverColors.textBody)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SwiftText(title, style: Typo.inter(15, TypoWeight.medium, TruverColors.textPrimary)),
                  const SizedBox(height: 2),
                  SwiftText(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: Typo.caption.copyWith(color: TruverColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20), // Spacer (min 8) + spacing 12
            const AppIconView(AppIcon.chevronRight, size: 16, color: TruverColors.textTertiary),
          ],
        ),
      ),
    ),
  );
}

/// Canvas «Здесь будет ваш прогресс»: 80 pt under the cards, a 64 pt ring (+ border) with the practice icon, the
/// button opens the session plan.
class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Column(
      children: [
        SizedBox(
          width: 66,
          height: 66,
          child: ShapeBox(
            shape: SwiftShape.circle,
            strokes: [SwiftStroke(TruverColors.white(0.12), inside: true)],
            child: const Center(child: AppIconView(AppIcon.practice, size: 26, color: TruverColors.textSecondary)),
          ),
        ),
        const SizedBox(height: 10),
        SwiftText('Здесь будет ваш прогресс', style: Typo.inter(18, TypoWeight.semibold, TruverColors.textPrimary)),
        const SizedBox(height: 10),
        Container(
          width: 280,
          padding: const EdgeInsets.symmetric(vertical: 1.55), // CSS line-height 1.45: half the extra leading
          child: SwiftText(
            'Минуты занятий, дни подряд и потолок темпа появятся после первого занятия с метрономом',
            textAlign: TextAlign.center,
            lineSpacing: 3.1,
            style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary),
          ),
        ),
        const SizedBox(height: 10),
        Pressable(
          onTap: onStart,
          child: ShapeBox(
            shape: const SwiftShape.rounded(1000),
            fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: Text('Начать первое занятие', style: Typo.button.copyWith(color: TruverColors.background)),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// iOS: the scroll view runs under the tuning pill and the tab bar (`safeAreaInset`) — content passes beneath
/// them while scrolling, clipped only at the top. The shell lays the tab out above the pill, so the bottom is
/// left unclipped here.
class _UnderInsetScroll extends StatelessWidget {
  const _UnderInsetScroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    clipper: const _TopClipper(),
    child: SingleChildScrollView(clipBehavior: Clip.none, child: child),
  );
}

class _TopClipper extends CustomClipper<Rect> {
  const _TopClipper();
  @override
  Rect getClip(Size size) => Rect.fromLTRB(-100, 0, size.width + 100, size.height + 1000);
  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
