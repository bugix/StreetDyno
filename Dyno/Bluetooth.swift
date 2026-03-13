import CoreBluetooth
import Dependencies
import DependenciesMacros
import Foundation

struct ScannedPeripheral: Identifiable {
    var id: UUID { peripheral.identifier }
    let peripheral: CBPeripheral
    let rssi: Int
    let advertisementData: [String: Any]
}

@DependencyClient
struct BluetoothClient {
    var startScanning: @Sendable () async -> AsyncThrowingStream<ScannedPeripheral, Error> = { .finished() }
}

extension BluetoothClient: DependencyKey {
    static var liveValue: BluetoothClient {
        let bluetooth = Bluetooth()
        return BluetoothClient(
            startScanning: {
                await bluetooth.startScanning()
            }
        )
    }

}

actor Bluetooth {
    private var scanningContinuation: AsyncThrowingStream<ScannedPeripheral, Error>.Continuation?

    func startScanning() -> AsyncThrowingStream<ScannedPeripheral, Error> {
        AsyncThrowingStream { continuation in
            self.scanningContinuation = continuation
            struct MyError: Error {}
            continuation.finish(throwing: MyError())
        }
    }
}
