import Cocoa
import WebKit
import UniformTypeIdentifiers

// Markdown Studio para macOS: ventana nativa con WKWebView que carga index.html del bundle.
// El HTML habla con el Mac a través de window.webkit.messageHandlers.md (copiar, pegar, guardar, abrir, compartir).

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "md")
        cfg.userContentController.addUserScript(WKUserScript(source: "window.MD_NATIVE='mac';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 840),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Markdown Studio"
        window.minSize = NSSize(width: 420, height: 560)
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("MarkdownStudioMain")
        window.makeKeyAndOrderFront(nil)

        let url = Bundle.main.url(forResource: "index", withExtension: "html")!
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }

    // MARK: puente JS
    func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { replyHandler(nil, "mensaje inválido"); return }
        let text = body["text"] as? String ?? ""
        let name = body["name"] as? String ?? "documento.md"
        switch action {
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            replyHandler(true, nil)
        case "paste":
            let pb = NSPasteboard.general
            var html = pb.string(forType: .html) ?? ""
            if html.isEmpty, let rtf = pb.data(forType: .rtf),
               let att = NSAttributedString(rtf: rtf, documentAttributes: nil),
               let data = try? att.data(from: NSRange(location: 0, length: att.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
                html = String(data: data, encoding: .utf8) ?? ""
            }
            replyHandler(["text": pb.string(forType: .string) ?? "", "html": html], nil)
        case "save":
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.canCreateDirectories = true
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, let url = panel.url else { replyHandler(nil, nil); return }
                do { try text.write(to: url, atomically: true, encoding: .utf8); replyHandler(url.lastPathComponent, nil) }
                catch { replyHandler(nil, error.localizedDescription) }
            }
        case "open":
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = ["txt", "md", "markdown", "html", "htm", "csv", "tsv", "json", "log", "xml", "rtf"].compactMap { UTType(filenameExtension: $0) } + [.plainText]
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, let url = panel.url else { replyHandler(nil, nil); return }
                var content = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
                var fname = url.lastPathComponent
                if url.pathExtension.lowercased() == "rtf", let att = try? NSAttributedString(url: url, options: [:], documentAttributes: nil),
                   let data = try? att.data(from: NSRange(location: 0, length: att.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
                    content = String(data: data, encoding: .utf8) ?? att.string
                    fname = url.deletingPathExtension().lastPathComponent + ".html"
                }
                replyHandler(["name": fname, "text": content], nil)
            }
        case "share":
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            var r = NSRect(x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0, width: body["w"] as? Double ?? 10, height: body["h"] as? Double ?? 10)
            if !web.isFlipped { r.origin.y = web.bounds.height - r.origin.y - r.height }
            NSSharingServicePicker(items: [url]).show(relativeTo: r, of: web, preferredEdge: .minY)
            replyHandler(true, nil)
        default:
            replyHandler(nil, "acción desconocida")
        }
    }

    // Enlaces externos se abren en el navegador
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme != "file", url.scheme != "about", url.scheme != "blob" {
            NSWorkspace.shared.open(url); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    // MARK: menús
    @objc func js(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String { web.evaluateJavaScript(code, completionHandler: nil) }
    }
    func jsItem(_ title: String, _ code: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: #selector(js(_:)), keyEquivalent: key)
        it.keyEquivalentModifierMask = mods; it.representedObject = code; it.target = self
        return it
    }
    func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de Markdown Studio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Markdown Studio", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let other = appMenu.addItem(withTitle: "Ocultar otros", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        other.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Salir de Markdown Studio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); bar.addItem(fileItem)
        let file = NSMenu(title: "Archivo")
        file.addItem(jsItem("Nuevo", "MDApp.clear()", "n"))
        file.addItem(jsItem("Abrir…", "MDApp.open()", "o"))
        file.addItem(.separator())
        file.addItem(jsItem("Guardar Markdown…", "MDApp.download()", "s"))
        file.addItem(jsItem("Compartir…", "MDApp.share()", "e", [.command, .shift]))
        file.addItem(.separator())
        file.addItem(withTitle: "Cerrar ventana", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file

        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(jsItem("Copiar Markdown", "MDApp.copy()", "c", [.command, .shift]))
        edit.addItem(jsItem("Pegar como texto nuevo", "MDApp.paste()", "v", [.command, .shift]))
        edit.addItem(jsItem("Cargar ejemplo", "MDApp.sample()", ""))
        editItem.submenu = edit

        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let view = NSMenu(title: "Ver")
        view.addItem(jsItem("Texto", "MDApp.view('in')", "1"))
        view.addItem(jsItem("Markdown", "MDApp.view('md')", "2"))
        view.addItem(jsItem("Vista previa", "MDApp.view('view')", "3"))
        view.addItem(.separator())
        let fs = view.addItem(withTitle: "Pantalla completa", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view

        let winItem = NSMenuItem(); bar.addItem(winItem)
        let win = NSMenu(title: "Ventana")
        win.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = bar
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
