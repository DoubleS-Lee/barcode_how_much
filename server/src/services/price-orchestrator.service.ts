import { searchCoupang } from './coupang.service';
import { searchNaver } from './naver.service';
import { searchOpenFoodFacts } from './openfoodfacts.service';
import { searchFoodSafety } from './foodsafety.service';
import { PriceResponse, PriceEntry } from '../types/price.types';

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error('TIMEOUT')), ms)),
  ]);
}

export async function priceOrchestrator(
  barcode: string,
  knownProductName?: string,
): Promise<PriceResponse | null> {
  const timeout = parseInt(process.env.API_TIMEOUT_MS || '3000');
  const hasCoupangKey = !!(process.env.COUPANG_ACCESS_KEY &&
    process.env.COUPANG_ACCESS_KEY !== 'your_access_key_here');

  let lookupName: string | undefined = knownProductName;
  let offResult: { productName: string; imageUrl: string | null } | null = null;
  let foodSafetyResult: { productName: string; companyName: string | null } | null = null;
  let coupangResult = null;

  if (knownProductName) {
    // 자체 DB에 상품명 있음 → 쿠팡만 가격용으로 호출
    console.log(`[Orchestrator] Using cached product name: "${knownProductName}"`);
    const [coupangSettled] = await Promise.allSettled([
      withTimeout(searchCoupang(barcode), timeout),
    ]);
    coupangResult = coupangSettled.status === 'fulfilled' ? coupangSettled.value : null;

  } else {
    // Phase 1: OFF + 식약처 + 쿠팡 병렬 호출 → 네이버 검색용 상품명 확보
    const [offSettled, foodSafetySettled, coupangSettled] = await Promise.allSettled([
      withTimeout(searchOpenFoodFacts(barcode), 2000),
      withTimeout(searchFoodSafety(barcode), 5000),
      withTimeout(searchCoupang(barcode), timeout),
    ]);

    offResult = offSettled.status === 'fulfilled' ? offSettled.value : null;
    foodSafetyResult = foodSafetySettled.status === 'fulfilled' ? foodSafetySettled.value : null;
    coupangResult = coupangSettled.status === 'fulfilled' ? coupangSettled.value : null;

    if (coupangSettled.status === 'rejected') {
      console.warn('[Orchestrator] Coupang failed:', (coupangSettled.reason as Error)?.message);
    }

    // 네이버 바코드 Step 1 실패 시 fallback 검색어 우선순위: 쿠팡(실제키) > OFF > 식약처
    lookupName = (hasCoupangKey ? coupangResult?.productName : undefined)
      || offResult?.productName
      || foodSafetyResult?.productName;

    if (lookupName) {
      console.log(`[Orchestrator] Lookup name for Naver: "${lookupName}"`);
    }
  }

  // Phase 2: 네이버 검색
  // - lookupName 있으면: 상품명으로 바로 검색
  // - lookupName 없으면: 바코드 2단계 검색 (naver.service 내부 처리)
  const [naverSettled] = await Promise.allSettled([
    withTimeout(searchNaver(barcode, lookupName), timeout),
  ]);
  const naverResult = naverSettled.status === 'fulfilled' ? naverSettled.value : null;

  if (naverSettled.status === 'rejected') {
    console.warn('[Orchestrator] Naver failed:', (naverSettled.reason as Error)?.message);
  }

  // 쿠팡/네이버 모두 실패 → lookupName만 있으면 최소 반환
  if (!coupangResult && !naverResult) {
    if (lookupName) {
      return {
        barcode,
        product_name: lookupName,
        image_url: offResult?.imageUrl ?? null,
        prices: [],
        lowest_price: 0,
        lowest_platform: '',
        cached_at: new Date().toISOString(),
        cache_age_minutes: 0,
      };
    }
    return null;
  }

  // 최종 결과 조합
  // 상품명 우선순위: 네이버 > 쿠팡(실제키) > 식약처 > OFF > 자체DB
  const productName =
    naverResult?.productName
    || (hasCoupangKey ? coupangResult?.productName : undefined)
    || foodSafetyResult?.productName
    || offResult?.productName
    || knownProductName
    || '';

  // 이미지 우선순위: 네이버 > 쿠팡(실제키) > OFF
  const imageUrl =
    naverResult?.imageUrl
    || (hasCoupangKey ? coupangResult?.imageUrl : undefined)
    || offResult?.imageUrl
    || null;

  const priceEntries: PriceEntry[] = [];
  if (coupangResult) {
    priceEntries.push({ platform: 'coupang', price: coupangResult.price, url: coupangResult.affiliateUrl, is_lowest: false });
  }
  if (naverResult) {
    priceEntries.push({ platform: 'naver', price: naverResult.price, url: naverResult.shoppingUrl, is_lowest: false });
  }

  const lowestEntry = priceEntries.reduce((a, b) => (a.price <= b.price ? a : b));
  lowestEntry.is_lowest = true;

  return {
    barcode,
    product_name: productName,
    image_url: imageUrl,
    prices: priceEntries,
    lowest_price: lowestEntry.price,
    lowest_platform: lowestEntry.platform,
    cached_at: new Date().toISOString(),
    cache_age_minutes: 0,
  };
}
