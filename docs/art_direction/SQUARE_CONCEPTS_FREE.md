# 광장 시안 — 무료 로컬 이미지 생성

- 엔진: stable-diffusion.cpp (Vulkan 빌드) + SDXL 1.0 base Q4 양자화(CreativeML Open RAIL++-M, 상업 사용 가능) + SDXL VAE fp16 수정본. 이 PC의 RTX 2060 SUPER에서 장당 약 75초. 크레딧·요금 없음
- 설치 위치: `C:\Users\a\tools\sdcpp` (저장소 밖, 약 4.3GB)
- 다시 만들기: `bash tools/art/square_concepts_sdxl.sh` → `docs/art_direction/square_concepts_free/`
- 프롬프트는 게임 설정만 사용: 네잎골, 네 문양(하트·클로버·다이아·스페이드)이 새겨진 분수, 클럽 간판 카드룸, 줄무늬 차양 가게, 게시판, 등불, 여우 소녀(루미), 작은 요정(모아)
- SDXL은 프롬프트를 약 77토큰까지만 읽어서, 스타일을 앞에 두고 내용은 짧게 씀

| 파일 | 방향 |
|---|---|
| 1_storybook_day | 손그림 동화, 낮 |
| 2_festival_evening | 저녁 축제, 줄 조명과 창문 불빛 |
| 3_playing_card_print | 트럼프 카드 그림처럼, 빨강·크림·남색·초록 네 색과 굵은 선 |
| 4_felt_and_chips | 장난감 같은 느낌, 펠트 잔디와 칩 모양 광장 |
| 5_papercraft | 종이 공작 팝업북 |
| 6_woodcut_evening | 목판화, 저녁 |

한계: SDXL 기본 모델은 분수의 문양, 캐릭터 생김새 같은 세부 지시를 잘 따르지 않음. 방향을 고른 뒤에는 같은 방향으로 여러 장을 뽑아 고르거나, 고른 그림을 바탕으로 다시 그리는(img2img) 단계가 필요함.
