import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/out_name.dart';
import 'package:metaclean/src/photo_edit.dart' show DateAction;

void main() {
  test('날짜로 이름을 짓는다 (폰 카메라와 같은 형식)', () {
    expect(dateStem(DateTime(1980, 1, 1, 12, 0, 0)), '19800101_120000');
    expect(dateStem(DateTime(2026, 11, 12, 9, 5, 7)), '20261112_090507');
  });

  group('내용 구분 글자', () {
    test('6자 16진수이고, 같은 내용이면 같고 다른 내용이면 다르다', () {
      final a = contentTag(Uint8List.fromList([1, 2, 3, 4]));
      final b = contentTag(Uint8List.fromList([1, 2, 3, 5]));
      expect(a, matches(RegExp(r'^[0-9a-f]{6}$')));
      expect(contentTag(Uint8List.fromList([1, 2, 3, 4])), a);
      expect(b, isNot(a));
      expect(contentTag(const []), matches(RegExp(r'^[0-9a-f]{6}$')));
    });

    test('많은 사진에서도 거의 겹치지 않는다', () {
      final seen = <String>{};
      for (var i = 0; i < 2000; i++) {
        seen.add(contentTag([i & 0xFF, i >> 8, 7, 7, 7, 7, 7, 7]));
      }
      expect(seen.length, greaterThan(1995));
    });
  });

  group('사진 지우기 결과 이름', () {
    test('원본 이름을 쓰지 않는다 (날짜·기기 표시가 남지 않는다)', () {
      final out = Uint8List.fromList(List.generate(64, (i) => i));
      final stem = cleanStem(out);
      expect(stem, '사진_${contentTag(out)}');
      expect(stem, matches(RegExp(r'^사진_[0-9a-f]{6}$')));
    });
  });

  group('사진 수정 결과 이름', () {
    final out = Uint8List.fromList(List.generate(64, (i) => i * 3 & 0xFF));
    final tag = contentTag(out);
    // 폰·메신저가 짓는 여러 가지 이름: 어느 것이든 날짜를 지우면 이름에 남지 않아야 한다
    const cameraNames = [
      '20261112_143000.jpg',
      'IMG_20261112_143000.jpg',
      'PXL_20261112_143000123.jpg',
      'Screenshot_20261112-143000_Gallery.jpg',
      'KakaoTalk_20261112_143000123.jpg',
      '1731393000000.jpg',
      '1699999999999.jpg',
      'IMG-20261112-WA0001.jpg',
      '12-11-2026 14.30.00.jpg',
      '261112_143000.jpg',
      'signal-2026-11-12-14-30-00-123.jpg',
    ];

    test('날짜를 바꾸면 바꾼 날짜로 짓는다', () {
      for (final name in cameraNames) {
        final stem = editStem(
          dateAction: DateAction.change,
          date: DateTime(1980, 5, 5, 12, 0, 0),
          originalName: name,
          out: out,
        );
        expect(stem, '19800505_120000_$tag');
      }
    });

    test('날짜를 지우면 원본 이름을 전혀 쓰지 않는다', () {
      for (final name in cameraNames) {
        final stem = editStem(
            dateAction: DateAction.remove, originalName: name, out: out);
        expect(stem, '사진_$tag');
      }
    });

    test('날짜를 그대로 두면 원본 이름을 잇는다', () {
      expect(
        editStem(
            dateAction: DateAction.keep,
            originalName: '20261112_143000.jpg',
            out: out),
        '20261112_143000_$tag',
      );
      expect(
        editStem(dateAction: DateAction.keep, originalName: '.jpg', out: out),
        '사진_$tag',
      );
    });

    test('같은 날짜로 바꾼 서로 다른 사진은 이름이 다르다', () {
      String stem(List<int> bytes) => editStem(
            dateAction: DateAction.change,
            date: DateTime(1980, 5, 5, 12),
            originalName: 'a.jpg',
            out: bytes,
          );
      expect(stem([1, 2, 3]), isNot(stem([1, 2, 4])));
      expect(stem([1, 2, 3]), stem([1, 2, 3]));
    });
  });

  test('확장자를 뗀다', () {
    expect(baseName('20261112_143000.jpg'), '20261112_143000');
    expect(baseName('a.b.png'), 'a.b');
    expect(baseName('noext'), 'noext');
  });

  test('겹치는 이름은 _2, _3 을 붙인다', () {
    final dir = Directory.systemTemp.createTempSync('out_name_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final a = uniquePathIn(dir, '19800101_120000', 'jpg');
    File(a).writeAsStringSync('x');
    final b = uniquePathIn(dir, '19800101_120000', 'jpg');
    File(b).writeAsStringSync('x');
    final c = uniquePathIn(dir, '19800101_120000', 'jpg');
    expect(a.split('/').last, '19800101_120000.jpg');
    expect(b.split('/').last, '19800101_120000_2.jpg');
    expect(c.split('/').last, '19800101_120000_3.jpg');
  });

  test('작업 폴더: 새로 만들고, 30분 지난 옛 폴더만 지운다', () async {
    final tmp = Directory.systemTemp.createTempSync('out_name_run');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final now = DateTime.now().microsecondsSinceEpoch;
    final old = Directory('${tmp.path}/edit_${now - const Duration(hours: 2).inMicroseconds}')..createSync();
    final recent = Directory('${tmp.path}/edit_${now - const Duration(minutes: 5).inMicroseconds}')..createSync();
    final other = Directory('${tmp.path}/clean_${now - const Duration(hours: 2).inMicroseconds}')..createSync();

    final run = await freshRunDir(tmp, 'edit_');
    expect(run.existsSync(), isTrue);
    expect(old.existsSync(), isFalse); // 오래된 같은 화면 폴더는 삭제
    expect(recent.existsSync(), isTrue); // 방금 것은 아직 공유 중일 수 있어 남김
    expect(other.existsSync(), isTrue); // 다른 화면 폴더는 건드리지 않음
  });
}
