import prisma from '../db/prisma';
import { logger } from '../utils/logger';

interface PriceResult {
  platform: string;
  price: number | null;
  productName: string | null;
  productUrl: string | null;
}

async function fetchNaverPrice(barcode: string): Promise<PriceResult> {
  const clientId = process.env.NAVER_CLIENT_ID;
  const clientSecret = process.env.NAVER_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    return { platform: 'naver', price: null, productName: null, productUrl: null };
  }
  try {
    const res = await fetch(
      `https://openapi.naver.com/v1/search/shop.json?query=${encodeURIComponent(barcode)}&display=1&sort=sim`,
      { headers: { 'X-Naver-Client-Id': clientId, 'X-Naver-Client-Secret': clientSecret } }
    );
    const data = await res.json() as any;
    const item = data.items?.[0];
    if (!item) return { platform: 'naver', price: null, productName: null, productUrl: null };
    return {
      platform: 'naver',
      price: item.lprice ? parseInt(item.lprice) : null,
      productName: item.title?.replace(/<[^>]+>/g, '') ?? null,
      productUrl: item.link ?? null,
    };
  } catch {
    return { platform: 'naver', price: null, productName: null, productUrl: null };
  }
}

async function fetchCoupangPrice(barcode: string): Promise<PriceResult> {
  // Coupang Partners API requires HMAC auth — implement when API key is available
  return { platform: 'coupang', price: null, productName: null, productUrl: null };
}

export async function triggerPriceLookup(postId: bigint, barcode: string): Promise<void> {
  try {
    const [naver, coupang] = await Promise.all([
      fetchNaverPrice(barcode),
      fetchCoupangPrice(barcode),
    ]);
    await prisma.postPriceLookup.createMany({
      data: [naver, coupang].map((r) => ({
        postId,
        platform: r.platform,
        price: r.price,
        productName: r.productName,
        productUrl: r.productUrl,
      })),
      skipDuplicates: false,
    });
  } catch (e) {
    logger.error('PriceLookup', 'Failed to fetch and store prices', e);
  }
}
