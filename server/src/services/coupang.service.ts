import axios from 'axios';
import crypto from 'crypto';
import dotenv from 'dotenv';
dotenv.config();

const BASE_URL = 'https://api-gateway.coupang.com';

export interface CoupangResult {
  platform: 'coupang';
  productName: string;
  price: number;
  imageUrl: string | null;
  affiliateUrl: string;
}

function generateSignature(method: string, path: string, query: string, datetime: string): string {
  const secretKey = process.env.COUPANG_SECRET_KEY || '';
  const message = `${datetime}\n${method}\n${path}\n${query}`;
  return crypto.createHmac('sha256', secretKey).update(message).digest('hex');
}

export async function searchCoupang(barcode: string): Promise<CoupangResult | null> {
  const accessKey = process.env.COUPANG_ACCESS_KEY;
  const partnerId = process.env.COUPANG_PARTNER_ID;

  // API 키 미설정 시 null 반환
  if (!accessKey || accessKey === 'your_access_key_here') {
    console.log('[Coupang] API key not set, skipping');
    return null;
  }

  const method = 'GET';
  const path = '/v2/providers/affiliate_open_api/apis/openapi/products/search';
  const query = `keyword=${encodeURIComponent(barcode)}&limit=5`;
  const datetime = new Date().toISOString().replace(/[:\-.]/g, '').slice(0, 14) + 'Z';
  const signature = generateSignature(method, path, query, datetime);

  const response = await axios.get(
    `${BASE_URL}${path}?${query}`,
    {
      headers: {
        Authorization: `CEA algorithm=HmacSHA256, access-key=${accessKey}, signed-date=${datetime}, signature=${signature}`,
      },
      timeout: parseInt(process.env.API_TIMEOUT_MS || '3000'),
    }
  );

  const products = response.data?.data?.productData;
  if (!products?.length) return null;

  const top = products[0];
  return {
    platform: 'coupang',
    productName: top.productName,
    price: top.productPrice,
    imageUrl: top.productImage || null,
    affiliateUrl: top.productUrl,
  };
}
