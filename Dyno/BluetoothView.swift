import CoreBluetooth
import SwiftUI

struct BluetoothView: View {
    @StateObject var bluetoothManager = BluetoothManager()
    @State private var searchText = ""

    // Hardcoded name to check for
    let targetName = "My Device Name"

    // Filtered list with search
    var filteredPeripherals: [ScannedPeripheral] {
        if searchText.isEmpty {
            return bluetoothManager.discoveredPeripherals
        }
        else {
            return bluetoothManager.discoveredPeripherals.filter {
                $0.peripheral.name?.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }

    // Devices matching the target name
    var matchedDevices: [ScannedPeripheral] {
        filteredPeripherals.filter { $0.peripheral.name == targetName }
    }

    // Devices NOT matching the target name
    var otherDevices: [ScannedPeripheral] {
        filteredPeripherals.filter { $0.peripheral.name != targetName }
    }

    var body: some View {
        NavigationView {
            VStack {
                if bluetoothManager.isScanning {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Scanning...")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .padding(8)
                }

                List {
                    // Section 1: Target device(s) or error
                    Section(header: Text("Target Device")) {
                        if matchedDevices.isEmpty {
                            Text("ERROR: Device '\(targetName)' not found.")
                                .foregroundColor(.red)
                        }
                        else {
                            ForEach(matchedDevices) { scanned in
                                NavigationLink(destination: BluetoothDetailView(scanned: scanned)) {
                                    VStack(alignment: .leading) {
                                        Text(scanned.peripheral.name ?? "Unknown Device")
                                            .font(.headline)
                                        Text("RSSI: \(scanned.rssi) | UUID: \(scanned.peripheral.identifier.uuidString)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }

                    // Section 2: Other devices
                    Section(header: Text("Other Devices")) {
                        if otherDevices.isEmpty {
                            Text("No other devices found.")
                                .foregroundColor(.secondary)
                        }
                        else {
                            ForEach(otherDevices) { scanned in
                                NavigationLink(destination: BluetoothDetailView(scanned: scanned)) {
                                    VStack(alignment: .leading) {
                                        Text(scanned.peripheral.name ?? "Unknown Device")
                                            .font(.headline)
                                        Text("RSSI: \(scanned.rssi) | UUID: \(scanned.peripheral.identifier.uuidString)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("Bluetooth Devices")
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        bluetoothManager.stopScanning()
                        bluetoothManager.startScanning()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Bluetooth Scan")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct BluetoothDetailView: View {
    let scanned: ScannedPeripheral

    var body: some View {
        List {
            Section(header: Text("Device Info")) {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(scanned.peripheral.name ?? "Unknown")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("UUID")
                    Spacer()
                    Text(scanned.peripheral.identifier.uuidString)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                HStack {
                    Text("RSSI")
                    Spacer()
                    Text("\(scanned.rssi)")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Advertisement Data")) {
                ForEach(scanned.advertisementData.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key)
                        Spacer()
                        Text("\(String(describing: scanned.advertisementData[key]!))")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(scanned.peripheral.name ?? "Device Details")
    }
}
