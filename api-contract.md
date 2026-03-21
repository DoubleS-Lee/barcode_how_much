# API Contract — 얼마였지?

> 팀장 에이전트 확정. Flutter는 이 스키마를 Mock JSON으로 하드코딩하여 Backend 완성 전에도 UI 개발 즉시 시작.

---

## Base URL

```
개발: http://localhost:3000/api/v1
프로덕션: https://api.eolmaeossjeo.com/api/v1
```

---

## 1. 가격 조회

### `GET /api/v1/price?barcode={ean}`

**Request**
```
GET /api/v1/price?barcode=8801234567890
```

**Response 200 — 상품 있음**
```json
{
  "barcode": "8801234567890",
  "product_name": "세탁세제 OO 2L",
  "image_url": "https://example.com/image.jpg",
  "prices": [
    {
      "platform": "coupang",
      "price": 9800,
      "url": "https://coupang.com/vp/products/...?partnerCode=af1234",
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
  "cached_at": "2026-03-20T14:30:00Z",
  "cache_age_minutes": 12
}
```

**Response 404 — 미등록 상품**
```json
{
  "error": "PRODUCT_NOT_FOUND",
  "message": "등록된 상품 정보가 없습니다.",
  "fallback_tried": ["coupang", "naver", "openfoodfacts"]
}
```

**Response 503 — 외부 API 전체 실패**
```json
{
  "error": "UPSTREAM_UNAVAILABLE",
  "message": "가격 정보를 가져올 수 없습니다. 잠시 후 다시 시도해주세요."
}
```

---

## 2. 스캔 이벤트 저장

### `POST /api/v1/scans`

**Request Body**
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "os": "ios",
  "app_version": "1.0.0",
  "scan_type": "product",
  "barcode": "8801234567890",
  "latitude": 37.498095,
  "longitude": 127.027610,
  "online_prices": [
    { "platform": "coupang", "price": 9800, "is_lowest": true },
    { "platform": "naver", "price": 10200, "is_lowest": false }
  ]
}
```

**scan_type 가능 값**: `"product"` | `"qr_url"` | `"qr_wifi"` | `"qr_contact"` | `"qr_text"` | `"isbn"` | `"unknown"`

**비상품 스캔 시 Request Body**
```json
{
  "device_uuid": "550e8400-e29b-41d4-a716-446655440000",
  "os": "android",
  "app_version": "1.0.0",
  "scan_type": "qr_url",
  "barcode": null,
  "latitude": null,
  "longitude": null,
  "barcode_content": {
    "raw_value": "https://naver.com/event/spring",
    "content_type": "url",
    "parsed_data": {
      "url": "https://naver.com/event/spring",
      "domain": "naver.com"
    }
  }
}
```

**Response 201**
```json
{
  "scan_id": 12345,
  "device_id": 789,
  "created_at": "2026-03-20T14:30:00Z"
}
```

---

## 3. 오프라인 가격 저장

### `POST /api/v1/scans/{scan_id}/offline-price`

**Request Body**
```json
{
  "price": 12500,
  "store_hint": "이마트 강남점 근처"
}
```

**Response 201**
```json
{
  "id": 456,
  "scan_id": 12345,
  "price": 12500,
  "store_hint": "이마트 강남점 근처",
  "created_at": "2026-03-20T14:30:00Z"
}
```

---

## 4. 스캔 이력 조회

### `GET /api/v1/history?device_uuid={uuid}&limit=50&offset=0`

**Response 200**
```json
{
  "total": 142,
  "items": [
    {
      "scan_id": 12345,
      "scan_type": "product",
      "scanned_at": "2026-03-20T14:30:00Z",
      "product": {
        "barcode": "8801234567890",
        "name": "세탁세제 OO 2L",
        "image_url": "https://example.com/image.jpg"
      },
      "lowest_online_price": 9800,
      "lowest_online_platform": "coupang",
      "offline_price": 12500,
      "store_hint": "이마트 강남점 근처"
    },
    {
      "scan_id": 12344,
      "scan_type": "qr_url",
      "scanned_at": "2026-03-20T13:00:00Z",
      "barcode_content": {
        "content_type": "url",
        "parsed_data": { "url": "https://naver.com", "domain": "naver.com" }
      }
    }
  ]
}
```

---

## 5. 상품별 가격 이력 (그래프용)

### `GET /api/v1/products/{barcode}/price-history?device_uuid={uuid}`

**Response 200 — Flutter fl_chart 그래프용 데이터**
```json
{
  "barcode": "8801234567890",
  "product_name": "세탁세제 OO 2L",
  "price_history": [
    {
      "scanned_at": "2026-01-15T10:00:00Z",
      "online_lowest_price": 10200,
      "online_lowest_platform": "naver",
      "offline_price": 13000,
      "store_hint": "홈플러스 역삼점 근처"
    },
    {
      "scanned_at": "2026-02-20T14:30:00Z",
      "online_lowest_price": 9800,
      "online_lowest_platform": "coupang",
      "offline_price": 12500,
      "store_hint": "이마트 강남점 근처"
    },
    {
      "scanned_at": "2026-03-20T09:15:00Z",
      "online_lowest_price": 9500,
      "online_lowest_platform": "coupang",
      "offline_price": null,
      "store_hint": null
    }
  ]
}
```

> 그래프: 파랑선 = online_lowest_price / 주황선 = offline_price (null이면 해당 날짜에 점 없음)

---

## Flutter Mock Data (개발 즉시 시작용)

```dart
// lib/shared/api/mock_data.dart
const mockPriceResponse = {
  "barcode": "8801234567890",
  "product_name": "세탁세제 OO 2L",
  "image_url": null,
  "prices": [
    {"platform": "coupang", "price": 9800, "url": "https://coupang.com", "is_lowest": true},
    {"platform": "naver", "price": 10200, "url": "https://shopping.naver.com", "is_lowest": false}
  ],
  "lowest_price": 9800,
  "lowest_platform": "coupang",
  "cached_at": "2026-03-20T14:30:00Z",
  "cache_age_minutes": 0
};

const mockPriceHistory = {
  "barcode": "8801234567890",
  "product_name": "세탁세제 OO 2L",
  "price_history": [
    {"scanned_at": "2026-01-15T10:00:00Z", "online_lowest_price": 10200, "offline_price": 13000},
    {"scanned_at": "2026-02-20T14:30:00Z", "online_lowest_price": 9800, "offline_price": 12500},
    {"scanned_at": "2026-03-20T09:15:00Z", "online_lowest_price": 9500, "offline_price": null}
  ]
};
```
