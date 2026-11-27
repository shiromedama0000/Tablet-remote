import CoreBluetooth
import Foundation

protocol BleManagerDelegate: AnyObject {
    func bleStatusChanged(connected: Bool, text: String?)
}

final class BleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    weak var delegate: BleManagerDelegate?

    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var wantScan = false

    private var txQueue: [Data] = []
    private var txBusy = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        wantScan = true
        if central.state == .poweredOn {
            beginScan()
        } else {
            delegate?.bleStatusChanged(connected: false, text: "Bluetoothの準備中…")
        }
    }

    private func beginScan() {
        delegate?.bleStatusChanged(connected: false, text: "タブレットを探しています…")
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    func disconnect() {
        wantScan = false
        central.stopScan()
        txQueue.removeAll()
        txBusy = false
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }

    func send(_ text: String) {
        let data = Data(text.utf8)
        var i = 0
        while i < data.count {
            let end = min(i + 20, data.count)
            txQueue.append(data.subdata(in: i..<end))
            i = end
        }
        if txQueue.count > 400 {
            txQueue.removeFirst(txQueue.count - 150)
        }
        pump()
    }

    private func pump() {
        guard !txBusy, let p = peripheral, let c = rxChar, !txQueue.isEmpty else { return }
        txBusy = true
        let chunk = txQueue.removeFirst()
        p.writeValue(chunk, for: c, type: .withResponse)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            if wantScan { beginScan() }
        case .poweredOff:
            delegate?.bleStatusChanged(connected: false, text: "Bluetoothをオンにしてください")
        case .unauthorized:
            delegate?.bleStatusChanged(connected: false, text: "設定でBluetoothの許可が必要です")
        default:
            break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        c.stopScan()
        peripheral = p
        p.delegate = self
        delegate?.bleStatusChanged(connected: false, text: "接続中…")
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        delegate?.bleStatusChanged(connected: false, text: "接続に失敗しました")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        rxChar = nil
        peripheral = nil
        txQueue.removeAll()
        txBusy = false
        delegate?.bleStatusChanged(connected: false, text: "切断されました")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        p.discoverCharacteristics([rxUUID], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let c = service.characteristics?.first(where: { $0.uuid == rxUUID }) {
            rxChar = c
            delegate?.bleStatusChanged(connected: true, text: nil)
            pump()
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        txBusy = false
        pump()
    }
}
