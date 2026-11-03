import 'failure.dart';

/// 화면에 보이는 모든 한국어 문구를 이 파일 한 곳에 모아 관리한다.
class S {
  S._();

  static const appName = '유튜브 블로그 채널 관리 비서';
  static const practiceMode = '연습 모드';
  static const practiceModeHint = '아직 실제 계정이나 인공지능이 연결되지 않아 가짜 자료로 연습하고 있어요.';

  // ---- 공통 버튼 ----
  static const ok = '확인';
  static const cancel = '취소';
  static const close = '닫기';
  static const save = '저장';
  static const next = '다음';
  static const back = '이전';
  static const skip = '건너뛰기';
  static const retry = '다시 시도';
  static const reconnect = '다시 연결';
  static const yes = '예';
  static const no = '아니요';
  static const delete = '삭제';
  static const copy = '복사';
  static const copied = '복사했어요.';
  static const loadMore = '더 불러오기';
  static const loading = '불러오는 중이에요…';
  static const done = '완료';
  static const edit = '수정';
  static const start = '시작';
  static const stop = '멈춤';
  static const empty = '아직 아무것도 없어요.';
  static const working = '작업 중이에요…';

  // ---- 로그인 ----
  static const loginTitle = '누가 사용하나요?';
  static const loginNewUser = '새 사용자 만들기';
  static const loginName = '이름';
  static const loginPassword = '비밀번호 (4자 이상)';
  static const loginPasswordAgain = '비밀번호 한 번 더';
  static const loginButton = '들어가기';
  static const loginWrong = '비밀번호가 맞지 않아요. 다시 입력해 주세요.';
  static const loginNameTaken = '이미 있는 이름이에요. 다른 이름을 써 주세요.';
  static const loginNameEmpty = '이름을 입력해 주세요.';
  static const loginPasswordShort = '비밀번호는 4자 이상으로 정해 주세요.';
  static const loginPasswordMismatch = '두 비밀번호가 서로 달라요.';
  static const logout = '로그아웃';
  static String loginAs(String name) => '$name 님으로 들어가기';

  // ---- 첫 실행 안내 ----
  static const wizardTitle = '처음 사용 안내';
  static const wizardStep1 = '1. 언어와 글씨 크기';
  static const wizardLanguage = '언어';
  static const wizardLanguageKo = '한국어';
  static const wizardLanguageOther = '다른 언어 (준비 중)';
  static const wizardStep2 = '2. 권한 허락';
  static const wizardPermIntro = '아래 권한은 허락하지 않아도 앱은 동작해요. 필요한 기능만 꺼져요.';
  static const permMic = '마이크';
  static const permMicWhy = '말로 명령하고 음성 메모를 남길 때 필요해요.';
  static const permNotify = '알림';
  static const permNotifyWhy = '자동 작업 시작·끝, 아침 브리핑, 만료 알림을 보내 드려요.';
  static const permStorage = '파일 저장';
  static const permStorageWhy = '직접 찍은 영상, 백업 파일을 고르고 저장할 때 필요해요.';
  static const permAllow = '허락하기';
  static const permAllowed = '허락됨';
  static const permDenied = '허락 안 됨 (괜찮아요)';
  static const wizardStep3 = '3. 계정 연결';
  static const wizardAccountIntro = '유튜브·블로그 계정은 지금 연결하거나, 나중에 설정에서 연결할 수 있어요.';
  static const wizardConnectNow = '지금 구글 계정 연결하기';
  static const wizardStep4 = '4. 연습 모드 안내';
  static const wizardPracticeIntro =
      '계정이나 인공지능 키가 없으면 "연습 모드"로 동작해요. 가짜 채널과 영상으로 모든 기능을 미리 써 볼 수 있고, '
      '실제 유튜브에는 아무것도 바뀌지 않아요. 화면 위에 "연습 모드" 표시가 보이면 연습 중이라는 뜻이에요.';
  static const wizardFinish = '시작하기';

  // ---- 메뉴 ----
  static const navHome = '홈';
  static const navChannels = '채널';
  static const navProduce = '제작';
  static const navBlog = '블로그';
  static const navCorner = '내 코너';
  static const navSettings = '설정';

  // ---- 현황 ----
  static const homeQuota = '오늘 남은 유튜브 사용량';
  static const homeCost = '이번 달 인공지능 비용';
  static const homeTodayEdits = '오늘 수정한 영상';
  static const homeReviewWaiting = '확인 기다리는 영상';
  static const homeBriefing = '아침 브리핑 듣기';
  static const homeDailyReport = '오늘 수정 내역 보기';
  static const homeRunEdits = '지금 수정 실행하기';
  static const homeVoiceSummary = '현황 음성으로 듣기';
  static const homeRunnerOff = '자동 작업: 꺼짐 (설정에서 켤 수 있어요)';
  static String homeRunnerOn(int from, int to) => '자동 작업: 켜짐 ($from시~$to시)';

  // ---- 채널 ----
  static const channelsTitle = '내 유튜브 채널';
  static const channelAdd = '채널 등록';
  static const channelUrl = '채널 주소 (예: https://youtube.com/@내채널)';
  static const channelConnectGoogle = '구글로 연결';
  static const channelConnectHint = '구글 로그인 창이 열려요. 비밀번호는 구글 창에만 입력하고, 이 앱에는 저장되지 않아요.';
  static const channelDisconnect = '연결 해제';
  static String channelDisconnectConfirm(String t) => '"$t" 채널 연결을 해제할까요? 앱에 저장된 이 채널 자료도 지워져요. (유튜브의 영상은 그대로예요)';
  static const channelSync = '새로 불러오기';
  static const channelVideos = '영상 목록';
  static const channelStyle = '채널 스타일 카드';
  static const channelEdits = '수정 내역';
  static const channelNone = '등록된 채널이 없어요. "채널 등록"을 눌러 시작해 보세요.';
  static String channelAdded(int n) => '채널 $n개를 등록했어요.';
  static String views(int n) => '조회수 ${_num(n)}';
  static String subscribers(int n) => '구독자 ${_num(n)}';
  static String videoCount(int n) => '영상 ${_num(n)}개';
  static const mockLoginTitle = '연습용 구글 로그인';
  static const mockLoginBody = '연습 모드라서 진짜 구글 창 대신 가짜 계정으로 연결해요. 실제 계정에는 아무 일도 일어나지 않아요.';
  static const mockLoginButton = '연습 계정으로 연결';

  // ---- 스타일 카드 ----
  static const styleAnalyze = '영상과 글을 분석해서 만들기';
  static const styleMood = '분위기';
  static const styleTone = '말투';
  static const styleTopics = '주로 다루는 주제';
  static const styleTitlePattern = '제목 스타일';
  static const styleAudience = '보는 사람';
  static const styleNotes = '기타 메모';
  static const styleSaved = '스타일 카드를 저장했어요.';
  static const styleEmpty = '아직 스타일 카드가 없어요. 분석 버튼을 눌러 만들어 보세요.';

  // ---- 자동 수정 ----
  static const editsTitle = '수정 내역';
  static const editRevert = '되돌리기';
  static const editRevertAll = '오늘 수정 모두 되돌리기';
  static const editReverted = '원래대로 되돌렸어요.';
  static const editRevertNewerFirst = '이 영상은 나중에 한 수정이 있어요. 가장 최근 수정부터 되돌려 주세요.';
  static const editRevertConflict = '수정한 뒤에 유튜브에서 이 영상 내용이 또 바뀌었어요. 그래도 수정 전 내용으로 되돌릴까요?';
  static const editRevertAnyway = '그래도 되돌리기';
  static const editBefore = '수정 전';
  static const editAfter = '수정 후';
  static String editViews(int before, int? after) =>
      after == null ? '수정 전 조회수 ${_num(before)}' : '조회수 ${_num(before)} → ${_num(after)}';
  static String editsDone(int n) => '영상 $n개를 수정했어요. 마음에 안 들면 언제든 되돌릴 수 있어요.';
  static const editsNone = '오늘은 수정할 영상이 없어요.';
  static const editsPreviewTitle = '이렇게 수정할게요';
  static const editsApply = '수정 적용하기';
  static String editsLimit(int n) => '채널당 하루 최대 $n개';
  static const editsFirstMonth = '처음 한 달은 채널당 하루 3개까지만 수정해요.';
  static const dailyReportTitle = '오늘 수정 내역 요약';
  static const editStatusApplied = '수정됨';
  static const editStatusReverted = '되돌림';
  static const editStatusFailed = '실패';

  // ---- 음성 ----
  static const voiceListen = '말하기';
  static const voiceListening = '듣고 있어요… 말씀하세요.';
  static const voiceNotAvailable = '이 기기에서는 음성 인식을 쓸 수 없어요. 글자로 입력해 주세요.';
  static const voiceTypeInstead = '글자로 입력';
  static const voiceCommandHint = '예: "이번 주 조회수 보여줘", "요리 채널에 쇼츠 하나 만들어"';
  static const voiceUnknown = '무슨 말씀인지 잘 모르겠어요. "도움말"이라고 말하면 할 수 있는 말을 알려 드려요.';
  static const voiceHelp =
      '이렇게 말해 보세요. 이번 주 조회수 보여줘. 비공개 영상 목록 읽어줘. 요리 채널에 쇼츠 하나 만들어. '
      '오늘 수정 내역 알려줘. 아침 브리핑 해줘. 메모, 그리고 남길 내용.';
  static const voiceMemoSaved = '음성 메모를 저장했어요.';
  static const voiceMemoTitle = '음성 메모';
  static const voiceMemoRecord = '말로 메모 남기기';
  static const voiceConfirmTitle = '중요한 작업 확인';
  static const voicePublishNotAllowed = '공개 전환은 안전을 위해 앱이 하지 않아요. 확인 대기 목록에서 유튜브로 가서 직접 공개해 주세요.';
  static const voiceDeleteNotAllowed = '영상 삭제는 안전을 위해 앱이 하지 않아요. 유튜브 스튜디오에서 직접 해 주세요.';
  static String voiceWeeklyViews(int total, int delta) =>
      '이번 주 전체 조회수는 ${_num(total)}회예요. 지난 7일 동안 ${_num(delta)}회 늘었어요.';
  static String voicePrivateList(int n, String titles) =>
      n == 0 ? '확인을 기다리는 비공개 영상이 없어요.' : '확인을 기다리는 비공개 영상이 $n개 있어요. $titles';

  // ---- 아침 브리핑 ----
  static const briefingTitle = '아침 브리핑';
  static const briefingYesterday = '어제 채널 변화';
  static const briefingToday = '오늘 할 일';
  static const briefingExpiring = '만료 임박';

  // ---- 설정 ----
  static const settingsTitle = '설정';
  static const settingsFontSize = '글씨 크기';
  static const settingsFontSmall = '보통';
  static const settingsFontLarge = '크게';
  static const settingsFontHuge = '아주 크게';
  static const settingsVoice = '음성 읽어주기';
  static const settingsVoiceRate = '읽는 속도';
  static const settingsBriefingTime = '아침 브리핑 시간';
  static const settingsBriefingOn = '아침 브리핑 켜기';
  static const settingsAi = '인공지능 연결 (API 키)';
  static const settingsAiKey = 'Claude 연결 열쇠 (API 키)';
  static const settingsAiModel = '인공지능 종류';
  static const settingsAiProvider = '인공지능 회사';
  static const settingsAiLimit = '한 달 비용 한도 (달러)';
  static const settingsAiUsed = '이번 달 사용한 비용';
  static const settingsAiKeySaved = '연결 열쇠를 안전한 곳(기기 보안 저장소)에 저장했어요.';
  static const settingsAiKeyRemove = '연결 열쇠 지우기';
  static const settingsGoogle = '구글 연결 준비 (구글 앱 번호)';
  static const settingsGoogleClientId = '구글 앱 번호 (클라이언트 ID)';
  static const settingsGoogleClientSecret = '구글 앱 비밀 값 (클라이언트 보안 비밀)';
  static const settingsGoogleHint = '설명서(README)의 "구글 연결 준비하기"를 보고 만든 값을 넣어 주세요. 비워 두면 연습 모드로 동작해요.';
  static const settingsQuotaLimit = '유튜브 하루 사용량 한도';
  static const settingsEditsPerDay = '채널당 하루 수정 개수';
  static const settingsRunner = '자동 작업 실행기';
  static const settingsRunnerOn = '자동 작업 켜기';
  static const settingsRunnerDesktopOnly = '자동 작업은 윈도우·맥 컴퓨터에서만 실행돼요. 휴대폰에서는 보기·승인·알림·음성만 쓸 수 있어요.';
  static const settingsRunnerFrom = '시작 시각';
  static const settingsRunnerTo = '끝 시각';
  static const settingsTools = '제작 도구 연결';
  static const settingsBackup = '백업 만들기';
  static const settingsRestore = '백업에서 복원';
  static const settingsBackupDone = '백업 파일을 만들었어요.';
  static const settingsRestoreDone = '복원했어요. 연결된 계정은 보안을 위해 다시 연결해 주세요.';
  static const settingsRestoreBad = '이 파일은 이 앱의 백업 파일이 아니에요.';
  static const settingsReset = '초기화 (모든 자료 삭제)';
  static const settingsReset1 = '정말 초기화할까요? 이 사용자의 채널·수정 내역·설정이 모두 지워져요. (유튜브의 영상은 그대로예요)';
  static const settingsReset2 = '마지막 확인이에요. 지운 자료는 되살릴 수 없어요. 그래도 초기화할까요?';
  static const settingsResetDone = '초기화했어요.';
  static const settingsReport = '문제 신고 (로그 내보내기)';
  static const settingsReportDone = '문제 신고 파일을 만들었어요. 이 파일을 Claude에게 보여 주세요. 비밀번호·연결 정보·열쇠는 지워져 있어요.';
  static const settingsVersion = '앱 버전';
  static const settingsChangelog = '변경 내역';
  static const settingsIphone = '아이폰 지원 (준비 중)';
  static const settingsIphoneHint = '아이폰 앱은 준비 중이에요. 다른 기기를 쓰신다면 신경 쓰지 않으셔도 돼요.';
  static const settingsProduceLimit = '하루 제작 개수 한도';
  static const settingsAiLabel = '인공지능 콘텐츠 표시 방법 (기본값)';
  static const settingsLanguage = '언어';
  static const settingsDeleteUser = '이 사용자 삭제';

  // ---- 자동 작업 ----
  static const runnerStarting = '자동 작업을 시작해요.';
  static String runnerDone(int edits, int deferred) =>
      '자동 작업이 끝났어요. 수정 $edits개${deferred > 0 ? ', 내일로 미룬 작업 $deferred개' : ''}.';
  static const runnerCostStop = '인공지능 비용 한도에 도달해서 자동 작업을 멈췄어요.';
  static const runnerQuotaDefer = '유튜브 오늘 사용량이 다 되어서 남은 작업을 내일로 미뤘어요.';
  static const progressCancel = '작업 취소';
  static const progressCancelled = '작업을 취소했어요.';

  // ---- 2단계: 제작 ----
  static const produceTitle = '콘텐츠 만들기';
  static const produceNew = '새로 만들기';
  static const produceChannel = '어느 채널에 만들까요?';
  static const produceFormat = '어떤 형식으로 만들까요?';
  static const produceTopic = '주제나 아이디어 (비워 두면 인공지능이 정해요)';
  static const produceUseMemo = '음성 메모 사용';
  static const produceMake = '만들기';
  static const produceReviewList = '확인 대기 목록';
  static const produceDrafts = '만든 콘텐츠';
  static const produceLimitReached = '오늘 만들 수 있는 개수를 다 썼어요. 설정에서 한도를 바꾸거나 내일 다시 만들어 주세요.';
  static const produceTooSimilar = '최근에 만든 콘텐츠와 너무 비슷해요. 주제를 바꿔서 다시 만들어 주세요.';
  static const produceUpload = '유튜브에 비공개로 올리기';
  static const produceUploadConfirm = '이 콘텐츠를 유튜브에 "비공개"로 올릴까요? 다른 사람에게는 보이지 않고, 확인 대기 목록에 들어가요.';
  static const produceAiLabelCheck = 'AI 콘텐츠 표시를 확인해 주세요';
  static const produceAiLabelDesc = '설명 글에 표시';
  static const produceAiLabelChannel = '채널 소개에 표시';
  static const produceAiLabelSetting = '업로드 설정의 인공지능 항목에 표시';
  static const produceNeedVideo = '올릴 영상 파일이 없어요. "내가 만든 영상 넣기" 또는 "힉스필드로 영상 만들기"를 먼저 해 주세요.';
  static const produceAddOwnVideo = '내가 만든 영상 넣기';
  static const produceHiggsfield = '힉스필드로 영상 만들기';
  static String produceHiggsfieldConfirm(int est, int left) =>
      '힉스필드로 영상을 만들면 사용권(크레딧)이 약 $est 들어요. 지금 남은 사용권은 $left이에요. 만들까요?';
  static const produceHiggsfieldNotEnough = '힉스필드 사용권(크레딧)이 부족해요.';
  static const produceOpenYoutube = '유튜브에서 확인하기';
  static const produceMarkPublished = '확인하고 공개했어요';
  static const produceUploaded = '비공개로 올렸어요. 확인 대기 목록에서 확인해 주세요.';
  static const produceDeferred = '오늘 유튜브 사용량이 부족해서 내일 올릴 수 있게 준비해 두었어요. 내일 확인 대기 목록에서 "올리기"를 눌러 주세요.';
  static const produceThumbnail = '썸네일 문구';
  static const produceScript = '대본·구성';
  static const formatShorts = '쇼츠';
  static const formatLong = '롱폼';
  static const formatDocu = '다큐멘터리';
  static const formatImage = '사진·이미지 게시물';
  static const formatTalk = '음성 대화형';

  // ---- 도구 연결 ----
  static const toolsTitle = '제작 도구 연결';
  static const toolConnected = '연결됨';
  static const toolNotConnected = '연결 안 됨';
  static const toolPreparing = '준비 중';
  static const toolTest = '연결 테스트';
  static const toolDisconnect = '연결 해제';
  static const toolConnect = '연결하기';
  static const toolApiKey = '연결 열쇠 (API 키)';
  static const toolTestOk = '연결이 잘 되어 있어요.';
  static const toolExpired = '연결이 만료되었어요. 다시 연결해 주세요.';
  static const toolPriority = '사용 우선순위';
  static const toolVideoGen = '영상 생성';
  static const toolMotion = '모션 그래픽';
  static const toolNarration = '음성 나레이션';
  static const toolVault = '앱 금고 연동 (준비 중)';

  // ---- 3단계: 블로그 ----
  static const blogTitle = '블로그 관리';
  static const blogAddBlogger = '구글 블로그 연결';
  static const blogAddTistory = '티스토리 블로그 추가';
  static const blogTistoryName = '티스토리 블로그 이름';
  static const blogTistoryUrl = '티스토리 주소 (예: https://내블로그.tistory.com)';
  static const blogPosts = '글 목록';
  static const blogNewPost = '새 글 만들기';
  static const blogRunEdits = '기존 글 다듬기';
  static const blogDraftSaved = '구글 블로그에 "초안(비공개)"으로 올렸어요. 블로그에서 확인 후 공개해 주세요.';
  static const blogTistoryCopyHint = '티스토리는 자동으로 올릴 수 없어요. 아래 "복사" 버튼으로 복사한 뒤 티스토리 글쓰기에 붙여 넣어 주세요.';
  static const blogCopyTitle = '제목 복사';
  static const blogCopyBody = '본문 복사';
  static const blogCopyTags = '태그 복사';
  static const blogNone = '등록된 블로그가 없어요.';
  static const blogPerDay = '새 글은 하루 1~2개씩만 만들어요.';

  // ---- 4단계: 사용자 코너 ----
  static const cornerTitle = '내 이야기 코너';
  static const cornerNew = '코너 만들기';
  static const cornerName = '코너 이름';
  static const cornerChannel = '올릴 채널';
  static const cornerAddVideo = '내가 찍은 영상 넣기';
  static const cornerAddMemo = '음성 메모 고르기';
  static const cornerImport = '폴더에서 소재 가져오기';
  static const cornerMake = '자동으로 만들기';
  static const cornerSubtitles = '자막';
  static const cornerCopyright = '저작권 확인';
  static const cornerCopyrightAsk = '이 소재는 저작권이 있을 수 있어요. 직접 찍었거나 사용 허락을 받은 소재인가요?';
  static const cornerCopyrightYes = '네, 사용해도 돼요';
  static const cornerCopyrightNo = '아니요, 빼 주세요';
  static const cornerNone = '아직 코너가 없어요.';

  // ---- 오류 ----
  static const errorGeneric = '문제가 생겼어요. 잠시 뒤 다시 해 주세요. 계속되면 설정 → 문제 신고를 눌러 주세요.';
  static const errorScreen = '이 화면을 보여 주는 중에 문제가 생겼어요. 뒤로 갔다가 다시 들어와 주세요.';

  static String failureMessage(FailureKind kind) {
    switch (kind) {
      case FailureKind.network:
        return '인터넷 연결이 불안정해요. 연결을 확인하고 "다시 시도"를 눌러 주세요. 저장된 자료는 그대로 볼 수 있어요.';
      case FailureKind.timeout:
        return '응답이 너무 늦어요. 잠시 뒤 "다시 시도"를 눌러 주세요.';
      case FailureKind.tokenExpired:
        return '계정 연결이 만료되었어요. "다시 연결"을 눌러 주세요.';
      case FailureKind.permissionRevoked:
        return '계정 권한이 취소되었어요. "다시 연결"을 눌러 권한을 다시 허락해 주세요.';
      case FailureKind.quotaExceeded:
        return '오늘 쓸 수 있는 유튜브 사용량을 다 썼어요. 남은 작업은 내일 이어서 할게요.';
      case FailureKind.rateLimited:
        return '잠깐 동안 요청이 너무 많았어요. 조금 뒤 "다시 시도"를 눌러 주세요.';
      case FailureKind.costLimit:
        return '이번 달 인공지능 비용 한도에 도달했어요. 설정에서 한도를 바꾸거나 다음 달에 다시 써 주세요. 그동안은 연습 모드로 동작해요.';
      case FailureKind.notConnected:
        return '아직 연결되지 않았어요. 설정에서 먼저 연결해 주세요.';
      case FailureKind.notFound:
        return '찾는 자료가 없어요. 이미 지워졌을 수 있어요.';
      case FailureKind.invalidInput:
        return '입력한 내용을 확인해 주세요.';
      case FailureKind.conflict:
        return '다른 곳에서 내용이 바뀌었어요. 새로 불러온 뒤 다시 해 주세요.';
      case FailureKind.cancelled:
        return '작업을 취소했어요.';
      case FailureKind.unknown:
        return errorGeneric;
    }
  }

  static String nextActionLabel(NextAction a) {
    switch (a) {
      case NextAction.retry:
        return retry;
      case NextAction.reconnect:
        return reconnect;
      case NextAction.tryTomorrow:
        return '내일 다시 시도';
      case NextAction.checkSettings:
        return '설정 열기';
      case NextAction.none:
        return ok;
    }
  }

  static String _num(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-$buf' : buf.toString();
  }

  static String num(int n) => _num(n);

  // ---- 화면별 문구 ----
  // 화면 개선 (공통 위젯)
  static const uiOk = '넉넉해요';
  static const uiProgress = '쓰는 중';
  static const uiLow = '얼마 안 남았어요';
  static const uiEmptyGauge = '다 썼어요';
  static const uiEmptyTitle = '아직 없어요';
  static const uiTipOk = '알겠어요';
  static const uiHome = '처음 화면으로';
  // 홈
  static const dashTodayTitle = '오늘 할 일';
  static const dashTodo = '해야 할 일이 있어요';
  static const dashAllDone = '모두 끝났어요';
  static const dashAllDoneSub = '지금은 급한 일이 없어요. 편히 쉬셔도 돼요.';
  static String dash2(String a) => '$a 연결이 끊어졌어요.';
  static String dash3(String a) => '$a 연결이 곧 끊어져요. 미리 다시 연결해 주세요.';
  static String dash4(int n) => '$n개 연결됨';
  static String dash5(int n) => '$n개 확인 필요';
  static String dash6(String name) => '$name 님, 반가워요!';
  static const dashHelloSub = '오늘도 채널 관리를 도와 드릴게요.';
  static const dashBroken = '연결 끊김';
  static const dashNoChannel = '채널 없음';
  static const dashNothingWaiting = '기다리는 것 없음';
  static const dashTileChannels = '채널 현황';
  static const dashTileChannelsSub = '내 채널과 영상 한눈에 보기';
  static const dashTileProduce = '콘텐츠 만들기';
  static const dashTileProduceSub = '쇼츠·롱폼·사진 게시물 만들기';
  static const dashTileReview = '확인 대기';
  static const dashTileReviewSub = '비공개로 올린 영상 확인하기';
  static const dashTileBlog = '블로그';
  static const dashTileBlogSub = '구글 블로그·티스토리 글 관리';
  static const dashTileBlogShort = '글 쓰고 관리하기';
  static String dashViews(String n) => '채널 · 조회수 $n';
  static const dashMaking = '만드는 중';
  static const dashTileCorner = '내 코너';
  static const dashTileCornerSub = '내 이야기로 콘텐츠 만들기';
  static const dashTileSettings = '설정';
  static const dashTileSettingsSub = '글씨 크기·연결·자동 작업';
  static String dash7(int n) => '비공개로 올린 영상 $n개가 확인을 기다려요. 보고 괜찮으면 유튜브에서 공개해 주세요.';
  static const dashReviewNow = '지금 확인하기';
  // 채널
  static const chanTip = '채널 카드를 누르면 영상 목록과 채널 스타일 카드를 볼 수 있어요. 왼쪽 띠가 초록이면 잘 연결된 것, 빨강이면 다시 연결이 필요해요.';
  static const chanEmptyHow = '"채널 등록"을 누르고 구글 계정으로 연결하면 내 채널이 모두 나타나요. 계정이 없어도 연습 계정으로 미리 써 볼 수 있어요.';
  static const chanConnected = '연결됨';
  static const chanNoVideos = '"새로 불러오기"를 누르면 유튜브에서 영상 목록을 가져와요.';
  // 수정·되돌리기
  static const editsTip = '앱이 고친 제목·설명·키워드가 모두 여기에 남아요. 마음에 안 들면 "되돌리기"를 누르면 바로 원래대로 돌아가요.';
  static const editsEmptyHow = '홈에서 "지금 수정 실행하기"를 누르면 앱이 영상 제목·설명·키워드를 다듬어요. 고친 내용은 여기서 언제든 되돌릴 수 있어요.';
  static const editsRevertAllAsk = '오늘 고친 영상을 모두 원래대로 되돌릴까요?';
  // 제작
  static const prodTip = '"새로 만들기"를 누르고 채널과 형식만 고르면 제목·설명·키워드·썸네일·대본을 한 번에 만들어 드려요. 유튜브에는 항상 "비공개"로만 올라가요.';
  static const prodEmptyHow = '"새로 만들기"를 누르고 채널과 형식(쇼츠, 롱폼 등)을 고르면 시작돼요.';
  static const prodReviewEmpty = '확인을 기다리는 영상이 없어요. 콘텐츠를 만들어 비공개로 올리면 여기에 모여요.';
  // 블로그·코너·메모
  static const blogTip = '구글 블로그는 연결하면 글을 자동으로 다듬고, 새 글은 "초안"으로만 올려요. 티스토리는 글을 만들어 드리면 "복사" 버튼으로 붙여 넣으면 돼요.';
  static const blogEmptyHow = '"구글 블로그 연결"을 누르거나, 티스토리 이름과 주소를 추가해 시작하세요.';
  static const blogWaiting = '확인 필요';
  static const cornerEmptyHow = '"코너 만들기"를 누르고 코너 이름(예: 사장님의 하루)과 올릴 채널을 정하면 시작돼요.';
  static const memoEmptyHow = '"말로 메모 남기기"를 누르고 떠오른 생각을 말해 보세요. 콘텐츠를 만들 때 소재로 쓸 수 있어요.';
  static const memoUsed = '제작에 사용함';
  // 설정 — 보기
  static const setViewTitle = '보기 (글씨·밝기·움직임)';
  static const setBrightness = '화면 밝기';
  static const setBrightAuto = '자동';
  static const setBrightLight = '밝게';
  static const setBrightDark = '어둡게';
  static const setHighContrast = '또렷하게 보기 (고대비)';
  static const setHighContrastSub = '글자와 바탕의 차이를 크게 해서 더 잘 보여요.';
  static const setReduceMotion = '움직임 줄이기';
  static const setReduceMotionSub = '화면이 움직이는 효과를 끄고 바로바로 보여 줘요.';
  static const setHaptics = '누를 때 진동';
  static const setSound = '누를 때 소리';
  static const setTipsAgain = '처음 사용 안내 다시 보기';
  static const setTipsAgainDone = '안내를 다시 보여 드릴게요.';
  static String wizStep(int n) => '$n / 4 단계';
  static String dollars(double v, [int digits = 2]) => '${v.toStringAsFixed(digits)}달러';
  // 추가 기능: 설명 템플릿
  static const tplTitle = '설명 템플릿';
  static const tplHelp = '자주 쓰는 문구·링크·해시태그를 저장해 두면, 이 채널에 새로 만드는 영상 설명 끝에 자동으로 붙어요.';
  static const tplNone = '아직 템플릿이 없어요';
  static const tplOn = '새 영상에 자동으로 붙어요';
  static const tplHelpShort = '자주 쓰는 문구·링크·해시태그 저장하기';
  static const tplMake = '템플릿 만들기';
  static const tplFixed = '고정 문구 (예: 구독과 좋아요 부탁드려요)';
  static const tplLinks = '링크 (한 줄에 하나씩)';
  static const tplTags = '해시태그 (예: #집밥 #요리)';
  static const tplSaved = '설명 템플릿을 저장했어요. 새 영상 설명에 자동으로 붙어요.';
  // 추가 기능: 일괄 수정 미리보기
  static const batchHelp = '아래 변경안을 확인하고, 적용하지 않을 것은 체크를 빼 주세요.';
  static const batchAll = '모두 고르기';
  static const batchNone = '모두 빼기';
  static const batchTitle = '제목 바뀜';
  static const batchDesc = '설명 바뀜';
  static String batchApply(int n) => '고른 $n개 적용하기';
  static const batchUndoAll = '방금 것 모두 되돌리기';
  // 추가 기능: 주목할 영상
  static const trendTitle = '주목할 영상';
  static const trendHelp = '평소보다 조회수가 빨리 늘고 있는 내 영상이에요. 비슷한 주제로 새 콘텐츠를 만들어 보세요.';
  static String trendBadge(int ratio, int perDay) => '평소보다 $ratio배 · 하루 +${num(perDay)}회';
  // 추가 기능: 검색어 추천
  static const kwSuggest = '검색어 추천';
  static const kwHelp = '넣고 싶은 검색어를 눌러 고른 뒤 "키워드에 더하기"를 눌러 주세요.';
  static const kwNone = '더 추천할 검색어가 없어요.';
  static const kwAdd = '키워드에 더하기';
  static const kwCostFree = '연습 모드라 비용이 들지 않았어요';
  static String kwCost(String usd) => '이번 추천 예상 비용 약 $usd달러';
  static String kwAdded(int n) => '검색어 $n개를 키워드에 더했어요.';
  // 추가 기능: 게시 달력
  static const calTitle = '게시 달력';
  static const calPrev = '지난달';
  static const calNext = '다음 달';
  static String calMonth(int y, int m) => '$y년 $m월';
  static const calWeekdays = ['일', '월', '화', '수', '목', '금', '토'];
  static String calDay(String d) => '${int.parse(d.substring(5, 7))}월 ${int.parse(d.substring(8, 10))}일';
  static const calNothing = '이날은 할 일이 없어요.';
  static String calCellLabel(int d, int n) => n == 0 ? '$d일' : '$d일, $n개';
  static const calMade = '만듦';
  static const calScheduled = '올릴 예정';
  static const calWaiting = '확인 대기';
  static const calPublished = '공개함';
  static const calBlogWaiting = '블로그 글 확인 대기';
  static const calBlogDone = '블로그 글 올림';
  static const calCheckLegend = '예정·확인 대기';
  // 추가 기능: 썸네일 비교 선택
  static const thumbCompare = '썸네일 2개 만들어 고르기';
  static const thumbCompareTitle = '어느 썸네일이 더 좋아요?';
  static const thumbCompareHelp = '문구와 색이 다른 썸네일 2개를 만들었어요. 마음에 드는 것을 눌러 주세요.';
  static String thumbChoice(String ab) => '$ab안';
  static const thumbChosen = '고른 썸네일을 저장했어요. 올릴 때 함께 올라가요.';
  // 긴급 수정
  static const reportFromError = '문제 신고 파일 만들기';
  static String reportMade(String path) => '문제 신고 파일을 만들었어요: $path';

  static const chanStatSubs = '구독자';
  static const chanStatVideos = '영상';
  static const chanStatViews = '조회수';

  // 구글 연결 준비 마법사
  static const gsTitle = '구글 연결 준비 마법사';
  static const gsOpenWizard = '구글 연결 준비 마법사 (처음이면 여기부터)';
  static String gsStepOf(int n, int all) => '$all단계 중 $n단계';
  static const gsPrev = '이전';
  static const gsNext = '다음';
  static const gsDone = '다 했어요';
  static const gs1Title = '1. 구글 클라우드 프로젝트 만들기';
  static const gs1Body =
      '구글 클라우드 콘솔에서 새 프로젝트를 만들어요. 이름은 아무거나 괜찮아요 (예: 채널비서). 만든 뒤 화면 위쪽에서 그 프로젝트가 선택되어 있는지 확인하세요. 돈은 들지 않아요.';
  static const gsOpenProject = '프로젝트 만들기 열기';
  static const gs2Title = '2. 유튜브·블로거 사용 켜기';
  static const gs2Body = '"YouTube Data API v3" 와 "Blogger API v3" 두 가지를 각각 열어 파란 "사용" 버튼을 눌러요. 블로그를 안 쓰면 유튜브만 켜도 돼요.';
  static const gsOpenYoutubeApi = 'YouTube Data API v3 열기';
  static const gsOpenBloggerApi = 'Blogger API v3 열기';
  static const gs3Title = '3. 앱 이름 정하기 (브랜딩)와 대상 "외부"';
  static const gs3Body =
      'Google Auth Platform → 브랜딩에서 앱 이름(예: 채널비서)과 내 이메일을 넣고 저장해요. 그다음 "대상(Audience)" 에서 사용자 유형을 "외부"로 골라요. 게시 상태는 "테스트"로 두면 돼요.';
  static const gsOpenBranding = '브랜딩 열기';
  static const gsOpenAudience = '대상(Audience) 열기';
  static const gs4Title = '4. 클라이언트 만들기: 유형 "데스크톱 앱"';
  static const gs4Body =
      '"클라이언트" 에서 "클라이언트 만들기"를 누르고 애플리케이션 유형을 꼭 "데스크톱 앱"으로 골라요. 만든 뒤 "JSON 다운로드" 를 눌러 파일을 받아 두세요 (client_secret_… 로 시작하는 파일).';
  static const gsOpenClients = '클라이언트 만들기 열기';
  static const gs5Title = '5. 테스트 사용자에 내 구글 계정 넣기';
  static const gs5Body =
      '"대상(Audience)" 아래쪽 "테스트 사용자"에서 "사용자 추가"를 눌러 유튜브 채널이 있는 내 구글 계정(지메일 주소)을 넣어요. 여기 넣은 계정만 연결할 수 있어요.';
  static const gs7Days =
      '앱이 "테스트" 상태이면 구글이 연결을 7일마다 끊어요. 끊기기 전에 앱이 알려 드리고, "다시 연결"만 누르면 돼요. 7일 제한을 없애려면 구글의 앱 확인(게시)을 받아야 해요.';
  static const gs6Title = '6. 앱 번호·비밀 값 넣기';
  static const gs6Body = '4단계에서 받은 JSON 파일을 불러오면 자동으로 채워져요. 직접 붙여 넣어도 돼요.';
  static const gsImportJson = 'JSON 파일 불러오기';
  static const gsOrType = '또는 직접 넣기';
  static const gsImported = '구글 앱 번호와 비밀 값을 불러와 저장했어요.';
  static const gsJsonErrorTitle = '이 파일은 쓸 수 없어요';
  static const gsWrongType = '유형이 달라요, 데스크톱 앱으로 다시 만들어 주세요. (4단계에서 애플리케이션 유형을 "데스크톱 앱"으로 고르고 다시 JSON 을 받아 주세요.)';
  static const gsNotJson = '구글에서 받은 JSON 파일이 아니에요. client_secret_… 로 시작하는 파일을 골라 주세요.';
  static const gsNotClientFile = '앱 번호나 비밀 값이 들어 있지 않아요. 4단계에서 "JSON 다운로드"로 받은 파일을 골라 주세요.';
  static const gs7Title = '7. 처음 연결할 때 나오는 경고';
  static const gs7Body = '내가 만든 앱은 구글의 확인을 받지 않아서 처음 연결할 때 "확인되지 않은 앱" 경고가 나와요. 내 앱이니 안심하고 아래 그림처럼 넘어가면 돼요.';
  static const gsPicTitle = 'Google에서 확인하지 않은 앱';
  static const gsPicWarning = '이 앱은 Google의 확인을 받지 않았습니다. 개발자를 알고 신뢰하는 경우에만 계속하세요.';
  static const gsPicWarningMore = '고급 설정을 눌렀더니 아래에 이 줄이 생겼어요.';
  static const gsPicAdvanced = '고급';
  static const gsPicGoTo = '채널비서(으)로 이동(안전하지 않음)';
  static const gsPicTapHere = '여기를 눌러요';
  static const gsPic1Caption = '왼쪽 아래 "고급"을 눌러요';
  static const gsPic2Caption = '아래에 생긴 "…(으)로 이동"을 눌러요';

  // 앱 꾸미기
  static const lookTitle = '앱 꾸미기';
  static const lookName = '앱 이름';
  static const lookNameHelp = '홈·창 제목·알림에 쓰여요. 비우면 기본 이름.';
  static const lookNameSaved = '앱 이름을 바꿨어요.';
  static const lookIcon = '아이콘';
  static String lookIconName(String id) => switch (id) {
    'blue' => '파랑 아이콘',
    'purple' => '보라 아이콘',
    'green' => '초록 아이콘',
    'orange' => '주황 아이콘',
    'pink' => '분홍 아이콘',
    _ => '아이콘',
  };
  static const lookIconCustom = '내 그림으로 아이콘 만들기';
  static const lookIconCustomDone = '내 그림을 아이콘으로 정했어요.';
  static const lookColor = '색 묶음';
  static const lookColorBasic = '기본';
  static const lookColorOcean = '바다';
  static const lookColorForest = '숲';
  static const lookColorSunset = '노을';
  static const lookColorContrastNote = '또렷하게 보기(고대비)를 켜면 색 묶음 대신 대비가 가장 큰 색을 써요.';
  static const lookAndroidNote =
      '기본 아이콘 5가지는 휴대폰 홈 화면 아이콘도 바로 바뀌어요 (휴대폰에 따라 잠깐 뒤에 바뀌어요). 내 그림·내 이름은 "홈 화면에 바로가기 만들기"로 홈 화면에 놓을 수 있어요.';
  static const lookDesktopNote = '컴퓨터에서는 앱 안에 바로 적용돼요. 바탕화면 바로가기 아이콘도 바꾸려면 아이콘 파일을 저장한 뒤 안내대로 하세요.';
  static const lookShortcut = '홈 화면에 바로가기 만들기';
  static const lookShortcutAsked = '홈 화면에 놓을지 묻는 창이 뜨면 "추가"를 눌러 주세요.';
  static const lookShortcutUnsupported = '이 휴대폰은 바로가기 만들기를 지원하지 않아요.';
  static const lookIconFile = '아이콘 파일 저장 (바로가기용)';
  static const lookIconFileDone = '아이콘 파일을 저장했어요';
  static const lookGuideWindows =
      '바탕화면의 "채널관리비서" 바로가기를 오른쪽 클릭 → 속성 → "아이콘 변경" → 찾아보기 → 위 .ico 파일 → 확인. 이름은 바로가기를 오른쪽 클릭 → "이름 바꾸기".';
  static const lookGuideMac =
      '위 그림 파일을 열어 "편집 → 모두 선택 → 복사" 한 뒤, 응용 프로그램 폴더의 앱을 클릭하고 "파일 → 정보 가져오기" → 왼쪽 위 작은 아이콘을 클릭하고 "붙여넣기". Dock 에서도 바뀌어요.';
  static const lookGuideOther = '바탕화면 바로가기의 아이콘을 위 그림 파일로 바꿔 주세요.';

  // 설정 묶음
  static const grpAccount = '계정 연결';
  static const grpAccountSub = '유튜브·구글 블로그 연결 준비';
  static const grpAi = '인공지능';
  static const grpAiSub = '연결 열쇠·모델·한 달 비용 한도';
  static const grpAuto = '자동 작업';
  static const grpAutoSub = '밤에 하는 일·하루 한도';
  static const grpView = '보기와 듣기';
  static const grpViewSub = '글씨·밝기·움직임·음성';
  static const grpData = '자료 관리';
  static const grpDataSub = '백업·되살리기·버전';
  static const grpDanger = '모두 지우기';
  static const grpDangerSub = '이 사용자의 모든 자료를 지워요. 지운 뒤에는 되살릴 수 없어요.';

  // 업데이트
  static const updCheck = '업데이트 확인';
  static const updCheckSub = '새 버전이 있는지 확인해요. 설치는 직접 누를 때만 해요.';
  static const updChecking = '새 버전 확인 중';
  static String updLatest(String v) => '지금 최신 버전이에요 ($v)';
  static String updNew(String v) => '새 버전 $v 이 나왔어요';
  static const updKeepsData = '설치해도 설정·연결 열쇠·채널·영상 자료는 그대로예요. 설치 전에 자동으로 백업해요.';
  static const updManual = '이 기기에서는 다운로드 페이지에서 받아 설치해 주세요.';
  static const updLater = '나중에';
  static const updInstall = '설치하기';
  static const updOpenPage = '다운로드 페이지 열기';
  static const updInstalling = '업데이트 준비 중';
  static const updBackingUp = '자료 백업 중';
  static const updDownloading = '새 버전 받는 중';
  static const updStarted = '설치 화면을 열었어요. 안내에 따라 "설치"를 눌러 주세요.';
  static const chanNoChannelAccount = '이 구글 계정에는 아직 유튜브 채널이 없어요. 채널을 가진 다른 구글 계정으로 연결해 주세요. (유튜브에서 채널을 먼저 만들어도 돼요)';
  static const chanOtherAccount = '다른 계정으로 연결';
  static String chanAddedSomeEmpty(int n, int empty) => '채널 $n개를 등록했어요. 그중 $empty개는 아직 영상이 없는 채널이에요.';
  // 연결 상태 (연습 모드 띠 대신)
  static const connTitle = '연결 상태';
  static const connGoogleOn = '구글: 연결됨';
  static const connGoogleOff = '구글: 아직 연결 안 됨';
  static const connAiOn = '인공지능: 연결됨';
  static const connAiOff = '인공지능: 아직 연결 안 됨';
  static const connAiOver = '인공지능: 이번 달 한도 도달';
  static const connPracticeHint = '가짜 자료로 연습하고 있어요. 실제 유튜브에는 아무것도 바뀌지 않아요.';
  static const connHowTo = '연결하러 가기';
  static const connPracticeShort = '가짜 자료로 연습 중';
  static const setShowPractice = '연습 자료 보기';
  static const setShowPracticeSub = '실제 채널을 연결하면 연습용 가짜 채널은 자동으로 숨겨져요. 다시 보고 싶을 때 켜세요.';
  static const setReportTop = '문제가 생겼나요? 문제 신고 파일 만들기';
  static const uiDangerSecond = '정말 할까요? 한 번 더 확인할게요.';
  static const thumbTitle = '썸네일 그림';
  static const thumbNone = '아직 썸네일 그림이 없어요. 문구로 만들거나 직접 만든 그림을 넣어 주세요.';
  static const thumbMake = '썸네일 문구로 그림 만들기';
  static const thumbAttach = '내 썸네일 그림 넣기';
  static const thumbUploadFailed = '영상은 올렸지만 썸네일은 올리지 못했어요. 유튜브 스튜디오에서 직접 넣어 주세요. (채널 인증이 안 된 경우 생길 수 있어요)';
  static String aiCostConfirm(String est, String used, String limit) =>
      '이 작업의 예상 인공지능 비용은 약 $est달러예요. (이번 달 사용 $used달러 / 한도 $limit달러) 진행할까요?';
  static const voiceEngine = '음성 인식·읽어주기 서비스';
  static const voiceEngineDevice = '기기 내장 (무료, 기본)';
  static const voiceEngineExternal = '외부 음성 서비스 (준비 중)';
  static const autoLogin = '이 기기에서 다음부터 자동으로 들어가기';
  static String join2(Object? a, Object? b) => '$a$b';
  static const prodPracticeCredits = '\n(지금은 연습 모드라 실제 크레딧은 쓰지 않아요)';
  static String videoLine(int views, String privacy, int tagCount) =>
      '${S.views(views)}${privacy == 'public' ? '' : (privacy == 'private' ? ' · 비공개' : ' · 일부 공개')}'
      '${tagCount == 0 ? ' · 키워드 없음' : ' · 키워드 $tagCount개'}';
  // blog_screen.dart
  static String blog1(Object? p0) => '블로그 $p0개를 등록했어요.';
  static const blog2 = '티스토리 · 복사해서 올리기';
  static String blog3(Object? p0) => '구글 블로그 · 글 $p0개';
  static const blog4 = '블로그 스타일 카드';
  static const blog5 = '새 글';
  static String blog6(Object? p0) => '$p0 (제목·라벨)';
  static const blog7 = '복사해서 티스토리에 올려 주세요';
  static const blog8 = '구글 블로그에 초안(비공개)으로 올림 · 확인 후 공개해 주세요';
  static const blog9 = '확인 완료';
  static const blog10 = '구글 블로그에서 열기';
  static const blog11 = '올렸어요';
  static const blog12 = '확인하고 공개했어요';
  static String blog13(Object? p0) => '글 $p0개를 다듬었어요. 마음에 안 들면 되돌릴 수 있어요.';
  static String blog14(Object? p0) => '"$p0" 블로그를 앱에서 뺄까요? (블로그의 글은 그대로예요)';
  // channels_screen.dart
  static String chan1(Object? p0) => '$p0 영상 불러오는 중';
  static String chan2(Object? p0) => '첫 불러오기 실패: $p0';
  static const chan5 = '설명';
  static const chan6 = '(없음)';
  static const chan7 = '키워드';
  static String chan8(Object? p0) => '$p0 (쉼표로 구분)';
  // corner_screen.dart
  static String corner1(Object? p0) => '$p0 (예: 사장님의 하루)';
  static const corner2 = '내 이야기를 콘텐츠로 만들어요. 직접 찍은 영상과 음성 메모를 넣으면 자막·제목·설명·키워드·썸네일을 여러 형식으로 만들어 드려요.';
  static String corner3(Object? p0, Object? p1) => '$p0 · 소재 $p1개';
  static const corner4 = '직접 찍음';
  static const corner5 = '사용 허락 받음';
  static const corner6 = '사용하기로 함';
  static const corner7 = '뺌';
  static const corner8 = '저작권 확인 필요';
  static const corner9 = '이야기 글로 쓰기';
  static String corner10(Object? p0) => '소재 ($p0)';
  static const corner11 = '저장된 음성 메모가 없어요. 마이크 버튼을 눌러 "메모, ..." 라고 말해 보세요.';
  static const corner12 = '이야기';
  static const corner13 = '들려주고 싶은 이야기';
  static String corner14(Object? p0, Object? p1) => '소재 $p0개를 가져왔어요.$p1';
  static String corner15(Object? p0) => '$p0가지 형식으로 만들었어요. "제작" 메뉴에서 확인하고 올릴 수 있어요.';
  // dashboard.dart
  static String home1(Object? p0) => '$p0개';
  // edits_screen.dart
  static String edits1(Object? p0) => '$p0 살펴보는 중';
  static String edits2(Object? p0) => '키워드: $p0';
  static const edits3 = '설명도 다듬어요';
  static String edits4(Object? p0, Object? p1, Object? p2) => '$p0$p1$p2';
  static String edits5(Object? p0, Object? p1) => '$p0개를 되돌렸어요.$p1';
  // home_shell.dart
  static const shell1 = '주기 확인 오류';
  // memos_screen.dart
  static const memo1 = '이 메모를 지울까요?';
  // onboarding.dart
  static const wiz1 = '가나다라 ABC 123 — 이 글씨 크기로 보여요.';
  static String wiz2(Object? p0) => '지금 연결된 채널: $p0개';
  // produce_screen.dart
  static const prod1 = '사용 안 함';
  static String prod2(Object? p0, Object? p1) => '오늘 만든 개수: $p0 / $p1';
  static const prod3 = '만듦 (아직 안 올림)';
  static const prod4 = '내일 올리기 준비됨';
  static const prod5 = '비공개로 올림 · 확인 기다림';
  static const prod6 = '제목';
  static const prod7 = '영상 파일';
  static String prod8(Object? p0) => '준비됨 ($p0)';
  static const prod9 = '아직 없어요';
  static const prod10 = '구글 비즈·브루 연결은 준비 중이에요. 지금은 직접 만든 영상을 넣거나 힉스필드로 만들 수 있어요.';
  static const prod11 = '사진·이미지 게시물은 유튜브 스튜디오의 "커뮤니티 게시물"에 위 글을 복사해 직접 올려 주세요.';
  static const prod12 = '이 콘텐츠를 앱에서 지울까요? (이미 유튜브에 올린 영상은 그대로예요)';
  static const prod13 = '키워드 (쉼표로 구분)';
  static const prod14 = '만들기';
  static const prod15 = '채널 소개에 "인공지능의 도움을 받아 만든 콘텐츠가 있어요" 문구가 있는지 확인해 주세요.';
  static const prod16 = '비공개로 올리기';
  static const prod17 = '비공개로 올린 영상이에요. "유튜브에서 확인하기"를 눌러 내용을 보고, 괜찮으면 유튜브에서 직접 공개해 주세요.';
  // settings_screen.dart
  static String set1(Object? p0, Object? p1) => '$p0시 $p1분';
  static const set2 = '유튜브';
  static String set3(Object? p0, Object? p1) => '$p0 ($p1)';
  static const set4 = '자료 관리';
  static String set5(Object? p0) => '지금은 $p0예요. 아래에 키를 넣으면 실제 인공지능이 켜져요.';
  static const set6 = '다른 제공자 (준비 중)';
  static const set7 = '저장된 키가 있어요 (보안을 위해 내용은 보여 주지 않아요)';
  static const set8 = '키가 없어요';
  static String set9(Object? p0) => '예: 영상 제목 다듬기 1번 ≈ $p0달러';
  static const set10 = '구글 앱이 아직 "테스트" 상태예요';
  static const set11 = '테스트 상태에서는 연결이 7일마다 만료돼요. 만료 전에 알려 드려요.';
  static const set12 = '저장했어요.';
  static const set13 = '켜면 정한 시간대에 하루 한 번: 채널 새로 불러오기 → 영상 다듬기. 시작과 끝에 알려 드려요. 업로드·삭제·공개는 하지 않아요.';
  static const set14 = '지금 한 번 실행';
  static const set15 = '작업 기록 보기';
  static String set16(Object? p0) => '$p0시';
  static const set17 = '작업 기록';
  static const set18 = '지금 자료를 이 백업으로 바꿀까요? (지금 자료도 자동으로 따로 보관해 둬요)';
  static const set19 = '내용 복사';
  // tools_screen.dart
  static String tool1(Object? p0) => '$p0: 피그마';
  static const tool2 = '영상 생성 순서 바꾸기';
  static const tool3 = '나레이션 순서 바꾸기';
  static const tool4 = '도구 비밀번호는 이 앱에 저장하지 않아요.';
  static const tool5 = '구글 비즈';
  static const tool6 = '힉스필드';
  static const tool7 = '내가 만든 영상';
  static const tool8 = '브루';
  static String tool9(Object? p0) => '힉스필드 $p0';
  static const tool10 = '피그마 연결';
  static const tool11 = '피그마 개발자 설정에서 만든 앱 정보를 넣고 "연결하기"를 누르면 피그마 로그인 창이 열려요.';
  static const tool12 = '피그마 앱 번호 (클라이언트 ID)';
  static const tool13 = '클라이언트 보안 비밀';
  // voice_sheet.dart
  static const voice1 = '잘 듣지 못했어요. 다시 눌러 말씀해 주세요.';
  static const voice2 = '취소했어요.';
  static String voice3(Object? p0) => '들은 말: "$p0"';
  // stages.dart
  static String stage1(Object? p0, Object? p1, Object? p2) => '$p0에 $p1 "$p2"을(를) 만들었어요. 제작 화면에서 확인해 주세요.';
  static const stage2 = '콘텐츠 제작';
}
