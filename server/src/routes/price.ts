import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { getCached, setCache, deleteCache, getCacheKey } from '../cache/redis';
import { PriceResponse } from '../types/price.types';
import { priceOrchestrator } from '../services/price-orchestrator.service';
import { searchNaverCandidates } from '../services/naver.service';
import prisma from '../db/prisma';
import { logger } from '../utils/logger';

const router = Router();

const barcodeSchema = z.string().regex(/^\d{8,13}$/, 'Barcode must be 8-13 digits');

// GET /api/v1/price?barcode=8801234567890
router.get('/', async (req: Request, res: Response) => {
  const parseResult = barcodeSchema.safeParse(req.query.barcode);
  if (!parseResult.success) {
    return res.status(400).json({
      error: 'INVALID_BARCODE',
      message: '바코드 형식이 올바르지 않습니다. (8~13자리 숫자)',
    });
  }

  const barcode = parseResult.data;
  const cacheKey = getCacheKey('price', barcode);

  // 1. Redis 캐시 확인
  const cached = await getCached<PriceResponse>(cacheKey);
  if (cached) {
    const ageMinutes = Math.floor((Date.now() - new Date(cached.cached_at).getTime()) / 60000);
    // 이미지가 있는 캐시인데 상품에 이미지가 없는 경우 백그라운드 업데이트
    if (cached.image_url) {
      void prisma.product.updateMany({
        where: { barcode, imageUrl: null },
        data: { imageUrl: cached.image_url },
      }).catch((e) => logger.warn('Price', 'Background image update failed', e));
    }
    return res.json({ ...cached, cache_age_minutes: ageMinutes });
  }

  // 2. 자체 DB(products 테이블)에서 상품명 선조회
  // → 있으면 OFF/go-upc 호출 없이 바로 네이버 검색으로 단축
  const cachedProduct = await prisma.product.findUnique({
    where: { barcode },
    select: { name: true, imageUrl: true, linkedNaverUrl: true, linkedNaverPrice: true },
  });
  // Mock 이름은 신뢰하지 않음 (개발환경 오염 방지)
  const knownProductName = cachedProduct?.name?.includes('(Mock)')
    ? undefined
    : cachedProduct?.name ?? undefined;
  if (knownProductName) {
    logger.info('Price', `Found in local DB: "${knownProductName}"`);
  }

  // 사용자가 직접 연결한 네이버 상품이 있으면 그것을 우선 사용
  const linkedNaverEntry = cachedProduct?.linkedNaverUrl && cachedProduct?.linkedNaverPrice
    ? { url: cachedProduct.linkedNaverUrl, price: cachedProduct.linkedNaverPrice }
    : undefined;

  // 3. 캐시 미스 → 병렬 API 호출 (Promise.allSettled in orchestrator)
  const result = await priceOrchestrator(barcode, knownProductName, linkedNaverEntry);

  if (!result) {
    return res.status(404).json({
      error: 'PRODUCT_NOT_FOUND',
      message: '등록된 상품 정보가 없습니다.',
      fallback_tried: ['coupang', 'naver', 'openfoodfacts'],
    });
  }

  await setCache(cacheKey, result);

  // 상품명/이미지를 products 테이블에 upsert (히스토리 표시용)
  // Mock 이름은 저장하지 않음
  // knownProductName이 있으면 사용자가 직접 수정한 이름 — 이름은 덮어쓰지 않음
  if (result.product_name && !result.product_name.includes('(Mock)')) {
    if (!knownProductName) {
      // 신규 상품 — 이름 + 이미지 모두 저장
      void prisma.product.upsert({
        where: { barcode },
        update: { name: result.product_name, imageUrl: result.image_url },
        create: { barcode, name: result.product_name, imageUrl: result.image_url },
      }).catch((e) => logger.warn('Price', 'Product upsert failed', e));
    } else if (result.image_url && !cachedProduct?.imageUrl) {
      // 기존 상품이지만 이미지가 없는 경우 — 이미지만 업데이트
      void prisma.product.update({
        where: { barcode },
        data: { imageUrl: result.image_url },
      }).catch((e) => logger.warn('Price', 'Product image update failed', e));
    }
  }

  return res.json(result);
});

// PATCH /api/v1/price/products/:barcode — 상품명 직접 수정
router.patch('/products/:barcode', async (req: Request, res: Response) => {
  const barcodeParseResult = barcodeSchema.safeParse(req.params.barcode);
  if (!barcodeParseResult.success) {
    return res.status(400).json({ error: 'INVALID_BARCODE' });
  }

  const bodySchema = z.object({ name: z.string().min(1).max(200) });
  const bodyResult = bodySchema.safeParse(req.body);
  if (!bodyResult.success) {
    return res.status(400).json({ error: 'INVALID_NAME', message: '상품명을 입력해주세요.' });
  }

  const barcode = barcodeParseResult.data;
  const { name } = bodyResult.data;

  const product = await prisma.product.upsert({
    where: { barcode },
    update: { name },
    create: { barcode, name },
  });

  // 캐시 무효화 — 다음 스캔 시 수정된 이름으로 재검색
  await deleteCache(getCacheKey('price', barcode)).catch((e) => logger.warn('Price', 'Cache delete failed', e));

  return res.json({ barcode: product.barcode, name: product.name });
});

// GET /api/v1/price/naver-candidates?name=... — 상품명으로 네이버 후보 목록 반환
router.get('/naver-candidates', async (req: Request, res: Response) => {
  const name = (req.query.name as string)?.trim();
  if (!name) return res.status(400).json({ error: 'name required' });

  const candidates = await searchNaverCandidates(name, 7);
  return res.json({ candidates });
});

// POST /api/v1/price/relink-naver — 유저가 선택한 네이버 상품으로 최신 스캔 가격 교체
router.post('/relink-naver', async (req: Request, res: Response) => {
  const schema = z.object({
    device_uuid: z.string().uuid(),
    barcode: z.string().min(1),
    product_name: z.string().min(1).max(500),
    price: z.number().int().positive(),
    shopping_url: z.string().url(),
    image_url: z.string().nullable().optional(),
  });
  const result = schema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ error: 'INVALID_PARAMS' });

  const { device_uuid, barcode, product_name, price, shopping_url, image_url } = result.data;

  const device = await prisma.device.findUnique({ where: { deviceUuid: device_uuid } });
  if (!device) return res.status(404).json({ error: 'DEVICE_NOT_FOUND' });

  // 해당 기기의 해당 바코드 최신 스캔
  const latestScan = await prisma.scan.findFirst({
    where: { deviceId: device.id, barcode, scanType: 'product' },
    orderBy: { scannedAt: 'desc' },
  });
  if (!latestScan) return res.status(404).json({ error: 'SCAN_NOT_FOUND' });

  // 기존 Naver 온라인 가격 삭제 후 새 가격으로 교체
  await prisma.onlinePrice.deleteMany({
    where: { scanId: latestScan.id, platform: 'naver' },
  });
  await prisma.onlinePrice.create({
    data: {
      scanId: latestScan.id,
      platform: 'naver',
      price,
      isLowest: true,
      productUrl: shopping_url,
    },
  });

  // 연결된 네이버 상품 저장 (재스캔 시 동일 상품 유지)
  // name은 업데이트하지 않음 — 사용자가 직접 설정한 상품명 보존
  await prisma.product.upsert({
    where: { barcode },
    update: { imageUrl: image_url ?? undefined, linkedNaverUrl: shopping_url, linkedNaverPrice: price },
    create: { barcode, name: product_name, imageUrl: image_url ?? null, linkedNaverUrl: shopping_url, linkedNaverPrice: price },
  });

  // 캐시 무효화 — 다음 스캔 시 재연결된 상품명으로 재검색
  await deleteCache(getCacheKey('price', barcode)).catch((e) => logger.warn('Price', 'Cache delete failed', e));

  return res.json({ ok: true });
});

export default router;
