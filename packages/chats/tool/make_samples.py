import json, sys, datetime as dt
out = sys.argv[1]
def iso(s): return s
# ---------- Claude ----------
claude = []
def cconv(uid, name, created, msgs):
    cm = []
    for i,(sender, text, extra) in enumerate(msgs):
        m = {"uuid": f"{uid}-m{i}", "text": text, "sender": sender,
             "created_at": created, "updated_at": created,
             "content": [{"type": "text", "text": text}],
             "attachments": [], "files": []}
        if extra: m.update(extra)
        cm.append(m)
    claude.append({"uuid": uid, "name": name, "summary": "", "created_at": created, "updated_at": created,
                   "account": {"uuid": "acc-sample"}, "chat_messages": cm})
cconv("c1a2b3c4-0001-4000-8000-000000000001", "유튜브 앱 기획 회의", "2026-10-12T09:15:00Z", [
 ("human", "유튜브 영상을 정리해 주는 앱을 만들고 싶어요. 어떤 기능부터 넣을까요?", None),
 ("assistant", "먼저 즐겨찾는 채널의 새 영상을 모아 보여주는 기능부터 시작하세요. 그다음 영상 요약, 마지막으로 알림 순서를 추천해요.", None),
 ("human", "좋아요. 첫 버전은 안드로이드로만 만들기로 할게요.", None),
 ("assistant", "네, 첫 버전은 안드로이드로 하기로 정했어요. 플러터로 만들면 나중에 아이폰도 쉽게 지원할 수 있어요.", None),
])
cconv("c1a2b3c4-0002-4000-8000-000000000002", "세븐 스플릿 투자 홍보 영상 대본", "2026-10-20T13:00:00Z", [
 ("human", "분할 매수 투자법을 소개하는 1분짜리 홍보 영상 대본을 써 주세요.", None),
 ("assistant", "[장면 1] 오르락내리락하는 주식 그래프. 내레이션: \"한 번에 다 사지 마세요. 일곱 번에 나눠 사세요.\"\n[장면 2] 일곱 개의 바구니에 돈을 나눠 담는 그림.", None),
 ("human", "마지막 장면은 '원칙이 수익을 만든다'로 끝내기로 결정했어요.", {"attachments": [{"file_name": "참고자료.pdf", "file_size": 1200, "file_type": "pdf", "extracted_content": "분할 매수 원칙 요약"}]}),
 ("assistant", "좋아요. 마지막 자막은 '원칙이 수익을 만든다'로 확정할게요.", None),
])
cconv("c1a2b3c4-0003-4000-8000-000000000003", "제주도 3박 4일 여행 일정", "2026-09-05T02:30:00Z", [
 ("human", "제주도 3박 4일 여행 일정을 짜 주세요. 부모님과 함께 가요.", None),
 ("assistant", "첫날은 공항 근처 해안도로와 숙소 휴식, 둘째 날은 성산 일출봉, 셋째 날은 한라산 둘레길, 넷째 날은 시장 구경 후 귀가를 추천해요.", None),
])
cconv("c1a2b3c4-0004-4000-8000-000000000004", "", "2026-11-02T23:40:00Z", [
 ("human", "혈압에 좋은 저녁 식단 알려 주세요", None),
 ("assistant", "싱겁게 조리한 생선구이, 나물 반찬, 현미밥을 추천해요. 국물은 적게 드세요.", None),
])
json.dump(claude, open(f"{out}/claude_sample.json","w"), ensure_ascii=False, indent=1)

# ---------- ChatGPT ----------
def ts(s): return dt.datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
gpt = []
def gconv(cid, title, created, turns, branch=None):
    mapping = {"root": {"id": "root", "message": None, "parent": None, "children": []}}
    sysid = "sys"
    mapping[sysid] = {"id": sysid, "parent": "root", "children": [], "message": {"id": sysid, "author": {"role": "system"}, "create_time": None, "content": {"content_type": "text", "parts": [""]}, "metadata": {"is_visually_hidden_from_conversation": True}}}
    mapping["root"]["children"].append(sysid)
    prev = sysid; t = ts(created)
    for i,(role, text) in enumerate(turns):
        nid = f"{cid}-n{i}"
        mapping[nid] = {"id": nid, "parent": prev, "children": [], "message": {"id": nid, "author": {"role": role}, "create_time": t + i*30, "content": {"content_type": "text", "parts": [text]}, "metadata": {}}}
        mapping[prev]["children"].append(nid)
        prev = nid
    if branch:
        # 다시 생성되어 버려진 답변(읽으면 안 됨)
        parent = f"{cid}-n{branch[0]}"
        bid = f"{cid}-old"
        mapping[bid] = {"id": bid, "parent": parent, "children": [], "message": {"id": bid, "author": {"role": "assistant"}, "create_time": t, "content": {"content_type": "text", "parts": [branch[1]]}, "metadata": {}}}
        mapping[parent]["children"].insert(0, bid)
    gpt.append({"title": title, "create_time": t, "update_time": t + len(turns)*30, "mapping": mapping,
                "current_node": prev, "conversation_id": cid, "id": cid, "default_model_slug": "gpt-sample", "is_archived": False})
gconv("6720a1b2-0001-8000-9000-00000000aa01", "유튜브 썸네일 문구 아이디어", "2026-10-03T11:00:00Z", [
 ("user", "유튜브 앱 소개 영상 썸네일 문구를 5개 추천해 줘"),
 ("assistant", "1. 영상 정리, 이제 앱 하나로\n2. 구독 채널 새 영상 한눈에\n3. 10초 요약으로 시간 절약\n4. 놓친 영상 없이\n5. 나만의 유튜브 비서"),
 ("user", "2번으로 하기로 했어. 글자 색은 노랑으로 할게."),
 ("assistant", "좋아요. 썸네일 문구는 '구독 채널 새 영상 한눈에', 글자 색은 노랑으로 정했어요."),
], branch=(0, "이 답변은 다시 생성되어 버려진 답변입니다"))
gconv("6720a1b2-0002-8000-9000-00000000aa02", "엑셀 가계부 만들기", "2026-08-14T05:20:00Z", [
 ("user", "엑셀로 월별 가계부를 만들고 싶어"),
 ("assistant", "날짜, 항목, 금액, 분류 열을 만들고 피벗 표로 월별 합계를 보세요."),
])
gconv("6720a1b2-0003-8000-9000-00000000aa03", "분할 매수 원칙 정리", "2026-10-25T08:00:00Z", [
 ("user", "주식 분할 매수할 때 지켜야 할 원칙을 정리해 줘"),
 ("assistant", "1. 매수 금액을 일곱 번으로 나눈다\n2. 정한 하락 폭마다 한 번씩 산다\n3. 각 회차마다 목표 수익률에서 판다\n4. 감정이 아니라 원칙으로 움직인다"),
 ("user", "하락 폭은 3%마다 한 번씩 사는 걸로 정했어"),
])
json.dump(gpt, open(f"{out}/chatgpt_sample.json","w"), ensure_ascii=False, indent=1)

# ---------- Gemini (Takeout HTML) ----------
cells = []
def cell(prompt, response, when):
    cells.append(f'''<div class="outer-cell mdl-cell mdl-cell--12-col mdl-shadow--2dp"><div class="mdl-grid"><div class="header-cell mdl-cell mdl-cell--12-col"><p class="mdl-typography--title">Gemini Apps<br></p></div><div class="content-cell mdl-cell mdl-cell--6-col mdl-typography--body-1">Prompted {prompt}<br>{when}<br><p>{response}</p></div><div class="content-cell mdl-cell mdl-cell--6-col mdl-typography--body-1 mdl-typography--text-right"></div><div class="content-cell mdl-cell mdl-cell--12-col mdl-typography--caption"><b>Products:</b><br>&emsp;Gemini Apps<br></div></div></div>''')
cell("블로그에 올릴 가을 산책 글 첫 문장 써 줘", "선선한 바람이 먼저 인사하는 계절, 오늘은 동네 공원을 천천히 걸어 봅니다.", "Oct 8, 2026, 7:10:05 PM KST")
cell("조금 더 짧게 바꿔 줘", "바람이 먼저 인사하는 계절, 공원을 걸어 봅니다.", "Oct 8, 2026, 7:12:40 PM KST")
cell("유튜브 앱에 넣을 알림 기능 이름 추천해 줘", "<b>새 영상 알리미</b>, <b>채널 소식</b>, <b>오늘의 영상</b> 중에서 골라 보세요.", "2026. 10. 15. 오전 10:05:00 KST")
cell("무릎에 무리 없는 운동 알려 줘", "수영, 실내 자전거, 걷기를 추천해요. 계단 오르기는 피하세요.", "Sep 30, 2026, 8:00:00 AM KST")
html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>내 활동</title></head><body><div class="mdl-grid">' + "".join(cells) + '</div></body></html>'
open(f"{out}/gemini_sample.html","w").write(html)
print("ok")
