import { priceOrchestrator } from './price-orchestrator.service';

jest.mock('./coupang.service');
jest.mock('./naver.service');
jest.mock('./openfoodfacts.service');

import { searchCoupang } from './coupang.service';
import { searchNaver } from './naver.service';
import { searchOpenFoodFacts } from './openfoodfacts.service';

const mockCoupang = searchCoupang as jest.MockedFunction<typeof searchCoupang>;
const mockNaver = searchNaver as jest.MockedFunction<typeof searchNaver>;
const mockOFF = searchOpenFoodFacts as jest.MockedFunction<typeof searchOpenFoodFacts>;

const barcode = '8801234567890';
const coupangMock = { platform: 'coupang' as const, productName: '세탁세제 2L', price: 9800, imageUrl: null, affiliateUrl: 'https://coupang.com/mock' };
const naverMock = { platform: 'naver' as const, productName: '세탁세제 2L', price: 10200, imageUrl: null, shoppingUrl: 'https://naver.com/mock' };

describe('priceOrchestrator', () => {
  beforeEach(() => jest.clearAllMocks());

  it('두 API 모두 성공: 병렬 결과 반환', async () => {
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
    expect(result!.prices).toHaveLength(1);
    expect(result!.prices[0].platform).toBe('naver');
  });

  it('네이버 실패: 쿠팡 단독 반환', async () => {
    mockCoupang.mockResolvedValue(coupangMock);
    mockNaver.mockRejectedValue(new Error('down'));
    const result = await priceOrchestrator(barcode);
    expect(result!.prices).toHaveLength(1);
    expect(result!.prices[0].platform).toBe('coupang');
  });

  it('두 API 모두 실패: OpenFoodFacts fallback', async () => {
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
    const result = await priceOrchestrator(barcode);
    expect(result).toBeNull();
  });

  it('is_lowest가 최저가 플랫폼에만 true', async () => {
    mockCoupang.mockResolvedValue(coupangMock);  // 9800
    mockNaver.mockResolvedValue(naverMock);       // 10200
    const result = await priceOrchestrator(barcode);
    const coupangEntry = result!.prices.find((p) => p.platform === 'coupang');
    const naverEntry = result!.prices.find((p) => p.platform === 'naver');
    expect(coupangEntry!.is_lowest).toBe(true);
    expect(naverEntry!.is_lowest).toBe(false);
  });
});
