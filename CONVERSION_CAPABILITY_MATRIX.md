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
| WEBP | JPEG | SUPPORTED / Native | ImageIO decode, white alpha flattening | Medium: lossy encode; transparency is removed |
| WEBP | PNG | SUPPORTED / Native | ImageIO decode | Low: pixels and alpha kept; WEBP metadata may be omitted |
| WEBP | PDF | SUPPORTED / Native | ImageIO decode + CoreGraphics PDF context | Low: one raster page; transparency uses a white page |
| WEBP | HEIC | PARTIALLY_SUPPORTED | ImageIO | Hidden for the same alpha/HDR reason as PNG → HEIC |
| Animated WEBP | any | UNSAFE | ImageIO could decode frames | Hidden because animation would be lost |
| Any | WEBP | REQUIRES_LIBRARY | libwebp | ImageIO has no WEBP encoder |
| WAV/AIFF/FLAC | M4A (AAC) | SUPPORTED / Native | AVAudioFile, AAC VBR max quality | Medium: lossy; tags and artwork are not copied |
| MP3 | M4A (AAC) | SUPPORTED / Native | AVAudioFile, AAC VBR max quality | Medium: second lossy generation; tags and artwork are not copied |
| AIFF/FLAC/MP3/M4A | WAV | SUPPORTED / Native | AVAudioFile, 16-bit PCM for lossy sources, 24-bit otherwise | Low: much larger file; tags and artwork are not copied |
| More than 2 channels | M4A (AAC) | NOT_SUPPORTED | CoreAudio AAC encoder rejects >2 channels | Hidden; WAV remains available |
| Any | MP3 | REQUIRES_LIBRARY | LAME | macOS has no MP3 encoder |
| OGG/OPUS and other audio | any | REQUIRES_EXTERNAL_TOOL | FFmpeg | Not reliably decodable natively |
| GIF | JPEG/PNG | UNSAFE | ImageIO could decode frames | Hidden because animation would be lost |
| PSD | JPEG/PNG | UNSAFE | ImageIO can flatten | Hidden because layers, masks, and editing structure would be lost |
| MOV | MP4 | SUPPORTED / Native | AVFoundation passthrough export; HighestQuality re-encode when codecs (e.g. ProRes) do not fit MP4 | Low for passthrough; Medium when re-encoded (lossy, slower) |
| MP4 | MOV | SUPPORTED / Native | AVFoundation passthrough export; HighestQuality re-encode as fallback | Low for passthrough; Medium when re-encoded (lossy, slower) |
| PDF | PNG | SUPPORTED / Native | CoreGraphics + ImageIO, 144 DPI | Medium: one image per page; text, vectors, links, forms, and annotations become raster content |
| PDF | JPEG | SUPPORTED / Native | CoreGraphics + ImageIO, 144 DPI | High: one lossy image per page; editable/interactive PDF structure is lost |
| JPEG/PNG/HEIC/WEBP | PDF | SUPPORTED / Native | CoreGraphics PDF context | Low: creates a one-page PDF containing raster content; transparency uses a white page |

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
| MKV/WEBM/AVI → MP4/MOV | REQUIRES_EXTERNAL_TOOL | FFmpeg | Containers/codecs are not reliably covered by AVFoundation |
| ZIP ↔ TAR.GZ | PARTIALLY_SUPPORTED | Archive framework/bsdtar | Requires secure extraction, symlink/path traversal defenses, and metadata policy |
| RAR/7Z | REQUIRES_LIBRARY | libarchive/7-Zip | No dependable native writer; license and bundled binary must be reviewed |
| EPUB ↔ MOBI/AZW3 | REQUIRES_EXTERNAL_TOOL | Calibre | Layout, DRM, fonts, and device-specific semantics prevent a simple safe conversion |
| TTF ↔ OTF/WOFF/WOFF2 | REQUIRES_LIBRARY | fonttools/woff2 | Font licensing, hinting, variations, and tables must be preserved |
| DWG ↔ DXF | NOT_SUPPORTED | Licensed CAD SDK/external CAD tool | Proprietary data and high fidelity risk; no suitable native backend |

## Detection and safety rules

- Image source format is detected from ImageIO content identifiers, not filename extension.
- HEIC, HEIF, and HEICS containers use the primary image selected by ImageIO. Multi-frame JPEG/PNG/WEBP remains hidden to avoid silently discarding animation.
- MOV/MP4 is detected from ISO Base Media File Format `ftyp` brands and then validated for a real video track by AVFoundation.
- MOV/MP4 options use `AVAssetExportSession.compatibility(ofExportPreset:with:outputFileType:)`: passthrough when the source codecs fit the target container, otherwise a HighestQuality re-encode with a re-encode warning. `supportedFileTypes` is not used because it lists MP4 for ProRes MOV even though passthrough then fails.
- Every PDF page is rendered sequentially at 144 DPI. Multi-page PDFs produce one collision-safe image per page, and per-page autorelease pools keep peak memory bounded.
- Image-to-PDF applies the image orientation, uses its valid DPI when available, and creates one raster page without changing the source image.
- Audio container type is detected with AudioToolbox `kAudioFilePropertyFileFormat`, not the extension. MPEG-4 files with a video track are left to the video converter.
- Destination encoder availability is queried from ImageIO at runtime.
- Conversion always writes a unique temporary file, then moves it to a collision-free final name.
- Existing files and source files are never overwritten.
- Unsupported targets never appear in the UI.
