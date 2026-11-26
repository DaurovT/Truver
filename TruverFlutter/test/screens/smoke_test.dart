import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:truver/core/truver_core.dart';
import 'package:truver/design/theme.dart';
import 'package:truver/design/typo.dart';

import '../support/screen_harness.dart';

void main() {
  testWidgets('harness: fonts, geometry and the Swift core', (tester) async {
    final core = TruverCore.instance;
    expect(core, isNotNull, reason: TruverCore.loadError);
    final templates = core!.call('theory.templates') as List;
    expect(templates.length, greaterThan(20));
    final file = await ScreenHarness.capture(
      tester,
      'smoke',
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [
          const Positioned.fill(child: ScreenBackground()),
          Positioned(
            left: 20,
            top: 60,
            child: Text('Тюнер · ${templates.length} строев', style: Typo.inter(17, TypoWeight.medium, TruverColors.textPrimary)),
          ),
          Positioned(left: 20, top: 100, child: NoteText('F♯1 B♭2', style: Typo.inter(40, TypoWeight.light, TruverColors.textPrimary))),
        ]),
      ),
    );
    expect(file.existsSync(), isTrue);
  });
}
