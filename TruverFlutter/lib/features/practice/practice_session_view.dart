/// Port of Truver/Sources/Features/Practice/PracticeSessionView.swift
///
/// PL-2 «Занятие» (corrected canvas «Занятие — план» / «Занятие — идёт»): the plan editor with the total in the
/// header, the running exercise with a progress ring, the metronome's beats, tempo / meter / play-check chips, what
/// comes next and a big pause button between «Закончить» and «Дальше»; the summary (PL-3 per exercise).
library;

import 'dart:math' as math;

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
import '../fretboard/neck_portrait.dart';
import 'practice_links.dart';
import 'practice_menu.dart';
import 'practice_session_controller.dart';

class PracticeSessionView extends StatefulWidget {
  const PracticeSessionView({super.key});

  static String clock(double s) {
    final v = s.round() < 0 ? 0 : s.round();
    return '${v ~/ 60}:${(v % 60).toString().padLeft(2, '0')}';
  }

  @override
  State<PracticeSessionView> createState() => _PracticeSessionViewState();
}

class _PracticeSessionViewState extends State<PracticeSessionView> {
  static bool _debugApplied = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Launch arguments of the session boards, once: `-sessionRunning`.
    final app = AppScope.read(context);
    if (!_debugApplied && app.args.has('-sessionRunning') && app.session.phase == SessionPhase.idle) {
      _debugApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => app.session.debugRunning());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final session = app.session;
    return ListenableBuilder(
      listenable: Listenable.merge([session, app.playCheck, app.metronome, app.fretboard]),
      builder: (context, _) {
        final padding = MediaQuery.paddingOf(context);
        final idleOrRunning = session.phase == SessionPhase.idle || session.isRunning;
        void close() {
          session.stop();
          if (session.phase == SessionPhase.done) session.reset();
          app.showSession = false;
        }

        return Stack(
          children: [
            const Positioned.fill(child: ScreenBackground()),
            Padding(
              padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PracticePageHeader(
                      icon: idleOrRunning ? AppIcon.chevronLeft : AppIcon.close,
                      label: idleOrRunning ? 'Назад' : 'Закрыть',
                      title: 'Занятие',
                      subtitle: _subtitle(session),
                      onTap: close,
                    ),
                    Expanded(
                      child: switch (session.phase) {
                        SessionPhase.idle => _Editor(app: app),
                        SessionPhase.playing || SessionPhase.pause => _Running(app: app),
                        SessionPhase.done => _Summary(app: app),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _subtitle(PracticeSessionController session) {
    final n = session.plan.steps.length;
    return switch (session.phase) {
      SessionPhase.idle =>
        'всего ${session.plan.steps.fold(0, (s, e) => s + e.minutes)} мин · $n ${PracticeSessionController.plural(n, 'упражнение', 'упражнения', 'упражнений')}',
      SessionPhase.playing => '${session.stepIndex + 1} из $n · ${session.currentStep == null ? '' : session.title(session.currentStep!)}',
      SessionPhase.pause => 'пауза · дальше ${session.stepIndex + 1} из $n',
      SessionPhase.done => 'занятие закончено',
    };
  }
}

/// Header of the practice pages (canvas `left 20, top 50`, a 44 pt row): a 40 pt round button, 12 apart, the title
/// 17 medium over a 12 pt subtitle (1 apart), an optional trailing button.
class PracticePageHeader extends StatelessWidget {
  const PracticePageHeader({
    super.key,
    required this.icon,
    required this.label,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final AppIcon icon;
  final String label;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 20, right: 20, top: 3),
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          RoundIconButton(icon: icon, iconSize: icon == AppIcon.close ? 16 : 18, label: label, onTap: onTap),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: SwiftText(title, maxLines: 1, softWrap: false, style: Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary)),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  SwiftText(
                    subtitle!,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Typo.monospacedDigit(Typo.caption.copyWith(color: TruverColors.textTertiary)),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

/// A canvas card row with its CSS box: `min-height` + the 1 pt bottom border (padding 0 16, gap 10, title 15,
/// subtitle 12 two points under it, trailing 14 secondary).
class PracticeRow extends StatelessWidget {
  const PracticeRow({super.key, required this.title, this.subtitle, this.minHeight = 58, this.divider = true, this.trailing});

  final String title;
  final String? subtitle;
  final double minHeight;
  final bool divider;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: divider ? rowDivider : const BoxDecoration(),
    child: Padding(
      padding: EdgeInsets.only(bottom: divider ? 1 : 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwiftText(title, style: Typo.row.copyWith(color: TruverColors.textBody)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      SwiftText(subtitle!, style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 18), // Spacer(minLength: 8) + spacing 10
                DefaultTextStyle(style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary), child: trailing!),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

// MARK: Plan (PL-1, PL-2)

class _Editor extends StatelessWidget {
  const _Editor({required this.app});
  final AppModel app;

  PracticeSessionController get session => app.session;

  @override
  Widget build(BuildContext context) {
    final plan = session.plan;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 18, bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < plan.steps.length; i++) ...[
                  _StepCard(app: app, index: i, step: plan.steps[i]),
                  const SizedBox(height: 12),
                ],
                Pressable(
                  onTap: () => session.updatePlan((p) => p.steps.add(p.steps.isEmpty ? PracticeStep() : p.steps.last.copy(id: newUuid()))),
                  child: const Chip(text: '+ Упражнение'),
                ),
                const SizedBox(height: 12),
                const SectionCaption(text: 'Между упражнениями'),
                Card(
                  children: [
                    PracticeRow(
                      title: 'Пауза',
                      subtitle: 'между упражнениями',
                      trailing: ValueStepper(
                        value: '${plan.pauseSeconds} с',
                        valueMaxWidth: null,
                        canDecrement: plan.pauseSeconds > 0,
                        canIncrement: plan.pauseSeconds < 300,
                        decrement: () => session.updatePlan((p) => p.pauseSeconds = (p.pauseSeconds - 10).clamp(0, 300)),
                        increment: () => session.updatePlan((p) => p.pauseSeconds = (p.pauseSeconds + 10).clamp(0, 300)),
                      ),
                    ),
                    PracticeRow(
                      title: 'Голосовые подсказки',
                      subtitle: 'что дальше и сколько осталось',
                      trailing: ToggleSwitch(
                        isOn: plan.voice,
                        label: 'Голосовые подсказки',
                        onChanged: (v) => session.updatePlan((p) => p.voice = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: SheetButton(title: 'Начать занятие', icon: AppIcon.play, height: 52, onTap: session.start),
        ),
      ],
    );
  }
}

/// Canvas exercise card: a 52 pt head (number, title, tempo · meter, chevron — the preset menu), then «Минут» (56),
/// «Проверка игры» and «На грифе» (58), each row with its divider.
class _StepCard extends StatelessWidget {
  const _StepCard({required this.app, required this.index, required this.step});
  final AppModel app;
  final int index;
  final PracticeStep step;

  PracticeSessionController get session => app.session;

  void _update(void Function(PracticeStep s) change) => session.updatePlan((p) {
    if (index < p.steps.length) change(p.steps[index]);
  });

  @override
  Widget build(BuildContext context) {
    final presets = PracticeLinks.presets(app);
    final canDelete = session.plan.steps.length > 1;
    return Card(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: rowDivider,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 12, bottom: 1),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (anchor) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showPracticeMenu(anchor, [
                          [
                            MenuItem('Текущие настройки', () => _update((s) => s.presetId = null)),
                            for (final p in presets)
                              MenuItem('${p.name} · ${((p.settings['bpm'] as num?) ?? 0).toInt()}', () => _update((s) => s.presetId = p.id)),
                          ],
                        ]),
                        child: Row(
                          children: [
                            SwiftText('${index + 1}', style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary)),
                            const SizedBox(width: 10),
                            Flexible(
                              child: SwiftText(
                                session.title(step),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: Typo.inter(16, TypoWeight.medium, TruverColors.textPrimary),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 14),
                            SwiftText(session.tempoText(step), maxLines: 1, softWrap: false, style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)),
                            const SizedBox(width: 10),
                            const AppIconView(AppIcon.chevronDown, size: 14, color: TruverColors.textTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (canDelete) ...[
                    const SizedBox(width: 10),
                    RoundIconButton(
                      icon: AppIcon.trash,
                      size: 32,
                      iconSize: 13,
                      label: 'Удалить упражнение',
                      onTap: () => session.updatePlan((p) {
                        if (index < p.steps.length) p.steps.removeAt(index);
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        PracticeRow(
          title: 'Минут',
          minHeight: 56,
          trailing: ValueStepper(
            value: '${step.minutes}',
            canDecrement: step.minutes > 1,
            canIncrement: step.minutes < 60,
            decrement: () => _update((s) => s.minutes -= 1),
            increment: () => _update((s) => s.minutes += 1),
          ),
        ),
        PracticeRow(
          title: 'Проверка игры',
          subtitle: 'темп растёт по результату',
          trailing: ToggleSwitch(
            isOn: step.check || step.onNeck,
            label: 'Проверка игры',
            onChanged: (v) => _update((s) {
              s.check = v;
              if (!v) s.onNeck = false;
            }),
          ),
        ),
        PracticeRow(
          title: 'На грифе',
          subtitle: 'ноты позиции проверяются',
          trailing: ToggleSwitch(
            isOn: step.onNeck,
            label: 'На грифе',
            onChanged: (v) => _update((s) {
              s.onNeck = v;
              if (v) s.check = true;
            }),
          ),
        ),
      ],
    );
  }
}

// MARK: Running

class _Running extends StatelessWidget {
  const _Running({required this.app});
  final AppModel app;

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    final step = session.currentStep;
    final playing = session.phase == SessionPhase.playing;
    final meter = PracticeLinks.meter(app);
    final next = session.phase == SessionPhase.pause ? session.currentStep : session.nextStep;
    final nextText = next == null ? 'конец занятия' : '${session.title(next)} · ${next.minutes} мин';
    return Column(
      children: [
        const SizedBox(height: 46),
        _Ring(session: session),
        if (playing && step != null && step.onNeck)
          // FB-14 inside the session: the position with the current note large and wrong notes red.
          Padding(
            padding: const EdgeInsets.only(left: 22, right: 22, top: 12),
            child: SizedBox(
              height: 110,
              child: NeckPortrait(
                courses: app.courseCount,
                lo: app.fretboard.visibleFrets.$1,
                hi: app.fretboard.visibleFrets.$2,
                cells: app.fretboard.cells(),
                leftHanded: PracticeLinks.leftHanded(app),
                fan: app.fretboard.data?.fan,
              ),
            ),
          )
        else
          Padding(padding: const EdgeInsets.only(top: 32), child: _Beats(app: app, meter: meter)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Chip(text: '${PracticeLinks.displayBPM(app).round()} BPM'),
            const SizedBox(width: 8),
            Chip(text: '${meter['numerator']}/${meter['denominator']}'),
            if (playing && step != null && (step.check || step.onNeck)) ...[
              const SizedBox(width: 8),
              _CheckChip(share: session.demoShare ?? PracticeLinks.playCheckShare(app)),
            ],
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, top: 34),
          child: Card(
            children: [
              PracticeRow(title: 'Дальше', minHeight: 52, trailing: Text(nextText, maxLines: 1, softWrap: false)),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 34),
          child: Row(
            children: [
              _SideButton(title: 'Закончить', onTap: session.stop),
              const Spacer(),
              Semantics(
                button: true,
                label: session.isPaused ? 'Продолжить' : 'Пауза',
                child: Pressable(
                  onTap: session.togglePause,
                  child: ShapeBox(
                    shape: SwiftShape.circle,
                    fills: const [SwiftFill.gradient(TruverGradients.primaryFill)],
                    shadows: const [SwiftShadow(Color(0x99000000), 9, y: 8)],
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: Center(
                        child: AppIconView(session.isPaused ? AppIcon.play : AppIcon.pause, size: 28, color: TruverColors.background),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _SideButton(title: 'Дальше', onTap: session.skip),
            ],
          ),
        ),
      ],
    );
  }
}

/// Canvas ring: 280 pt, radius 120, 8 pt stroke — white 8 % track, ivory remaining part from the top, clockwise.
class _Ring extends StatelessWidget {
  const _Ring({required this.session});
  final PracticeSessionController session;

  @override
  Widget build(BuildContext context) {
    final length = session.phaseLength;
    final fraction = length > 0 ? (session.remaining / length).clamp(0.0, 1.0) : 0.0;
    final clock = PracticeSessionView.clock;
    return Semantics(
      label: 'Осталось ${clock(session.remaining)} из ${clock(length)}',
      excludeSemantics: true,
      child: SizedBox(
        width: 280,
        height: 280,
        child: CustomPaint(
          painter: _RingPainter(fraction),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwiftText(
                  clock(session.remaining),
                  style: Typo.monospacedDigit(Typo.inter(64, TypoWeight.light, TruverColors.textPrimary)).copyWith(letterSpacing: -1.28),
                ),
                const SizedBox(height: 4),
                SwiftText(
                  session.phase == SessionPhase.pause ? 'пауза из ${clock(length)}' : 'осталось из ${clock(length)}',
                  style: Typo.inter(13, TypoWeight.regular, TruverColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: 120);
    canvas.drawCircle(
      c,
      120,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = TruverColors.white(0.08),
    );
    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = TruverColors.beat,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

/// Canvas beats: 34 pt bars, 5 apart, accented 28 high (ivory 38 %), others 18 (white 16 %); the current beat lit.
class _Beats extends StatelessWidget {
  const _Beats({required this.app, required this.meter});
  final AppModel app;
  final Map<String, dynamic> meter;

  @override
  Widget build(BuildContext context) {
    final n = (meter['numerator'] as num?)?.toInt() ?? 4;
    final accents = [for (final a in (meter['accents'] as List? ?? const [])) (a as num).toInt()];
    final current = PracticeLinks.metronomeIsPlaying(app) ? PracticeLinks.currentBeat(app) : null;
    return Semantics(
      label: 'Доли $n/${meter['denominator']}',
      excludeSemantics: true,
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              _bar(i < accents.length ? accents[i] : 2, current == i),
            ],
          ],
        ),
      ),
    );
  }

  /// Accent levels of the core: 0 off, 1 soft, 2 normal, 3 strong.
  Widget _bar(int accent, bool lit) {
    final height = accent == 3 ? 28.0 : (accent == 0 ? 6.0 : 18.0);
    return SizedBox(
      width: 34,
      height: height,
      child: ShapeBox(
        shape: const SwiftShape.rounded(3),
        fills: [SwiftFill(accent == 3 ? TruverColors.beat.withValues(alpha: 0.38) : TruverColors.white(0.16))],
        child: lit
            ? ShapeBox(
                shape: const SwiftShape.rounded(3),
                fills: const [SwiftFill(TruverColors.beat)],
                shadows: [SwiftShadow(TruverColors.beat.withValues(alpha: 0.9), 6)],
              )
            : null,
      ),
    );
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({this.share});
  final double? share;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ShapeBox(
      shape: const SwiftShape.rounded(16),
      fills: const [SwiftFill(TruverColors.fill)],
      strokes: const [SwiftStroke(TruverColors.hairlineStrong, inside: true)],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconView(AppIcon.mic, size: 14, color: TruverColors.inTune),
            const SizedBox(width: 6),
            Text(
              share == null ? 'Проверка' : 'Проверка · ${(share! * 100).round()} %',
              maxLines: 1,
              style: Typo.chip.copyWith(color: TruverColors.textBody),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Canvas side buttons: 120 × 50 capsules (card fill, hairline), 15 medium.
class _SideButton extends StatelessWidget {
  const _SideButton({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: SizedBox(
      width: 120,
      height: 50,
      child: ShapeBox(
        shape: const SwiftShape.rounded(1000),
        fills: const [SwiftFill.gradient(TruverGradients.cardFill)],
        strokes: const [SwiftStroke(TruverColors.hairline, inside: true)],
        child: Center(child: Text(title, style: Typo.inter(15, TypoWeight.medium, TruverColors.textBody))),
      ),
    ),
  );
}

// MARK: Summary (PL-3)

class _Summary extends StatelessWidget {
  const _Summary({required this.app});
  final AppModel app;

  static String? _subtitle(StepResult r) {
    final a = r.attempt;
    if (a == null) return null;
    final tempo = a.startBPM == a.endBPM ? '${a.endBPM.toInt()}' : '${a.startBPM.toInt()}→${a.endBPM.toInt()}';
    return '${(a.accurateShare * 100).round()} % · темп $tempo · разброс ${a.spread.round()} мс';
  }

  String? get _weakest {
    final attempts = [
      for (final r in app.session.results)
        if (r.attempt != null) (r.title, r.attempt!),
    ];
    if (attempts.isEmpty) return null;
    final worst = attempts.reduce((a, b) => b.$2.accurateShare < a.$2.accurateShare ? b : a);
    var text = '«${worst.$1}» — ${(worst.$2.accurateShare * 100).round()} %';
    final beat = worst.$2.weakestBeat, d = worst.$2.weakestBeatDeviation;
    if (beat != null && d != null) text += ', доля ${beat + 1}: ${d < 0 ? 'спешите' : 'тянете'} ${d.abs().round()} мс';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final session = app.session;
    final results = session.results;
    final total = results.fold(0.0, (s, r) => s + r.seconds);
    final weak = _weakest;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwiftText('Занятие · ${PracticeSessionView.clock(total)}', style: Typo.inter(24, TypoWeight.semibold, TruverColors.textPrimary)),
          const SizedBox(height: 12),
          Card(
            children: [
              for (var i = 0; i < results.length; i++)
                CardRow(
                  title: results[i].title,
                  subtitle: _subtitle(results[i]),
                  showsDivider: i < results.length - 1,
                  trailing: Text(
                    PracticeSessionView.clock(results[i].seconds),
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
            ],
          ),
          if (weak != null) ...[
            const SizedBox(height: 12),
            SwiftText('Самое слабое место: $weak', style: Typo.inter(14, TypoWeight.regular, TruverColors.textSecondary)),
          ],
          const SizedBox(height: 12 + 8),
          SheetButton(
            title: 'Готово',
            height: 52,
            onTap: () {
              session.reset();
              app.showSession = false;
            },
          ),
        ],
      ),
    );
  }
}
