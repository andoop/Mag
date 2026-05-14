import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

class OfficeRenderResult {
  const OfficeRenderResult({
    required this.bytes,
    required this.mime,
    required this.extension,
    required this.itemCount,
  });

  final Uint8List bytes;
  final String mime;
  final String extension;
  final int itemCount;
}

class OfficeRenderer {
  const OfficeRenderer._();

  static OfficeRenderResult renderDocument(JsonMap args) {
    final title = _string(args['title'], fallback: 'Document');
    final blocks = _maps(args['blocks']);
    if (blocks.isEmpty) {
      throw Exception('Document requires at least one block.');
    }

    final body = StringBuffer();
    body.write(_docxParagraph(title, style: 'Title'));
    var count = 1;
    for (final block in blocks) {
      count++;
      final type = _string(block['type'], fallback: 'paragraph');
      if (type == 'heading') {
        final level = _int(block['level'], fallback: 1).clamp(1, 2);
        body.write(
          _docxParagraph(
            _string(block['text']),
            style: level == 1 ? 'Heading1' : 'Heading2',
          ),
        );
      } else if (type == 'list') {
        for (final item in _strings(block['items'])) {
          body.write(_docxParagraph('• $item', style: 'ListParagraph'));
        }
      } else if (type == 'table') {
        body.write(_docxTable(_tableRows(block['rows'])));
      } else {
        body.write(_docxParagraph(_string(block['text'])));
      }
    }
    body.write(_docxSectPr());

    final entries = <String, String>{
      '[Content_Types].xml': _docxContentTypes(),
      '_rels/.rels': _packageRels(
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
        'word/document.xml',
      ),
      'word/document.xml': _docxDocument(body.toString()),
      'word/styles.xml': _docxStyles(),
    };
    return OfficeRenderResult(
      bytes: _zipXml(entries),
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      extension: 'docx',
      itemCount: count,
    );
  }

  static OfficeRenderResult renderSpreadsheet(JsonMap args) {
    final rawSheets = _maps(args['sheets']);
    final sheets = rawSheets.isEmpty
        ? <JsonMap>[
            {
              'name': 'Sheet1',
              'rows': _lists(args['rows']),
            }
          ]
        : rawSheets;
    if (sheets.isEmpty) {
      throw Exception('Spreadsheet requires at least one sheet.');
    }

    final entries = <String, String>{
      '[Content_Types].xml': _xlsxContentTypes(sheets.length),
      '_rels/.rels': _packageRels(
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
        'xl/workbook.xml',
      ),
      'xl/workbook.xml': _xlsxWorkbook(sheets),
      'xl/_rels/workbook.xml.rels': _xlsxWorkbookRels(sheets.length),
      'xl/styles.xml': _xlsxStyles(),
    };

    var rowCount = 0;
    for (var i = 0; i < sheets.length; i++) {
      final rows = _lists(sheets[i]['rows']);
      rowCount += rows.length;
      entries['xl/worksheets/sheet${i + 1}.xml'] = _xlsxWorksheet(rows);
    }

    return OfficeRenderResult(
      bytes: _zipXml(entries),
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      extension: 'xlsx',
      itemCount: rowCount,
    );
  }

  static OfficeRenderResult renderPresentation(JsonMap args) {
    final title = _string(args['title'], fallback: 'Presentation');
    final slides = _maps(args['slides']);
    if (slides.isEmpty) {
      throw Exception('Presentation requires at least one slide.');
    }

    final entries = <String, String>{
      '[Content_Types].xml': _pptxContentTypes(slides.length),
      '_rels/.rels': _packageRels(
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument',
        'ppt/presentation.xml',
      ),
      'ppt/presentation.xml': _pptxPresentation(slides.length),
      'ppt/_rels/presentation.xml.rels': _pptxPresentationRels(slides.length),
      'ppt/slideMasters/slideMaster1.xml': _pptxSlideMaster(),
      'ppt/slideMasters/_rels/slideMaster1.xml.rels': _pptxSlideMasterRels(),
      'ppt/slideLayouts/slideLayout1.xml': _pptxSlideLayout(),
      'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _pptxSlideLayoutRels(),
      'ppt/theme/theme1.xml': _pptxTheme(),
      'docProps/app.xml': _appProps('Presentation', slides.length),
      'docProps/core.xml': _coreProps(title),
    };
    for (var i = 0; i < slides.length; i++) {
      entries['ppt/slides/slide${i + 1}.xml'] = _pptxSlide(slides[i], i + 1);
      entries['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _pptxSlideRels();
    }

    return OfficeRenderResult(
      bytes: _zipXml(entries),
      mime:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      extension: 'pptx',
      itemCount: slides.length,
    );
  }
}

Uint8List _zipXml(Map<String, String> entries) {
  final archive = Archive();
  for (final item in entries.entries) {
    final data = utf8.encode(item.value);
    archive.addFile(ArchiveFile(item.key, data.length, data));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw Exception('Failed to encode Office zip package.');
  }
  return Uint8List.fromList(encoded);
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? fallback;
}

List<JsonMap> _maps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

List<List<dynamic>> _lists(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<List>()
      .map((item) => List<dynamic>.from(item))
      .toList(growable: false);
}

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => _string(item)).toList(growable: false);
}

List<List<String>> _tableRows(Object? value) {
  return _lists(value)
      .map((row) => row.map((cell) => _string(cell)).toList(growable: false))
      .toList(growable: false);
}

String _xmlText(Object? value) {
  return _string(value)
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String _xmlAttr(Object? value) {
  return _xmlText(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

String _packageRels(String type, String target) {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="$type" Target="$target"/>
</Relationships>''';
}

String _appProps(String app, int count) {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Mag</Application>
  <AppVersion>1.0</AppVersion>
  <${app == 'Presentation' ? 'Slides' : 'Pages'}>$count</${app == 'Presentation' ? 'Slides' : 'Pages'}>
</Properties>''';
}

String _coreProps(String title) {
  final now = DateTime.now().toUtc().toIso8601String();
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>${_xmlText(title)}</dc:title>
  <dc:creator>Mag</dc:creator>
  <cp:lastModifiedBy>Mag</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';
}

String _docxContentTypes() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>''';
}

String _docxDocument(String body) {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>$body</w:body>
</w:document>''';
}

String _docxParagraph(String text, {String? style}) {
  final styleXml =
      style == null ? '' : '<w:pPr><w:pStyle w:val="$style"/></w:pPr>';
  return '<w:p>$styleXml<w:r><w:t xml:space="preserve">${_xmlText(text)}</w:t></w:r></w:p>';
}

String _docxTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final out = StringBuffer();
  out.write('''<w:tbl><w:tblPr><w:tblBorders>
<w:top w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
<w:left w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
<w:bottom w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
<w:right w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
<w:insideH w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
<w:insideV w:val="single" w:sz="4" w:space="0" w:color="D9D9D9"/>
</w:tblBorders></w:tblPr>''');
  for (final row in rows) {
    out.write('<w:tr>');
    for (final cell in row) {
      out.write(
          '<w:tc><w:p><w:r><w:t>${_xmlText(cell)}</w:t></w:r></w:p></w:tc>');
    }
    out.write('</w:tr>');
  }
  out.write('</w:tbl>');
  return out.toString();
}

String _docxSectPr() {
  return '''<w:sectPr>
<w:pgSz w:w="12240" w:h="15840"/>
<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
</w:sectPr>''';
}

String _docxStyles() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="44"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/></w:style>
</w:styles>''';
}

String _xlsxContentTypes(int sheetCount) {
  final sheets = StringBuffer();
  for (var i = 1; i <= sheetCount; i++) {
    sheets.write(
        '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  $sheets
</Types>''';
}

String _xlsxWorkbook(List<JsonMap> sheets) {
  final out = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    final name =
        _xmlAttr(_string(sheets[i]['name'], fallback: 'Sheet${i + 1}'));
    out.write('<sheet name="$name" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>$out</sheets>
</workbook>''';
}

String _xlsxWorkbookRels(int sheetCount) {
  final out = StringBuffer();
  for (var i = 1; i <= sheetCount; i++) {
    out.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>');
  }
  out.write(
      '<Relationship Id="rId${sheetCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$out</Relationships>''';
}

String _xlsxWorksheet(List<List<dynamic>> rows) {
  final out = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    final rowIndex = r + 1;
    out.write('<row r="$rowIndex">');
    for (var c = 0; c < rows[r].length; c++) {
      out.write(_xlsxCell(rows[r][c], _xlsxRef(c, rowIndex), header: r == 0));
    }
    out.write('</row>');
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>$out</sheetData>
</worksheet>''';
}

String _xlsxCell(Object? value, String ref, {required bool header}) {
  if (value is num) {
    return '<c r="$ref"${header ? ' s="1"' : ''}><v>$value</v></c>';
  }
  if (value is Map) {
    final map = Map<String, dynamic>.from(value);
    final formula = _string(map['formula']);
    if (formula.isNotEmpty) {
      return '<c r="$ref"><f>${_xmlText(formula)}</f></c>';
    }
    value = map['value'];
  }
  return '<c r="$ref" t="inlineStr"${header ? ' s="1"' : ''}><is><t>${_xmlText(value)}</t></is></c>';
}

String _xlsxRef(int col, int row) => '${_xlsxCol(col)}$row';

String _xlsxCol(int index) {
  var n = index + 1;
  final chars = <String>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    chars.insert(0, String.fromCharCode(65 + rem));
    n = (n - rem - 1) ~/ 26;
  }
  return chars.join();
}

String _xlsxStyles() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font/><font><b/></font></fonts>
  <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
  <borders count="1"><border/></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1"/></cellXfs>
</styleSheet>''';
}

String _pptxContentTypes(int slideCount) {
  final slides = StringBuffer();
  for (var i = 1; i <= slideCount; i++) {
    slides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>');
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  $slides
</Types>''';
}

String _pptxPresentation(int slideCount) {
  final ids = StringBuffer();
  for (var i = 1; i <= slideCount; i++) {
    ids.write('<p:sldId id="${255 + i}" r:id="rId$i"/>');
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId${slideCount + 1}"/></p:sldMasterIdLst>
  <p:sldIdLst>$ids</p:sldIdLst>
  <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>''';
}

String _pptxPresentationRels(int slideCount) {
  final out = StringBuffer();
  for (var i = 1; i <= slideCount; i++) {
    out.write(
        '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>');
  }
  out.write(
      '<Relationship Id="rId${slideCount + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>');
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$out</Relationships>''';
}

String _pptxSlide(JsonMap slide, int index) {
  final title = _string(slide['title'], fallback: 'Slide $index');
  final subtitle = _string(slide['subtitle']);
  final bullets = _strings(slide['bullets']);
  final table = _tableRows(slide['table']);
  final body = StringBuffer();
  body.write(_pptxTextShape(2, title,
      x: 610000,
      y: 420000,
      w: 10900000,
      h: 700000,
      fontSize: 3600,
      bold: true));
  if (subtitle.isNotEmpty) {
    body.write(_pptxTextShape(3, subtitle,
        x: 760000, y: 1120000, w: 10400000, h: 520000, fontSize: 2200));
  }
  if (bullets.isNotEmpty) {
    final bulletText = bullets.map((item) => '• $item').join('\n');
    body.write(_pptxTextShape(4, bulletText,
        x: 900000, y: 1800000, w: 10200000, h: 3900000, fontSize: 2200));
  }
  if (table.isNotEmpty) {
    final tableText = table.map((row) => row.join('    ')).join('\n');
    body.write(_pptxTextShape(5, tableText,
        x: 900000,
        y: 1800000,
        w: 10200000,
        h: 3900000,
        fontSize: 1800,
        mono: true));
  }
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld><p:spTree>
    <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
    $body
  </p:spTree></p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''';
}

String _pptxTextShape(
  int id,
  String text, {
  required int x,
  required int y,
  required int w,
  required int h,
  required int fontSize,
  bool bold = false,
  bool mono = false,
}) {
  final paragraphs = text.split('\n').map((line) {
    return '<a:p><a:r><a:rPr lang="en-US" sz="$fontSize"${bold ? ' b="1"' : ''}>${mono ? '<a:latin typeface="Courier New"/>' : ''}</a:rPr><a:t>${_xmlText(line)}</a:t></a:r></a:p>';
  }).join();
  return '''<p:sp>
  <p:nvSpPr><p:cNvPr id="$id" name="Text $id"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>
  <p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>$paragraphs</p:txBody>
</p:sp>''';
}

String _pptxSlideRels() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''';
}

String _pptxSlideMaster() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
  <p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>
</p:sldMaster>''';
}

String _pptxSlideMasterRels() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''';
}

String _pptxSlideLayout() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" type="blank" preserve="1">
  <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>''';
}

String _pptxSlideLayoutRels() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''';
}

String _pptxTheme() {
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Mag">
  <a:themeElements>
    <a:clrScheme name="Mag"><a:dk1><a:srgbClr val="111827"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="374151"/></a:dk2><a:lt2><a:srgbClr val="F9FAFB"/></a:lt2><a:accent1><a:srgbClr val="2563EB"/></a:accent1><a:accent2><a:srgbClr val="16A34A"/></a:accent2><a:accent3><a:srgbClr val="DC2626"/></a:accent3><a:accent4><a:srgbClr val="9333EA"/></a:accent4><a:accent5><a:srgbClr val="EA580C"/></a:accent5><a:accent6><a:srgbClr val="0891B2"/></a:accent6><a:hlink><a:srgbClr val="2563EB"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink></a:clrScheme>
    <a:fontScheme name="Mag"><a:majorFont><a:latin typeface="Aptos Display"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Mag"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements>
</a:theme>''';
}
