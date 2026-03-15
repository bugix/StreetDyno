@preconcurrency import CoreBluetooth
@preconcurrency import Dependencies
import Observation
import SwiftUI

@Observable
@MainActor
final class BluetoothModel {
    @ObservationIgnored
    @Dependency(BluetoothClient.self) var bluetooth

    func task() async {
        do {
            for try await scanned in await bluetooth.startScanning() {
                let localName = scanned.advertisementData["kCBAdvDataLocalName"] as? String
                guard localName == "StreetDyno" else { continue }
                for try await value in await bluetooth.readCharacteristic(scanned.peripheral, CBUUID(string: "2222")) {
                    print(value)
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
        EmptyView()
            .task {
                await model.task()
            }
    }
}
