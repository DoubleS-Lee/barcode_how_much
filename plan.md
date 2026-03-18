# 얼마였지? — 개발 실행 계획 (plan.md)

> 최초 작성: 2026-03-18
> 기반 문서: [research.md](./research.md)
> 목적: MVP부터 글로벌 확장까지 에이전트 기반 개발 아키텍처 및 실행 계획

---

## 목차

1. [프로젝트 요약](#1-프로젝트-요약)
2. [확정 기술 스택](#2-확정-기술-스택)
3. [에이전트 기반 개발 아키텍처](#3-에이전트-기반-개발-아키텍처)
4. [Phase 1: MVP 개발 계획](#4-phase-1-mvp-개발-계획)
5. [Phase 2: 성장 + 일본 진출](#5-phase-2-성장--일본-진출)
6. [Phase 3: 글로벌 확장](#6-phase-3-글로벌-확장)
7. [에이전트 작업 지시 규격](#7-에이전트-작업-지시-규격)
8. [품질 기준 & 검수 체크리스트](#8-품질-기준--검수-체크리스트)

---

## 1. 프로젝트 요약

| 항목 | 내용 |
|---|---|
| 앱 이름 | **얼마였지?** |
| 핵심 가치 | 마트 바코드 스캔 → 2초 안에 온라인 최저가 + 내 이전 스캔가 비교 |
| 핵심 메시지 | "마트의 가짜 세일에 속지 마세요" |
| 플랫폼 | iOS + Android (Flutter) |
| 수익 모델 | AdMob 배너 광고 + 쿠팡 파트너스 제휴 커미션 |
| MVP 범위 | 바코드 스캔 + 쿠팡/네이버 가격 비교 + 내 스캔 이력 로컬 저장 |

**MVP 우선순위**

| 우선순위 | 기능 |
|---|---|
| **[P0]** | 바코드 스캐너 (Type 1 UX — 앱 실행 즉시 카메라) |
| **[P0]** | 쿠팡 파트너스 API + 네이버 쇼핑 API 연동 (병렬 호출) |
| **[P0]** | Redis 캐싱 (2초 이내 응답 목표) |
| **[P1]** | 가격 비교 결과 화면 + 수동 저장 팝업 (거대 키패드 UI) |
| **[P1]** | 내 스캔 이력 로컬 저장 + 재스캔 시 변동 표시 |
| **[P1]** | AdMob 배너 광고 (결과 화면 하단) |
| **[P1]** | 카카오톡 공유 기능 |

---

## 2. 확정 기술 스택

### 프론트엔드
```
Flutter (Dart)
├── 상태 관리: Riverpod (또는 Bloc — 팀장 에이전트가 프로젝트 초기 결정)
├── 바코드 스캔: google_mlkit_barcode_scanning (패키지)
├── 로컬 저장: Hive (빠른 NoSQL, 가입 없이도 이력 유지)
├── 광고: google_mobile_ads (AdMob SDK)
├── 소셜 공유: kakao_flutter_sdk
├── 네트워킹: dio (HTTP 클라이언트)
├── 스플래시: flutter_native_splash
├── 스켈레톤 UI: shimmer
└── 로컬 설정 저장: shared_preferences (온보딩 동의 여부 등)
```

### 백엔드
```
Node.js (Express.js 또는 Fastify)
├── 언어: TypeScript (타입 안전성, 자동완성)
├── ORM: Prisma (PostgreSQL)
├── 캐싱: ioredis (Redis 클라이언트)
└── API 문서: Swagger/OpenAPI 자동 생성
```

### 인프라
```
데이터베이스: PostgreSQL 16
캐시: Redis 7
클라우드: AWS (ap-northeast-2, 서울 리전) 또는 Naver Cloud Platform
배포: Docker + Docker Compose (로컬) → ECS Fargate 또는 EC2 (프로덕션)
CI/CD: GitHub Actions
```

### 외부 API (MVP)
```
쿠팡 파트너스 API  — 상품 검색, 가격 조회, 제휴 링크 생성
네이버 쇼핑 검색 API — 상품 검색, 최저가 조회
```

---

## 3. 에이전트 기반 개발 아키텍처

이 프로젝트는 **Claude Agent SDK**를 활용하여 AI 에이전트들이 병렬로 코드를 작성하고, 팀장 에이전트가 검토·검증·재작업 지시를 내리는 구조로 개발한다.

### 3-1. 에이전트 계층 구조

```
┌─────────────────────────────────────────────────────┐
│                   팀장 에이전트 (Lead)               │
│  역할: 전체 조율, 코드 리뷰, 품질 검증, 재작업 지시  │
│  모델: claude-opus-4-6 (가장 강력한 모델)            │
└────────────────────┬────────────────────────────────┘
                     │ 작업 지시 / 결과 수신
         ┌───────────┼───────────┬──────────────┐
         │           │           │              │
    ┌────▼───┐  ┌────▼───┐  ┌───▼────┐  ┌─────▼──┐
    │Flutter │  │Backend │  │  API   │  │  QA    │
    │Manager │  │Manager │  │Manager │  │Manager │
    │(Dart)  │  │(Node)  │  │(연동)  │  │(테스트)│
    └────────┘  └────────┘  └────────┘  └────────┘
    병렬 실행   병렬 실행   병렬 실행   병렬 실행
```

### 3-2. 팀장 에이전트 (Lead Agent)

**역할 및 책임**

| 책임 | 구체적 행동 |
|---|---|
| **작업 분배** | 기능 요구사항을 매니저별 태스크로 쪼개서 지시 |
| **병렬 조율** | 의존성 있는 작업은 순차, 독립 작업은 병렬 실행 |
| **코드 리뷰** | 매니저가 제출한 코드를 검토. 버그, 보안, 성능 이슈 체크 |
| **품질 검증** | 단위 테스트 커버리지, API 응답 속도, 요구사항 충족 여부 확인 |
| **재작업 지시** | 기준 미달 시 구체적인 수정 지침과 함께 재작업 지시 |
| **통합 검증** | 각 매니저 결과물을 합쳤을 때 전체 시스템이 동작하는지 확인 |
| **문서화** | API 스펙, 변경 이력, 결정 사항 자동 문서화 |

**팀장이 재작업을 지시하는 기준**

```
재작업 트리거 조건:
├── 단위 테스트 실패 (커버리지 < 70%)
├── API 응답 시간 > 500ms (Redis 캐시 상태)
├── 바코드 인식 속도 > 200ms (정상 조도)
├── 보안 취약점 감지 (SQL 인젝션, API 키 노출 등)
├── 요구사항 명세 미충족 (예: 병렬 API 호출 대신 순차 호출)
├── 코드 스타일 불일치 (ESLint/Dart Analyzer 오류)
├── 하드코딩된 설정값 (API 키, URL 등 .env 미사용)
└── 네이티브 설정 파일 미수정 (AdMob/카카오 Dart 코드만 짜고 Info.plist·AndroidManifest.xml 누락)
```

**팀장 에이전트 시스템 프롬프트 (핵심)**

```
당신은 "얼마였지?" 앱 개발 팀장입니다.

역할:
- 매니저 에이전트들에게 구체적인 코딩 태스크를 지시한다
- 결과물을 받으면 반드시 코드를 직접 확인하고 검증한다
- 기준 미달 시 "무엇이 왜 문제인지"를 명시하고 재작업을 지시한다
- 모든 매니저의 작업이 완료되면 통합 테스트를 지시한다

검토 우선순위:
1. 기능 정확성 (요구사항 명세 100% 충족)
2. 성능 (2초 스캔 목표, API 500ms 이하)
3. 보안 (API 키 관리, 사용자 데이터 보호)
4. 코드 품질 (가독성, 유지보수성)

절대 통과 금지:
- 순차 API 호출 (병렬 호출이 아닌 경우)
- API 키가 코드에 하드코딩된 경우
- 에러 처리 없는 외부 API 호출
- 테스트 코드 없는 핵심 비즈니스 로직
```

---

### 3-3. 매니저 에이전트 구성

#### Flutter Manager (프론트엔드)

**담당 영역**: 전체 앱 UI/UX, 바코드 스캔 화면, 결과 화면, 이력 화면, 카카오 공유

**작업 방식**
- Flutter/Dart 전문 에이전트
- 모든 화면 컴포넌트를 독립 위젯으로 분리 개발
- 상태 관리, 로컬 저장(Hive), AdMob 연동 포함
- 팀장에게 제출 시: 화면 설명 + 코드 + 위젯 트리 구조

**주요 태스크 (Phase 1)**
```
T-F01: 앱 기본 구조 설정 (main.dart, 라우팅, 테마)
        - flutter_native_splash 패키지로 스플래시 화면 설정
          → 앱 실행 시 흰 화면 번쩍임 방지. 로고 + 브랜드 컬러 배경
          → Cold Start → 스플래시 → (최초 1회 온보딩) → 카메라 화면
        - [최초 1회] 온보딩/개인정보 동의 화면
          → device_uuid 서버 저장에 대한 동의 필수
          → 동의 없이 서버 데이터 전송 시 개인정보보호법 위반 + 앱스토어 리젝
          → 구성: "가짜 세일 판별을 시작합니다!" 한 줄 + 필수 약관 동의 체크박스 + 시작 버튼
          → SharedPreferences로 동의 여부 저장 → 2회차부터 완전 생략
          → [주의] 위치 권한은 여기서 요청하지 않음
              앱 시작 시 위치 요청 = 거부율 높음 + Apple/Google 가이드라인 위반
              위치 권한은 T-F04 수동 저장 팝업에서 필요할 때만 요청
T-F02: 바코드 스캐너 화면 (Type 1 UX — 앱 실행 즉시 카메라)
        - 네트워크 지연/단절 시 UX 처리 (대형 마트 지하 데드존 대응)
          → API 호출 중: 스켈레톤 UI (결과 카드 영역에 shimmer 애니메이션)
          → 타임아웃(3초) 발생 시: 에러 코드 대신 친근한 안내
            "마트 안이라 인터넷이 느려요! 조금 이동해서 다시 찍어볼까요?" + [다시 시도] 버튼
          → 완전 오프라인(네트워크 없음): "인터넷 연결을 확인해주세요" + 로컬 이력은 그대로 표시
          → shimmer 패키지 사용 (shimmer: ^3.0.0)
T-F03: 가격 비교 결과 화면 (최저가 하이라이트, 제휴 링크 버튼)
T-F04: 수동 저장 팝업 (거대 숫자 키패드 UI)
        - 가격 입력 완료 후 "지금 마트 위치도 같이 기록할까요?" 버튼 표시
        - [여기서 위치 권한 요청] — 맥락이 명확하므로 허용률 높음
          → 허용: GPS 좌표 수집 + 역지오코딩으로 "이마트 강남점 근처" 표시
          → 거부: 위치 없이 가격만 저장 (강요하지 않음)
T-F05: 내 스캔 이력 화면 + 가격 변동 그래프
        - 가로축: 스캔 날짜, 세로축: 금액 (온라인 최저가 + 수동 입력 오프라인 가격)
        - 차트 라이브러리: fl_chart (Flutter 생태계 표준, 무료)
        - 데이터 포인트: 스캔 1회 = 점 1개. 탭 시 날짜/가격 툴팁 표시
        - 선 색상: 온라인 최저가(파랑), 수동 입력 오프라인 가격(주황) — 두 선 겹쳐서 비교
        - Y축: 최저값 하단 여백 10%, 최고값 상단 여백 10% (꽉 차지 않게)
        - X축: 날짜 라벨 (MM/DD 형식), 데이터 많을 시 자동 skip
        - 그래프 하단: 날짜별 스캔 목록 (스크롤 가능)
T-F06: AdMob 배너 광고 연동 (결과 화면 하단)
        - Dart 코드(google_mobile_ads 패키지) 구현
        - [필수 — 누락 시 앱 크래시] 네이티브 설정 파일 동시 수정
          → Android: android/app/src/main/AndroidManifest.xml
              <meta-data android:name="com.google.android.gms.ads.APPLICATION_ID"
                         android:value="ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX"/>
          → iOS: ios/Runner/Info.plist
              <key>GADApplicationIdentifier</key>
              <string>ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX</string>
          → 위 설정 없으면 앱 실행 즉시 크래시 (Dart 코드가 아무리 완벽해도 소용없음)
T-F07: 카카오톡 공유 기능
        - Dart 코드(kakao_flutter_sdk 패키지) 구현
        - [필수 — 누락 시 앱 크래시] 네이티브 설정 파일 동시 수정
          → Android: android/app/src/main/AndroidManifest.xml
              카카오 커스텀 URL 스킴, 인터넷 권한, 쿼리 스킴 설정
          → iOS: ios/Runner/Info.plist
              카카오 네이티브 앱 키, LSApplicationQueriesSchemes 설정
          → android/app/build.gradle: manifestPlaceholders 설정
          → 위 설정 없으면 카카오 로그인/공유 호출 즉시 크래시
T-F08: 권한 처리 + iOS ATT + Debounce (앱스토어 리젝 방지)
        - 카메라 권한 요청/거부 안내 UI
        - [iOS 필수] ATT(App Tracking Transparency) 팝업 구현
          → iOS 14.5+ 에서 AdMob 사용 시 법적 의무. 누락 시 Apple 심사 100% 리젝
          → AppTrackingTransparency 패키지 사용
          → 앱 첫 실행 시 카메라 권한 직후 순차 표시
        - [성능 필수] 바코드 스캐너 Debounce 로직
          → 동일 바코드를 2~3초 내 재인식 시 API 중복 호출 차단
          → 구현: 마지막 스캔 바코드 + 타임스탬프 저장, 3초 이내 동일 바코드면 skip
          → 없으면 카메라가 초당 수십 회 API 호출 → Rate Limit 즉시 초과
```

---

#### Backend Manager (백엔드)

**담당 영역**: Node.js API 서버, PostgreSQL 스키마, Redis 캐싱 레이어, 비즈니스 로직

**작업 방식**
- TypeScript + Node.js 전문 에이전트
- RESTful API 설계 및 구현
- 모든 엔드포인트에 Swagger 문서 자동 생성
- 팀장에게 제출 시: API 스펙 + 코드 + 테스트 결과

**주요 태스크 (Phase 1)**
```
T-B01: 프로젝트 구조 설정 (TypeScript, ESLint, Prettier)
T-B02: PostgreSQL 스키마 설계 및 Prisma 마이그레이션
        - devices: 익명 기기 (device_uuid, os, country, app_version)
        - products: 상품 마스터 (barcode, name, brand, category, image_url)
        - scans: 스캔 이벤트 팩트 테이블 (device_id, barcode, lat, lng, scanned_at)
        - online_prices: 스캔 당시 플랫폼별 전체 가격 (scan_id, platform, price, is_lowest)
        - offline_prices: 유저 수동 입력 오프라인 가격 (scan_id, price, store_hint)
T-B03: Redis 캐싱 레이어 구현 (TTL 30분)
T-B04: 가격 조회 엔드포인트 (GET /price?barcode={ean})
        - Redis 캐시 확인 → 미스 시 병렬 API 호출
T-B05: 스캔 저장 엔드포인트 (POST /api/v1/scans)
        - 기기 uuid로 devices 테이블 upsert → scan_id 반환
        - online_prices에 모든 플랫폼 가격 INSERT (최저가 1개만 아님)
T-B05-B: 오프라인 가격 저장 엔드포인트 (POST /api/v1/scans/{scan_id}/offline-price)
T-B06: 에러 핸들링 미들웨어 (API 타임아웃, 재시도 로직)
T-B07: 환경변수 관리 (.env.example 포함)
T-B08: 단위 테스트 (Jest) — 핵심 로직 70%+ 커버리지
```

**핵심 API 엔드포인트 명세**

```
GET /api/v1/price?barcode=8801234567890
Response:
{
  "barcode": "8801234567890",
  "product_name": "세탁세제 OO 2L",
  "image_url": "https://...",
  "prices": [
    {
      "platform": "coupang",
      "price": 9800,
      "url": "https://coupang.com/...?partnerCode=...",
      "is_lowest": true
    },
    {
      "platform": "naver",
      "price": 10200,
      "url": "https://shopping.naver.com/...",
      "is_lowest": false
    }
  ],
  "lowest_price": 9800,
  "lowest_platform": "coupang",
  "cached_at": "2026-03-18T14:30:00Z",
  "cache_age_minutes": 12
}
```

---

#### API Integration Manager (외부 API 연동)

**담당 영역**: 쿠팡 파트너스 API, 네이버 쇼핑 검색 API 연동 모듈

**작업 방식**
- 각 외부 API를 독립 서비스 모듈로 구현
- 병렬 호출 오케스트레이션 구현
- API별 에러 처리, Rate Limit 대응, 재시도 로직 포함
- 팀장에게 제출 시: API 연동 결과 샘플 + 코드 + 에러 시나리오 테스트

**주요 태스크 (Phase 1)**
```
T-A01: 쿠팡 파트너스 API 서비스 모듈
        - 바코드(EAN) → 상품 검색 → 가격 + 파트너스 링크 반환
        - Rate Limit 처리 (429 시 exponential backoff)
T-A02: 네이버 쇼핑 검색 API 서비스 모듈
        - 바코드 → 상품명 검색 → 최저가 반환
        - 네이버 쇼핑 파트너 링크 생성
T-A03: 병렬 호출 오케스트레이션 (Promise.allSettled)
        - 두 API 동시 호출
        - 한 쪽 실패해도 나머지 결과 반환
        - 전체 타임아웃 3초 설정
T-A04: 미등록 상품 Fallback 로직 (쿠팡/네이버 모두 실패 시 상품명이라도 확보)
        - 1차: 쿠팡 파트너스 API 검색
        - 2차: 네이버 쇼핑 API 검색
        - 3차 (둘 다 실패): Open Food Facts API (무료, 글로벌 오픈소스 상품 DB)
          → https://world.openfoodfacts.org/api/v2/product/{barcode}
          → 대한상공회의소 유통물류진흥원 API는 일반 개발자 공개 API 아님 → 제외
        - 4차 (전부 실패): "상품명을 입력해주세요" — 유저 직접 타이핑 필드 표시
        → 최소한 상품명은 확보해야 수동 저장 팝업 UX가 자연스러움
T-A05: API 응답 정규화 (각기 다른 응답 구조 → 통일된 내부 형식)
```

**병렬 호출 구현 패턴 (필수)**

```typescript
// ❌ 금지: 순차 호출
const coupangResult = await coupangApi.search(barcode);
const naverResult = await naverApi.search(barcode);

// ✅ 필수: 병렬 호출
const [coupangResult, naverResult] = await Promise.allSettled([
  coupangApi.search(barcode),
  naverApi.search(barcode),
]);
```

---

#### QA Manager (품질 보증)

**담당 영역**: 통합 테스트, 성능 테스트, 에러 시나리오 검증, 버그 리포트

**작업 방식**
- 각 매니저의 코드가 완성되면 테스트 시나리오 작성 및 실행
- 팀장에게 테스트 결과 + 발견 버그 + 수정 제안 제출

**주요 태스크**
```
T-Q01: API 응답 시간 측정
        - 캐시 히트: < 500ms
        - 캐시 미스: < 2000ms
        - 검증: 100회 연속 호출 평균값으로 측정
T-Q02: 바코드 스캔 성공률 검증
        - EAN-13 표준 바코드 50종 테스트
        - 정상 조도 < 200ms, 저조도 < 500ms
        - 성공률 95%+ 목표
T-Q03: 에러 시나리오 테스트
        - 쿠팡 API 다운 시 네이버 단독 결과 반환 확인
        - 두 API 모두 실패 시 에러 메시지 확인
        - 네트워크 없을 때 오프라인 안내 확인
        - 미등록 바코드 → "데이터 없음" 안내 확인
T-Q04: 수익화 검증
        - 쿠팡 파트너스 링크 클릭 → 추적 URL 정상 동작 확인
        - AdMob 배너 노출 확인 (테스트 광고 단위)
T-Q05: 보안 검토
        - API 키 노출 여부 (.env 사용 확인)
        - 사용자 입력값 검증 (바코드 형식 검증)
        - HTTPS 통신 확인
```

---

### 3-4. 에이전트 워크플로우 (Phase 1 MVP 기준)

> **원칙**: 팀장이 API Contract(JSON 스키마)를 먼저 확정하면, Flutter는 Mock Data로 UI를 즉시 시작한다. Backend 완성을 기다리지 않는다.

```
[팀장] 프로젝트 구조 및 API Contract 확정
       (GET /price, POST /scans 응답 JSON 스키마를 문서로 먼저 정의)
        ↓
[완전 병렬 시작]
├── [Flutter Manager] T-F01~F05: 앱 기본 구조 + 모든 화면 UI
│                                 (Mock JSON으로 즉시 개발, Backend 대기 없음)
├── [Backend Manager] T-B01~B04: DB 스키마 + Redis + 가격 조회 엔드포인트
└── [API Manager] T-A01~A03: 쿠팡/네이버 모듈 + 병렬 호출 오케스트레이션

        ↓ (Flutter UI 1차 완성 + Backend API 1차 완성 — 각자 독립 완료 후)
[통합 작업]
├── [Flutter Manager] Mock Data → 실제 Backend API 엔드포인트 교체 연동
└── [Backend Manager] T-B05~B08: 스캔 저장, 오프라인 가격 저장, 에러 처리, 테스트

        ↓ (통합 완성 후)
[병렬]
├── [Flutter Manager] T-F06~F08: AdMob + 카카오 연동 + iOS ATT + Debounce
└── [QA Manager] T-Q01~Q03: 성능 + 에러 시나리오 테스트

        ↓
[팀장] 통합 리뷰 → 재작업 지시 or 승인
        ↓
[QA Manager] T-Q04~Q05: 수익화 + 보안 최종 검증
        ↓
[팀장] 최종 승인 → Phase 1 완료
```

**API Contract 예시 (팀장이 개발 시작 전 확정)**

```json
// GET /api/v1/price?barcode=8801234567890 — 응답 스키마
{
  "barcode": "string",
  "product_name": "string",
  "image_url": "string | null",
  "prices": [
    { "platform": "string", "price": 0, "url": "string", "is_lowest": false }
  ],
  "lowest_price": 0,
  "lowest_platform": "string",
  "cached_at": "ISO8601",
  "cache_age_minutes": 0
}
// Flutter는 이 스키마를 가짜 데이터로 하드코딩해서 UI 개발 즉시 시작
```

---

### 3-5. 재작업 사이클

팀장 에이전트는 매니저의 결과물을 받은 후 다음 절차로 검토한다.

```
매니저 → 팀장: "T-B04 완성, 코드 제출"
        ↓
팀장 코드 리뷰:
  1. 요구사항 체크리스트 대조
  2. 성능 기준 충족 확인
  3. 보안 이슈 스캔
  4. 테스트 코드 존재 여부

        ↓
[기준 충족] 팀장 → 매니저: "승인. 다음 태스크 T-B05 진행"
[기준 미달] 팀장 → 매니저: "재작업 요청
  - 문제: API 호출이 순차 방식으로 구현됨 (Promise.allSettled 미사용)
  - 영향: 응답 시간이 2배 증가 (2.8초 측정됨, 목표 2초 초과)
  - 수정 지시: T-A03 병렬 호출 오케스트레이션 참고하여 Promise.allSettled로 변경"
        ↓
매니저 → 수정 후 재제출
```

---

## 4. Phase 1: MVP 개발 계획

### 4-1. 개발 기간 및 마일스톤

| 주차 | 마일스톤 | 담당 에이전트 |
|---|---|---|
| 1주 | 프로젝트 구조, DB 스키마, API 서비스 모듈 초안 | Backend + API Manager |
| 2주 | 가격 조회 API 완성 (Redis 캐싱 + 병렬 호출) | Backend + API Manager |
| 3주 | Flutter 바코드 스캐너 + 결과 화면 | Flutter Manager |
| 4주 | 수동 저장 팝업 + 이력 화면 + AdMob + 카카오 | Flutter Manager |
| 5주 | 통합 테스트 + 버그 수정 + 성능 최적화 | QA Manager + 팀장 |
| 6주 | 앱스토어 제출 준비 (스크린샷, 설명문, 개인정보처리방침) | 팀장 조율 |

### 4-2. 디렉토리 구조

```
barcode_app/
├── app/                          # Flutter 앱
│   ├── lib/
│   │   ├── main.dart             # Type 1 UX: 앱 실행 즉시 스캐너
│   │   ├── features/
│   │   │   ├── scanner/          # 바코드 스캐너 화면
│   │   │   ├── price_result/     # 가격 비교 결과 화면
│   │   │   ├── scan_history/     # 내 스캔 이력 화면
│   │   │   └── manual_price/     # 수동 저장 팝업 (키패드)
│   │   ├── shared/
│   │   │   ├── api/              # Backend API 클라이언트
│   │   │   ├── local_db/         # Hive 로컬 저장
│   │   │   └── widgets/          # 공용 위젯
│   │   └── core/
│   │       ├── theme/            # 앱 테마 (색상, 폰트)
│   │       └── constants/        # 상수 (API URL 등)
│   ├── android/
│   ├── ios/
│   └── pubspec.yaml
│
├── server/                       # Node.js 백엔드
│   ├── src/
│   │   ├── index.ts              # 서버 진입점
│   │   ├── routes/
│   │   │   ├── price.ts          # GET /api/v1/price
│   │   │   └── history.ts        # POST /api/v1/scan-history
│   │   ├── services/
│   │   │   ├── coupang.service.ts    # 쿠팡 파트너스 API
│   │   │   ├── naver.service.ts      # 네이버 쇼핑 API
│   │   │   └── price.service.ts      # 병렬 호출 오케스트레이션
│   │   ├── cache/
│   │   │   └── redis.ts          # Redis 캐싱 레이어
│   │   ├── db/
│   │   │   └── prisma.ts         # Prisma 클라이언트
│   │   └── middleware/
│   │       └── error.ts          # 에러 핸들링
│   ├── prisma/
│   │   └── schema.prisma         # DB 스키마
│   ├── tests/                    # Jest 테스트
│   ├── .env.example
│   └── package.json
│
├── research.md                   # 시장 분석 (이 문서의 기반)
├── plan.md                       # 이 파일
└── docker-compose.yml            # PostgreSQL + Redis 로컬 개발환경
```

### 4-3. 핵심 데이터 모델

> **설계 원칙**: 스캔 이벤트 즉시 서버 저장 (필수). 로컬 저장은 오프라인 fallback + 빠른 그래프 조회용 보조 역할.
> 유저의 오프라인 수동 입력 가격은 전 세계 어디에도 없는 데이터 자산 — 반드시 서버에 수집한다.

#### 테이블 관계도

```
devices ──< scans >── products
               │
               ├──< online_prices   (스캔 당시 플랫폼별 전체 가격)
               └──< offline_prices  (유저 직접 입력한 오프라인 가격 ← 핵심 자산)
```

#### 스키마

```sql
-- 익명 기기 등록 (가입 불필요, 앱 첫 실행 시 UUID 자동 발급)
CREATE TABLE devices (
  id            BIGSERIAL PRIMARY KEY,
  device_uuid   VARCHAR(36) UNIQUE NOT NULL,  -- 앱 생성 UUID (PII 없음)
  os            VARCHAR(10) NOT NULL,          -- 'ios' | 'android'
  country       VARCHAR(10) DEFAULT 'KR',      -- ISO 국가 코드 (글로벌 확장 대비)
  app_version   VARCHAR(20),
  first_seen_at TIMESTAMPTZ DEFAULT NOW(),
  last_seen_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 상품 마스터
CREATE TABLE products (
  id          BIGSERIAL PRIMARY KEY,
  barcode     VARCHAR(20) UNIQUE NOT NULL,
  name        VARCHAR(500) NOT NULL,
  brand       VARCHAR(200),
  category    VARCHAR(100),                    -- '식품', '생활용품', '화장품' 등 (카테고리 분석용)
  image_url   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 스캔 이벤트 (팩트 테이블 — 1스캔 = 1행)
-- 스캔 즉시 서버에 INSERT. 오프라인 시 로컬 큐에 저장 후 복구 시 자동 전송.
CREATE TABLE scans (
  id          BIGSERIAL PRIMARY KEY,
  device_id   BIGINT NOT NULL REFERENCES devices(id),
  barcode     VARCHAR(20) NOT NULL REFERENCES products(barcode),
  latitude    DECIMAL(9,6),                    -- 선택. 소수점 6자리 = 약 11cm 정밀도
  longitude   DECIMAL(9,6),
  scanned_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 스캔 당시 플랫폼별 전체 가격 (빅데이터 핵심)
-- 최저가 1개만 저장하지 않고 모든 플랫폼 가격을 저장 → 플랫폼 간 가격 경쟁 분석 가능
CREATE TABLE online_prices (
  id          BIGSERIAL PRIMARY KEY,
  scan_id     BIGINT NOT NULL REFERENCES scans(id),
  platform    VARCHAR(30) NOT NULL,            -- 'coupang' | 'naver' | 'gmarket' | ...
  price       INTEGER NOT NULL,                -- 원화
  is_lowest   BOOLEAN DEFAULT FALSE,
  fetched_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 유저 직접 입력 오프라인 가격 (가장 희귀하고 귀한 데이터)
-- 경쟁사 중 이 데이터를 보유한 곳 없음 → 수집할수록 데이터 해자 강화
CREATE TABLE offline_prices (
  id          BIGSERIAL PRIMARY KEY,
  scan_id     BIGINT NOT NULL REFERENCES scans(id),
  price       INTEGER NOT NULL,                -- 원화
  store_hint  VARCHAR(200),                    -- GPS 역지오코딩 결과 (예: "이마트 강남점 근처")
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

#### 구 모델 대비 개선 사항

| 항목 | 구 모델 | 신 모델 |
|---|---|---|
| 플랫폼 가격 저장 | 최저가 1개만 | **모든 플랫폼 전체 저장** |
| 기기 정보 | 매 행에 device_id 문자열 | **devices 테이블 정규화** (OS/국가/버전 분석) |
| 상품 카테고리 | 없음 | **category 컬럼** (카테고리별 분석) |
| 위치 정보 | VARCHAR 비구조화 | **위경도 숫자** (반경 N km 쿼리 가능) |
| 저장 전략 | 로컬 주, 서버 선택적 | **서버 필수**, 로컬은 fallback |
| 오프라인 가격 | scan_history에 혼재 | **offline_prices 독립 테이블** |

#### 이 구조로 가능한 빅데이터 분석

```sql
-- 어떤 상품이 오프라인-온라인 가격 차이가 가장 큰가? (가짜 세일 패턴 탐지)
SELECT p.name, p.barcode,
       AVG(op.price) AS avg_offline,
       AVG(onp.price) AS avg_online,
       AVG(op.price - onp.price) AS avg_gap
FROM offline_prices op
JOIN scans s ON s.id = op.scan_id
JOIN online_prices onp ON onp.scan_id = s.id AND onp.is_lowest = TRUE
JOIN products p ON p.barcode = s.barcode
GROUP BY p.id ORDER BY avg_gap DESC;

-- 어느 플랫폼이 가장 자주 최저가인가?
SELECT platform, COUNT(*) AS lowest_count
FROM online_prices WHERE is_lowest = TRUE
GROUP BY platform ORDER BY lowest_count DESC;

-- 가장 많이 스캔된 상품 Top 20 (수요 지도)
SELECT p.name, p.category, COUNT(s.id) AS scan_count
FROM scans s JOIN products p ON p.barcode = s.barcode
GROUP BY p.id ORDER BY scan_count DESC LIMIT 20;

-- 특정 반경 내 오프라인 가격 집계 (향후 지역별 마트 가격 DB 구축)
SELECT p.name, AVG(op.price) AS avg_offline_price, COUNT(*) AS report_count
FROM offline_prices op
JOIN scans s ON s.id = op.scan_id
JOIN products p ON p.barcode = s.barcode
WHERE s.latitude BETWEEN 37.48 AND 37.52   -- 서울 강남구 근방
  AND s.longitude BETWEEN 127.0 AND 127.05
GROUP BY p.id;
```

#### 서버 저장 전략 (Flutter → Node.js)

```
[유저 바코드 스캔]
        ↓
[앱] 스캔 이벤트 즉시 서버 POST /api/v1/scans
        ├── 성공: scan_id 반환 → 가격 조회 병렬 실행
        └── 실패(오프라인): 로컬 큐(Hive)에 저장
                              → 네트워크 복구 시 자동 배치 전송

[유저 오프라인 가격 수동 입력]
        ↓
[앱] 즉시 서버 POST /api/v1/scans/{scan_id}/offline-price
        └── 실패(오프라인): 로컬 큐 → 자동 재전송
```

> **개인정보 원칙**: device_uuid는 앱이 생성한 랜덤 UUID (이름/이메일/전화번호 없음). 위치 정보는 유저 동의 후 수집. 개인정보처리방침에 "익명화된 가격 데이터를 서비스 개선에 활용"으로 명시.

### 4-4. 환경변수 명세 (.env.example)

```bash
# 서버
PORT=3000
NODE_ENV=development

# 데이터베이스
DATABASE_URL=postgresql://user:password@localhost:5432/eolmaeossjeo

# Redis
REDIS_URL=redis://localhost:6379
REDIS_TTL_MINUTES=30

# 쿠팡 파트너스 API
COUPANG_ACCESS_KEY=your_access_key_here
COUPANG_SECRET_KEY=your_secret_key_here
COUPANG_PARTNER_ID=your_partner_id_here

# 네이버 쇼핑 API
NAVER_CLIENT_ID=your_client_id_here
NAVER_CLIENT_SECRET=your_client_secret_here

# API 타임아웃
API_TIMEOUT_MS=3000
```

---

## 5. Phase 2: 성장 + 일본 진출

### 5-1. 한국 기능 확장

| 태스크 | 담당 매니저 | 우선순위 |
|---|---|---|
| G마켓/옥션 API 연동 (eBay Korea API) | API Manager | 높음 |
| 11번가, SSG, 롯데온 크롤러 개발 | API Manager | 높음 |
| 카카오톡 로그인 + 이력 클라우드 싱크 | Flutter + Backend Manager | 높음 |
| 가격 하락 알림 (워치리스트 + 푸시) | Backend + Flutter Manager | 중 |
| 월간 절약 리포트 (공유 가능 카드) | Flutter Manager | 중 |
| 전면 광고 (Interstitial) 추가 | Flutter Manager | 낮음 |
| 네이버 쇼핑 파트너 링크 커미션 연동 | API Manager | 중 |

### 5-2. 일본 시장 진출

| 태스크 | 내용 |
|---|---|
| Amazon.co.jp PA API 연동 | Phase 2 API Manager 핵심 작업 |
| 라쿠텐 API 연동 | 라쿠텐 Ichiba 상품 API |
| 일본어 현지화 (i18n) | Flutter Manager — flutter_localizations |
| 앱스토어 일본 메타데이터 | 팀장 조율 |

> **일본 진출이 용이한 이유**: EAN-13 = JAN (동일 체계), 기존 바코드 스캔 엔진 재사용 가능

---

## 6. Phase 3: 글로벌 확장

### 6-1. Amazon 국가 확장

Amazon PA API 5.0은 단일 SDK로 여러 나라 지원 → 확장 비용 낮음

| 국가 | 플랫폼 | 현지화 작업 |
|---|---|---|
| 미국 | Amazon US + Walmart Open API | 영어 (Flutter i18n 기반) |
| 영국 | Amazon UK | 영어 재활용 |
| 독일 | Amazon DE + idealo | 독일어 현지화 |

### 6-2. 고급 기능

| 기능 | 담당 매니저 | 설명 |
|---|---|---|
| AI 가격 예측 | Backend Manager | 계절/행사 패턴 ML 분석 |
| 장바구니 실질 최저가 계산기 | Flutter + Backend Manager | 표준 배송비 기준 합산 |
| 오프라인 크라우드소싱 고도화 | Backend + Flutter Manager | 사용자 제보 기반 오프라인 가격 DB |
| B2B 가격 데이터 API | Backend Manager | Keepa 모델 적용 |

---

## 7. 에이전트 작업 지시 규격

팀장 에이전트가 매니저에게 태스크를 지시할 때 반드시 포함해야 하는 항목.

### 작업 지시서 템플릿

```markdown
## 태스크 ID: T-{매니저코드}{번호}
## 담당: {매니저 이름} 에이전트

### 목표
한 문장으로 이 태스크의 목적을 서술한다.

### 입력
이 태스크에 필요한 선행 조건, 파일, API 정보를 나열한다.

### 요구사항
구현해야 할 기능을 번호 목록으로 구체적으로 서술한다.
1. ...
2. ...

### 성능 기준
- 응답 시간: XXms 이하
- 성공률: XX%+

### 금지 사항
- 절대로 하지 말아야 할 구현 방식을 명시한다

### 완료 조건 (팀장 검수 기준)
팀장이 승인하기 위해 반드시 충족해야 하는 조건 목록.
- [ ] 요구사항 N개 모두 구현됨
- [ ] 단위 테스트 작성됨 (커버리지 70%+)
- [ ] .env 변수 사용 (API 키 하드코딩 없음)

### 제출 형식
제출 시 포함해야 하는 파일 목록과 간단한 동작 설명.
```

---

### 실제 작업 지시 예시

```markdown
## 태스크 ID: T-A03
## 담당: API Integration Manager 에이전트

### 목표
쿠팡과 네이버 쇼핑 API를 동시에 호출하여 2초 이내에 최저가를 반환하는
병렬 호출 오케스트레이션 서비스를 구현한다.

### 입력
- T-A01 완성: src/services/coupang.service.ts
- T-A02 완성: src/services/naver.service.ts
- 환경변수: .env (API_TIMEOUT_MS=3000)

### 요구사항
1. Promise.allSettled()를 사용해 두 API를 동시에 호출한다
2. 전체 타임아웃 3초 — 3초 초과 시 진행 중인 API도 중단
3. 한 API 실패 시 나머지 성공 결과만 반환 (한쪽 실패로 전체 실패 금지)
4. 두 API 모두 실패 시 → 명확한 에러 응답 반환
5. 응답을 정규화하여 통일된 PriceResult[] 타입으로 반환
6. is_lowest: true 를 가장 낮은 가격에 표시

### 성능 기준
- Redis 캐시 히트: 500ms 이하
- 캐시 미스 (실제 API 호출): 2000ms 이하 (99th percentile)

### 금지 사항
- await coupangApi() 후 await naverApi() 순차 호출 절대 금지
- API 키 코드 내 하드코딩 절대 금지

### 완료 조건
- [ ] Promise.allSettled 사용 확인
- [ ] 한 API 실패 시나리오 단위 테스트 포함
- [ ] 두 API 모두 실패 시나리오 단위 테스트 포함
- [ ] 타임아웃 3초 테스트 포함
- [ ] PriceResult 타입 정의 포함

### 제출 형식
- src/services/price-orchestrator.service.ts
- src/services/price-orchestrator.service.test.ts
- src/types/price.types.ts (PriceResult 타입 정의)
- 간단한 동작 설명 주석 (JSDoc)
```

---

## 8. 품질 기준 & 검수 체크리스트

### 8-1. Phase 1 출시 전 팀장 최종 검수 항목

#### 기능 검수

- [ ] 앱 실행 시 즉시 카메라 스캐너 열림 (Type 1 UX)
- [ ] EAN-13 바코드 스캔 → 2초 이내 결과 표시
- [ ] 쿠팡 최저가 / 네이버 최저가 동시 표시
- [ ] 최저가 플랫폼 초록 배지로 강조
- [ ] "쿠팡에서 사기" 버튼 → 쿠팡 파트너스 URL로 이동
- [ ] 스캔 즉시 서버에 저장 (scans + online_prices 동시 INSERT)
- [ ] 오프라인 수동 입력 시 즉시 서버 저장 (offline_prices INSERT)
- [ ] 오프라인 상태에서 스캔 → 로컬 큐 저장 → 네트워크 복구 시 자동 전송
- [ ] 재스캔 시 가격 변동 그래프 표시 (가로축: 날짜, 세로축: 금액)
- [ ] 온라인 최저가(파랑선) + 수동 입력 오프라인 가격(주황선) 두 선 동시 표시
- [ ] 그래프 데이터 포인트 탭 시 날짜/가격 툴팁 표시
- [ ] 수동 저장 팝업 → 거대 키패드 → 저장 → 토스트 메시지
- [ ] AdMob 배너 광고 결과 화면 하단 노출
- [ ] 카카오톡 공유 → 링크 포함 메시지 전송
- [ ] 미등록 바코드 → "온라인 데이터 없음" 안내 + 수동 입력 유도
- [ ] 카메라 권한 거부 → 안내 화면

#### 성능 검수

- [ ] 인기 상품 (Redis 캐시): 응답 500ms 이하
- [ ] 신규 상품 (API 호출): 응답 2초 이하
- [ ] 바코드 인식: 정상 조도 200ms 이하
- [ ] 앱 콜드 스타트 → 카메라 열리기까지 2초 이하

#### 보안 검수

- [ ] API 키 전부 .env 관리 (코드 내 노출 없음)
- [ ] 쿠팡/네이버 API 키 GitHub 커밋 이력에 없음
- [ ] HTTPS 통신 (HTTP 허용 없음)
- [ ] 사용자 입력 바코드 형식 검증 (숫자 8~13자리)

#### 수익화 검수

- [ ] 쿠팡 파트너스 URL 형식 정상 (`partnerCode` 파라미터 포함)
- [ ] 링크 클릭 → 쿠팡 앱/웹으로 정상 이동
- [ ] "이 링크를 통한 구매 시 소액의 수수료가 발생합니다" 명시
- [ ] AdMob 테스트 광고 단위 → 실제 광고 단위로 교체 확인

#### 앱스토어 제출 준비

- [ ] 스플래시 화면 표시 (앱 실행 시 흰 화면 번쩍임 없음)
- [ ] 최초 1회 온보딩 + 개인정보 동의 화면 표시 (2회차 실행 시 생략 확인)
- [ ] API 타임아웃 시 친근한 에러 메시지 표시 (에러 코드 노출 없음)
- [ ] 네트워크 호출 중 스켈레톤 UI(shimmer) 표시
- [ ] iOS ATT 팝업 구현 확인 (AdMob 사용 시 필수 — 없으면 Apple 리젝)
- [ ] 바코드 Debounce 동작 확인 (동일 바코드 3초 내 재스캔 시 API 미호출)
- [ ] AdMob App ID — Info.plist(iOS) + AndroidManifest.xml(Android) 모두 추가 확인
- [ ] 카카오 네이티브 앱 키 — Info.plist + AndroidManifest.xml + build.gradle 모두 확인
- [ ] 위치 권한이 온보딩에서 요청되지 않고 수동 저장 팝업에서만 요청되는지 확인
- [ ] iOS: Info.plist 카메라 권한 사유 한국어 작성
- [ ] Android: AndroidManifest 카메라 권한 선언
- [ ] 개인정보처리방침 URL 준비 (스캔 이력 저장 내용 포함)
- [ ] 앱 스크린샷 5장 (한국 마트 배경, 한국인 모델)
- [ ] 앱 설명 첫 줄: "마트 가짜 세일에 속지 마세요"
- [ ] 앱 아이콘: 바코드 + ₩ 기호 조합, 초록/노랑 계열

### 8-2. KPI 목표 (Phase 1 출시 후 3개월)

| 지표 | 목표 |
|---|---|
| 누적 다운로드 | 10,000 |
| DAU | 2,000 |
| 일일 스캔 수 | 10,000 |
| 스캔 성공률 | 95%+ |
| 앱스토어 평점 | 4.3+ |
| 월 광고 수익 (MAU 10K) | 20~60만원 |
| 월 제휴 커미션 (MAU 10K) | 36~60만원 |

---

*이 문서는 개발 진행에 따라 팀장 에이전트가 업데이트합니다.*
*에이전트 아키텍처 관련 결정 사항은 팀장 에이전트가 이 파일에 변경 이력을 기록합니다.*
