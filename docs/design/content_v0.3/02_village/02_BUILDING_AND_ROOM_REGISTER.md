# 건물·공간 레지스트리 (최초 17개 기능 공간)

| id | 지구 | 명칭 | 진입/기능 | 선행 |
|---|---|---|---|---|
| village_square | square | 네잎 광장 | 최초 스폰·게시판·아르바이트 | 시작 |
| player_home | residential | 플레이어의 집 | 수면 전환·배치·손님 초대 | 시작 |
| card_room | square | 저녁 카드룸 | 기본 원드로·모아·루미 | 저녁, 낮 문에서 대기 가능 |
| small_shop | market | 세라의 잡화점 | 등불·가구·기초 의뢰 | 시작 |
| notice_board | square | 마을 게시판 | 생활 의뢰·행사/기여 확인 | 시작 |
| post_office | residential | 노아의 우편함 | 편지·배달 연계 | 1막 도중 |
| tailor | market | 테오의 수선 가게 | 의상/장식 해금 | 의뢰 1개 |
| tea_house | market | 리라의 찻집 | 친목·대화·홈게임 초대 | 시작 |
| workshop | market | 비비의 공방 | 가구 제작 **아닌** 수선/구매·전시 | 사업1 완료 |
| reading_nook | grove | 숲길 독서 쉼터 | 카드 전설·수집 단서 | 1막 |
| lantern_path | grove | 반딧불 산책로 | 등불 이벤트·수집 | 시작 |
| waterside_deck | waterfront | 둔치 데크 | 두 주민 갈등/화해 이벤트 | 시작 |
| swap_stall | market | 작은 교환대 | NPC 고정 교환·도감 | 사업2 완료 |
| festival_square | square | 축제 부스 구역 | 반복 축제 메뉴·배치 | 3막 |
| guest_cottage | residential | 방문객 객실 | 외부 캐릭터의 *NPC 방문*, 온라인 아님 | 사업3 완료 |
| game_garden | waterfront | 카드 정원 | 캐주얼 변형 룰 모임 | 2막 |
| community_hall | square | 마을 회관 | 공공사업·마을 전시·공동 회의 | 시작, 단계별 확장 |

각 공간은 **기능이 연결된 장소**다. 완전히 별도 실내 씬이 필요 없는 `notice_board`, `lantern_path`, `festival_square` 등은 외부 상호작용 영역으로 구현 가능하다. 17개 공간이 17개 독립 건물 모델을 뜻하지 않는다. `place_id`, `scene_id`, `entrance_id`, `time_allowed`, `spawn_at_exit`, `unlock_condition` 명시.
