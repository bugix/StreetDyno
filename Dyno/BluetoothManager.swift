import Combine
import CoreBluetooth
import Foundation

// MARK: - BluetoothManager

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!

    @Published var discoveredPeripherals: [ScannedPeripheral] = []
    @Published var isScanning: Bool = false

    private var peripheralsSet: Set<UUID> = []

    private var scanTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
        else {
            print("Bluetooth not available")
            stopScanning()
        }
    }

    func startScanning() {
        peripheralsSet.removeAll()
        discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        DispatchQueue.main.async {
            self.isScanning = true
        }
        print("Started scanning...")

        // Auto-stop after 5 seconds
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        DispatchQueue.main.async {
            self.isScanning = false
        }
        scanTimer?.invalidate()
        scanTimer = nil
        print("Stopped scanning.")
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

        DispatchQueue.main.async {
            self.discoveredPeripherals.append(scanned)
        }
    }
}
