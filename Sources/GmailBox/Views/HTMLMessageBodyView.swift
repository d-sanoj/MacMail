import SwiftUI
import WebKit

struct HTMLMessageBodyView: View {
    let html: String
    @State private var contentHeight: CGFloat = 260

    var body: some View {
        HTMLWebView(html: html, contentHeight: $contentHeight)
            .frame(minHeight: 120, idealHeight: contentHeight, maxHeight: contentHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(Color.white)
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let wrappedHTML = htmlDocument(for: html)
        if context.coordinator.lastHTML != wrappedHTML {
            context.coordinator.lastHTML = wrappedHTML
            webView.loadHTMLString(wrappedHTML, baseURL: nil)
        } else {
            context.coordinator.updateHeight(for: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    private func htmlDocument(for body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: light; }
            html, body {
              margin: 0;
              padding: 0;
              background: #ffffff;
              color: #202124;
              font: -apple-system-body;
              word-wrap: break-word;
            }
            body { padding: 8px; }
            img, video { max-width: 100%; height: auto; }
            table { max-width: 100%; border-collapse: collapse; }
            pre { white-space: pre-wrap; }
            a { color: -apple-system-link; }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?
        private let contentHeight: Binding<CGFloat>

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(for: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func updateHeight(for webView: WKWebView) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);") { [weak self] result, _ in
                guard let self else { return }
                let height = (result as? CGFloat) ?? (result as? Double).map { CGFloat($0) } ?? 260
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = max(120, min(height + 16, 8000))
                }
            }
        }
    }
}
