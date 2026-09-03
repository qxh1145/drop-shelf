# DropShelf Conversion Capability Matrix

The MVP exposes only conversions backed by native macOS frameworks and verified against the actual source file at runtime. “Technically decodable” is not enough: animated, layered, multi-page, proprietary, or semantically lossy conversions remain hidden.

## Implemented MVP

| Input | Output | Status | Implementation | Data-loss risk |
| --- | --- | --- | --- | --- |
| HEIC/HEIF/HEICS | JPEG | SUPPORTED / Native | ImageIO primary image | Medium: lossy encode; HDR and HEIC metadata may be reduced |
| HEIC/HEIF/HEICS | PNG | SUPPORTED / Native | ImageIO primary image | Low: HEIC-specific metadata/HDR may be reduced |
| JPEG | PNG | SUPPORTED / Native | ImageIO | Low: no new pixel loss; format-specific metadata may be omitted |
| JPEG | HEIC | SUPPORTED / Native | ImageIO | Medium: lossy recompression |
| PNG | JPEG | SUPPORTED / Native | ImageIO, white alpha flattening | Medium: transparency is removed; lossy encode |
| PNG | HEIC | PARTIALLY_SUPPORTED | ImageIO | Hidden in MVP because alpha/HDR behavior varies by encoder |
| WEBP | JPEG/PNG/HEIC | PARTIALLY_SUPPORTED | Native decode varies; no native ImageIO WEBP encoder | Hidden until a reliable bundled codec is selected |
| GIF | JPEG/PNG | UNSAFE | ImageIO could decode frames | Hidden because animation would be lost |
| PSD | JPEG/PNG | UNSAFE | ImageIO can flatten | Hidden because layers, masks, and editing structure would be lost |
| MOV | MP4 | SUPPORTED_WHEN_COMPATIBLE / Native | AVFoundation passthrough export | Low: container changes; existing codecs are not re-encoded |
| MP4 | MOV | SUPPORTED_WHEN_COMPATIBLE / Native | AVFoundation passthrough export | Low: container changes; existing codecs are not re-encoded |
| PDF | PNG | SUPPORTED / Native | CoreGraphics + ImageIO, 144 DPI | Medium: one image per page; text, vectors, links, forms, and annotations become raster content |
| PDF | JPEG | SUPPORTED / Native | CoreGraphics + ImageIO, 144 DPI | High: one lossy image per page; editable/interactive PDF structure is lost |
| JPEG/PNG/HEIC | PDF | SUPPORTED / Native | CoreGraphics PDF context | Low: creates a one-page PDF containing raster content; transparency uses a white page |

## Long-term format assessment

| Group / conversion | Status | Required implementation | Reason / risk |
| --- | --- | --- | --- |
| DOCX/DOC/ODT → PDF | REQUIRES_EXTERNAL_TOOL | LibreOffice | Native APIs do not provide faithful Office layout conversion |
| RTF → TXT | UNSAFE | Foundation | Formatting, attachments, and document structure are lost |
| MD → HTML/PDF | REQUIRES_EXTERNAL_TOOL | Pandoc or a defined Markdown renderer | Markdown dialect and styling must be explicit |
| XLSX/XLS → CSV | UNSAFE | LibreOffice/library | Formulas, styles, charts, and all but one sheet can be lost |
| CSV → XLSX | REQUIRES_LIBRARY_AND_SCHEMA | Spreadsheet library/LibreOffice | CSV has no sheet, formula, style, or reliable data-type schema; automatic inference can change IDs, dates, and leading zeroes |
| XLSX ↔ XLS/ODS | REQUIRES_EXTERNAL_TOOL | LibreOffice | Complex workbook fidelity cannot be guaranteed natively |
| PPTX/PPT → PDF | REQUIRES_EXTERNAL_TOOL | LibreOffice | Fonts, transitions, media, and layout can change |
| KEY → PDF/PPTX | REQUIRES_EXTERNAL_TOOL | Keynote automation | Proprietary format and UI automation/distribution constraints |
| SVG → PNG/PDF | REQUIRES_LIBRARY | Resvg/WebKit-based renderer | Font, filter, script, and external-resource behavior needs sandboxing |
| EPS/AI → raster/PDF | REQUIRES_EXTERNAL_TOOL | Ghostscript/Illustrator-compatible tool | AI is proprietary; layers and color spaces may be lost |
| Other MOV/MP4 codec combinations | PARTIALLY_SUPPORTED | AVFoundation transcode presets | Hidden when passthrough export says the codecs are incompatible with the target container |
| MKV/WEBM/AVI → MP4/MOV | REQUIRES_EXTERNAL_TOOL | FFmpeg | Containers/codecs are not reliably covered by AVFoundation |
| WAV → M4A/AAC | PARTIALLY_SUPPORTED | AVFoundation/AudioToolbox | Safe once channel layout, sample rate, metadata, and progress UX are defined |
| MP3/AAC/M4A → WAV | PARTIALLY_SUPPORTED | AVFoundation/AudioToolbox | Large output and metadata loss require warning/progress handling |
| FLAC and broad audio conversion | REQUIRES_EXTERNAL_TOOL | FFmpeg or libFLAC | Native encode/decode coverage is not uniform across deployment targets |
| ZIP ↔ TAR.GZ | PARTIALLY_SUPPORTED | Archive framework/bsdtar | Requires secure extraction, symlink/path traversal defenses, and metadata policy |
| RAR/7Z | REQUIRES_LIBRARY | libarchive/7-Zip | No dependable native writer; license and bundled binary must be reviewed |
| EPUB ↔ MOBI/AZW3 | REQUIRES_EXTERNAL_TOOL | Calibre | Layout, DRM, fonts, and device-specific semantics prevent a simple safe conversion |
| TTF ↔ OTF/WOFF/WOFF2 | REQUIRES_LIBRARY | fonttools/woff2 | Font licensing, hinting, variations, and tables must be preserved |
| DWG ↔ DXF | NOT_SUPPORTED | Licensed CAD SDK/external CAD tool | Proprietary data and high fidelity risk; no suitable native backend |

## Detection and safety rules

- Image source format is detected from ImageIO content identifiers, not filename extension.
- HEIC, HEIF, and HEICS containers use the primary image selected by ImageIO. Multi-frame JPEG/PNG remains hidden to avoid silently discarding animation.
- MOV/MP4 is detected from ISO Base Media File Format `ftyp` brands and then validated for a real video track by AVFoundation.
- MOV/MP4 options appear only if an AVFoundation passthrough export session reports that the target container is supported for the source codecs.
- Every PDF page is rendered sequentially at 144 DPI. Multi-page PDFs produce one collision-safe image per page, and per-page autorelease pools keep peak memory bounded.
- Image-to-PDF applies the image orientation, uses its valid DPI when available, and creates one raster page without changing the source image.
- Destination encoder availability is queried from ImageIO at runtime.
- Conversion always writes a unique temporary file, then moves it to a collision-free final name.
- Existing files and source files are never overwritten.
- Unsupported targets never appear in the UI.
