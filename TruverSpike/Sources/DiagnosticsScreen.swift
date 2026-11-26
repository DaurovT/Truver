import SwiftUI

/// Stage-0 spike checks (DEVELOPMENT.md, "Что проверить в спайке на устройстве").
struct DiagnosticsScreen: View {
    @Environment(SpikeModel.self) private var model

    @AppStorage("check.au6.volume") private var volume = false
    @AppStorage("check.au6.lows") private var lows = false
    @AppStorage("check.au5.gap") private var gap = false
    @AppStorage("check.au7.unplug") private var unplug = false
    @AppStorage("check.au3.bluetooth") private var bluetooth = false
    @AppStorage("check.me4.background") private var background = false
    @AppStorage("check.tuner.live") private var live = false
    @AppStorage("check.mac.devices") private var macDevices = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Звук") {
                LabeledContent("Сессия", value: model.sessionRole)
                LabeledContent("Задержка", value: model.latencyText)
                #if os(iOS)
                Toggle("Режим .measurement (AU-1)", isOn: $model.useMeasurementMode)
                    .onChange(of: model.useMeasurementMode) { model.applyMeasurementModeChange() }
                #endif
                Stepper("Канал входа: \(model.inputChannel + 1)", value: $model.inputChannel, in: 0...7)
                Button("Обновить") { model.refreshDiagnostics() }
            }

            Section("Входы") {
                #if os(macOS)
                Picker("Устройство", selection: $model.selectedDeviceID) {
                    Text("По умолчанию").tag(Optional<UInt32>.none)
                    ForEach(model.macDevices) { device in
                        Text("\(device.name) (\(device.inputChannels))").tag(Optional(device.id))
                    }
                }
                #else
                ForEach(Array(model.inputDescriptions.enumerated()), id: \.offset) { index, text in
                    Button(text) { model.selectInput(index) }
                }
                #endif
                if model.inputDescriptions.isEmpty { Text("Нет входов").foregroundStyle(.secondary) }
            }

            Section("A4") {
                Stepper("A4 = \(Int(model.a4)) Гц", value: $model.a4, in: 415...466, step: 1)
            }

            Section("Чек-лист спайка") {
                Toggle("AU-6: метроном достаточно громкий в .measurement", isOn: $volume)
                Toggle("AU-6: B0 и B1 читаются в .default", isOn: $lows)
                Toggle("AU-5: разрыв щелчка при включении микрофона приемлем", isOn: $gap)
                Toggle("AU-7: выдернул интерфейс — тюнер продолжил с микрофона", isOn: $unplug)
                Toggle("AU-3: Bluetooth — вход встроенный, звук в наушниках", isOn: $bluetooth)
                Toggle("ME-4: метроном играет в фоне и на блокировке", isOn: $background)
                Toggle("Тюнер на живой гитаре: стрелка в ±2 ц на выдержанной ноте", isOn: $live)
                Toggle("Mac: интерфейс виден, Hi-Z вход выбирается", isOn: $macDevices)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshDiagnostics() }
    }
}
