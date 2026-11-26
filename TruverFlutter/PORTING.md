# Перенос Truver на Android (Flutter)

Цель: Android-телефон выглядит и ведёт себя **один в один как iOS-приложение** (`../Truver`, SwiftUI). Планшеты и десктоп (Windows) — позже по отдельным макетам; сейчас не делаем. Источник истины — iOS-код и холст; решения, где iOS отступает от холста, записаны в `../DEVELOPMENT.md` (например, шестерёнка вместо «солнца», октавы на кнопках струн) — переносим как в iOS.

## Архитектура

| Слой | Где | Что |
|---|---|---|
| Ядро | `../TruverCore` (Swift, общий с iOS) | теория, DSP, метроном, синтезатор, тюнер. **Логику ядра не переписываем на Dart** |
| Звук Android | `TruverCore/Sources/TruverHost` | `AudioHost` поверх AAudio — двойник `TruverAudio.AudioEngineHost` |
| Мост | `TruverCore/Sources/TruverBridge` | C API: `truver_call("метод", JSON)`; команды по файлам `*Commands.swift` |
| Dart-ядро | `lib/core/truver_core.dart` | FFI: `TruverCore.instance!.call('theory.templates')` |
| Дизайн-система | `lib/design/` | `theme.dart`, `typo.dart`, `motion.dart` (готово), иконки, компоненты, контролы |
| Состояние | `lib/app/` | `AppModel` (≈ `AppModel.swift`), настройки (≈ `Storage.swift`) |
| Экраны | `lib/features/<feature>/` | по папкам iOS: `tuner`, `metronome`, `fretboard`, `instrument`, `onboarding`, `practice`, `settings`, `root` |

Соответствие файлов: один Swift-файл → один Dart-файл с тем же смыслом и именем в snake_case (`TunerScreen.swift` → `lib/features/tuner/tuner_screen.dart`). В начале Dart-файла — строка `/// Port of Truver/Sources/…/X.swift`.

## Правила переноса

- **Числа как в Swift.** pt = логические пиксели Flutter. Размеры, отступы, радиусы, прозрачности, шрифты — те же значения, что в SwiftUI-коде. Не «примерно похоже», а те же константы.
- **Цвета и градиенты** — только из `TruverColors` / `TruverGradients` (`lib/design/theme.dart`). Новых цветов не вводить; если в Swift есть `Color.white.opacity(x)` — `TruverColors.white(x)`.
- **Шрифт** — `Typo.inter(size, weight, color)`; ноты со знаками — `NoteText` / `Typo.notes` (♯ ♭ системным шрифтом). Тексты, которые в iOS `Typo.fixed`, ставить с `textScaler: TextScaler.noScaling`.
- **Движение** — `Motion.*` (длительности, кривые `out`/`inCurve`, пружины `snap`/`pop`, `SpringFollower` для стрелки). «Уменьшить движение» = `Motion.reduced(context)`.
- **Рисование** — `CustomPainter` по тем же координатам, что `Canvas`/`Path` в SwiftUI. Углы SwiftUI в градусах, ось Y вниз — как во Flutter.
- **Тексты** — по-русски, слово в слово как в iOS (включая «ё», тире, неразрывные пробелы).
- **Material/Cupertino-виджеты не использовать** для видимых элементов (у них свои отступы и анимации). Всё рисуем своими виджетами по образцу iOS. `GestureDetector`, `Listener`, `CustomPaint`, `Stack`, `Positioned` — основа.
- **Платформенные отличия**: хаптика — `HapticFeedback.*`; системные экраны iOS (Live Activity, виджеты, Siri, пункт управления) — не переносим сейчас, оставляем `// TODO(android): …` с аналогом (уведомление переднего плана, виджет, плитка быстрых настроек).
- **Логика контроллеров** (`*Controller.swift`) переносится на Dart как `ChangeNotifier` с теми же полями и методами; всё, что считает ядро (гаммы, позиции, аккорды, строи, метроном), — через мост, не переписывать.

## Мост: как добавить команду

1. В `TruverCore/Sources/TruverBridge/` — свой файл `<Feature>Commands.swift` с `extension Bridge { func register<Feature>() { … } }`, вызов добавить в `Bridge.init`.
2. Параметры — `Decodable`-структура; ответ — `Encodable` (типы ядра, которые уже `Codable`, отдаём как есть: `Instrument`, `Tuning`, `MeterSettings`, `Scale`, `Chord`…). Подписи нот считает ядро (обозначение `session.notation`, знаки строя) — в DTO отдаём готовые строки, как `AppModel.stringName/chromaticName`.
3. Пересобрать: `tool/build_core.sh macos` (для тестов) и `tool/build_core.sh android` (для телефона). Сборки разных людей не мешают друг другу, если задать `TRUVER_CORE_BUILD=<своя папка>`.
4. Импорты в ядре: `FoundationEssentials` вместо `Foundation` на не-Apple (см. существующие файлы) — без `NSLock`, `String(format:)`, `Thread`.

## Проверка «один в один»

**Эталон** — снимок iOS-приложения на симуляторе «Truver QA 17e» (iPhone 17e, 390 × 844, как холст):

```
SIM=5552CC6A-1A11-42D8-8263-64FA4376990F
xcrun simctl terminate $SIM app.truver.ios; xcrun simctl launch $SIM app.truver.ios -skipOnboarding -tab tuner -tunerDemo flat -muteAudio
sleep 8; xcrun simctl io $SIM screenshot test/reference/ios/tuner_flat.png
```

Отладочные аргументы iOS перечислены в `../DEVELOPMENT.md` и `AppModel.swift` (`-tab`, `-sheet …`, `-tunerDemo …`, `-metroDemo`, `-fretDemo`, `-onboardingStep N`, `-template <id>`, `-notation …`). На Android — те же аргументы (см. «Отладочные аргументы»). Симулятор один на всех: снимать эталоны по очереди, по одному запуску.

**Рендер Flutter** — без устройства, в тесте, в точной геометрии iPhone 17e (`test/support/screen_harness.dart`: 390 × 844 × 3, отступы 47 / 34):

```dart
testWidgets('tuner flat', (t) async => ScreenHarness.capture(t, 'tuner_flat', const TruverTestApp(args: '-tab tuner -tunerDemo flat')));
```
```
flutter test test/screens/tuner_test.dart
swift tool/compare.swift test/reference/ios/tuner_flat.png build/shots/tuner_flat.png build/shots/cmp_tuner_flat.jpg
```

С исправленного холста (25.11.2026) эталон — рендеры макетов холста (390 × 844 × 3, без строки состояния), а не снимки iOS: `swift tool/compare.swift <рендер холста> build/shots/<name>.png <out.jpg>`. Фон экрана рисует шум холста (`ScreenNoise`); в тестах он считается один раз и кэшируется в `build/noise/`.

`compare.swift` кладёт «iOS | Flutter | разница ×4» и печатает долю различающихся пикселей. Цель — чёрная разница везде, кроме сглаживания краёв и знаков ♯/♭ (другой шрифт). Расхождение в позиции на 1 pt видно как двойной контур — ищите его. Смотрите картинку сравнения глазами (Read), не только процент.

**Устройство** — эмулятор `Eskiz_Pixel` (можно перевести в 390 × 844: `adb shell wm size 1170x2532 && adb shell wm density 480`) и телефон Xiaomi (393 × 873 dp). Микрофон и звук — только на телефоне.

## Отладочные аргументы на Android

`adb shell am start -n app.truver.android/.MainActivity --es args "'-skipOnboarding -tab tuner -tunerDemo flat'"` (строку аргументов — в одинарных кавычках внутри двойных: adb отдаёт команду удалённой оболочке, и без них до приложения доходит только первый аргумент) — строка приходит в Dart (`DebugArgs`), разбирается так же, как `ProcessInfo.arguments` на iOS. В тестах — параметр `args` у `TruverTestApp`.

## Состояние работ

См. `../DEVELOPMENT.md`, раздел «Android и Windows».

## API каркаса (готово, 25.11.2026)

- **Состояние:** `AppScope.of(context)` (подписка) / `AppScope.read(context)`. `settings`, `updateSettings((s) => …)` (сохраняет, побочные эффекты, notify), `tab`.
- **Инструмент:** `instrument`, `tuning`, `tunings`, `tuningName`, `a4`, `courseCount`, `title`, `AppModel.shortInstrumentName()`; подписи ядром: `noteName(nameJson, octave:)`, `stringName(course, [string])`, `chromaticName(cents)`; правки: `updateInstrument((json) => …)`, `selectTuning`, `addTemplate`, `replaceInstrument(id, fretCount:)`, `deleteTuning`. Инструмент, обозначения и A4 уходят в ядро (`session.set`) сами.
- **Оболочка:** `sheet = AppSheet('metroTimer')` / `AppSheet('tuningEditor', id)`; тост `show(text, icon:, iconColor:)`; `showSettings`, `showSession`, `showTrainer`, `showOnboarding`, `unsavedTuning`, `tuningEditorFromTuner`, `showTunings`.
- **Контроллеры:** `app.tuner`, `metronome`, `fretboard`, `practice`, `trainer`, `playCheck`, `session` — заглушки в `lib/features/<f>/…_controller.dart`; фича заполняет свой файл (члены, которые зовёт `AppModel`, сохранить).
- **Звук:** `app.audio.call('audio.*', params)`, `addPollListener` / `removePollListener` (один `audio.poll` на кадр на всех), `setVolumes`, `playNote`, `requestMicPermission` / `refreshMicPermission`.
- **Регистрация фичи** — в своём `lib/features/<f>/<f>_feature.dart`, функция `register<F>()`: `FeatureRegistry.tabScreens[AppTab.x]`, `landscapeScreens`, `sheets['kind']` (лист возвращает `DesignSheet`, затемнение и выезд рисует хост), `debugSheets['metroParams']` (аргумент `-sheet` сложнее `AppSheet(name)`), `debugHooks` (прочие аргументы запуска), `settings` / `session` / `trainer` — полноэкранные обложки.
- **Раскладка:** экран вкладки кладётся в безопасную область iOS (от верхнего отступа до «таблетки» строя), `MediaQuery.padding` внутри — ноль.
- **Компоненты** (`lib/design/`): `Pressable`, `RoundIconButton`, `PrimaryRoundButton`, `HeaderChip`, `PrimaryButton`, `SheetButton`, `SegmentedPill`/`SegmentsBar`, `ScreenHeader`, `CardGroup`, `CardRow`, `StatCard`, `Panel`, `ToastView`; `ToggleSwitch`, `RadioMark`, `RadioRow`, `ValueStepper`, `Segments`, `Chip(style: ChipStyle.*)`, `DesignToast`, `SectionCaption`, `Card`, `FlowLayout`, `DesignSheet(title, height, close, child, footer)`, `TextFieldAlert`, `DesignAlert`, `SwipeRow`; `ShapeBox` + `SwiftShape`/`SwiftFill`/`SwiftStroke`/`SwiftShadow` (тени с радиусом как в SwiftUI); `AppIconView`; `BrandMark`, `Wordmark`, `MiniBezel`; `LandscapeCanvas`.
- **Текст — важно:** цифры не табличные по умолчанию (как iOS); где в Swift `.monospacedDigit()` — `Typo.monospacedDigit(style)`. Высота строки SwiftUI ≠ Flutter: тексты, стоящие друг под другом, — через `SwiftText`; многострочный текст — `textWidthBasis: TextWidthBasis.longestLine`.
- **Тест экрана:** `ScreenHarness.capture(t, 'name', TruverTestApp(args: '-resetSettings -skipOnboarding -template g8-standard-fs -muteAudio …'))`. Эталоны iOS — `test/reference/ios/<name>.png`, список состояний и аргументов — `test/reference/ios/states.txt` (снимает `tool/ios_refs.sh`).

## Параллельная работа нескольких агентов

- Свои файлы: `lib/features/<f>/`, `test/screens/<f>_*`, `TruverBridge/<F>Commands.swift`. Чужие не править; если нужна правка общего компонента — минимальная, обратно совместимая, и записать в отчёт.
- Swift-ядро собирают все: держите свой Swift-файл всегда компилируемым (пишите файл целиком). Если сборка падает в чужом файле — подождать минуту и повторить. Своя папка сборки: `TRUVER_CORE_BUILD=<scratchpad>/core-<f>`.
- Симулятор iOS и телефон/эмулятор не трогать: эталоны уже сняты (`test/reference/ios/`); если нужного нет — записать в отчёт, какое состояние и с какими аргументами снять.
- Тяжёлые задачи (xcodebuild, flutter test/build, swift build, gradle, `tool/build_core.sh`) — только через `Truver/Tools/heavy_slot.sh <команда…>` (не больше 3 одновременно); flutter test — по одному файлу. Симулятор iOS — только через `Truver/Tools/sim_turn.sh <UDID> <batch.sh>` (один на машине; собрать до очереди, всё про симулятор одним пакетом).

## Экономия токенов (для всех агентов)

Каждый шаг агента перечитывает всю его историю, поэтому большие выводы и картинки дорожают с каждым следующим шагом.

- **Короткие выводы.** Вывод команд — через `tail`/`grep`/`head`; логи сборки и тестов писать в файл и смотреть только итог и ошибки. Файлы читать нужными кусками (`offset`/`limit`, `grep -n`), не целиком.
- **Картинки — редко и маленькими.** Сначала число из `tool/compare.swift` (и `--rows`); смотреть картинку только если число плохое, и тогда уменьшенную (`sips -Z 900`) или вырезанный участок (`sips -c`), а не полный кадр 1170×2532. Сравнительную картинку — одну, а не эталон и снимок по отдельности.
- **Не опрашивать в цикле.** Долгие команды запускать в фоне и ждать уведомления о завершении; не делать `until …; do sleep; done` и не перепроверять статус каждые несколько секунд.
- **Узкие задачи.** Один агент — один экран или небольшая группа экранов. Закончил — отчёт и выход; следующую группу берёт свежий агент по короткой передаче дел (что сделано, файлы, проценты, открытые вопросы), а не тот же агент с длинной историей.
- **Подгонку экранов** выполняет агент `screen-porter` (`.claude/agents/screen-porter.md`, модель Sonnet). Opus — для ядра на Swift, звука, сборки под Android и архитектурных решений.
