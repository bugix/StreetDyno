@preconcurrency import CoreBluetooth
@preconcurrency import Dependencies
import Observation
import SwiftUI

@Observable
@MainActor
final class BluetoothModel {
    @ObservationIgnored
    @Dependency(BluetoothClient.self) var bluetooth

    var value = 0

    @ObservationIgnored
    private var resetTask: Task<Void, Never>?

    func task() async {
        do {
            for try await scanned in await bluetooth.startScanning() {
                let localName = scanned.advertisementData["kCBAdvDataLocalName"] as? String
                guard localName == "StreetDyno" else { continue }
                print(localName)
                for try await value in await bluetooth.readCharacteristic(scanned.peripheral, CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")) {
                    self.value = value
                    resetTask?.cancel()
                    resetTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 1000)) { self.value = 0 }
                    }
                }
                break
            }
        } catch {
            print(error)
        }
    }
}

struct BluetoothView: View {
    @State var model = BluetoothModel()

    var body: some View {
        Gauge(value: $model.value)
            .task { await model.task() }
    }
}
