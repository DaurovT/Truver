import Testing
@testable import TruverTheory

@Suite("Tuning library")
struct TuningLibraryTests {
    @Test("Ids are unique")
    func uniqueIds() {
        let ids = TuningTemplates.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("No two templates of one instrument sound the same")
    func noDuplicates() {
        var seen: [String: String] = [:]
        for t in TuningTemplates.all {
            let key = "\(t.type)-\(t.courseCount)-" + t.notes.map { String($0.pitch.cents) }.joined(separator: ",")
            #expect(seen[key] == nil, "\(t.id) repeats \(seen[key] ?? "")")
            seen[key] = t.id
        }
    }

    @Test("Kinds follow the library chips")
    func kinds() {
        func kind(_ id: String) -> TuningCategory? { TuningTemplates.template(id: id)?.category }
        #expect(kind("g6-open-em") == .open)
        #expect(kind("g6-double-drop-d") == .drop)
        #expect(kind("g6-standard-c") == .lower)
        #expect(kind("g6-csus2") == .alternative)
        #expect(kind("g6-nst") == .alternative)
        #expect(kind("g7-russian-minor") == .open)
        #expect(kind("b4-standard") == .standard)
        #expect(kind("b4-standard-b") == .lower)
    }

    @Test("Every template has a popularity rank, and the standard leads each instrument")
    func popularity() {
        #expect(Set(TuningTemplates.popularity) == Set(TuningTemplates.all.map(\.id)))
        let ordered = TuningTemplates.byPopularity(TuningTemplates.all)
        for t in TuningTemplates.all {
            let first = ordered.first { $0.type == t.type && $0.courseCount == t.courseCount }
            #expect(first?.id.contains("standard") == true || first?.type == .guitarExtendedHigh)
        }
    }

    @Test("Library: sections standard, lower, drop, open, alternative")
    func libraryOrder() {
        let six = TuningTemplates.template(id: "g6-standard-e")!.makeInstrument()
        let ids = TuningTemplates.library(for: six).map(\.id)
        #expect(Array(ids.prefix(3)) == ["g6-standard-e", "g6-standard-eb", "g6-standard-d"])
        #expect(ids.firstIndex(of: "g6-drop-d")! < ids.firstIndex(of: "g6-open-c")!)
    }
}
