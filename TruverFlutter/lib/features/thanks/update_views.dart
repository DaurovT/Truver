/// Port of Truver/Sources/Features/Thanks/UpdateViews.swift
///
/// Update notices: «Вышла версия» / «Что нового» sheets, «Нужно обновить Truver», the banner of «О Truver».
library;

import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/storage.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'svg_path.dart';
import 'thanks_art.dart';
import 'thanks_chrome.dart';
import 'thanks_model.dart';

/// Update notices over the whole app (an overlay above `RootView`, see `thanks_feature.dart`).
class UpdateNoticeHost extends StatefulWidget {
  const UpdateNoticeHost({super.key});

  @override
  State<UpdateNoticeHost> createState() => _UpdateNoticeHostState();
}

class _UpdateNoticeHostState extends State<UpdateNoticeHost> {
  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    // Not while the metronome plays or another sheet is open (canvas note).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateCenter.of(app).launch(() => !app.metronome.isPlaying && app.sheet == null && !app.showOnboarding);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final updates = UpdateCenter.of(app);
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) => Stack(children: [
        Positioned.fill(
          child: ThanksSheetHost<UpdateSheetKind>(
            item: updates.sheet,
            dismiss: updates.later,
            builder: (context, kind) => UpdateSheet(kind: kind),
          ),
        ),
        if (updates.showsRequired && app.tab == AppTab.tuner && updates.info != null)
          Positioned.fill(
            child: UpdateRequiredView(
              info: updates.info!,
              // «Метроном и гриф работают и без обновления»: the caption leads there.
              openMetronome: () => app.tab = AppTab.metronome,
            ),
          ),
      ]),
    );
  }
}

/// «Вышла версия 1.2» (with «Позже» / «Обновить») or «Что нового в 1.2» («Понятно»).
class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.kind, this.atLaunch = true, this.close});
  final UpdateSheetKind kind;

  /// Shown by itself at launch (the footnote points to the full list) or opened from «О Truver».
  final bool atLaunch;
  final VoidCallback? close;

  @override
  Widget build(BuildContext context) {
    final updates = UpdateCenter.of(AppScope.read(context));
    switch (kind) {
      case UpdateSheetKind.available:
        final info = updates.info ?? UpdateCenter.demo;
        return ThanksSheetPanel(
          title: 'Вышла версия ${info.version}',
          height: 400,
          footer: [
            GraphiteCapsuleButton(title: 'Позже', height: 54, width: 120, onTap: updates.later),
            Expanded(
              child: IvoryCapsuleButton(
                title: 'Обновить',
                height: 54,
                fullWidth: true,
                onTap: () {
                  updates.closeSheet();
                  openExternal(UpdateCenter.storeUrl);
                },
              ),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwiftText('У вас ${updates.currentVersion} · обновление ${info.sizeMB} МБ · бесплатно',
                style: Typo.inter(13, TypoWeight.regular, TruverColors.textSecondary)),
            const SizedBox(height: 16),
            ReleaseNotesList(notes: info.notes),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: (16.8 - 14.53) / 2), // line-height 1.4
              child: SwiftText('«Позже» — напомним через 3 дня.', style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
            ),
          ]),
        );
      case UpdateSheetKind.whatsNew:
        final notes = updates.whatsNew;
        return ThanksSheetPanel(
          title: 'Что нового в ${notes?.$1 ?? updates.currentVersion}',
          height: 374,
          footer: [
            Expanded(child: IvoryCapsuleButton(title: 'Понятно', height: 54, fullWidth: true, onTap: close ?? updates.closeSheet)),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ReleaseNotesList(notes: notes?.$2 ?? const []),
            if (atLaunch) ...[
              const SizedBox(height: 16),
              SwiftText('Полный список — Настройки → О Truver → Что нового',
                  style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
            ],
          ]),
        );
    }
  }
}

/// Green checks with «Раздел: изменение» (15, line height 1.4), 10 pt apart.
class ReleaseNotesList extends StatelessWidget {
  const ReleaseNotesList({super.key, required this.notes});
  final List<ReleaseNote> notes;

  @override
  Widget build(BuildContext context) {
    const extra = 21 - 18.15; // CSS line-height 1.4 (21 pt) over Inter's own 18.15
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, note) in notes.indexed) ...[
        if (i > 0) const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SvgGlyph('M5 12.5l4.5 4.5L19 7.5',
              size: 18, color: TruverColors.inTune, stroke: 2, cap: StrokeCap.round, join: StrokeJoin.round),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: extra / 2),
              child: SwiftText.rich(
                TextSpan(children: [
                  TextSpan(text: note.section, style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
                  TextSpan(text: ' ${note.text}', style: Typo.inter(15, TypoWeight.regular, TruverColors.textBody)),
                ]),
                style: Typo.inter(15, TypoWeight.regular, TruverColors.textBody),
                lineSpacing: extra,
              ),
            ),
          ),
        ]),
      ],
    ]);
  }
}

/// «Нужно обновить Truver» (canvas UpdateRequired): only for a critical error; the metronome and the fretboard work.
class UpdateRequiredView extends StatelessWidget {
  const UpdateRequiredView({super.key, required this.info, required this.openMetronome});
  final UpdateInfo info;
  final VoidCallback openMetronome;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const extra = 22.5 - 18.15; // CSS line-height 1.5
    return Stack(children: [
      const Positioned.fill(child: ScreenBackground()),
      Positioned(
        left: 32,
        right: 32,
        top: top + 143, // 190 from the top of the screen
        child: Column(children: [
          const TruverAppIconArt(size: 88, radius: 19),
          const SizedBox(height: 18),
          SwiftText('Нужно обновить Truver', textAlign: TextAlign.center, style: Typo.inter(24, TypoWeight.semibold, TruverColors.textPrimary)),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: extra / 2),
            child: SwiftText(
              info.requiredReason ?? '',
              textAlign: TextAlign.center,
              lineSpacing: extra,
              style: Typo.inter(15, TypoWeight.regular, TruverColors.textSecondary),
            ),
          ),
        ]),
      ),
      Positioned(
        left: 24,
        right: 24,
        top: top + 643, // 690 from the top of the screen
        child: Column(children: [
          IvoryCapsuleButton(title: 'Обновить в Google Play', height: 56, fullWidth: true, onTap: () => openExternal(UpdateCenter.storeUrl)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: openMetronome,
            behavior: HitTestBehavior.opaque,
            child: Semantics(
              button: true,
              hint: 'Открывает метроном',
              child: SwiftText('Метроном и гриф работают и без обновления',
                  textAlign: TextAlign.center, style: Typo.inter(12, TypoWeight.regular, TruverColors.textTertiary)),
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// The banner of «О Truver»: a newer version (gold) or a failed check (neutral). Nothing when up to date.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = UpdateCenter.of(AppScope.read(context));
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final info = updates.info;
        if ((updates.status == UpdateStatus.available || updates.status == UpdateStatus.required) && info != null) {
          return _banner(
            title: 'Доступна версия ${info.version}',
            subtitle: 'У вас ${updates.currentVersion} (${updates.currentBuild}) · ${info.sizeMB} МБ',
            button: 'Обновить',
            fill: ThanksColors.goldA(0.08),
            border: ThanksColors.goldA(0.35),
            onTap: () => openExternal(UpdateCenter.storeUrl),
          );
        }
        if (updates.status == UpdateStatus.failed) {
          return _banner(
            title: 'Не удалось проверить обновления',
            subtitle: 'Нет связи с Google Play · версия ${updates.currentVersion} (${updates.currentBuild})',
            button: 'Повторить',
            fill: TruverColors.white(0.04),
            border: TruverColors.white(0.12),
            onTap: updates.check,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _banner({
    required String title,
    required String subtitle,
    required String button,
    required Color fill,
    required Color border,
    required VoidCallback onTap,
  }) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwiftText(title, style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
                const SizedBox(height: 2),
                SwiftText(subtitle, style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 12),
            IvoryCapsuleButton(title: button, onTap: onTap),
          ]),
        ),
      );
}
