import CoreBluetooth
import Foundation

protocol BleManagerDelegate: AnyObject {
    func bleStatusChanged(connected: Bool, text: String?)
}

/// iPhone = セントラル。タブレット(ペリフェラル)が広告している
/// Nordic UART Service を探して自動接続し、RXキャラクタリスティックへ書き込む。
/// プロトコルはWi-Fi/Web版と同一(改行区切りの文字列)。
final class BleManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    weak var delegate: BleManagerDelegate?

    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID      = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxChar: CBCharacteristic?
    private var wantScan = false

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
        if let p = peripheral {
            central.cancelPeripheralConnection(p)
        }
    }

    /// 改行区切りの文字列を20バイトずつ書き込む(タブレット側が改行で再結合する)
    func send(_ text: String) {
        guard let p = peripheral, let c = rxChar else { return }
        let data = Data(text.utf8)
        var i = 0
        let step = 20
        while i < data.count {
            let end = min(i + step, data.count)
            p.writeValue(data.subdata(in: i..<end), for: c, type: .withoutResponse)
            i = end
        }
    }

    // MARK: - CBCentralManagerDelegate

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
        // 自前の固有サービスなので、最初に見つかった機器へ接続する
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
        delegate?.bleStatusChanged(connected: false, text: "切断されました")
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let svc = p.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        p.discoverCharacteristics([rxUUID], for: svc)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let c = service.characteristics?.first(where: { $0.uuid == rxUUID }) {
            rxChar = c
            delegate?.bleStatusChanged(connected: true, text: nil)
        }
    }
}
