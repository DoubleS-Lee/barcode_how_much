import { Router, Request, Response } from 'express';
import { z } from 'zod';
import prisma from '../db/prisma';

const router = Router();

const scanTypeEnum = z.enum(['product', 'qr_url', 'qr_wifi', 'qr_contact', 'qr_text', 'isbn', 'unknown']);

const scanRequestSchema = z.object({
  device_uuid: z.string().uuid(),
  os: z.enum(['ios', 'android']),
  app_version: z.string().optional(),
  scan_type: scanTypeEnum,
  barcode: z.string().optional().nullable(),
  latitude: z.number().optional().nullable(),
  longitude: z.number().optional().nullable(),
  online_prices: z.array(z.object({
    platform: z.string(),
    price: z.number().int().positive(),
    is_lowest: z.boolean(),
  })).optional(),
  barcode_content: z.object({
    raw_value: z.string(),
    content_type: z.string(),
    parsed_data: z.record(z.unknown()).optional(),
  }).optional().nullable(),
});

// POST /api/v1/scans — 스캔 이벤트 저장 (상품/비상품 모두)
router.post('/', async (req: Request, res: Response) => {
  const parseResult = scanRequestSchema.safeParse(req.body);
  if (!parseResult.success) {
    return res.status(400).json({ error: 'INVALID_REQUEST', details: parseResult.error.flatten() });
  }

  const data = parseResult.data;

  const device = await prisma.device.upsert({
    where: { deviceUuid: data.device_uuid },
    update: { lastSeenAt: new Date(), appVersion: data.app_version },
    create: { deviceUuid: data.device_uuid, os: data.os, appVersion: data.app_version },
  });

  const scan = await prisma.scan.create({
    data: {
      deviceId: device.id,
      scanType: data.scan_type,
      barcode: data.barcode,
      latitude: data.latitude,
      longitude: data.longitude,
    },
  });

  // 상품 스캔 → 온라인 가격 저장
  if (data.scan_type === 'product' && data.online_prices?.length) {
    await prisma.onlinePrice.createMany({
      data: data.online_prices.map((p) => ({
        scanId: scan.id,
        platform: p.platform,
        price: p.price,
        isLowest: p.is_lowest,
      })),
    });
  }

  // 비상품 스캔 → barcode_contents 저장
  if (data.scan_type !== 'product' && data.barcode_content) {
    await prisma.barcodeContent.create({
      data: {
        scanId: scan.id,
        rawValue: data.barcode_content.raw_value,
        contentType: data.barcode_content.content_type,
        parsedData: (data.barcode_content.parsed_data as object) ?? undefined,
      },
    });
  }

  return res.status(201).json({
    scan_id: scan.id.toString(),
    device_id: device.id.toString(),
    created_at: scan.scannedAt,
  });
});

// POST /api/v1/scans/:scanId/offline-price — 마트 직접 입력 가격 저장
router.post('/:scanId/offline-price', async (req: Request, res: Response) => {
  const scanIdParam = Array.isArray(req.params.scanId) ? req.params.scanId[0] : req.params.scanId;
  const scanId = BigInt(scanIdParam);
  const schema = z.object({
    price: z.number().int().positive(),
    store_hint: z.string().optional(),
  });

  const parseResult = schema.safeParse(req.body);
  if (!parseResult.success) {
    return res.status(400).json({ error: 'INVALID_REQUEST', details: parseResult.error.flatten() });
  }

  const offlinePrice = await prisma.offlinePrice.create({
    data: { scanId, price: parseResult.data.price, storeHint: parseResult.data.store_hint },
  });

  return res.status(201).json({
    id: offlinePrice.id.toString(),
    scan_id: offlinePrice.scanId.toString(),
    price: offlinePrice.price,
    store_hint: offlinePrice.storeHint,
    created_at: offlinePrice.createdAt,
  });
});

// GET /api/v1/scans/history?device_uuid=...&limit=50&offset=0
router.get('/history', async (req: Request, res: Response) => {
  const { device_uuid, limit = '50', offset = '0' } = req.query as Record<string, string>;

  const device = await prisma.device.findUnique({ where: { deviceUuid: device_uuid } });
  if (!device) return res.json({ total: 0, items: [] });

  const [total, scans] = await Promise.all([
    prisma.scan.count({ where: { deviceId: device.id } }),
    prisma.scan.findMany({
      where: { deviceId: device.id },
      orderBy: { scannedAt: 'desc' },
      take: parseInt(limit),
      skip: parseInt(offset),
      include: { onlinePrices: true, offlinePrices: true, barcodeContent: true },
    }),
  ]);

  // 상품 스캔의 바코드 목록으로 products 테이블 일괄 조회
  const productBarcodes = scans
    .filter((s) => s.scanType === 'product' && s.barcode)
    .map((s) => s.barcode as string);

  const products = productBarcodes.length > 0
    ? await prisma.product.findMany({ where: { barcode: { in: productBarcodes } } })
    : [];
  const productMap = new Map(products.map((p) => [p.barcode, p]));

  const items = scans.map((scan) => {
    const lowestOnline = scan.onlinePrices.find((p) => p.isLowest);
    const offlinePrice = scan.offlinePrices[0];
    const product = scan.barcode ? productMap.get(scan.barcode) : null;
    return {
      scan_id: scan.id.toString(),
      scan_type: scan.scanType,
      scanned_at: scan.scannedAt,
      ...(scan.scanType === 'product'
        ? {
            product: {
              barcode: scan.barcode,
              name: product?.name ?? null,
              image_url: product?.imageUrl ?? null,
            },
            lowest_online_price: lowestOnline?.price ?? null,
            lowest_online_platform: lowestOnline?.platform ?? null,
            offline_price: offlinePrice?.price ?? null,
            store_hint: offlinePrice?.storeHint ?? null,
          }
        : {
            barcode_content: scan.barcodeContent
              ? { content_type: scan.barcodeContent.contentType, parsed_data: scan.barcodeContent.parsedData }
              : null,
          }),
    };
  });

  return res.json({ total, items });
});

// GET /api/v1/scans/products/:barcode/price-history — fl_chart 그래프용
router.get('/products/:barcode/price-history', async (req: Request, res: Response) => {
  const { barcode } = req.params;
  const { device_uuid } = req.query as { device_uuid: string };

  const device = await prisma.device.findUnique({ where: { deviceUuid: device_uuid } });
  if (!device) return res.json({ barcode, product_name: null, price_history: [] });

  const scans = await prisma.scan.findMany({
    where: { deviceId: device.id, barcode: barcode as string, scanType: 'product' },
    orderBy: { scannedAt: 'asc' },
    include: { onlinePrices: true, offlinePrices: true },
  });

  const priceHistory = scans.map((scan) => {
    const lowestOnline = scan.onlinePrices.find((p) => p.isLowest);
    const offlinePrice = scan.offlinePrices[0];
    return {
      scanned_at: scan.scannedAt,
      online_lowest_price: lowestOnline?.price ?? null,
      online_lowest_platform: lowestOnline?.platform ?? null,
      offline_price: offlinePrice?.price ?? null,
      store_hint: offlinePrice?.storeHint ?? null,
    };
  });

  return res.json({ barcode, product_name: null, price_history: priceHistory });
});

// DELETE /api/v1/scans/history?device_uuid=... — 기기의 모든 스캔 기록 삭제
router.delete('/history', async (req: Request, res: Response) => {
  const { device_uuid } = req.query as Record<string, string>;
  if (!device_uuid) return res.status(400).json({ error: 'device_uuid required' });

  const device = await prisma.device.findUnique({ where: { deviceUuid: device_uuid } });
  if (!device) return res.json({ deleted: 0 });

  // 스캔에 연결된 온라인/오프라인 가격, QR 내용 먼저 삭제
  const scanIds = (await prisma.scan.findMany({
    where: { deviceId: device.id },
    select: { id: true },
  })).map((s) => s.id);

  await prisma.onlinePrice.deleteMany({ where: { scanId: { in: scanIds } } });
  await prisma.offlinePrice.deleteMany({ where: { scanId: { in: scanIds } } });
  await prisma.barcodeContent.deleteMany({ where: { scanId: { in: scanIds } } });

  const { count } = await prisma.scan.deleteMany({ where: { deviceId: device.id } });

  return res.json({ deleted: count });
});

export default router;
