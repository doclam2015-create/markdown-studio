import Cocoa
import PDFKit
import Vision
import Speech
import AVFoundation

// Conversión nativa en el Mac: PDF (PDFKit + OCR), Word .doc/RTF/ODT (Cocoa),
// imágenes (Vision OCR) y audio/video (reconocimiento de voz en el dispositivo).

let nativeExts: Set<String> = ["pdf", "doc", "dot", "rtf", "odt", "webarchive", "wordml",
    "png", "jpg", "jpeg", "jpe", "jfif", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff", "avif",
    "mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "amr",
    "mp4", "m4v", "mov", "3gp", "3g2"]
private let imageExts: Set<String> = ["png", "jpg", "jpeg", "jpe", "jfif", "heic", "heif", "webp", "gif", "bmp", "tif", "tiff", "avif"]
private let mediaExts: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "amr", "mp4", "m4v", "mov", "3gp", "3g2"]

final class Converter {
    var progress: (String, Double) -> Void = { _, _ in }
    private var speechJob: SpeechJob?

    func convert(url: URL, name: String, done: @escaping ([String: Any]) -> Void) {
        let ext = url.pathExtension.lowercased()
        let fail: (String) -> Void = { msg in done(["name": name, "error": msg]) }
        if ext == "pdf" {
            DispatchQueue.global(qos: .userInitiated).async {
                let t = self.pdfText(url)
                DispatchQueue.main.async { t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fail("No se encontró texto en el PDF") : done(["name": name, "text": t]) }
            }
        } else if imageExts.contains(ext) {
            progress("Reconociendo texto en la imagen…", -1)
            DispatchQueue.global(qos: .userInitiated).async {
                var t = ""
                if let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) { t = self.ocr(cg) }
                DispatchQueue.main.async { t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fail("No se encontró texto en la imagen") : done(["name": name, "text": t]) }
            }
        } else if mediaExts.contains(ext) {
            transcribe(url: url, name: name, done: done)
        } else {
            do { done(["name": name, "md": try docToMd(url)]) }
            catch { fail("No se pudo leer \(name): \(error.localizedDescription)") }
        }
    }

    // MARK: PDF
    func pdfText(_ url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        if doc.isLocked { _ = doc.unlock(withPassword: "") }
        struct Line { var t: String; var h: CGFloat; var y: CGFloat }
        var pages: [[Line]] = []
        var ocrPages: [Int: String] = [:]
        let n = doc.pageCount
        for i in 0..<n {
            guard let page = doc.page(at: i) else { pages.append([]); continue }
            progress("Leyendo PDF · página \(i + 1) de \(n)", Double(i + 1) / Double(max(n, 1)) * 100)
            let raw = page.string ?? ""
            if raw.trimmingCharacters(in: .whitespacesAndNewlines).count < 25 {
                let b = page.bounds(for: .mediaBox)
                let img = page.thumbnail(of: NSSize(width: b.width * 2.5, height: b.height * 2.5), for: .mediaBox)
                if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    progress("PDF escaneado · reconociendo página \(i + 1) de \(n)", Double(i + 1) / Double(max(n, 1)) * 100)
                    ocrPages[i] = ocr(cg)
                }
                pages.append([]); continue
            }
            var ls: [Line] = []
            if let sel = page.selection(for: page.bounds(for: .mediaBox)) {
                for l in sel.selectionsByLine() {
                    let t = (l.string ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { continue }
                    let bb = l.bounds(for: page)
                    ls.append(Line(t: t, h: bb.height, y: bb.midY))
                }
            }
            pages.append(ls)
        }
        // tamaño de letra del cuerpo = mediana ponderada de la altura de línea
        var hs: [(CGFloat, Int)] = []
        for p in pages { for l in p { hs.append((l.h, l.t.count)) } }
        hs.sort { $0.0 < $1.0 }
        let total = hs.reduce(0) { $0 + $1.1 }
        var acc = 0, body: CGFloat = 12
        for (h, c) in hs { acc += c; if acc >= total / 2 { body = h; break } }
        let pageNo = try! NSRegularExpression(pattern: "^(p[aá]g(ina)?\\.?\\s*)?\\d{1,4}(\\s*(de|/|of)\\s*\\d{1,4})?$", options: .caseInsensitive)
        var out: [String] = []
        for (i, ls) in pages.enumerated() {
            if let o = ocrPages[i] { out.append(o); out.append(""); continue }
            var gaps: [CGFloat] = []
            for k in 1..<max(ls.count, 1) where k < ls.count { let g = ls[k - 1].y - ls[k].y; if g > 0 { gaps.append(g) } }
            gaps.sort()
            let lead = gaps.isEmpty ? body * 1.2 : gaps[gaps.count / 2]
            var prevHead = ""
            for (k, l) in ls.enumerated() {
                if pageNo.firstMatch(in: l.t, range: NSRange(l.t.startIndex..., in: l.t)) != nil { continue }
                let lvl = l.t.count < 110 ? (l.h >= body * 1.45 ? 2 : (l.h >= body * 1.18 ? 3 : 0)) : 0
                if k > 0 { let g = ls[k - 1].y - l.y; if g > lead * 1.45 || g < 0 { out.append("") } }
                if lvl > 0 {
                    let mk = String(repeating: "#", count: lvl) + " "
                    if prevHead == mk, let last = out.last, last.hasPrefix(mk) { out[out.count - 1] = last + " " + l.t }
                    else { if let last = out.last, !last.isEmpty { out.append("") }; out.append(mk + l.t) }
                    prevHead = mk; continue
                }
                if !prevHead.isEmpty { out.append(""); prevHead = "" }
                out.append(l.t)
            }
            out.append("")
        }
        return out.joined(separator: "\n").replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    // MARK: OCR (Vision)
    func ocr(_ cg: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["es-ES", "en-US"]
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        let obs: [(String, CGRect)] = (req.results ?? []).compactMap { o in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            return (s, o.boundingBox)
        }
        var lines: [[(String, CGRect)]] = []
        for o in obs.sorted(by: { $0.1.midY > $1.1.midY }) {
            if let ref = lines.last?.first, abs(ref.1.midY - o.1.midY) < ref.1.height * 0.5 { lines[lines.count - 1].append(o) }
            else { lines.append([o]) }
        }
        var out = ""
        var prevY: CGFloat? = nil, prevH: CGFloat = 0
        for l in lines {
            let ls = l.sorted { $0.1.minX < $1.1.minX }
            var text = ""
            for (k, o) in ls.enumerated() {
                if k > 0 { text += (o.1.minX - ls[k - 1].1.maxX) > o.1.height * 1.5 ? "\t" : " " }
                text += o.0
            }
            let y = ls[0].1.midY, h = ls.map { $0.1.height }.max() ?? 0
            if let py = prevY, py - y > (h + prevH) * 1.15 { out += "\n" }
            out += text + "\n"
            prevY = y; prevH = h
        }
        return out
    }

    // MARK: Documentos (Cocoa)
    func docToMd(_ url: URL) throws -> String {
        var opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch url.pathExtension.lowercased() {
        case "doc", "dot": opts[.documentType] = NSAttributedString.DocumentType.docFormat
        case "odt": opts[.documentType] = NSAttributedString.DocumentType.openDocument
        case "rtf": opts[.documentType] = NSAttributedString.DocumentType.rtf
        case "webarchive": opts[.documentType] = NSAttributedString.DocumentType.webArchive
        case "wordml": opts[.documentType] = NSAttributedString.DocumentType.wordML
        default: break
        }
        let att = try NSAttributedString(url: url, options: opts, documentAttributes: nil)
        return attToMd(att)
    }

    func attToMd(_ att: NSAttributedString) -> String {
        let ns = att.string as NSString
        let full = NSRange(location: 0, length: ns.length)
        var sizes: [CGFloat: Int] = [:]
        att.enumerateAttribute(.font, in: full) { v, r, _ in
            if let f = v as? NSFont { sizes[f.pointSize.rounded(), default: 0] += r.length }
        }
        let body = sizes.max { $0.value < $1.value }?.key ?? 12
        var out: [String] = []
        var lastWasList = false
        var table: [[String]] = [], tableRef: NSTextTable? = nil
        func flushTable() {
            guard !table.isEmpty else { return }
            let w = table.map { $0.count }.max() ?? 0
            var md: [String] = []
            for (i, r) in table.enumerated() {
                let cells = (0..<w).map { $0 < r.count ? r[$0].replacingOccurrences(of: "|", with: "\\|") : "" }
                md.append("| " + cells.joined(separator: " | ") + " |")
                if i == 0 { md.append("|" + String(repeating: " --- |", count: w)) }
            }
            out.append(""); out.append(md.joined(separator: "\n")); out.append("")
            table = []; tableRef = nil
        }
        ns.enumerateSubstrings(in: full, options: .byParagraphs) { sub, r, _, _ in
            let raw = (sub ?? "").trimmingCharacters(in: .whitespaces)
            let ps = r.length > 0 ? att.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle : nil
            if let cell = ps?.textBlocks.last as? NSTextTableBlock {
                if tableRef !== cell.table { flushTable(); tableRef = cell.table }
                while table.count <= cell.startingRow { table.append([]) }
                while table[cell.startingRow].count <= cell.startingColumn { table[cell.startingRow].append("") }
                table[cell.startingRow][cell.startingColumn] = raw
                return
            }
            flushTable()
            if raw.isEmpty { if !lastWasList { out.append("") }; return }
            var line = "", maxSize: CGFloat = 0, allBold = true
            att.enumerateAttributes(in: r, options: []) { a, rr, _ in
                var t = ns.substring(with: rr)
                let f = a[.font] as? NSFont
                maxSize = max(maxSize, f?.pointSize ?? body)
                let tr = f.map { NSFontManager.shared.traits(of: $0) } ?? []
                let b = tr.contains(.boldFontMask), it = tr.contains(.italicFontMask)
                let core = t.trimmingCharacters(in: .whitespaces)
                if !core.isEmpty && !b { allBold = false }
                if let link = a[.link] { let u = (link as? URL)?.absoluteString ?? "\(link)"; if !core.isEmpty { t = t.replacingOccurrences(of: core, with: "[\(core)](\(u))") } }
                if (b || it) && !core.isEmpty && a[.link] == nil {
                    let mk = b && it ? "***" : (b ? "**" : "*")
                    t = t.replacingOccurrences(of: core, with: mk + core + mk)
                }
                line += t
            }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let lists = ps?.textLists, !lists.isEmpty {
                let ordered = lists.last!.markerFormat.rawValue.contains("decimal")
                line = line.replacingOccurrences(of: "^[^\\t]{0,6}\\t", with: "", options: .regularExpression)
                if !lastWasList { out.append("") }
                out.append(String(repeating: "    ", count: lists.count - 1) + (ordered ? "1. " : "- ") + line)
                lastWasList = true; return
            }
            if lastWasList { out.append(""); lastWasList = false }
            let plain = raw.count < 120
            if line.range(of: "^[•◦▪·‣●○■–-]\\s+", options: .regularExpression) != nil {
                if !lastWasList { out.append("") }
                out.append(line.replacingOccurrences(of: "^[•◦▪·‣●○■–-]\\s+", with: "- ", options: .regularExpression))
                lastWasList = true; return
            }
            if plain && maxSize >= body * 1.8 { out.append(contentsOf: ["", "# " + raw, ""]) }
            else if plain && maxSize >= body * 1.3 { out.append(contentsOf: ["", "## " + raw, ""]) }
            else if plain && maxSize >= body * 1.12 { out.append(contentsOf: ["", "### " + raw, ""]) }
            else if plain && raw.count < 90 && allBold && !raw.hasSuffix(".") { out.append(contentsOf: ["", "### " + raw, ""]) }
            else { out.append(line); out.append("") }
        }
        flushTable()
        return out.joined(separator: "\n").replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    // MARK: Audio y video (Speech)
    func transcribe(url: URL, name: String, done: @escaping ([String: Any]) -> Void) {
        progress("Solicitando permiso de reconocimiento de voz…", -1)
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    done(["name": name, "error": "Permite el reconocimiento de voz en Configuración del Sistema › Privacidad y seguridad › Reconocimiento de voz."]); return
                }
                self.progress("Preparando audio…", -1)
                self.extractAudio(url) { audioURL in
                    let ids = ["es-CL", "es-419", "es-MX", "es-US", "es-ES"]
                    let recs = ids.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
                    guard let rec = recs.first(where: { $0.isAvailable && $0.supportsOnDeviceRecognition }) ?? recs.first(where: { $0.isAvailable }) else {
                        done(["name": name, "error": "El reconocimiento de voz en español no está disponible en este Mac."]); return
                    }
                    let dur = CMTimeGetSeconds(AVURLAsset(url: audioURL).duration)
                    let req = SFSpeechURLRecognitionRequest(url: audioURL)
                    req.shouldReportPartialResults = true
                    req.addsPunctuation = true
                    if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
                    let job = SpeechJob(duration: dur.isFinite ? dur : 0, progress: self.progress) { text, err in
                        self.speechJob = nil
                        if let t = text, !t.isEmpty {
                            let m = Int(dur) / 60, s = Int(dur) % 60
                            let md = "# Transcripción: \((name as NSString).deletingPathExtension)\n\n> Duración: \(m):\(String(format: "%02d", s)) · Transcrito en el Mac\n\n" + t + "\n"
                            done(["name": name, "md": md])
                        } else { done(["name": name, "error": err ?? "No se reconoció voz en el archivo"]) }
                    }
                    self.speechJob = job
                    job.task = rec.recognitionTask(with: req, delegate: job)
                }
            }
        }
    }

    // Convierte video o audio comprimido a m4a para el reconocedor
    private func extractAudio(_ url: URL, then: @escaping (URL) -> Void) {
        let ext = url.pathExtension.lowercased()
        if ["m4a", "wav", "wave", "aif", "aiff", "caf"].contains(ext) { then(url); return }
        let asset = AVURLAsset(url: url)
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { then(url); return }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        ex.outputURL = out
        ex.outputFileType = .m4a
        ex.exportAsynchronously {
            DispatchQueue.main.async { then(ex.status == .completed ? out : url) }
        }
    }
}

final class SpeechJob: NSObject, SFSpeechRecognitionTaskDelegate {
    var task: SFSpeechRecognitionTask?
    private var paras: [String] = []
    private var cur = ""
    private let duration: Double
    private let progress: (String, Double) -> Void
    private let finish: (String?, String?) -> Void
    private var finished = false

    init(duration: Double, progress: @escaping (String, Double) -> Void, finish: @escaping (String?, String?) -> Void) {
        self.duration = duration; self.progress = progress; self.finish = finish
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription t: SFTranscription) {
        guard duration > 0, let last = t.segments.last else { progress("Transcribiendo audio…", -1); return }
        let done = min(99, (last.timestamp + last.duration) / duration * 100)
        progress("Transcribiendo audio… \(Int(done))%", done)
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition r: SFSpeechRecognitionResult) {
        let s = r.bestTranscription.formattedString.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        cur += (cur.isEmpty ? "" : " ") + s
        if cur.count > 550 { paras.append(cur); cur = "" }
    }
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully ok: Bool) {
        guard !finished else { return }
        finished = true
        if !cur.isEmpty { paras.append(cur); cur = "" }
        DispatchQueue.main.async {
            if !self.paras.isEmpty { self.finish(self.paras.joined(separator: "\n\n"), nil) }
            else { self.finish(nil, ok ? nil : task.error?.localizedDescription) }
        }
    }
}
