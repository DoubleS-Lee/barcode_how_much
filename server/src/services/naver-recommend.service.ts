import axios from 'axios';
import dotenv from 'dotenv';
import { logger } from '../utils/logger';
dotenv.config();

export interface RecommendItem {
  product_name: string;
  price: number;
  image_url: string | null;
  shopping_url: string;
  trend_score: number | null;
}

export interface RecommendResult {
  recommendations: RecommendItem[];
  trending_keywords: string[];
  source: 'datalab' | 'basic';
}

// 네이버 쇼핑 category1 텍스트 → DataLab 카테고리 ID 매핑
const CATEGORY_MAP: Record<string, string> = {
  '패션의류':     '50000000',
  '패션잡화':     '50000001',
  '화장품':       '50000002',
  '미용':         '50000002',
  '디지털':       '50000003',
  '가전':         '50000003',
  '가구':         '50000004',
  '인테리어':     '50000004',
  '출산':         '50000005',
  '육아':         '50000005',
  '식품':         '50000006',
  '식음료':       '50000006',
  '스포츠':       '50000007',
  '레저':         '50000007',
  '생활':         '50000008',
  '건강':         '50000008',
  '세제':         '50000008',
};

function findCategoryId(categoryText: string): string | null {
  for (const [keyword, id] of Object.entries(CATEGORY_MAP)) {
    if (categoryText.includes(keyword)) return id;
  }
  return null;
}

/** 상품명에서 핵심 키워드 2~3개 추출 (괄호·특수문자 제거) */
function extractKeywords(productName: string): string[] {
  const clean = productName.replace(/<[^>]+>/g, '').replace(/[()[\]{}]/g, ' ');
  const tokens = clean.split(/\s+/).filter((t) => t.length >= 2);
  // 숫자만, 단위만 제거
  const filtered = tokens.filter((t) => !/^\d+[a-zA-Z]*$/.test(t));
  return [...new Set(filtered)].slice(0, 3);
}

/** DataLab 쇼핑인사이트 — 카테고리 내 키워드 트렌드 조회 */
async function getDataLabTrends(
  categoryId: string,
  keywords: string[],
  clientId: string,
  clientSecret: string,
): Promise<Record<string, number>> {
  const today = new Date();
  const endDate = today.toISOString().split('T')[0];
  const startDate = new Date(today.getFullYear(), today.getMonth() - 2, 1)
    .toISOString()
    .split('T')[0];

  const body = {
    startDate,
    endDate,
    timeUnit: 'month',
    category: categoryId,
    keyword: keywords.map((k) => ({ name: k, param: [k] })),
  };

  const response = await axios.post(
    'https://openapi.naver.com/v1/datalab/shopping/category/keywords',
    body,
    {
      headers: {
        'X-Naver-Client-Id': clientId,
        'X-Naver-Client-Secret': clientSecret,
        'Content-Type': 'application/json',
      },
      timeout: 4000,
    },
  );

  const results: Record<string, number> = {};
  for (const item of response.data?.results ?? []) {
    const latest = item.data?.at(-1)?.ratio ?? 0;
    results[item.title] = latest;
  }
  return results;
}

/** 네이버 쇼핑 검색 — 인기 유사상품 (sort=sim) */
async function searchNaverSimilar(
  keyword: string,
  clientId: string,
  clientSecret: string,
  display = 5,
): Promise<RecommendItem[]> {
  const response = await axios.get(
    'https://openapi.naver.com/v1/search/shop.json',
    {
      params: { query: keyword, display, sort: 'sim' },
      headers: {
        'X-Naver-Client-Id': clientId,
        'X-Naver-Client-Secret': clientSecret,
      },
      timeout: 3000,
    },
  );

  const items = (response.data?.items ?? []) as Record<string, string>[];
  return items
    .map((item) => ({
      product_name: item.title.replace(/<[^>]+>/g, ''),
      price: parseInt(item.lprice) || 0,
      image_url: item.image || null,
      shopping_url: item.link,
      trend_score: null,
    }))
    .filter((item) => item.price >= 1000); // 라벨·부품 등 저가 악세서리 제외
}

export async function getRecommendations(
  barcode: string,
  productName: string,
  categoryText = '',
): Promise<RecommendResult> {
  const clientId = process.env.NAVER_CLIENT_ID;
  const clientSecret = process.env.NAVER_CLIENT_SECRET;

  // API 키 미설정 → mock 반환
  if (!clientId || clientId === 'your_client_id_here') {
    logger.debug('Recommend', 'Using mock data (API key not set)');
    return {
      recommendations: [
        { product_name: '비슷한 상품 A (Mock)', price: 8900, image_url: null, shopping_url: '#', trend_score: 82 },
        { product_name: '비슷한 상품 B (Mock)', price: 11200, image_url: null, shopping_url: '#', trend_score: 67 },
        { product_name: '비슷한 상품 C (Mock)', price: 9500, image_url: null, shopping_url: '#', trend_score: 55 },
      ],
      trending_keywords: ['인기키워드A', '인기키워드B'],
      source: 'datalab',
    };
  }

  const keywords = extractKeywords(productName);
  if (keywords.length === 0) keywords.push(barcode);

  // DataLab 트렌드 조회 시도
  let trendScores: Record<string, number> = {};
  let topKeyword = keywords[0];
  let source: 'datalab' | 'basic' = 'basic';

  // categoryText 없으면 productName으로 카테고리 탐색
  const categoryId = findCategoryId(categoryText || productName);
  if (categoryId && keywords.length >= 1) {
    try {
      trendScores = await getDataLabTrends(categoryId, keywords, clientId, clientSecret!);
      const sorted = Object.entries(trendScores).sort((a, b) => b[1] - a[1]);
      if (sorted.length > 0) {
        topKeyword = sorted[0][0];
        source = 'datalab';
      }
    } catch (e) {
      logger.warn('Recommend', 'DataLab failed, falling back to basic search', (e as Error).message);
    }
  }

  // 인기 유사상품 검색
  const items = await searchNaverSimilar(topKeyword, clientId, clientSecret!);

  // trend_score 주입
  const withScores: RecommendItem[] = items.map((item) => {
    const matchedKeyword = keywords.find((k) => item.product_name.includes(k));
    return {
      ...item,
      trend_score: matchedKeyword ? (trendScores[matchedKeyword] ?? null) : null,
    };
  });

  const trendingKeywords = Object.entries(trendScores)
    .sort((a, b) => b[1] - a[1])
    .map(([k]) => k);

  return { recommendations: withScores, trending_keywords: trendingKeywords, source };
}
