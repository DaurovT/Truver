import SwiftUI
import TruverDSP
import TruverTheory

struct TunerScreen: View {
    @Environment(SpikeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 20) {
            Picker("Строй", selection: $model.templateId) {
                ForEach(TuningTemplates.all) { template in
                    Text(template.names.ru).tag(template.id)
                }
            }
            .pickerStyle(.menu)

            Spacer(minLength: 0)
            readout
            Spacer(minLength: 0)

            strings

            Picker("Режим", selection: modeBinding) {
                Text("Авто").tag(0)
                Text("Хроматический").tag(1)
            }
            .pickerStyle(.segmented)

            controls
        }
        .padding()
        .task { await model.startTuner() }
    }

    private var modeBinding: Binding<Int> {
        Binding(get: { model.targetMode == .chromatic ? 1 : 0 },
                set: { model.targetMode = $0 == 1 ? .chromatic : .auto })
    }

    @ViewBuilder private var readout: some View {
        if model.micDenied {
            stateText("Нужен доступ к микрофону", detail: "Настройки → Конфиденциальность → Микрофон")
        } else if model.needsMicrophoneButton {
            VStack(spacing: 8) {
                Button("Включить микрофон") { Task { await model.startTuner(userConfirmedGap: true) } }
                    .buttonStyle(.borderedProminent)
                Text("Щелчок метронома на долю секунды прервётся").font(.footnote).foregroundStyle(.secondary)
            }
        } else if let error = model.lastError {
            stateText("Звук недоступен", detail: error)
        } else {
            switch model.display {
            case .idle: stateText("Сыграйте струну", detail: model.tunerRunning ? nil : "Тюнер остановлен")
            case .listening: stateText("Слушаю…", detail: nil)
            case .outOfRange: stateText("Вне диапазона", detail: nil)
            case .reading(let reading): ReadingView(reading: reading)
            }
        }
    }

    private func stateText(_ title: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title2.weight(.semibold))
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(height: 220)
    }

    private var strings: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.tuning.coursePitches.indices), id: \.self) { course in
                    let ref = StringRef(course: course)
                    Button {
                        model.tapString(course)
                    } label: {
                        VStack(spacing: 2) {
                            Text(model.noteName(for: ref)).font(.callout.monospaced())
                            Image(systemName: model.tuned.contains(ref) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.tuned.contains(ref) ? .green : .secondary)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.targetMode == .manual(course) ? .orange : .gray)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            if model.allTuned { Label("Готово", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
            Spacer()
            Button("Сбросить отметки") { model.resetTunedMarks() }
            Button(model.tunerRunning ? "Стоп" : "Слушать") {
                if model.tunerRunning { model.stopTuner() } else { Task { await model.startTuner(userConfirmedGap: true) } }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ReadingView: View {
    @Environment(SpikeModel.self) private var model
    let reading: TunerReading

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 72, weight: .bold, design: .rounded))
            Needle(cents: reading.target.deviationCents)
                .frame(height: 36)
            Text(String(format: "%+.1f ц · %.2f Гц", reading.target.deviationCents, reading.frequency))
                .font(.title3.monospacedDigit())
            Text(hint).font(.headline).foregroundStyle(hintColor)
            if case let .chromatic(_, _, h?) = reading.target {
                Text("ближайшая струна \(model.noteName(for: h.string)), \(String(format: "%+.0f", h.deviationCents)) ц")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if reading.isProvisional { Text("предварительно").font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(height: 220)
    }

    private var title: String {
        switch reading.target {
        case let .string(ref, _, _): return model.noteName(for: ref)
        case let .chromatic(nearest, _, _): return model.noteName(for: nearest)
        }
    }

    private var hint: String {
        let d = reading.target.deviationCents
        if abs(d) <= 3 { return "в строю" }
        return d < 0 ? "ниже — подтяните" : "выше — ослабьте"
    }

    private var hintColor: Color { abs(reading.target.deviationCents) <= 3 ? .green : .orange }
}

/// ±50 cent needle; the colour is doubled by the sign and the text (NFR accessibility).
struct Needle: View {
    let cents: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = width / 2 + CGFloat(max(-50, min(50, cents)) / 50) * (width / 2 - 4)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 6).frame(maxHeight: .infinity)
                Rectangle().fill(.secondary).frame(width: 2).position(x: width / 2, y: geo.size.height / 2)
                Capsule().fill(abs(cents) <= 3 ? Color.green : Color.orange)
                    .frame(width: 6, height: geo.size.height)
                    .position(x: x, y: geo.size.height / 2)
                    .animation(.easeOut(duration: 0.08), value: cents)
            }
        }
        .accessibilityLabel(String(format: "%+.0f центов", cents))
    }
}
