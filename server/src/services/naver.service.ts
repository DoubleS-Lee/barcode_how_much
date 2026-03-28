import axios from 'axios';
import dotenv from 'dotenv';
import { logger } from '../utils/logger';
dotenv.config();

export interface NaverResult {
  platform: 'naver';
  productName: string;
  price: number;
  imageUrl: string | null;
  shoppingUrl: string;
}

export interface NaverCandidate {
  productName: string;
  price: number;
  imageUrl: string | null;
  shoppingUrl: string;
  mallName: string;
}

// 네이버 쇼핑 API 단일 호출 (내부 헬퍼)
async function naverApiSearch(
  query: string,
  clientId: string,
  clientSecret: string,
  timeout: number,
): Promise<NaverResult | null> {
  const response = await axios.get(
    'https://openapi.naver.com/v1/search/shop.json',
    {
      params: { query, display: 5, sort: 'sim' },
      headers: {
        'X-Naver-Client-Id': clientId,
        'X-Naver-Client-Secret': clientSecret,
      },
      timeout,
    }
  );

  const items = response.data?.items;
  if (!items?.length) return null;

  const top = items[0];
  const price = parseInt(top.lprice) || 0;
  if (price === 0) return null;

  return {
    platform: 'naver',
    productName: top.title.replace(/<[^>]+>/g, ''),
    price,
    imageUrl: top.image || null,
    shoppingUrl: top.link,
  };
}

// 상품명으로 여러 결과 반환 (유저 선택용)
export async function searchNaverCandidates(name: string, count = 7): Promise<NaverCandidate[]> {
  const clientId = process.env.NAVER_CLIENT_ID ?? '';
  const clientSecret = process.env.NAVER_CLIENT_SECRET ?? '';
  if (!clientId || clientId === 'your_client_id_here') return [];

  const timeout = parseInt(process.env.API_TIMEOUT_MS || '3000');

  const response = await axios.get(
    'https://openapi.naver.com/v1/search/shop.json',
    {
      params: { query: name, display: count, sort: 'sim' },
      headers: {
        'X-Naver-Client-Id': clientId,
        'X-Naver-Client-Secret': clientSecret,
      },
      timeout,
    }
  );

  const items: any[] = response.data?.items ?? [];
  return items
    .map((item) => ({
      productName: item.title.replace(/<[^>]+>/g, ''),
      price: parseInt(item.lprice) || 0,
      imageUrl: item.image || null,
      shoppingUrl: item.link,
      mallName: item.mallName || '',
    }))
    .filter((c) => c.price > 0);
}

// barcode: 조회용 바코드, productName: 이미 확보된 상품명 (있으면 1번만 검색)
// productName 없을 때: 2단계 검색
//   Step 1 — 바코드 번호로 검색 → 상품명 추출
//   Step 2 — 추출된 상품명으로 재검색 → 이미지/가격 정확도 향상
export async function searchNaver(barcode: string, productName?: string): Promise<NaverResult | null> {
  const clientId = process.env.NAVER_CLIENT_ID ?? '';
  const clientSecret = process.env.NAVER_CLIENT_SECRET ?? '';

  // API 키 미설정 시 null 반환
  if (!clientId || clientId === 'your_client_id_here') {
    logger.debug('Naver', 'API key not set, skipping');
    return null;
  }

  const timeout = parseInt(process.env.API_TIMEOUT_MS || '3000');

  // Step 1: 항상 바코드로 먼저 검색 (네이버 카탈로그에 있으면 한국어 이름 + 이미지 확보)
  logger.debug('Naver', `Step 1 — barcode search: "${barcode}"`);
  const step1 = await naverApiSearch(barcode, clientId, clientSecret, timeout);

  if (step1) {
    // 바코드로 찾았으면 한국어 이름으로 재검색해서 정확도 향상
    logger.debug('Naver', `Step 2 — name search: "${step1.productName}"`);
    const step2 = await naverApiSearch(step1.productName, clientId, clientSecret, timeout);
    return step2 || step1;
  }

  // Step 1 실패 → OFF/쿠팡에서 온 상품명으로 fallback 검색
  if (productName && productName.trim().length > 1) {
    logger.debug('Naver', `Barcode not found, fallback name search: "${productName}"`);
    return naverApiSearch(productName, clientId, clientSecret, timeout);
  }

  logger.debug('Naver', `No result for barcode: "${barcode}"`);
  return null;
}
