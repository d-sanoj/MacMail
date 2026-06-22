import SwiftUI
import WebKit

struct HTMLMessageBodyView: View {
    let html: String

    var body: some View {
        HTMLWebView(html: html)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .background(Color.white)
    }
}

private struct HTMLWebView: NSViewRepresentable {
    let html: String

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
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
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
            
            /* Collapse repetitive quote chains mimicking Gmail's thread view */
            .gmail_quote, .gmail_extra, blockquote[type="cite"] {
              display: none !important;
            }
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // No longer forcing height
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
    }
}
