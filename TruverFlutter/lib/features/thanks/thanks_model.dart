/// Port of Truver/Sources/Features/Thanks/ThanksModel.swift
///
/// «Спасибо»: the people to thank (bundled `assets/thanks/thanks.json` + photos) and the update notices.
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/app_model.dart';
import '../../app/debug_args.dart';
import '../../app/storage.dart';

// MARK: - People and partners

enum LinkKind { youtube, instagram, tiktok, telegram, spotify, site }

/// A link of a person or partner: the platform and the handle shown under its name.
class ThanksLink {
  const ThanksLink({required this.kind, required this.handle, required this.url});
  final LinkKind kind;
  final String handle;
  final String url;

  static ThanksLink? fromJson(Map<String, dynamic> j) {
    final kind = LinkKind.values.where((k) => k.name == j['kind']).firstOrNull;
    if (kind == null) return null;
    return ThanksLink(kind: kind, handle: j['handle'] as String? ?? '', url: j['url'] as String? ?? '');
  }

  /// Platform names (canvas «Ссылки на площадки — набор»).
  static String platformName(LinkKind kind) => switch (kind) {
        LinkKind.youtube => 'YouTube',
        LinkKind.instagram => 'Instagram',
        LinkKind.tiktok => 'TikTok',
        LinkKind.telegram => 'Telegram',
        LinkKind.spotify => 'Spotify',
        LinkKind.site => 'Сайт',
      };

  String get platform => platformName(kind);

  /// The second line of a link row: `@handle`, `t.me/handle` or the site's address.
  String get displayHandle => switch (kind) {
        LinkKind.telegram => 't.me/$handle',
        LinkKind.site => handle,
        _ => handle.startsWith('@') ? handle : '@$handle',
      };
}

/// Partner kinds — the badge on the square avatar (canvas «Спасибо — партнёры»).
enum PartnerKind { school, shop, festival, channel }

/// A musician or a partner from `thanks.json`.
class ThanksPerson {
  const ThanksPerson({
    required this.id,
    required this.name,
    required this.subtitle,
    this.thanks,
    this.photo,
    this.photoSmall,
    this.links = const [],
    this.kind,
  });

  final String id;
  final String name;
  final String subtitle;
  final String? thanks;
  final String? photo;
  final String? photoSmall;
  final List<ThanksLink> links;
  final PartnerKind? kind;

  factory ThanksPerson.fromJson(Map<String, dynamic> j, {bool partner = false}) => ThanksPerson(
        id: j['id'] as String,
        name: j['name'] as String,
        subtitle: j['subtitle'] as String? ?? '',
        thanks: j['thanks'] as String?,
        photo: j['photo'] as String?,
        photoSmall: j['photoSmall'] as String?,
        links: [for (final l in (j['links'] as List? ?? const [])) ?ThanksLink.fromJson(l as Map<String, dynamic>)],
        kind: partner ? (PartnerKind.values.where((k) => k.name == j['kind']).firstOrNull ?? PartnerKind.school) : null,
      );

  /// Initials for a person without a photo (canvas: «АВ», «MS»).
  String get initials {
    final words = name.split(RegExp(r'[\s«»]+')).where((w) => w.isNotEmpty && RegExp(r'\p{L}', unicode: true).hasMatch(w[0]));
    return words.take(2).map((w) => w[0]).join().toUpperCase();
  }
}

/// The list of people to thank — bundled for now.
/// TODO(server): load the list from our server (JSON + pictures), cache it with its date and show the cached copy
/// offline («Нет интернета · показан список от …», canvas ThanksOffline) — people get added without a new release.
class ThanksData {
  ThanksData._();
  static final instance = ThanksData._();

  List<ThanksPerson> musicians = const [];
  List<ThanksPerson> partners = const [];

  /// Decoded photos by file name (the downscaled whole photo — never cropped; the circle aspect-fills it).
  final photos = <String, ui.Image>{};
  final loaded = ValueNotifier(false);
  Future<void>? _loading;

  /// Loads the list and decodes the avatar photos (tests: inside `runAsync`).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      apply(jsonDecode(await rootBundle.loadString('assets/thanks/thanks.json')) as Map<String, dynamic>);
      for (final person in [...musicians, ...partners]) {
        final name = person.photoSmall ?? person.photo;
        if (name == null) continue;
        final data = await rootBundle.load('assets/thanks/$name');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        photos[name] = (await codec.getNextFrame()).image;
      }
    } catch (_) {
      // A broken bundle shows an empty list rather than crashing the settings.
    }
    loaded.value = true;
  }

  /// Takes the people of a `thanks.json` (tests: the canvas fixture `Truver/Tools/canvas/thanks_canvas_sample.json`).
  void apply(Map<String, dynamic> json) {
    musicians = [for (final m in (json['musicians'] as List? ?? const [])) ThanksPerson.fromJson(m as Map<String, dynamic>)];
    partners = [for (final p in (json['partners'] as List? ?? const [])) ThanksPerson.fromJson(p as Map<String, dynamic>, partner: true)];
  }

  ThanksPerson? person(String id) => [...musicians, ...partners].where((p) => p.id == id).firstOrNull;
}

// MARK: - Updates

/// One line of «Что нового»: a bold section and the change.
class ReleaseNote {
  const ReleaseNote(this.section, this.text);
  final String section;
  final String text;
}

/// A version the store knows about.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.sizeMB, required this.notes, this.requiredReason});
  final String version;
  final int sizeMB;
  final List<ReleaseNote> notes;

  /// Set for a mandatory update (only a critical error — wrong tuning or cents): why.
  final String? requiredReason;
}

/// Where the app learns about new versions.
abstract class UpdateSource {
  Future<UpdateInfo?> latest();
}

/// TODO(server): Android — Play In-App Updates (or our file with the latest and the minimum version);
/// iOS/Mac — App Store lookup. There is no server yet: the stub always answers «no newer version».
class StubUpdateSource implements UpdateSource {
  @override
  Future<UpdateInfo?> latest() async => null;
}

enum UpdateStatus { unknown, checking, upToDate, available, required, failed }

enum UpdateSheetKind { available, whatsNew }

/// `CFBundleShortVersionString` / `CFBundleVersion` — pubspec `version: 1.0.0+1` (Android versionName 1.0.0).
/// TODO(android): read them at run time (package_info_plus) once the version moves past 1.0.
const appVersion = '1.0';
const appBuild = '1';

/// Update notices and the «Спасибо» page state of one app (canvas «Спасибо · обновления»): 1) a newer version —
/// once per version at launch (not while the metronome plays), «Позже» = in 3 days, plus the banner in «О Truver»;
/// 2) «Что нового» — once after an update, and from «О Truver»; 3) a mandatory update — only for a critical error.
class UpdateCenter extends ChangeNotifier {
  UpdateCenter._(this.store, this.args) {
    // Screenshot hooks: `-updateDemo available|banner|whatsNew|required|failed`, `-thanksOffline`.
    switch (args.value('-updateDemo')) {
      case 'available':
        _set(UpdateStatus.available, demo);
        if (!args.has('-settingsPage')) sheet = UpdateSheetKind.available;
      case 'banner':
        _set(UpdateStatus.available, demo);
      case 'whatsNew':
        _demoWhatsNew = demo;
        _set(UpdateStatus.upToDate, null);
        sheet = UpdateSheetKind.whatsNew;
      case 'required':
        _set(UpdateStatus.required, demo);
        showsRequired = true;
      case 'failed':
        _set(UpdateStatus.failed, null);
    }
    _demoMode = args.value('-updateDemo') != null;
    if (args.has('-thanksOffline')) offlineSince = DateTime(2026, 11, 20);
  }

  static final _byApp = Expando<UpdateCenter>();

  /// The centre of this app (created on first use).
  static UpdateCenter of(AppModel app) => _byApp[app] ??= UpdateCenter._(app.store, app.args);

  final SettingsStore store;
  final DebugArgs args;
  UpdateSource source = StubUpdateSource();

  UpdateStatus status = UpdateStatus.unknown;
  UpdateInfo? info;
  UpdateSheetKind? sheet;
  bool showsRequired = false;
  /// Set when the server could not be reached and a saved list is shown (its date).
  DateTime? offlineSince;
  bool _demoMode = false;
  UpdateInfo? _demoWhatsNew;
  bool _launched = false;

  static const _lastLaunched = 'updates.lastLaunchedVersion';
  static const _dismissed = 'updates.dismissedVersion';
  static const _remindAfter = 'updates.remindAfter';

  String get currentVersion => appVersion;
  String get currentBuild => appBuild;

  /// Notes of each released version, newest first.
  static const history = <(String, List<ReleaseNote>)>[
    ('1.0', [
      ReleaseNote('Тюнер:', 'строи для 6–9 струн и свои строи'),
      ReleaseNote('Гриф:', 'гаммы, аккорды и прогрессии на всём грифе'),
      ReleaseNote('Метроном:', 'ритмические фигуры, разгон и проверка игры'),
    ]),
  ];

  /// The canvas sample (debug launch arguments only).
  static const demo = UpdateInfo(
    version: '1.2',
    sizeMB: 18,
    notes: [
      ReleaseNote('Тюнер:', 'быстрее ловит низкий B0 на 9 струнах'),
      ReleaseNote('Строи:', 'Drop A и Drop G♯ для 8 струн'),
      ReleaseNote('Метроном:', 'не сбивается при блокировке экрана'),
    ],
    requiredReason: 'В версии 1.0 найдена ошибка: на частоте A4 ≠ 440 Гц тюнер показывал неверные центы. Исправлено в 1.2.',
  );

  void _set(UpdateStatus s, UpdateInfo? i) {
    status = s;
    info = i;
  }

  /// The version «Что нового» describes: the newer one when known, otherwise this one.
  (String, List<ReleaseNote>)? get whatsNew {
    if (_demoWhatsNew != null) return (_demoWhatsNew!.version, _demoWhatsNew!.notes);
    if (status == UpdateStatus.available && info != null && info!.notes.isNotEmpty) return (info!.version, info!.notes);
    return history.where((h) => h.$1 == currentVersion).firstOrNull ?? history.firstOrNull;
  }

  /// At launch: «Что нового» once after an update, then the store check.
  void launch(bool Function() canInterrupt) {
    if (_launched || _demoMode) return;
    _launched = true;
    final last = store.getString(_lastLaunched);
    store.setString(_lastLaunched, currentVersion);
    if (last != null && compare(last, currentVersion) < 0 && history.any((h) => h.$1 == currentVersion)) {
      sheet = UpdateSheetKind.whatsNew;
      notifyListeners();
    }
    check(canInterrupt: canInterrupt);
  }

  Future<void> check({bool Function()? canInterrupt}) async {
    if (_demoMode && status != UpdateStatus.failed) return;
    _set(UpdateStatus.checking, info);
    notifyListeners();
    try {
      final latest = await source.latest();
      if (latest == null || compare(currentVersion, latest.version) >= 0) {
        _set(UpdateStatus.upToDate, null);
      } else if (latest.requiredReason != null) {
        _set(UpdateStatus.required, latest);
        showsRequired = true;
      } else {
        _set(UpdateStatus.available, latest);
        final remind = DateTime.tryParse(store.getString(_remindAfter) ?? '') ?? DateTime(2000);
        if (sheet == null &&
            (store.getString(_dismissed) != latest.version || remind.isBefore(DateTime.now())) &&
            (canInterrupt?.call() ?? true)) {
          sheet = UpdateSheetKind.available;
        }
      }
    } catch (_) {
      _set(UpdateStatus.failed, null);
    }
    notifyListeners();
  }

  /// «Позже»: once per version, again in 3 days.
  void later() {
    if (info != null) {
      store.setString(_dismissed, info!.version);
      store.setString(_remindAfter, DateTime.now().add(const Duration(days: 3)).toIso8601String());
    }
    closeSheet();
  }

  void closeSheet() {
    sheet = null;
    notifyListeners();
  }

  void closeRequired() {
    showsRequired = false;
    notifyListeners();
  }

  /// Numeric version order: `1.10` after `1.9`.
  static int compare(String a, String b) {
    final x = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final y = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// The store page of Truver.
  static const storeUrl = 'https://play.google.com/store/apps/details?id=app.truver.android';

  /// «Обратная связь» (iOS `mailto:?subject=Truver`).
  static const feedbackUrl = 'mailto:?subject=Truver';

  /// «20 ноября» for the offline toast.
  static String dayMonth(DateTime d) {
    const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return '${d.day} ${months[d.month - 1]}';
  }
}
