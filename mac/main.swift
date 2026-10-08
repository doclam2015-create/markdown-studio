import Cocoa
import WebKit
import UniformTypeIdentifiers

// Markdown Studio para macOS: ventana nativa con WKWebView que carga index.html del bundle.
// El HTML habla con el Mac a través de window.webkit.messageHandlers.md (copiar, pegar, guardar, abrir, compartir).

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let converter = Converter()

    // Archivos elegidos en el panel: el Mac convierte los formatos nativos y entrega el resto a la página
    func convertMany(_ urls: [URL], done: @escaping ([[String: Any]]) -> Void) {
        var out: [[String: Any]] = []
        var i = 0
        func next() {
            guard i < urls.count else { NSLog("MS convertMany listo: %d", out.count); done(out); return }
            let url = urls[i]; i += 1
            let name = url.lastPathComponent
            NSLog("MS convirtiendo %@", name)
            if nativeExts.contains(url.pathExtension.lowercased()) {
                converter.convert(url: url, name: name) { out.append($0); next() }
            } else if let data = try? Data(contentsOf: url) {
                out.append(["name": name, "b64": data.base64EncodedString()]); next()
            } else { out.append(["name": name, "error": "No se pudo leer \(name)"]); next() }
        }
        next()
    }

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
        converter.progress = { [weak self] msg, pct in
            DispatchQueue.main.async {
                let m = (try? JSONSerialization.data(withJSONObject: [msg])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
                self?.web.evaluateJavaScript("window.MDApp&&MDApp.progress(\(m)[0],\(pct))", completionHandler: nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // Archivos abiertos desde Finder («Abrir con») o soltados sobre el ícono del Dock
    var pageReady = false
    var pendingURLs: [URL] = []
    func application(_ application: NSApplication, open urls: [URL]) {
        if pageReady { importURLs(urls) } else { pendingURLs += urls }
    }
    func importURLs(_ urls: [URL]) {
        window?.makeKeyAndOrderFront(nil)
        convertMany(urls) { list in
            guard let data = try? JSONSerialization.data(withJSONObject: list), let json = String(data: data, encoding: .utf8) else { return }
            self.web.evaluateJavaScript("MDApp.progress(null);MDApp.applyNative(\(json));1") { _, e in if let e = e { NSLog("MS JS error: %@", "\(e)") } }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        if !pendingURLs.isEmpty { let u = pendingURLs; pendingURLs = []; importURLs(u) }
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
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.item]
            panel.message = "Elige uno o más archivos: PDF, Word, Excel, PowerPoint, imágenes, audio, video, texto…"
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, !panel.urls.isEmpty else { replyHandler(nil, nil); return }
                self.convertMany(panel.urls) { replyHandler($0, nil) }
            }
        case "fetch":
            guard let s = body["url"] as? String, let u = URL(string: s) else { replyHandler(["error": "Enlace inválido"], nil); return }
            var req = URLRequest(url: u, timeoutInterval: 40)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            req.setValue("es-CL,es;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                DispatchQueue.main.async {
                    guard let data = data, err == nil else { replyHandler(["error": err?.localizedDescription ?? "Sin respuesta"], nil); return }
                    if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { replyHandler(["error": "La página respondió con error \(h.statusCode)"], nil); return }
                    let mime = (resp?.mimeType ?? "").lowercased()
                    let head = String(data: data.prefix(512), encoding: .isoLatin1)?.lowercased() ?? ""
                    if mime.contains("html") || head.contains("<!doctype html") || head.contains("<html") {
                        var enc = String.Encoding.utf8
                        if let n = resp?.textEncodingName {
                            let cf = CFStringConvertIANACharSetNameToEncoding(n as CFString)
                            if cf != kCFStringEncodingInvalidId { enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)) }
                        }
                        let html = String(data: data, encoding: enc) ?? String(data: data, encoding: .isoLatin1) ?? ""
                        replyHandler(["html": html, "url": resp?.url?.absoluteString ?? s], nil)
                    } else {
                        replyHandler(["name": resp?.suggestedFilename ?? u.lastPathComponent, "b64": data.base64EncodedString()], nil)
                    }
                }
            }.resume()
        case "convert":
            guard let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) else { replyHandler(["name": name, "error": "Archivo vacío"], nil); return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent((name as NSString).lastPathComponent)
            do { try data.write(to: url) } catch { replyHandler(["name": name, "error": error.localizedDescription], nil); return }
            converter.convert(url: url, name: name) { replyHandler($0, nil) }
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
        file.addItem(jsItem("Agregar archivos…", "MDApp.open()", "o"))
        file.addItem(jsItem("Importar página web…", "MDApp.link()", "l"))
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
