import Testing
@testable import TruverTheory

@Suite("Tunings, generator, templates, editing")
struct TuningTests {
    func note(_ s: String) -> Pitch { SpelledNote(parsing: s)!.pitch }

    @Test("Generator reproduces every 7–9-string and bass template (5.1.1)",
          arguments: [
            ("g7-standard-b", "B1", false), ("g7-drop-a", "B1", true), ("g7-standard-bb", "B♭1", false),
            ("g7-standard-a", "A1", false), ("g7-drop-g", "A1", true),
            ("g8-standard-fs", "F♯1", false), ("g8-drop-e", "F♯1", true), ("g8-standard-f", "F1", false),
            ("g8-standard-e", "E1", false), ("g8-drop-d", "E1", true),
            ("g9-standard-cs", "C♯1", false), ("g9-drop-b", "C♯1", true), ("g9-standard-c", "C1", false),
            ("g9-standard-b", "B0", false), ("g9-high-a", "F♯1", false),
            ("g6-standard-e", "E2", false), ("g6-drop-d", "E2", true), ("g6-standard-eb", "E♭2", false),
            ("b4-standard", "E1", false), ("b5-standard", "B0", false), ("b6-standard", "B0", false),
          ])
    func generatorMatchesTemplates(templateId: String, lowest: String, drop: Bool) throws {
        let template = try #require(TuningTemplates.template(id: templateId))
        let result = try #require(TuningGenerator.generate(type: template.type, stringCount: template.courseCount,
                                                            lowestStandard: note(lowest), drop: drop))
        #expect(result.notes == template.notes, "\(templateId): \(result.notes)")
        // Guitar templates are named like the generator; bass and "with high A" have descriptive names.
        if template.type == .guitar {
            #expect(result.name.text(language: .ru) == template.names.ru, "\(templateId)")
        }
    }

    @Test func generatorIsNilWithoutTemplate() {
        #expect(TuningGenerator.generate(type: .mandolin, stringCount: 4, lowestStandard: note("G3")) == nil)
    }

    @Test func templateSpellingFamilies() throws {
        let drops = try #require(TuningTemplates.template(id: "g6-standard-eb")).makeTuning()
        #expect(drops.spelledNotes.map(\.description) == ["E♭2", "A♭2", "D♭3", "G♭3", "B♭3", "E♭4"])
        let fs = try #require(TuningTemplates.template(id: "g8-standard-fs")).makeTuning()
        #expect(fs.spelledNotes.first?.description == "F♯1")
        let openD = try #require(TuningTemplates.template(id: "g6-open-d")).makeTuning()
        #expect(openD.spelledNotes[3].description == "F♯3")
    }

    @Test func mandolinHasUnisonPairs() throws {
        let instrument = try #require(TuningTemplates.template(id: "mandolin-standard")).makeInstrument()
        #expect(instrument.courses.allSatisfy { $0.pairing == .unison && $0.strings.count == 2 })
        #expect(instrument.fits(instrument.currentTuning!))
    }

    @Test("PR-5: A4 inherits the default until set")
    func a4Inheritance() {
        var tuning = Tuning(name: "x", openCents: [[0]])
        #expect(tuning.effectiveA4(default: 442) == 442)
        tuning.a4 = 432
        #expect(tuning.effectiveA4(default: 442) == 432)
    }

    @Test("PR-3: all strings a semitone down")
    func shift() throws {
        let tuning = try #require(TuningTemplates.template(id: "g7-standard-b")).makeTuning().shifted(bySemitones: -1)
        #expect(!tuning.isTemplateCopy)
        #expect(tuning.coursePitches.first == note("B♭1"))
    }

    @Test("6.1 п. 19: library filtered by type and string count")
    func compatibleTemplates() throws {
        let seven = try #require(TuningTemplates.template(id: "g7-standard-b")).makeInstrument()
        let ids = TuningTemplates.compatible(with: seven).map(\.id)
        #expect(ids.allSatisfy { $0.hasPrefix("g7-") })
        #expect(ids.count == 12)
        #expect(throws: EditError.shapeMismatch) {
            try InstrumentEditing.adding(TuningTemplates.template(id: "g8-drop-e")!, to: seven)
        }
        let withDropA = try InstrumentEditing.adding(TuningTemplates.template(id: "g7-drop-a")!, to: seven)
        #expect(withDropA.tunings.count == 2)
        #expect(withDropA.currentTuning?.templateId == "g7-drop-a")
    }

    @Test("6.1 п. 20: adding strings by a fourth")
    func addStrings() throws {
        let seven = try #require(TuningTemplates.template(id: "g7-standard-b")).makeInstrument()
        let (low, report) = InstrumentEditing.changingStringCount(of: seven, to: 8, side: .low)
        #expect(low.courses.count == 8)
        #expect(low.currentTuning!.spelledNotes == TuningTemplates.template(id: "g8-standard-fs")!.notes)
        #expect(report.needsManualTuning.isEmpty)
        #expect(low.currentTuning!.isTemplateCopy == false)

        let (high, _) = InstrumentEditing.changingStringCount(of: seven, to: 9, side: .high)
        #expect(high.currentTuning!.coursePitches.suffix(2) == [note("A4"), note("D5")])

        let (fewer, _) = InstrumentEditing.changingStringCount(of: seven, to: 6, side: .low)
        #expect(fewer.currentTuning!.spelledNotes == TuningTemplates.template(id: "g6-standard-e")!.notes)
    }

    @Test("Names follow the string count: automatic instrument name and «Стандарт X»; typed names stay")
    func renameAfterResize() throws {
        let seven = try #require(TuningTemplates.template(id: "g7-standard-b")).makeInstrument()
        #expect(seven.name == "7-струнная гитара")
        let (low, _) = InstrumentEditing.changingStringCount(of: seven, to: 8, side: .low)
        #expect(low.name == "8-струнная гитара")
        #expect(low.currentTuning!.name == "Стандарт F♯")
        let (fewer, _) = InstrumentEditing.changingStringCount(of: seven, to: 6, side: .low)
        #expect(fewer.currentTuning!.name == "Стандарт E")

        var custom = seven
        custom.name = "Моя Ибанез"
        custom.tunings[0].name = "Для риффов"
        let (kept, _) = InstrumentEditing.changingStringCount(of: custom, to: 8, side: .low)
        #expect(kept.name == "Моя Ибанез")
        #expect(kept.currentTuning!.name == "Для риффов")

        // Drop tunings are not the standard pattern: their name stays.
        let drop = try InstrumentEditing.adding(TuningTemplates.template(id: "g7-drop-a")!, to: seven)
        let (dropLow, _) = InstrumentEditing.changingStringCount(of: drop, to: 8, side: .low)
        #expect(dropLow.tunings.contains { $0.name.hasPrefix("Drop") })
    }

    @Test("Tuning down a half step spells E♭ standard, not D♯")
    func halfStepDownSpelling() throws {
        let six = try #require(TuningTemplates.template(id: "g6-standard-e")).makeInstrument()
        let down = six.currentTuning!.shifted(bySemitones: -1)
        #expect(down.spelledNotes.map(\.name.description) == ["E♭", "A♭", "D♭", "G♭", "B♭", "E♭"])
    }

    @Test("6.1 п. 20: types without a template copy the neighbour and ask for manual tuning")
    func addStringWithoutTemplate() throws {
        let mandolin = try #require(TuningTemplates.template(id: "mandolin-standard")).makeInstrument()
        let (result, report) = InstrumentEditing.changingStringCount(of: mandolin, to: 5, side: .high)
        #expect(report.needsManualTuning == [4])
        #expect(result.currentTuning!.openCents[4] == mandolin.currentTuning!.openCents[3])
        #expect(result.courses[4].pairing == .unison)
        #expect(result.fits(result.currentTuning!))
    }

    @Test func pairingChange() throws {
        let six = try #require(TuningTemplates.template(id: "g6-standard-e")).makeInstrument()
        let (twelve, _) = InstrumentEditing.changingPairing(of: six, course: 0, to: .octave)
        #expect(twelve.currentTuning!.openCents[0] == [note("E2").cents, note("E3").cents])
        #expect(twelve.fits(twelve.currentTuning!))
    }

    @Test func lastTuningCannotBeDeleted() throws {
        var instrument = try #require(TuningTemplates.template(id: "g6-standard-e")).makeInstrument()
        #expect(throws: EditError.cannotDeleteLastTuning) {
            try instrument.deleteTuning(id: instrument.tunings[0].id)
        }
    }
}
