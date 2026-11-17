import 'package:assistant_core/assistant_core.dart';

import '../modules/channel_module.dart';
import '../modules/chats_module.dart';
import 'assistant_state.dart';
import 'data_folders.dart';

/// 찾은(또는 직접 고른) 폴더를 모듈에 연결하고, 결과를 쉬운 말로 돌려준다. 폴더는 읽기만 한다.
class FolderLinker {
  FolderLinker(this.s);
  final AssistantState s;

  ConnectedFolders get connected => ConnectedFolders(s.settings);

  bool isConnected(FolderMatch m) => connected.of(m.module).contains(m.path);

  Future<String> connect(FolderMatch m) async {
    try {
      final msg = switch (m.module) {
        ModuleId.chats => await _chats(m),
        ModuleId.channel => await _channel(m),
        _ => null,
      };
      if (msg == null) return '이 폴더는 아직 연결할 수 있는 모듈이 없어요.';
      CoreLog.info('자료 폴더 연결 (${m.module.title}): ${m.name}');
      return msg;
    } catch (e, st) {
      CoreLog.error('자료 폴더 연결 실패 (${m.module.title})', e, st);
      return '연결하지 못했어요. 다시 시도해 보고, 계속되면 설정 → 문제 신고를 눌러 주세요.';
    }
  }

  Future<String> _chats(FolderMatch m) async {
    final r = await (s.modules.of(ModuleId.chats) as ChatsModule).importFolder(m.path);
    if (r == null) return 'AI 대화 기록에 잠금 번호가 있어요. 대화 모듈을 한 번 열어 잠금을 푼 뒤 다시 눌러 주세요.';
    connected.add(m.module, m.path);
    if (r.files == 0) return '대화 내보내기 파일(zip·json·html)을 찾지 못했어요. 연결은 해 두었으니 파일을 넣고 다시 눌러 주세요.';
    return '대화 파일 ${r.files}개 중 ${r.done}개를 가져왔어요.${r.failed > 0 ? ' 읽지 못한 파일 ${r.failed}개는 대화 모듈에서 확인해 주세요.' : ''} 이미 있던 대화는 늘어나지 않아요.';
  }

  Future<String> _channel(FolderMatch m) async {
    final r = await (s.modules.of(ModuleId.channel) as ChannelModule).connectFolder(m.path);
    if (r == null) return '채널을 먼저 등록해 주세요 (채널 관리 → 채널 추가). 그다음 다시 누르면 "📁 ${m.name}" 코너로 들어가요.';
    connected.add(m.module, m.path);
    final check = r.needCheck > 0 ? ' 저작권 확인이 필요한 것 ${r.needCheck}개는 코너에서 사용 여부를 정해 주세요.' : '';
    return '"📁 ${m.name}" 코너에 소재 ${r.added}개를 넣었어요 (이미 있던 것 ${r.skipped}개).$check';
  }
}
