import SwiftUI

struct MetronomeScreen: View {
    @Environment(SpikeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 20) {
                Text("\(Int(model.metronomeRunning ? model.liveBPM : model.bpm))")
                    .font(.system(size: 88, weight: .bold, design: .rounded).monospacedDigit())
                    .onTapGesture(count: 2) { model.toggleMetronome() }   // 6: double tap = start/stop
                Text("BPM").font(.caption).foregroundStyle(.secondary)

                beats

                HStack {
                    Button { model.bpm = max(20, model.bpm - 1) } label: { Image(systemName: "minus") }
                    Slider(value: $model.bpm, in: 20...400, step: 1)
                    Button { model.bpm = min(400, model.bpm + 1) } label: { Image(systemName: "plus") }
                }
                .buttonStyle(.bordered)

                HStack {
                    Button("Tap") { model.tap() }.buttonStyle(.bordered)
                    Spacer()
                    Button(model.metronomeRunning ? "Стоп" : "Старт") { model.toggleMetronome() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Stepper("Долей в такте: \(model.numerator)", value: $model.numerator, in: 1...12)
                Stepper("Деление доли: \(model.subdivision)", value: $model.subdivision, in: 1...9)
                if model.subdivision % 2 == 0 {
                    VStack(alignment: .leading) {
                        Text("Свинг: \(Int(model.swing * 100))%")
                        Slider(value: $model.swing, in: 0.5...0.75)
                    }
                }
                Picker("Режим", selection: $model.modeChoice) {
                    ForEach(MetronomeModeChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                #if os(iOS)
                Toggle("Вибрация в такт", isOn: $model.vibration)
                #endif

                if let notice = model.lastNotice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                }
                if let error = model.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    /// Beat strip: the flash is the strip, not the whole screen (6.1 п. 9).
    private var beats: some View {
        HStack(spacing: 8) {
            ForEach(0..<model.numerator, id: \.self) { beat in
                RoundedRectangle(cornerRadius: 6)
                    .fill(color(for: beat))
                    .frame(height: 28)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if model.metronomeRunning {
                Text(model.silentBar ? "такт \(model.currentBar + 1) · тихий" : "такт \(model.currentBar + 1)")
                    .font(.caption2).foregroundStyle(.secondary).offset(y: 18)
            }
        }
        .padding(.bottom, 12)
    }

    private func color(for beat: Int) -> Color {
        guard model.metronomeRunning, model.currentBeat == beat, !model.silentBar else { return Color.gray.opacity(0.25) }
        return model.flashOn ? (beat == 0 ? .orange : .yellow) : Color.gray.opacity(0.6)
    }
}
