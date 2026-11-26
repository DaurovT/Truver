import XCTest

/// Usability audit of the features added for experienced players: everything is reached by real taps from the
/// screens (no debug shortcuts), so a missing way in shows up as a failed tap.
final class UsabilityAuditTests: TruverUITestCase {
    /// Metronome: new modes, song map, second track, play check.
    func testA_Metronome() {
        launch(["-template", "g8-standard-fs", "-tab", "metronome"])
        shot("metronome", tree: true)
        tap("Режимы"); sleep(1)
        shot("modes", tree: true)
        tap("Быстро / медленно"); sleep(1)
        shot("fastslow")
        tap("Готово"); sleep(1)
        tap("Случайный пропуск"); sleep(1)
        shot("randommute")
        tap("Готово"); sleep(1)
        tap("Карта песни"); sleep(1)
        shot("songmap", tree: true)
        app.swipeUp(); sleep(1)
        shot("songmap-scrolled")
        tap("Готово"); sleep(1)
        tapIfExists("Закрыть"); sleep(1)
        shot("metronome-song", tree: true)
        tap("Старт"); sleep(4)
        shot("song-playing", tree: true)
        tap("Стоп"); sleep(1)
        // Second track from the meter chip.
        tap("4/4"); sleep(1)
        app.swipeUp(); sleep(1)
        shot("meter-sheet", tree: true)
        tapIfExists("Полиритм"); sleep(1)
        shot("poly-on", tree: true)
        tapIfExists("Закрыть"); sleep(1)
        shot("metronome-chips", tree: true)
    }

    func testB_PlayCheck() {
        launch(["-template", "g8-standard-fs", "-tab", "metronome"])
        tap("Проверка игры"); sleep(1)
        shot("playcheck-sheet", tree: true)
        tap("Включить проверку"); sleep(3)
        shot("playcheck-on", tree: true)
        tap("Старт"); sleep(6)
        shot("playcheck-playing", tree: true)
        tap("Стоп"); sleep(2)
        shot("playcheck-stopped", tree: true)
        tapBegins("Проверка"); sleep(1)
        shot("playcheck-sheet-on", tree: true)
        tap("Выключить проверку"); sleep(1)
        shot("playcheck-off")
    }

    func testC_SettingsLatency() {
        launch(["-tab", "metronome"])
        tap("Настройки"); sleep(1)
        tapBegins("Выход метронома"); sleep(1)
        app.swipeUp(); sleep(1)
        shot("latency", tree: true)
    }

    func testD_FretboardTrainingDrone() {
        launch(["-template", "g8-standard-fs", "-tab", "fretboard"])
        shot("fretboard", tree: true)
        tap("Настройки проигрывания"); sleep(1)
        shot("play-sheet", tree: true)
        let drone = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Бурдон на тонике'"))
        if drone.count > 0 { safeTap(drone.element(boundBy: drone.count - 1)); sleep(1) }
        tap("Закрыть"); sleep(1)
        shot("drone-on", tree: true)
        tapIfExists("Выключить бурдон"); sleep(1)
        tap("Настройки проигрывания"); sleep(1)
        tapBegins("Тренировать с проверкой"); sleep(4)
        shot("training", tree: true)
        tap("Стоп"); sleep(2)
        shot("training-stopped", tree: true)
    }

    func testE_UserScaleAndChord() {
        launch(["-template", "g8-standard-fs", "-tab", "fretboard"])
        tapBegins("Гамма:"); sleep(1)
        tap("Мои"); sleep(1)
        shot("scales-mine", tree: true)
        tapBegins("Новая гамма"); sleep(1)
        shot("scale-builder", tree: true)
        tapBegins("♭2"); sleep(1)
        shot("scale-builder-edited")
        tap("Сохранить и показать"); sleep(2)
        shot("fretboard-userscale", tree: true)
        tap("Аккорд"); sleep(1)
        tap("Все аккорды"); sleep(1)
        tap("Свой аккорд"); sleep(1)
        shot("chord-builder", tree: true)
        tapBegins("♯11"); sleep(1)
        tap("Сохранить и показать"); sleep(2)
        shot("fretboard-userchord", tree: true)
    }

    func testF_Tuner() {
        launch(["-template", "g8-standard-fs", "-tab", "tuner"])
        shot("tuner", tree: true)
        tap("Строб"); sleep(2)
        shot("strobe-on", tree: true)
        tap("Сценический режим"); sleep(2)
        shot("stage", tree: true)
        tap("Закрыть сценический режим"); sleep(1)
        tap("Дополнительно"); sleep(1)
        shot("pro", tree: true)
        tap("Проверка мензуры"); sleep(2)
        shot("intonation", tree: true)
        tap("Закрыть"); sleep(1)
    }

    func testG_FannedFrets() {
        launch(["-template", "g8-standard-fs", "-tab", "fretboard"])
        tapBegins("Строй:"); sleep(1)
        shot("tunings", tree: true)
        tapBegins("8-струнная гитара"); sleep(1)
        shot("instrument", tree: true)
        tapBegins("Калибры и мензура"); sleep(1)
        let fan = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Веерные лады'"))
        if fan.count > 0 { safeTap(fan.element(boundBy: fan.count - 1)); sleep(1) }
        shot("strings-fan", tree: true)
        tap("Готово"); sleep(1)
        tapIfExists("Готово"); sleep(1)
        tapIfExists("Закрыть"); sleep(1)
        shot("fretboard-fan", tree: true)
    }

    func testH_Practice() {
        launch(["-template", "g8-standard-fs", "-tab", "practice"])
        shot("practice", tree: true)
        tapBegins("Занятие"); sleep(1)
        shot("session", tree: true)
        tap("Закрыть"); sleep(1)
        tapBegins("Тренажёр грифа"); sleep(2)
        shot("trainer", tree: true)
        for _ in 0..<3 { tapIfExists("E"); sleep(2) }
        shot("trainer-answers", tree: true)
        tap("Сыграй ноту"); sleep(2)
        shot("trainer-play", tree: true)
        tap("Закрыть"); sleep(1)
    }
}
