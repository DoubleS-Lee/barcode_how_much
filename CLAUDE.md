# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**얼마였지?** — 바코드 가격 비교 앱. Flutter 모바일 앱 + Node.js/Express 백엔드.
사용자가 바코드를 스캔하면 Naver/Coupang 온라인 가격을 조회하고, 오프라인 마트 가격과 비교해준다.

## Repository Structure

```
barcode_app/
├── app/          # Flutter 앱 (Android/iOS)
└── server/       # Node.js/TypeScript 백엔드
```

---

## Flutter App (`app/`)

### Common Commands

```bash
cd app

# 의존성 설치
flutter pub get

# 연결된 Android 기기에 실행 (실기기 ID 예: R3CY20CLGTN)
flutter run -d R3CY20CLGTN

# 분석
flutter analyze

# Release APK 빌드
flutter build apk --release
```

### Architecture

- **State Management:** Riverpod (`flutter_riverpod`) — `FutureProvider`, `AsyncNotifierProvider` 사용
- **Routing:** `go_router` — `lib/core/router.dart`에서 전체 라우트 정의. `routerProvider`는 `Provider.family<GoRouter, String>`
- **HTTP Client:** `dio` 싱글톤 — `lib/shared/api/api_client.dart`의 `dio` 인스턴스 사용
- **Local Storage:** Hive (구조화 데이터) + SharedPreferences (설정값)

**API Base URL:** `lib/shared/api/api_client.dart`의 `kBaseUrl` — 실기기 테스트 시 PC의 로컬 IP로 변경 필요 (예: `http://192.168.x.x:3000`)

### Feature Modules (`lib/features/`)

| 모듈 | 설명 |
|------|------|
| `onboarding` | 최초 실행, 약관 동의, 소셜 로그인 |
| `scanner` | 카메라 바코드 스캔 (`mobile_scanner`) |
| `price_result` | 온라인/오프라인 가격 비교, 차트 표시 |
| `manual_price` | 사용자 오프라인 가격 직접 입력 |
| `scan_history` | 스캔 이력 조회 |
| `community` | 가격 공유 게시판 |
| `settings` | 설정, 법적 문서 (`settings/legal_screen.dart`) |

### Key Providers

- `priceResultProvider` — `autoDispose.family` 사용. 화면 이탈 시 dispose되어 재스캔 시 새 스캔 저장됨
- `scanHistoryProvider` — 스캔 이력 목록
- `liveOfflinePriceProvider` — 오프라인 가격 실시간 반영

### Android 주의사항

- `app/android/app/src/main/AndroidManifest.xml`에 `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, 카메라/인터넷 권한 선언 필요
- `flutter_local_notifications` 사용으로 `build.gradle.kts`에 `isCoreLibraryDesugaringEnabled = true` 및 `desugar_jdk_libs` 의존성 필요

---

## Server (`server/`)

### Common Commands

```bash
cd server

# 의존성 설치
npm install

# 개발 서버 시작 (ts-node-dev, hot reload)
npm run dev

# 빌드
npm run build

# 프로덕션 실행
npm start

# 테스트
npm test

# DB 마이그레이션
npm run db:migrate

# Prisma 클라이언트 재생성
npm run db:generate

# DB GUI
npm run db:studio
```

### Infrastructure

Docker Compose로 로컬 인프라 실행:
```bash
docker-compose up -d   # PostgreSQL 16 (5432) + Redis 7 (6379) 시작
```

### Architecture

- **Framework:** Express + TypeScript
- **ORM:** Prisma (`server/prisma/schema.prisma`) — PostgreSQL
- **Cache:** Redis (ioredis) — `src/cache/redis.ts`, `lazyConnect: true`
- **Validation:** Zod (라우트 핸들러에서 request body 검증)
- **Scheduling:** node-cron — 6시간마다 즐겨찾기 가격 알림 (`priceAlert.service.ts`)

### API Routes (`src/routes/`)

모두 `/api/v1/` 접두사:

| 라우트 | 설명 |
|--------|------|
| `GET /price?barcode=` | 멀티 플랫폼 가격 조회 (Naver, Coupang) |
| `POST /scans` | 스캔 이벤트 기록 |
| `POST /scans/:id/offline-price` | 오프라인 가격 저장 (`store_hint`, `memo` 포함) |
| `GET /scans/history` | 스캔 이력 |
| `POST /posts` | 커뮤니티 게시글 작성 |
| `GET/PUT/DELETE /posts/:id` | 게시글 CRUD |
| `POST /favorites` | 즐겨찾기 추가/제거 |

### Price Orchestration

`src/services/price-orchestrator.service.ts`:
1. 바코드로 Coupang 검색 → 상품명 추출
2. 상품명으로 Naver 검색 (바코드만 있을 경우 timeout × 2)
3. API 키 미설정 시 `null` 반환 (mock 데이터 없음)
4. `priceEntries`가 비어있으면 상품명만 반환 (크래시 방지)

### Environment Variables

`server/.env` 필요:
```
DATABASE_URL=postgresql://eolmae:eolmae1234@localhost:5432/eolmaeossjeo
REDIS_URL=redis://localhost:6379
COUPANG_ACCESS_KEY=...
COUPANG_SECRET_KEY=...
COUPANG_PARTNER_ID=...
NAVER_CLIENT_ID=...
NAVER_CLIENT_SECRET=...
API_TIMEOUT_MS=3000
```

Coupang/Naver API 키 미설정 시 해당 플랫폼 검색을 건너뜀 (에러 아님).

---

## Key Cross-cutting Concerns

### Device Identification
계정 없이 `device_uuid`로 사용자 식별. `lib/shared/utils/device_id.dart`에서 생성, 모든 API 요청에 포함.

### 법적 문서
`app/lib/features/settings/legal_screen.dart` — `PrivacyPolicyScreen`, `TermsScreen`, `MarketingInfoScreen` 포함. 라우트: `/privacy`, `/terms`, `/marketing`.

### Redis 에러
Redis 미실행 시 `setCache`/`getCache` 에러 발생하지만 서비스는 정상 동작 (캐싱만 실패). 기능 영향 없음.
