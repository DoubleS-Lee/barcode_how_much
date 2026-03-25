import { Router, Request, Response } from 'express';
import prisma from '../db/prisma';

const router = Router();

// GET /api/v1/favorites?device_uuid=xxx
router.get('/', async (req: Request, res: Response) => {
  const device_uuid = req.query.device_uuid as string;
  if (!device_uuid) return res.status(400).json({ error: 'MISSING_DEVICE_UUID' });

  const favorites = await prisma.deviceFavorite.findMany({
    where: { deviceUuid: device_uuid },
    select: { barcode: true },
    orderBy: { createdAt: 'desc' },
  });

  res.json({ barcodes: favorites.map((f) => f.barcode) });
});

// POST /api/v1/favorites  { device_uuid, barcode }
router.post('/', async (req: Request, res: Response) => {
  const { device_uuid, barcode } = req.body;
  if (!device_uuid || !barcode) return res.status(400).json({ error: 'INVALID_REQUEST' });

  await prisma.deviceFavorite.upsert({
    where: { deviceUuid_barcode: { deviceUuid: device_uuid, barcode } },
    create: { deviceUuid: device_uuid, barcode },
    update: {},
  });

  res.json({ ok: true });
});

// DELETE /api/v1/favorites/:barcode  body: { device_uuid }
router.delete('/:barcode', async (req: Request, res: Response) => {
  const { device_uuid } = req.body;
  const barcode = req.params.barcode as string;
  if (!device_uuid) return res.status(400).json({ error: 'INVALID_REQUEST' });

  await prisma.deviceFavorite.deleteMany({
    where: { deviceUuid: device_uuid as string, barcode },
  });

  res.json({ ok: true });
});

export default router;
