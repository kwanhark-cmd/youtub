// 개인비서(통합 앱)에서 이 앱을 여는 입구. 화면·기능은 단독 앱과 똑같고,
// 단독 앱의 업데이트 확인·새 버전 띠·ⓘ 업데이트 창만 숨긴다 (업데이트는 개인비서 설정 하나로).
// 이 앱은 따로 저장해 두는 자료가 없다 (만든 사본은 임시 폴더·문서 폴더·갤러리에 저장).
import 'package:flutter/widgets.dart';

import 'main.dart';

/// 개인비서 안에서 띄우는 메타지우개 플러스 화면. [MetaCleanApp]을 hostedByAssistant 로 연다.
Widget metacleanApp() => const MetaCleanApp(hostedByAssistant: true);
