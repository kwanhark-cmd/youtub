import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_log.dart';
import '../../theme/tokens.dart';
import 'dialogs.dart';

/// 새 파일로 저장(저장 창 → 실패하면 공유하기). 사용자 원본 파일은 건드리지 않습니다.
Future<bool> saveBytes(BuildContext context, String fileName, Uint8List bytes, {String mime = 'application/octet-stream'}) async {
  try {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mime, dialogTitle: '저장할 곳을 고르세요');
    if (uri != null) {
      if (context.mounted) showNotice(context, '저장했어요!');
      return true;
    }
    return false; // 사용자가 취소
  } catch (e) {
    AppLog.warn('저장 창 실패, 공유로 대체', {'error': e.runtimeType.toString()});
  }
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: mime)],
        title: fileName,
      ),
    );
    return true;
  } catch (e) {
    AppLog.warn('공유 실패', {'error': e.runtimeType.toString()});
    if (context.mounted) showNotice(context, '파일을 저장하지 못했어요. 저장 공간을 확인해 주세요.', kind: StatusKind.problem);
    return false;
  }
}

/// 파일 하나 고르기 → (이름, 내용)
Future<(String, Uint8List)?> pickOneFile(BuildContext context, {List<String>? extensions}) async {
  try {
    final files = await FilePicker.pickFiles(
      dialogTitle: '파일을 고르세요',
      type: extensions == null ? FileType.any : FileType.custom,
      allowedExtensions: extensions,
    );
    if (files.isEmpty) return null;
    final f = files.first;
    return (f.name, await f.readAsBytes());
  } catch (e) {
    AppLog.warn('파일 고르기 실패', {'error': e.runtimeType.toString()});
    if (context.mounted) showNotice(context, '파일을 열 수 없어요. 다시 골라 주세요.', kind: StatusKind.problem);
    return null;
  }
}
