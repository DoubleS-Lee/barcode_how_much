// API Contract 기반 Mock 데이터 — Backend 완성 전 UI 개발용

const mockPriceResponse = {
  'barcode': '8801234567890',
  'product_name': '세탁세제 OO 2L',
  'image_url': null,
  'prices': [
    {'platform': 'coupang', 'price': 9800, 'url': 'https://coupang.com', 'is_lowest': true},
    {'platform': 'naver', 'price': 10200, 'url': 'https://shopping.naver.com', 'is_lowest': false},
  ],
  'lowest_price': 9800,
  'lowest_platform': 'coupang',
  'cached_at': '2026-03-20T14:30:00Z',
  'cache_age_minutes': 0,
};

const mockPriceHistory = {
  'barcode': '8801234567890',
  'product_name': '세탁세제 OO 2L',
  'price_history': [
    {'scanned_at': '2026-01-15T10:00:00Z', 'online_lowest_price': 10200, 'offline_price': 13000},
    {'scanned_at': '2026-02-20T14:30:00Z', 'online_lowest_price': 9800, 'offline_price': 12500},
    {'scanned_at': '2026-03-20T09:15:00Z', 'online_lowest_price': 9500, 'offline_price': null},
  ],
};

const mockScanHistory = [
  {
    'scan_id': 1,
    'scan_type': 'product',
    'scanned_at': '2026-03-20T14:30:00Z',
    'product': {'barcode': '8801234567890', 'name': '세탁세제 OO 2L', 'image_url': null},
    'lowest_online_price': 9800,
    'lowest_online_platform': 'coupang',
    'offline_price': 12500,
    'store_hint': '이마트 강남점 근처',
  },
  {
    'scan_id': 2,
    'scan_type': 'qr_url',
    'scanned_at': '2026-03-20T13:00:00Z',
    'barcode_content': {
      'content_type': 'url',
      'parsed_data': {'url': 'https://naver.com', 'domain': 'naver.com'},
    },
  },
  {
    'scan_id': 3,
    'scan_type': 'qr_wifi',
    'scanned_at': '2026-03-19T11:00:00Z',
    'barcode_content': {
      'content_type': 'wifi',
      'parsed_data': {'ssid': 'HomeNetwork_5G', 'security': 'WPA'},
    },
  },
];
