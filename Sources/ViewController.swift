import UIKit
import WebKit

/// 画面全体にWebView(今までのリモコンUI)を表示し、
/// JavaScriptの送信要求をSwift側のBluetooth(BleManager)へ橋渡しする。
class ViewController: UIViewController, WKScriptMessageHandler, BleManagerDelegate {

    private var webView: WKWebView!
    private let ble = BleManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x15/255.0, green: 0x17/255.0, blue: 0x1c/255.0, alpha: 1)

        let ucc = WKUserContentController()
        ucc.add(self, name: "native")               // JS: window.webkit.messageHandlers.native
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc
        cfg.allowsInlineMediaPlayback = true

        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view.addSubview(webView)

        ble.delegate = self

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // JS → Swift
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let t = body["t"] as? String else { return }
        switch t {
        case "scan":       ble.startScan()
        case "disconnect": ble.disconnect()
        case "tx":         if let v = body["v"] as? String { ble.send(v) }
        default:           break
        }
    }

    // Swift → JS (接続状態の反映)
    func bleStatusChanged(connected: Bool, text: String?) {
        let state = connected ? "connected" : "disconnected"
        let js = "window.nativeStatus && window.nativeStatus('\(state)', \(jsArg(text)))"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func jsArg(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "undefined" }
        let esc = s.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "'", with: "\\'")
                   .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(esc)'"
    }
}
