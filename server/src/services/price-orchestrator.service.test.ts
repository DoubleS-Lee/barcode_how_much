import { priceOrchestrator } from './price-orchestrator.service';

jest.mock('./coupang.service');
jest.mock('./naver.service');
jest.mock('./openfoodfacts.service');
jest.mock('./foodsafety.service');

import { searchCoupang } from './coupang.service';
import { searchNaver } from './naver.service';
import { searchOpenFoodFacts } from './openfoodfacts.service';
import { searchFoodSafety } from './foodsafety.service';

const mockCoupang = searchCoupang as jest.MockedFunction<typeof searchCoupang>;
const mockNaver = searchNaver as jest.MockedFunction<typeof searchNaver>;
const mockOFF = searchOpenFoodFacts as jest.MockedFunction<typeof searchOpenFoodFacts>;
const mockFoodSafety = searchFoodSafety as jest.MockedFunction<typeof searchFoodSafety>;

const barcode = '8801234567890';
const coupangMock = {
  platform: 'coupang' as const,
  productName: '세탁세제 2L',
  price: 9800,
  imageUrl: null,
  affiliateUrl: 'https://coupang.com/mock',
};
const naverMock = {
  platform: 'naver' as const,
  productName: '세탁세제 2L',
  price: 10200,
  imageUrl: null,
  shoppingUrl: 'https://naver.com/mock',
};

describe('priceOrchestrator', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // 쿠팡 API 키 설정 — 키 없으면 쿠팡 결과를 최종 응답에서 제외하는 로직 때문에 필요
    process.env.COUPANG_ACCESS_KEY = 'test_access_key';
    process.env.COUPANG_SECRET_KEY = 'test_secret_key';
    process.env.COUPANG_PARTNER_ID = 'test_partner';
    // foodsafety 기본값: null (실제 API 호출 방지)
    mockFoodSafety.mockResolvedValue(null);
    mockOFF.mockResolvedValue(null);
  });

  afterEach(() => {
    delete process.env.COUPANG_ACCESS_KEY;
    delete process.env.COUPANG_SECRET_KEY;
    delete process.env.COUPANG_PARTNER_ID;
  });

  it('쿠팡 + 네이버 모두 성공: 2개 가격 반환', async () => {
    mockCoupang.mockResolvedValue(coupangMock);
    mockNaver.mockResolvedValue(naverMock);

    const result = await priceOrchestrator(barcode);

    expect(result).not.toBeNull();
    expect(result!.prices).toHaveLength(2);
    expect(result!.lowest_price).toBe(9800);
    expect(result!.lowest_platform).toBe('coupang');
  });

  it('쿠팡 실패: 네이버 단독 반환', async () => {
    mockCoupang.mockRejectedValue(new Error('down'));
    mockNaver.mockResolvedValue(naverMock);

    const result = await priceOrchestrator(barcode);

    expect(result).not.toBeNull();
    expect(result!.prices).toHaveLength(1);
    expect(result!.prices[0].platform).toBe('naver');
  });

  it('네이버 실패: 쿠팡 단독 반환', async () => {
    mockCoupang.mockResolvedValue(coupangMock);
    mockNaver.mockRejectedValue(new Error('down'));

    const result = await priceOrchestrator(barcode);

    expect(result).not.toBeNull();
    expect(result!.prices).toHaveLength(1);
    expect(result!.prices[0].platform).toBe('coupang');
  });

  it('두 API 모두 실패 + OFF fallback: 상품명만 반환', async () => {
    mockCoupang.mockRejectedValue(new Error('down'));
    mockNaver.mockRejectedValue(new Error('down'));
    mockOFF.mockResolvedValue({ productName: '세탁세제', brand: 'OO', imageUrl: null });

    const result = await priceOrchestrator(barcode);

    expect(result).not.toBeNull();
    expect(result!.prices).toHaveLength(0);
    expect(result!.product_name).toBe('세탁세제');
  });

  it('모든 API 실패: null 반환', async () => {
    mockCoupang.mockRejectedValue(new Error('down'));
    mockNaver.mockRejectedValue(new Error('down'));
    mockOFF.mockResolvedValue(null);
    mockFoodSafety.mockResolvedValue(null);

    const result = await priceOrchestrator(barcode);

    expect(result).toBeNull();
  });

  it('is_lowest가 최저가 플랫폼(쿠팡 9800원)에만 true', async () => {
    mockCoupang.mockResolvedValue(coupangMock);  // 9800
    mockNaver.mockResolvedValue(naverMock);       // 10200

    const result = await priceOrchestrator(barcode);

    const coupangEntry = result!.prices.find((p) => p.platform === 'coupang');
    const naverEntry = result!.prices.find((p) => p.platform === 'naver');
    expect(coupangEntry!.is_lowest).toBe(true);
    expect(naverEntry!.is_lowest).toBe(false);
  });

  it('knownProductName 있을 때: 기존 상품명 유지', async () => {
    mockCoupang.mockResolvedValue(coupangMock);
    mockNaver.mockResolvedValue(naverMock);

    const result = await priceOrchestrator(barcode, '사용자 수정 상품명');

    expect(result!.product_name).toBe('사용자 수정 상품명');
  });

  it('linkedNaverEntry 있을 때: 네이버 검색 스킵하고 연결된 가격 사용', async () => {
    mockCoupang.mockResolvedValue(coupangMock);
    const linkedEntry = { url: 'https://naver.com/linked', price: 8500 };

    const result = await priceOrchestrator(barcode, '상품명', linkedEntry);

    expect(result).not.toBeNull();
    const naverEntry = result!.prices.find((p) => p.platform === 'naver');
    expect(naverEntry!.price).toBe(8500);
    expect(naverEntry!.url).toBe('https://naver.com/linked');
  });
});
