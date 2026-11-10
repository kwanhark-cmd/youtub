import 'dart:typed_data';

import 'cfb_meta.dart';
import 'doc_types.dart';
import 'pdf_meta.dart';
import 'zip_docs.dart';

export 'doc_types.dart';

/// 파일 내용을 보고 문서 종류를 알아낸다. 다룰 수 없으면 null.
DocKind? detectDocKind(Uint8List b) {
  if (b.length >= 5 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46) {
    return DocKind.pdf;
  }
  if (isCfb(b)) return DocKind.cfb;
  if (b.length >= 4 && b[0] == 0x50 && b[1] == 0x4B) return zipDocKind(b);
  return null;
}

/// 화면에 보일 문서 종류 이름.
String docKindLabel(DocKind kind, String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  switch (kind) {
    case DocKind.pdf:
      return 'PDF 문서';
    case DocKind.hwpx:
      return '한글 문서 (hwpx)';
    case DocKind.ooxml:
      return switch (ext) {
        'xlsx' => '엑셀 문서 (xlsx)',
        'pptx' => '파워포인트 문서 (pptx)',
        _ => '워드 문서 (docx)',
      };
    case DocKind.cfb:
      return switch (ext) {
        'doc' => '워드 문서 (doc, 옛 형식)',
        'xls' => '엑셀 문서 (xls, 옛 형식)',
        'ppt' => '파워포인트 문서 (ppt, 옛 형식)',
        _ => '한글 문서 (hwp)',
      };
  }
}

const _unsupported = DocUnsupported(
    '지원하지 않는 파일이에요. PDF, 한글(hwp·hwpx), 워드(docx·doc), 엑셀, 파워포인트 문서를 골라 주세요.');

/// 문서의 메타데이터를 "이름 → 값"으로 읽는다.
Map<String, String> readDocMeta(Uint8List bytes) {
  switch (detectDocKind(bytes)) {
    case DocKind.pdf:
      return readPdfMeta(bytes);
    case DocKind.ooxml:
      return readOoxmlMeta(bytes);
    case DocKind.hwpx:
      return readHwpxMeta(bytes);
    case DocKind.cfb:
      return readCfbMeta(bytes);
    case null:
      throw _unsupported;
  }
}

/// 문서의 메타데이터를 전부 지우거나([edit]가 null) 일부만 고친 사본을 만든다.
DocOutput cleanDocument(Uint8List bytes, {DocEdit? edit}) {
  switch (detectDocKind(bytes)) {
    case DocKind.pdf:
      return cleanPdf(bytes, edit: edit);
    case DocKind.ooxml:
      return cleanOoxml(bytes, edit: edit);
    case DocKind.hwpx:
      return cleanHwpx(bytes, edit: edit);
    case DocKind.cfb:
      return cleanCfb(bytes, edit: edit);
    case null:
      throw _unsupported;
  }
}
