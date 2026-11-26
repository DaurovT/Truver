// Device check of the audio path (not part of the app): flutter build apk --debug -t lib/dev/spike_main.dart
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/truver_core.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Spike()));

class _Spike extends StatefulWidget {
  const _Spike();
  @override
  State<_Spike> createState() => _SpikeState();
}

class _SpikeState extends State<_Spike> with SingleTickerProviderStateMixin {
  final core = TruverCore.instance;
  late final Ticker ticker = createTicker(_poll);
  String status = '';
  Map<String, dynamic>? reading;
  double level = -160;
  int ticks = 0;
  bool metronome = false;
  final log = <String>[];

  @override
  void initState() {
    super.initState();
    status = core == null ? 'нет ядра: ${TruverCore.loadError}' : 'ядро ${core!.call('core.version')}';
    if (core != null) _start();
  }

  Future<void> _start() async {
    final p = await Permission.microphone.request();
    if (!p.isGranted) return setState(() => status = 'микрофон: $p');
    final instrument = core!.call('theory.instrumentFromTemplate', {'id': 'g6-standard-e'});
    core!.call('session.set', {'instrument': instrument});
    try {
      final r = core!.call('audio.startTuner', {'mode': 'auto'});
      setState(() => status = 'слушаю $r · 6 струн, стандарт E');
      ticker.start();
    } catch (e) {
      setState(() => status = '$e');
    }
  }

  void _poll(Duration _) {
    final poll = core!.call('audio.poll') as Map<String, dynamic>;
    final updates = poll['tuner'] as List, t = poll['ticks'] as List;
    if (updates.isEmpty && t.isEmpty) return;
    setState(() {
      for (final u in updates.cast<Map<String, dynamic>>()) {
        level = (u['level'] as num).toDouble();
        if (u['display'] == 'reading') {
          reading = u['reading'] as Map<String, dynamic>;
          final r = reading!, tg = r['target'] as Map<String, dynamic>;
          debugPrint('TRUVERREAD t=${(u['time'] as num).toStringAsFixed(3)} f=${(r['frequency'] as num).toStringAsFixed(3)} '
              'note=${(r['pitch'] as Map)['label']} target=${(tg['target'] as Map)['label']} dev=${(tg['deviation'] as num).toStringAsFixed(2)} '
              'prov=${r['provisional']} inTune=${r['inTune']} level=${(u['level'] as num).toStringAsFixed(1)}');
        } else {
          debugPrint('TRUVERREAD t=${(u['time'] as num).toStringAsFixed(3)} display=${u['display']} level=${(u['level'] as num).toStringAsFixed(1)}');
        }
        for (final s in (u['tuned'] as List)) {
          log.insert(0, 'настроена струна ${(s as Map)['course'] + 1}');
        }
      }
      ticks += t.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = reading, target = r?['target'] as Map<String, dynamic>?;
    final dev = (target?['deviation'] as num?)?.toDouble() ?? 0;
    final color = r == null ? Colors.white : (r['inTune'] == true ? const Color(0xFF46E08F) : dev < 0 ? const Color(0xFF6AA8FF) : const Color(0xFFFF9B52));
    return Scaffold(
      backgroundColor: const Color(0xFF0A0B0D),
      body: SafeArea(
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white70, fontSize: 15),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Проверка звука Truver', style: const TextStyle(fontSize: 20, color: Colors.white)),
              Text(status, style: const TextStyle(fontSize: 12, color: Colors.white38)),
              const SizedBox(height: 40),
              Center(child: Text(r == null ? '—' : (r['pitch'] as Map)['label'] as String, style: TextStyle(fontSize: 110, fontWeight: FontWeight.w200, color: color))),
              Center(child: Text(r == null ? 'сыграйте струну' : '${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(1)} ц · ${(r['frequency'] as num).toStringAsFixed(2)} Гц', style: TextStyle(fontSize: 22, color: color))),
              Center(child: Text(r == null ? '' : 'струна ${(target!['target'] as Map)['label']}${r['inTune'] == true ? ' · в строю' : ''}')),
              const SizedBox(height: 24),
              Text('уровень ${level.toStringAsFixed(0)} dBFS'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  if (metronome) {
                    core!.call('audio.stopMetronome');
                  } else {
                    core!.call('audio.startMetronome', {'settings': {'bpm': 100, 'numerator': 4, 'denominator': 4, 'accents': [3, 1, 1, 1], 'subdivision': 1, 'swing': 0}});
                  }
                  setState(() => metronome = !metronome);
                },
                child: Text(metronome ? 'Стоп метроном' : 'Метроном 100'),
              ),
              Text('доли: $ticks'),
              const SizedBox(height: 12),
              Text('${core?.call('audio.diagnostics')}', style: const TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(height: 12),
              ...log.take(6).map(Text.new),
            ]),
          ),
        ),
      ),
    );
  }
}
