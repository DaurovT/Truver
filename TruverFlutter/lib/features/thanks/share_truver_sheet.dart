/// Port of Truver/Sources/Features/Thanks/ShareTruverSheet.swift
///
/// «Поделиться Truver» (canvas ShareSheet): the link card, four targets (Сообщения, Telegram, Instagram, «Ещё» — the
/// system share sheet), «Скопировать ссылку» and a QR code for a friend's camera.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../design/components.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/motion.dart';
import '../../design/shapes.dart';
import '../../design/swift_text.dart';
import '../../design/theme.dart';
import '../../design/typo.dart';
import 'svg_path.dart';
import 'thanks_art.dart';
import 'thanks_chrome.dart';
import 'thanks_model.dart';

class ShareTruverSheet extends StatefulWidget {
  const ShareTruverSheet({super.key, required this.close});
  final VoidCallback close;

  static const link = UpdateCenter.storeUrl;
  static const title = 'Truver — тюнер, гриф и метроном';
  static const message = '$title: $link';

  @override
  State<ShareTruverSheet> createState() => _ShareTruverSheetState();
}

class _ShareTruverSheetState extends State<ShareTruverSheet> {
  bool _qr = false;
  bool _copied = false;

  void _copy() {
    Clipboard.setData(const ClipboardData(text: ShareTruverSheet.link));
    setState(() => _copied = true);
  }

  static String _enc(String s) => Uri.encodeComponent(s);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 414,
      width: double.infinity,
      child: ShapeBox(
        shape: const SwiftShape.topRounded(22, continuous: false),
        fills: const [SwiftFill(Color(0xFF1F2125))],
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom * 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: TruverColors.white(0.08)))),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 15), // 14 + the border
                child: Row(children: [
                  const TruverAppIconArt(size: 44, radius: 9),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SwiftText(ShareTruverSheet.title, maxLines: 1, style: Typo.inter(15, TypoWeight.semibold, TruverColors.textPrimary)),
                      const SizedBox(height: 2),
                      SwiftText('для 6–9 струн · бесплатно · play.google.com',
                          maxLines: 1, style: Typo.inter(12, TypoWeight.regular, TruverColors.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  RoundIconButton(icon: AppIcon.close, size: 30, iconSize: 14, label: 'Закрыть', onTap: widget.close),
                ]),
              ),
            ),
            if (_qr) _qrCode() else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _target('Сообщения', _tile(0xFF5FE07A, 0xFF2BB44A, _MessagesGlyph()),
                      () => openExternal('sms:?body=${_enc(ShareTruverSheet.message)}')),
                  _target('Telegram', const PlatformTile(kind: LinkKind.telegram, size: 58, radius: 16, glyph: 39),
                      () => openExternal('https://t.me/share/url?url=${_enc(ShareTruverSheet.link)}&text=${_enc(ShareTruverSheet.title)}')),
                  _target('Instagram', const PlatformTile(kind: LinkKind.instagram, size: 58, radius: 16, glyph: 39), () {
                    // Instagram takes no links from other apps: copy it and open Instagram to paste.
                    _copy();
                    openExternal('https://instagram.com');
                  }),
                  _target(
                    'Ещё',
                    _tile(
                      0xFF6B7380,
                      0xFF3D434C,
                      const SvgGlyph('M12 19V5M6 11l6-6 6 6', size: 26, stroke: 1.6, cap: StrokeCap.round, join: StrokeJoin.round),
                    ),
                    () => SharePlus.instance.share(ShareParams(text: ShareTruverSheet.message, subject: ShareTruverSheet.title)),
                  ),
                ]),
              ),
              Card(children: [
                Pressable(
                  scale: 1,
                  onTap: _copy,
                  child: CardRow(
                    title: _copied ? 'Ссылка скопирована' : 'Скопировать ссылку',
                    minHeight: 51,
                    trailing: AppIconView(_copied ? AppIcon.check : AppIcon.plus, size: 16, color: TruverColors.textTertiary),
                  ),
                ),
                Pressable(
                  scale: 1,
                  onTap: () => setState(() => _qr = true),
                  child: const CardRow(title: 'Показать QR-код', subtitle: 'чтобы друг навёл камеру', minHeight: 59, trailing: SizedBox.shrink()),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _tile(int a, int b, Widget glyph) => SizedBox(
        width: 58,
        height: 58,
        child: ShapeBox(
          shape: const SwiftShape.rounded(14),
          fills: [SwiftFill.gradient(cssLinearGradient(160, [Color(a), Color(b)]))],
          child: Center(child: SizedBox(width: 26, height: 26, child: glyph)),
        ),
      );

  Widget _target(String title, Widget tile, VoidCallback onTap) => Pressable(
        onTap: onTap,
        label: title,
        child: SizedBox(
          width: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile,
            const SizedBox(height: 6),
            SwiftText(title, maxLines: 1, softWrap: false, style: Typo.inter(11, TypoWeight.regular, TruverColors.textBody)),
          ]),
        ),
      );

  Widget _qrCode() {
    final code = QrCode.fromData(data: ShareTruverSheet.link, errorCorrectLevel: QrErrorCorrectLevel.M);
    final image = QrImage(code);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Semantics(
        label: 'QR-код ссылки на Truver',
        child: Column(children: [
          AnimatedOpacity(
            opacity: 1,
            duration: Motion.base,
            child: Container(
              width: 244,
              height: 244,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(16)),
              child: CustomPaint(painter: _QrPainter(image)),
            ),
          ),
          const SizedBox(height: 12),
          SwiftText('Наведите камеру телефона на код', style: Typo.caption.copyWith(color: TruverColors.textTertiary)),
        ]),
      ),
    );
  }
}

class _MessagesGlyph extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Stack(fit: StackFit.expand, children: [
        SvgGlyph('M9 18V6l10-2v12', stroke: 1.6),
        SvgGlyph('M4.8 18a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0M14.8 16a2.2 2.2 0 1 0 4.4 0a2.2 2.2 0 1 0-4.4 0', stroke: 1.6),
      ]);
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / n;
    final paint = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.01, cell + 0.01), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
