@preconcurrency import CoreBluetooth
import Dependencies
import DependenciesMacros
import Foundation

struct ScannedPeripheral: Identifiable, @unchecked Sendable {
    var id: UUID { peripheral.identifier }
    let peripheral: CBPeripheral
    let rssi: Int
    let advertisementData: [String: Any]
}

@DependencyClient
public struct BluetoothClient: Sendable {
    var startScanning: @Sendable () async -> AsyncThrowingStream<ScannedPeripheral, Error> = { .finished() }
    var connect: @Sendable (CBPeripheral) async -> AsyncThrowingStream<String, Error> = { _ in .finished() }
    var readCharacteristic: @Sendable (CBPeripheral, CBUUID) async -> AsyncThrowingStream<Int, Error> = { _, _ in .finished() }
}

extension BluetoothClient: DependencyKey {
    public static var liveValue: BluetoothClient {
        let bluetooth = Bluetooth()
        return BluetoothClient(
            startScanning: {
                await bluetooth.startScanning()
            },
            connect: { peripheral in
                await bluetooth.connect(peripheral)
            },
            readCharacteristic: { peripheral, uuid in
                await bluetooth.readCharacteristic(peripheral, uuid)
            }
        )
    }
}

enum BluetoothError: Error {
    case unavailable
    case connectionFailed
    case characteristicNotFound
}

@MainActor
final class Bluetooth {
    private var bluetoothDelegate: BluetoothDelegate?
    private var connectDelegate: ConnectDelegate?
    private var peripheralDelegate: PeripheralDelegate?

    func startScanning() -> AsyncThrowingStream<ScannedPeripheral, Error> {
        bluetoothDelegate = nil
        return AsyncThrowingStream { continuation in
            let delegate = BluetoothDelegate(continuation: continuation)
            self.bluetoothDelegate = delegate
        }
    }

    func connect(_ peripheral: CBPeripheral) -> AsyncThrowingStream<String, Error> {
        connectDelegate = nil
        return AsyncThrowingStream { continuation in
            let delegate = ConnectDelegate(peripheralIdentifier: peripheral.identifier, continuation: continuation)
            self.connectDelegate = delegate
        }
    }

    func readCharacteristic(_ peripheral: CBPeripheral, _ characteristicUUID: CBUUID) -> AsyncThrowingStream<Int, Error> {
        peripheralDelegate = nil
        return AsyncThrowingStream { continuation in
            let delegate = PeripheralDelegate(
                peripheralIdentifier: peripheral.identifier,
                characteristicUUID: characteristicUUID,
                continuation: continuation
            )
            self.peripheralDelegate = delegate
        }
    }
}

private class BluetoothDelegate: NSObject, CBCentralManagerDelegate {
    private let continuation: AsyncThrowingStream<ScannedPeripheral, Error>.Continuation
    private var centralManager: CBCentralManager!
    private var peripheralsSet: Set<UUID> = []
    private var scanTimer: Timer?

    init(continuation: AsyncThrowingStream<ScannedPeripheral, Error>.Continuation) {
        self.continuation = continuation
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            continuation.finish(throwing: BluetoothError.unavailable)
        }
    }

    private func startScanning() {
        peripheralsSet.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }

    private func stopScanning() {
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        continuation.finish()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard !peripheralsSet.contains(peripheral.identifier) else { return }
        peripheralsSet.insert(peripheral.identifier)

        let scanned = ScannedPeripheral(
            peripheral: peripheral,
            rssi: RSSI.intValue,
            advertisementData: advertisementData
        )
        continuation.yield(scanned)
    }
}

private class ConnectDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private var centralManager: CBCentralManager!
    private let peripheralIdentifier: UUID
    private var peripheral: CBPeripheral?
    private var pendingServices = 0

    init(peripheralIdentifier: UUID, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.peripheralIdentifier = peripheralIdentifier
        self.continuation = continuation
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let peripheral = self.peripheral else { return }
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            guard let retrieved = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier]).first else {
                continuation.finish(throwing: BluetoothError.connectionFailed)
                return
            }
            peripheral = retrieved
            retrieved.delegate = self
            centralManager.connect(retrieved)
        } else {
            continuation.finish(throwing: BluetoothError.unavailable)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        continuation.finish(throwing: error ?? BluetoothError.connectionFailed)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            continuation.finish()
            return
        }
        pendingServices = services.count
        for service in services {
            continuation.yield("Service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        for characteristic in service.characteristics ?? [] {
            continuation.yield("  Characteristic: \(characteristic.uuid) properties=\(characteristic.properties.rawValue)")
        }
        pendingServices -= 1
        if pendingServices == 0 {
            continuation.finish()
        }
    }
}

private class PeripheralDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let continuation: AsyncThrowingStream<Int, Error>.Continuation
    private var centralManager: CBCentralManager!
    private let peripheralIdentifier: UUID
    private var peripheral: CBPeripheral?
    private let characteristicUUID: CBUUID

    init(
        peripheralIdentifier: UUID,
        characteristicUUID: CBUUID,
        continuation: AsyncThrowingStream<Int, Error>.Continuation
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.characteristicUUID = characteristicUUID
        self.continuation = continuation
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let peripheral = self.peripheral else { return }
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            guard let retrieved = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier]).first else {
                continuation.finish(throwing: BluetoothError.connectionFailed)
                return
            }
            peripheral = retrieved
            retrieved.delegate = self
            centralManager.connect(retrieved)
        } else {
            continuation.finish(throwing: BluetoothError.unavailable)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        continuation.finish(throwing: error ?? BluetoothError.connectionFailed)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        peripheral.services?.forEach { service in
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID })
        else { return }

        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            continuation.finish(throwing: error)
            return
        }
        guard let data = characteristic.value, !data.isEmpty else { return }
        var value = 0
        for (index, byte) in data.prefix(MemoryLayout<Int>.size).enumerated() {
            value |= Int(byte) << (index * 8)
        }
        continuation.yield(value)
    }
}

extension DependencyValues {
    public var bluetoothClient: BluetoothClient {
        get { self[BluetoothClient.self] }
        set { self[BluetoothClient.self] = newValue }
    }
}
