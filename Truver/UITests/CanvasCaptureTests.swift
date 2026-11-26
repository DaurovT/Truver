import XCTest

/// Captures every screen of the app as it is now, for the design canvas page «Приложение · как сейчас».
final class CanvasCaptureTests: TruverUITestCase {
    func cap(_ name: String, _ args: [String], wait: UInt32 = 3, _ actions: (() -> Void)? = nil) {
        XCUIDevice.shared.orientation = .portrait
        launch(args)
        sleep(wait)
        actions?()
        shot(name)
        app.terminate()
    }

    func neck() -> XCUIElement { elementBegins("Гриф,") }

    func testA_Tuner() {
        let t = ["-template", "g6-standard-e", "-tab", "tuner"]
        cap("tuner-flat", t + ["-tunerDemo", "flat"])
        cap("tuner-strobe", t + ["-tunerDemo", "flat", "-tuner.strobe", "YES"])
        cap("tuner-stage", t + ["-tunerDemo", "flat", "-tunerStage"], wait: 4)
        cap("tuner-pro", t + ["-tunerDemo", "flat"]) { self.tapIfExists("Дополнительно"); sleep(2) }
        cap("tuner-intonation", t + ["-sheet", "intonation"])
        cap("tuner-tunings", t + ["-sheet", "tunings"])
        cap("tuner-tuning-editor", t + ["-sheet", "tuningEditor"]) { self.app.swipeUp(); sleep(1) }
        cap("tuner-instrument", t + ["-sheet", "instrument"])
        cap("tuner-strings-fan", ["-template", "g8-standard-fs", "-tab", "tuner", "-fan", "-sheet", "instrumentStrings"])
    }

    func testB_Fretboard() {
        let f = ["-template", "g8-standard-fs", "-tab", "fretboard"]
        cap("fret-position", f)
        cap("fret-whole", f + ["-neckWhole"])
        cap("fret-note-menu", f) { self.neck().coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.55)).press(forDuration: 1.0); sleep(1) }
        cap("fret-path", f) {
            self.neck().coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.55)).press(forDuration: 1.0); sleep(1)
            self.tapIfExists("Путь отсюда"); sleep(3)
        }
        cap("fret-path-sheet", f + ["-fretMode", "path4", "-sheet", "fretPath"])
        cap("fret-play-sheet", f + ["-sheet", "fretPlay"])
        cap("fret-training", f + ["-trainingDemo"])
        cap("fret-fan", f + ["-fan"])
        cap("fret-scale-sheet", f + ["-sheet", "fretScale"])
        cap("fret-scale-builder", f + ["-sheet", "scaleBuilder"])
        cap("fret-chord", f + ["-fretMode", "chord"])
        cap("fret-chord-library", f + ["-fretMode", "chord", "-chordLibrary"])
        cap("fret-chord-builder", f + ["-fretMode", "chord", "-sheet", "chordBuilder"])
        cap("fret-search", f + ["-fretMode", "search"])
        cap("fret-progression", f + ["-fretMode", "progression"])
        cap("fret-view-sheet", f + ["-sheet", "fretView"])
    }

    func testC_Metronome() {
        let m = ["-template", "g8-standard-fs", "-tab", "metronome"]
        cap("metro-main", m)
        cap("metro-modes", m + ["-sheet", "metroModes"])
        cap("metro-fastslow", m + ["-sheet", "metroFastSlow"])
        cap("metro-randommute", m + ["-sheet", "metroRandomMute"])
        cap("metro-songmap", m + ["-sheet", "metroSong"])
        cap("metro-meter-poly", m + ["-sheet", "metroMeter"]) { self.tapIfExists("Полиритм"); sleep(1) }
        cap("metro-rhythm", m + ["-sheet", "metroRhythm"])
        cap("metro-playcheck-sheet", m + ["-sheet", "playCheck"])
        cap("metro-playcheck-summary", m + ["-sheet", "playCheckSummary"])
        cap("metro-presets", m + ["-sheet", "metroPresets"])
        cap("metro-sounds", m + ["-sheet", "metroSounds"])
    }

    func testD_Practice() {
        let p = ["-template", "g8-standard-fs", "-tab", "practice"]
        cap("practice-charts", p + ["-playCheckHistoryDemo"])
        cap("practice-session", p + ["-sheet", "session"])
        cap("practice-trainer-name", p + ["-sheet", "trainerName"])
        cap("practice-trainer-feedback", p + ["-sheet", "trainerName"]) { self.tapIfExists("C"); usleep(300_000) }
    }

    func testE_Settings() {
        cap("settings-main", ["-tab", "metronome", "-showSettings"])
        cap("settings-volume-latency", ["-tab", "metronome", "-settingsPage", "volume"]) { self.app.swipeUp(); sleep(1) }
        cap("settings-input", ["-tab", "tuner", "-settingsPage", "input"])
        XCUIDevice.shared.orientation = .portrait
        launch(["-onboardingStep", "1"], skipOnboarding: false)
        sleep(3)
        shot("onboarding-instrument")
        app.terminate()
    }

    func testF_Landscape() {
        func land(_ name: String, _ args: [String]) {
            launch(args)
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(4)
            shot(name)
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        land("land-fret-whole", ["-template", "g8-standard-fs", "-tab", "fretboard", "-neckWhole"])
        land("land-fret-path", ["-template", "g8-standard-fs", "-tab", "fretboard", "-fretMode", "path4"])
        land("land-metro", ["-tab", "metronome"])
        land("land-tuner", ["-template", "g6-standard-e", "-tab", "tuner", "-tunerDemo", "flat"])
    }
}
