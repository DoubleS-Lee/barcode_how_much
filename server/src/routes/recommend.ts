import { Router, Request, Response } from 'express';
import { getCached, setCache, getCacheKey } from '../cache/redis';
import { getRecommendations, RecommendResult } from '../services/naver-recommend.service';

const router = Router();

// GET /api/v1/recommend?barcode=...&product_name=...&category=...
router.get('/', async (req: Request, res: Response) => {
  const barcode = String(req.query.barcode || '');
  const productName = String(req.query.product_name || '');
  const categoryText = String(req.query.category || '');

  if (!barcode && !productName) {
    return res.status(400).json({ error: 'barcode 또는 product_name 필요' });
  }

  const cacheKey = getCacheKey('recommend', barcode || productName);
  const cached = await getCached<RecommendResult>(cacheKey);
  if (cached) return res.json(cached);

  const result = await getRecommendations(barcode, productName, categoryText);

  // 추천 데이터는 6시간 캐시 (트렌드는 자주 안 바뀜)
  await setCache(cacheKey, result, 60 * 60 * 6);

  return res.json(result);
});

export default router;
