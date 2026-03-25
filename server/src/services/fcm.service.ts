import admin from 'firebase-admin';
import path from 'path';
import { readFileSync } from 'fs';

let initialized = false;

function ensureInitialized(): boolean {
  if (initialized) return true;

  const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  if (!serviceAccountPath) {
    // FCM 비활성화 상태 — 설정 후 활성화됨
    return false;
  }

  try {
    const raw = readFileSync(path.resolve(serviceAccountPath), 'utf-8');
    const serviceAccount = JSON.parse(raw);
    admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
    initialized = true;
    console.log('[FCM] Firebase Admin SDK initialized');
    return true;
  } catch (e) {
    console.error('[FCM] Failed to initialize:', e);
    return false;
  }
}

export async function sendFavoriteDropNotification(params: {
  token: string;
  productName: string;
  currentPrice: number;
  previousPrice: number;
  barcode: string;
}): Promise<void> {
  if (!ensureInitialized()) return;

  const fmt = (n: number) => n.toLocaleString('ko-KR');
  const diff = params.previousPrice - params.currentPrice;

  try {
    await admin.messaging().send({
      token: params.token,
      notification: {
        title: `⭐ ${params.productName}`,
        body: `찜한 상품이 ${fmt(diff)}원 내려갔어요! 지금 ${fmt(params.currentPrice)}원`,
      },
      data: {
        type: 'favorite_drop',
        barcode: params.barcode,
        current_price: String(params.currentPrice),
        previous_price: String(params.previousPrice),
      },
      android: {
        notification: { channelId: 'price_drop', priority: 'high', sound: 'default' },
      },
      apns: {
        payload: { aps: { sound: 'default', badge: 1 } },
      },
    });
    console.log(`[FCM] Sent favorite drop: ${params.productName}`);
  } catch (e: any) {
    console.error('[FCM] Send error:', e?.errorInfo?.code ?? e);
  }
}

export async function sendPriceDropNotification(params: {
  token: string;
  productName: string;
  onlinePrice: number;
  offlinePrice: number;
  barcode: string;
}): Promise<void> {
  if (!ensureInitialized()) return;

  const fmt = (n: number) => n.toLocaleString('ko-KR');
  const diff = params.offlinePrice - params.onlinePrice;

  try {
    await admin.messaging().send({
      token: params.token,
      notification: {
        title: `💰 ${params.productName}`,
        body: `마트(${fmt(params.offlinePrice)}원)보다 온라인이 ${fmt(diff)}원 더 저렴해요!`,
      },
      data: {
        type: 'price_drop',
        barcode: params.barcode,
        online_price: String(params.onlinePrice),
        offline_price: String(params.offlinePrice),
      },
      android: {
        notification: {
          channelId: 'price_drop',
          priority: 'high',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: { sound: 'default', badge: 1 },
        },
      },
    });
    console.log(`[FCM] Sent price drop: ${params.productName}`);
  } catch (e: any) {
    // 토큰 만료 시 DB에서 제거
    if (e?.errorInfo?.code === 'messaging/registration-token-not-registered') {
      console.log('[FCM] Token expired, removing...');
      // token으로 device 찾아서 fcmToken null 처리는 caller에서
    }
    console.error('[FCM] Send error:', e?.errorInfo?.code ?? e);
  }
}
