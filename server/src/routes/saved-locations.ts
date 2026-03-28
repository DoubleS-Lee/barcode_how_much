import { Router, Request, Response } from 'express';
import { z } from 'zod';
import prisma from '../db/prisma';

const router = Router();
const MAX_LOCATIONS = 8;

// GET /api/v1/saved-locations?device_uuid=
router.get('/', async (req: Request, res: Response) => {
  const { device_uuid } = req.query as Record<string, string>;
  if (!device_uuid) return res.status(400).json({ error: 'device_uuid required' });

  const rows = await prisma.savedLocation.findMany({
    where: { deviceUuid: device_uuid },
    orderBy: { createdAt: 'asc' },
  });

  return res.json({ locations: rows.map((r) => r.name) });
});

// POST /api/v1/saved-locations
router.post('/', async (req: Request, res: Response) => {
  const schema = z.object({
    device_uuid: z.string().uuid(),
    name: z.string().min(1).max(200),
  });
  const result = schema.safeParse(req.body);
  if (!result.success) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const { device_uuid, name } = result.data;

  // 최대 8개 제한
  const count = await prisma.savedLocation.count({ where: { deviceUuid: device_uuid } });
  if (count >= MAX_LOCATIONS) {
    return res.status(400).json({ error: 'MAX_LOCATIONS_REACHED' });
  }

  await prisma.savedLocation.upsert({
    where: { deviceUuid_name: { deviceUuid: device_uuid, name } },
    update: {},
    create: { deviceUuid: device_uuid, name },
  });

  const rows = await prisma.savedLocation.findMany({
    where: { deviceUuid: device_uuid },
    orderBy: { createdAt: 'asc' },
  });

  return res.status(201).json({ locations: rows.map((r) => r.name) });
});

// DELETE /api/v1/saved-locations/:name?device_uuid=
router.delete('/:name', async (req: Request, res: Response) => {
  const { device_uuid } = req.query as Record<string, string>;
  const name = decodeURIComponent(req.params.name as string);
  if (!device_uuid) return res.status(400).json({ error: 'device_uuid required' });

  await prisma.savedLocation.deleteMany({
    where: { deviceUuid: device_uuid, name },
  });

  const rows = await prisma.savedLocation.findMany({
    where: { deviceUuid: device_uuid },
    orderBy: { createdAt: 'asc' },
  });

  return res.json({ locations: rows.map((r) => r.name) });
});

export default router;
