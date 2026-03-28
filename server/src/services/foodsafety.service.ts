import axios from 'axios';
import dotenv from 'dotenv';
import { logger } from '../utils/logger';
dotenv.config();

export interface FoodSafetyResult {
  productName: string;
  companyName: string | null;
}

const BASE = 'http://openapi.foodsafetykorea.go.kr/api';

// I2570: 식품의약품안전처 유통바코드 — BRCD_NO로 검색
async function searchI2570(barcode: string, apiKey: string): Promise<FoodSafetyResult | null> {
  const url = `${BASE}/${apiKey}/I2570/json/1/5/BRCD_NO=${barcode}`;
  const res = await axios.get(url, { timeout: 10000 });
  const rows = res.data?.I2570?.row;
  if (!rows?.length) return null;

  const row = rows[0];
  const productName = row.PRDT_NM?.trim();
  if (!productName) return null;

  return {
    productName,
    companyName: row.CMPNY_NM?.trim() || null,
  };
}

// C005: 식품의약품안전처 바코드연계제품정보 — BAR_CD로 검색
async function searchC005(barcode: string, apiKey: string): Promise<FoodSafetyResult | null> {
  const url = `${BASE}/${apiKey}/C005/json/1/5/BAR_CD=${barcode}`;
  const res = await axios.get(url, { timeout: 10000 });
  const rows = res.data?.C005?.row;
  if (!rows?.length) return null;

  const row = rows[0];
  const productName = row.PRDLST_NM?.trim();
  if (!productName) return null;

  return {
    productName,
    companyName: row.BSSH_NM?.trim() || null,
  };
}

// I2570 먼저 시도, 없으면 C005 fallback
export async function searchFoodSafety(barcode: string): Promise<FoodSafetyResult | null> {
  const apiKey = process.env.FOODSAFETY_API_KEY;
  if (!apiKey || apiKey === 'your_key_here') {
    logger.debug('FoodSafety', 'API key not set, skipping');
    return null;
  }

  try {
    const result = await searchI2570(barcode, apiKey);
    if (result) {
      logger.debug('FoodSafety', `I2570 found: "${result.productName}" (${result.companyName})`);
      return result;
    }
  } catch (e) {
    logger.warn('FoodSafety', 'I2570 error', (e as Error)?.message);
  }

  try {
    const result = await searchC005(barcode, apiKey);
    if (result) {
      logger.debug('FoodSafety', `C005 found: "${result.productName}" (${result.companyName})`);
      return result;
    }
  } catch (e) {
    logger.warn('FoodSafety', 'C005 error', (e as Error)?.message);
  }

  logger.debug('FoodSafety', `Not found for barcode: ${barcode}`);
  return null;
}
