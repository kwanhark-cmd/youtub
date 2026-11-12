import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metaclean/src/out_name.dart';

void main() {
  test('날짜로 이름을 짓는다 (폰 카메라와 같은 형식)', () {
    expect(dateStem(DateTime(1980, 1, 1, 12, 0, 0)), '19800101_120000');
    expect(dateStem(DateTime(2026, 11, 12, 9, 5, 7)), '20261112_090507');
  });

  test('이름에 든 날짜·시각을 뺀다', () {
    expect(scrubDateFromName('20261112_143000'), '사진');
    expect(scrubDateFromName('IMG_20261112_143000'), 'IMG');
    expect(scrubDateFromName('Screenshot_20261112-143000_Gallery'), 'Screenshot_Gallery');
    expect(scrubDateFromName('KakaoTalk_20261112_143000123'), 'KakaoTalk');
    expect(scrubDateFromName('photo_2024-03-05'), 'photo');
    expect(scrubDateFromName('2024-03-05 14.30.00'), '사진');
    expect(scrubDateFromName('1731393000000'), '사진'); // 숫자로 적은 시각
    expect(scrubDateFromName('19800101_120000'), '사진');
  });

  test('날짜가 아닌 이름은 그대로 둔다', () {
    expect(scrubDateFromName('아이폰13_전면'), '아이폰13_전면');
    expect(scrubDateFromName('DSCN0010'), 'DSCN0010');
    expect(scrubDateFromName('model_2024'), 'model_2024');
    expect(scrubDateFromName('20x20cm_frame'), '20x20cm_frame');
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

  test('파일 수정 시각을 맞춘다', () async {
    final dir = Directory.systemTemp.createTempSync('out_name_time');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/a.jpg')..writeAsStringSync('x');
    final t = DateTime(1980, 1, 1, 12, 0, 0);
    await setFileTime(f.path, t);
    expect(f.lastModifiedSync(), t);
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
