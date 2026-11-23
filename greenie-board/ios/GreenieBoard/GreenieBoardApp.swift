import SwiftUI
import UIKit
import WebKit

// The iPhone app is a thin wrapper around the Greenie Board web page.
// The page's own files (index.html, grade.js, grt-log.js, runways.json) are
// copied into the app when it is built, so the app works with no internet and
// grades landings exactly the way the web page does.

@main
struct GreenieBoardApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                // Fills the strip behind the clock and battery so it matches the page header.
                Color(red: 0x0f / 255, green: 0x1f / 255, blue: 0x33 / 255).ignoresSafeArea()
                BoardWebView().ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

struct BoardWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Pages are served from the app bundle under greenie://app/ so that the
        // page can read runways.json and keep its board in storage that lasts.
        config.setURLSchemeHandler(BundleFileServer(), forURLScheme: BundleFileServer.scheme)
        config.websiteDataStore = .default()

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "saveFile")
        controller.addUserScript(WKUserScript(source: Coordinator.saveFileHook,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.load(URLRequest(url: URL(string: "\(BundleFileServer.scheme)://app/index.html")!))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        // The page saves its backup by "downloading" a file. Inside the app that
        // file is handed to the iPhone share sheet instead, so it can be saved to
        // Files or Dropbox.
        static let saveFileHook = """
        (function(){
          var click = HTMLAnchorElement.prototype.click;
          HTMLAnchorElement.prototype.click = function(){
            if (this.download && /^blob:/.test(this.href)) {
              var name = this.download;
              fetch(this.href).then(function(r){ return r.text(); }).then(function(text){
                window.webkit.messageHandlers.saveFile.postMessage({ name: name, text: text });
              });
              return;
            }
            return click.apply(this, arguments);
          };
        })();
        """

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "saveFile",
                  let body = message.body as? [String: Any],
                  let text = body["text"] as? String else { return }
            let rawName = (body["name"] as? String) ?? "greenie-board-backup.json"
            let name = rawName.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return
            }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            guard let top = Self.topViewController() else { return }
            sheet.popoverPresentationController?.sourceView = top.view
            top.present(sheet, animated: true)
        }

        // Links to web sites open in Safari; everything else stays in the app.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.url, let scheme = url.scheme?.lowercased(),
               ["http", "https", "mailto", "tel"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // A link that asks for a new window opens in Safari too.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.url { UIApplication.shared.open(url) }
            return nil
        }

        // Ordinary page messages and yes/no questions, shown as iPhone alerts.
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            guard let top = Self.topViewController() else { completionHandler(); return }
            top.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            guard let top = Self.topViewController() else { completionHandler(false); return }
            top.present(alert, animated: true)
        }

        static func topViewController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive } ??
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }
}

/// Serves the web page's files from inside the app.
final class BundleFileServer: NSObject, WKURLSchemeHandler {
    static let scheme = "greenie"

    private static let types: [String: String] = [
        "html": "text/html",
        "js": "text/javascript",
        "json": "application/json",
        "png": "image/png",
        "css": "text/css",
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var name = url.lastPathComponent
        if name.isEmpty || name == "/" { name = "index.html" }
        let ext = (name as NSString).pathExtension.lowercased()
        let base = (name as NSString).deletingPathExtension

        guard let type = Self.types[ext],
              let fileURL = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Web"),
              let data = try? Data(contentsOf: fileURL) else {
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": type + (type.hasPrefix("text/") ? "; charset=utf-8" : ""),
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
