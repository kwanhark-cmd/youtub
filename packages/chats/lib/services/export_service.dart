import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';

enum ExportFormat { markdown, text, pdf }

extension ExportFormatInfo on ExportFormat {
  String get label => switch (this) {
    ExportFormat.markdown => '마크다운 문서(.md)',
    ExportFormat.text => '글자 파일(.txt)',
    ExportFormat.pdf => 'PDF 문서(.pdf)',
  };
  String get ext => switch (this) {
    ExportFormat.markdown => 'md',
    ExportFormat.text => 'txt',
    ExportFormat.pdf => 'pdf',
  };
}

/// 대화 하나를 문서로 내보냅니다(새 파일을 만들 뿐, 원본은 건드리지 않음).
class ExportService {
  static final _date = DateFormat('yyyy년 M월 d일 HH:mm');

  static String roleLabel(Role r, AiSource s) => switch (r) {
    Role.user => '나',
    Role.assistant => s.label,
    Role.system => '안내',
  };

  static String safeFileName(String title) {
    final t = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').trim();
    final short = t.length > 40 ? t.substring(0, 40) : t;
    return short.isEmpty ? '대화' : short;
  }

  static String markdown(ConversationSummary c, List<Message> msgs, {List<Note> notes = const []}) {
    final b = StringBuffer()
      ..writeln('# ${c.title}')
      ..writeln()
      ..writeln('- AI: ${c.source.label}')
      ..writeln('- 날짜: ${_date.format(c.createdAt)}')
      ..writeln('- 메시지: ${msgs.length}개');
    if (c.link != null) b.writeln('- 원래 대화: ${c.link}');
    if (c.summary != null) b.writeln('- 요약: ${c.summary}');
    b.writeln();
    for (final m in msgs) {
      b.writeln('## ${roleLabel(m.role, c.source)}${m.time != null ? ' (${_date.format(m.time!)})' : ''}');
      b.writeln();
      b.writeln(m.text);
      for (final a in m.attachments) {
        b.writeln();
        b.writeln('> 첨부: $a (파일 내용은 내보내기에 들어 있지 않아요)');
      }
      b.writeln();
    }
    if (notes.isNotEmpty) {
      b.writeln('## 내 메모');
      for (final n in notes) {
        b.writeln('- ${_date.format(n.createdAt)}: ${n.text}');
      }
    }
    return b.toString();
  }

  static String plainText(ConversationSummary c, List<Message> msgs, {List<Note> notes = const []}) {
    final b = StringBuffer()
      ..writeln(c.title)
      ..writeln('${c.source.label} · ${_date.format(c.createdAt)}')
      ..writeln('=' * 30);
    for (final m in msgs) {
      b.writeln('[${roleLabel(m.role, c.source)}]');
      b.writeln(m.text);
      for (final a in m.attachments) {
        b.writeln('(첨부: $a)');
      }
      b.writeln();
    }
    if (notes.isNotEmpty) {
      b.writeln('[내 메모]');
      for (final n in notes) {
        b.writeln('- ${n.text}');
      }
    }
    return b.toString();
  }

  static Future<Uint8List> pdf(
    ConversationSummary c,
    List<Message> msgs, {
    required ByteData regularFont,
    required ByteData boldFont,
    List<Note> notes = const [],
  }) async {
    final regular = pw.Font.ttf(regularFont);
    final bold = pw.Font.ttf(boldFont);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Text(c.title, style: pw.TextStyle(font: bold, fontSize: 18)),
          pw.SizedBox(height: 4),
          pw.Text('${c.source.label} · ${_date.format(c.createdAt)}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.Divider(),
          for (final m in msgs) ...[
            pw.Text(
              roleLabel(m.role, c.source),
              style: pw.TextStyle(font: bold, fontSize: 11, color: m.role == Role.user ? PdfColors.indigo : PdfColors.deepOrange),
            ),
            for (final para in m.text.split('\n'))
              pw.Paragraph(text: para.isEmpty ? ' ' : para, style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2)),
            for (final a in m.attachments) pw.Text('첨부: $a', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 8),
          ],
          if (notes.isNotEmpty) ...[
            pw.Divider(),
            pw.Text('내 메모', style: pw.TextStyle(font: bold, fontSize: 12)),
            for (final n in notes) pw.Bullet(text: n.text, style: const pw.TextStyle(fontSize: 10)),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
