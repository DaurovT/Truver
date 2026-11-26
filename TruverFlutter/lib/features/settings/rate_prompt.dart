/// Port of Truver/Sources/Features/Settings/RatePrompt.swift
///
/// Canvas «Оценка — системный запрос после удачной настройки (не чаще 3 раз в год)». The dialog is the platform's
/// own (iOS: StoreKit; Android: Google Play In-App Review — it draws and throttles it). Our rule on top: after a
/// successful tuning (all strings in tune), from the 3rd such tuning on, not while the metronome plays, at most 3
/// requests in 365 days and at least 60 days apart.
library;

import 'dart:async';
import 'dart:convert';

import '../../app/app_model.dart';
import 'settings_view.dart' show noiseGateKey;

/// Hooks of the settings feature started with the app: the saved noise threshold and the rate prompt.
abstract final class SettingsHooks {
  static void start(AppModel app) {
    final gate = app.store.getDouble(noiseGateKey);
    if (gate != null) app.tuner.noiseGate = gate;
    final prompt = RatePrompt(app)..observe();
    // Screenshot hook: `-ratePrompt` asks at once (with `-tunerDemo done` — the board «Оценка»).
    if (app.args.has('-ratePrompt')) Timer(const Duration(milliseconds: 1500), prompt.request);
  }
}

class RatePrompt {
  RatePrompt(this.app);
  final AppModel app;

  static const tuningsKey = 'rate.successfulTunings';
  static const requestsKey = 'rate.requests';
  bool _wasTuned = false;

  void observe() {
    _wasTuned = app.tuner.allTuned;
    app.tuner.addListener(_changed);
  }

  void _changed() {
    final tuned = app.tuner.allTuned;
    if (tuned && !_wasTuned) _successfulTuning();
    _wasTuned = tuned;
  }

  void _successfulTuning() {
    final count = (app.store.getDouble(tuningsKey) ?? 0).toInt() + 1;
    app.store.setDouble(tuningsKey, count.toDouble());
    if (!shouldAsk(successfulTunings: count, requests: requests, now: DateTime.now()) || app.metronome.isPlaying) return;
    // Let «Готово» show first.
    Timer(const Duration(milliseconds: 1500), request);
  }

  List<DateTime> get requests {
    final raw = app.store.getString(requestsKey);
    if (raw == null) return [];
    return [for (final s in (jsonDecode(raw) as List)) DateTime.fromMillisecondsSinceEpoch((s as num).toInt())];
  }

  /// The rule, separately for tests.
  static bool shouldAsk({required int successfulTunings, required List<DateTime> requests, required DateTime now}) {
    if (successfulTunings < 3) return false;
    final year = now.subtract(const Duration(days: 365));
    if (requests.where((d) => d.isAfter(year)).length >= 3) return false;
    if (requests.isNotEmpty) {
      final last = requests.reduce((a, b) => a.isAfter(b) ? a : b);
      if (now.difference(last) < const Duration(days: 60)) return false;
    }
    return true;
  }

  void request() {
    final list = [...requests, DateTime.now()];
    final kept = list.length > 6 ? list.sublist(list.length - 6) : list;
    app.store.setString(requestsKey, jsonEncode([for (final d in kept) d.millisecondsSinceEpoch]));
    // TODO(android): Google Play In-App Review (`in_app_review` plugin or a ReviewManager method channel) — not in
    // pubspec yet; the rule and the bookkeeping above are ready.
  }
}
