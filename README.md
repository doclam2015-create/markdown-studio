# Markdown Studio

Transforma cualquier texto en Markdown: correos, notas, páginas web, tablas de Excel o documentos de Word.
Copia, descarga el `.md` o compártelo. Funciona sin conexión y sin costo de API.

**Abrir:** https://doclam2015-create.github.io/markdown-studio/

## Qué convierte
- **Texto** escrito o pegado: títulos, viñetas, listas numeradas, tareas, tablas de Excel, pares `Clave: valor`, citas, enlaces; une líneas cortadas de PDF.
- **Texto enriquecido** pegado (web, Word, Google Docs, Pages): negritas, cursivas, enlaces, listas, tablas y código.
- **Archivos** (uno o varios a la vez, también arrastrando):
  - PDF (con OCR si es escaneado), Word `.docx` y `.doc`, RTF, OpenDocument `.odt`/`.odp`/`.ods`
  - Excel `.xlsx`/`.xls`/`.xlsb`, Numbers, CSV/TSV; PowerPoint `.pptx`; EPUB
  - Imágenes (JPG, PNG, HEIC, WebP, TIFF…) → OCR
  - Audio y video (MP3, M4A, WAV, MP4, MOV…) → transcripción
  - Correo `.eml`, HTML, Markdown, JSON, notebooks `.ipynb`, subtítulos `.srt`/`.vtt`, código fuente
- **Páginas web**: botón *Web* (o arrastra un enlace) → extrae el contenido principal.

**Combinar:** cada archivo o página se agrega donde está el cursor, entre marcas `<!-- archivo: … -->`, y se puede seguir escribiendo alrededor. Para empezar de cero, usa el botón de borrar.

**Dónde se procesa:** todo en el dispositivo. En el Mac usa PDFKit, Vision y el reconocimiento de voz de macOS. En iPhone/iPad, el OCR (Tesseract) y la voz (Whisper) se descargan la primera vez (~15 MB y ~80 MB) y quedan en caché. Las páginas web en iPhone/iPad se leen a través de r.jina.ai (gratuito); en el Mac se descargan directamente.

## Instalar
- **iPhone / iPad:** abrir el enlace en Safari → Compartir → *Añadir a pantalla de inicio*.
- **Mac (app nativa):** `./mac/build.sh` compila `Markdown Studio.app` (Swift + WKWebView) y la instala en `/Applications`.

Atajos en el Mac: ⌘S guardar, ⇧⌘C copiar Markdown, ⇧⌘V pegar como texto nuevo, ⌘O agregar archivos, ⌘L importar página web, ⌘1/2/3 vistas. También acepta archivos soltados sobre el ícono del Dock y «Abrir con» desde Finder.
