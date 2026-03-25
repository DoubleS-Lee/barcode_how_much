import { Router, Request, Response } from 'express';
import { z } from 'zod';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import prisma from '../db/prisma';
import { triggerPriceLookup } from '../services/priceLookup';

// 업로드 디렉토리 생성
const uploadDir = path.join(__dirname, '..', '..', 'uploads', 'posts');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
    cb(null, `${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
    cb(null, allowed.includes(file.mimetype));
  },
});

const router = Router();

const serializePost = (p: any, extras?: { commentCount?: number; liked?: boolean; reported?: boolean }) => ({
  id: p.id.toString(),
  author_id: p.deviceUuid.substring(0, 8),
  title: p.title,
  content: p.content,
  price: p.price,
  barcode: p.barcode ?? null,
  image_url: p.imageUrl ?? null,
  share_location: p.shareLocation,
  latitude: p.latitude != null ? Number(p.latitude) : null,
  longitude: p.longitude != null ? Number(p.longitude) : null,
  location_hint: p.locationHint ?? null,
  view_count: p.viewCount ?? 0,
  like_count: p.likeCount ?? 0,
  report_count: p.reportCount ?? 0,
  comment_count: extras?.commentCount ?? p._count?.comments ?? 0,
  liked: extras?.liked ?? false,
  reported: extras?.reported ?? false,
  price_lookups: (p.priceLookups ?? []).map((pl: any) => ({
    platform: pl.platform,
    price: pl.price,
    product_name: pl.productName,
    product_url: pl.productUrl,
    fetched_at: pl.fetchedAt,
  })),
  created_at: p.createdAt,
  updated_at: p.updatedAt,
});

const postSelect = {
  id: true, deviceUuid: true, title: true, content: true, price: true,
  barcode: true, imageUrl: true, shareLocation: true, latitude: true, longitude: true,
  locationHint: true, viewCount: true, likeCount: true, reportCount: true,
  createdAt: true, updatedAt: true,
  _count: { select: { comments: true } },
};

// POST /api/v1/posts/upload-image
router.post('/upload-image', upload.single('image'), (req: Request, res: Response) => {
  if (!req.file) return res.status(400).json({ error: 'NO_FILE' });
  const baseUrl = `${req.protocol}://${req.get('host')}`;
  const imageUrl = `${baseUrl}/uploads/posts/${req.file.filename}`;
  res.json({ image_url: imageUrl });
});

// GET /api/v1/posts
router.get('/', async (req: Request, res: Response) => {
  const page = Math.max(1, parseInt(req.query.page as string) || 1);
  const limit = Math.min(50, parseInt(req.query.limit as string) || 20);
  const skip = (page - 1) * limit;
  const search = (req.query.search as string)?.trim() || undefined;
  const device_uuid = req.query.device_uuid as string | undefined;

  const where = search
    ? { OR: [
        { title: { contains: search, mode: 'insensitive' as const } },
        { content: { contains: search, mode: 'insensitive' as const } },
      ]}
    : {};

  const [posts, total] = await Promise.all([
    prisma.post.findMany({ where, orderBy: { createdAt: 'desc' }, skip, take: limit, select: postSelect }),
    prisma.post.count({ where }),
  ]);

  let likedSet = new Set<string>();
  let reportedSet = new Set<string>();
  if (device_uuid) {
    const [likes, reports] = await Promise.all([
      prisma.postLike.findMany({
        where: { deviceUuid: device_uuid, postId: { in: posts.map((p) => p.id) } },
        select: { postId: true },
      }),
      prisma.postReport.findMany({
        where: { deviceUuid: device_uuid, postId: { in: posts.map((p) => p.id) } },
        select: { postId: true },
      }),
    ]);
    likedSet = new Set(likes.map((l) => l.postId.toString()));
    reportedSet = new Set(reports.map((r) => r.postId.toString()));
  }

  res.json({
    posts: posts.map((p) => serializePost(p, {
      liked: likedSet.has(p.id.toString()),
      reported: reportedSet.has(p.id.toString()),
    })),
    total, page, limit,
  });
});

// GET /api/v1/posts/:id
router.get('/:id', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const device_uuid = req.query.device_uuid as string | undefined;

  const post = await prisma.post.update({
    where: { id },
    data: { viewCount: { increment: 1 } },
    include: { priceLookups: true, _count: { select: { comments: true } } },
  });
  if (!post) return res.status(404).json({ error: 'NOT_FOUND' });

  let liked = false;
  let reported = false;
  if (device_uuid) {
    const [like, report] = await Promise.all([
      prisma.postLike.findUnique({ where: { postId_deviceUuid: { postId: id, deviceUuid: device_uuid } } }),
      prisma.postReport.findUnique({ where: { postId_deviceUuid: { postId: id, deviceUuid: device_uuid } } }),
    ]);
    liked = !!like;
    reported = !!report;
  }

  res.json(serializePost(post, { liked, reported }));
});

// POST /api/v1/posts
const createSchema = z.object({
  device_uuid: z.string().uuid(),
  title: z.string().min(1).max(200),
  content: z.string().min(1),
  price: z.number().int().positive(),
  barcode: z.string().max(20).optional().nullable(),
  image_url: z.string().url().optional().nullable(),
  share_location: z.boolean().default(false),
  latitude: z.number().optional().nullable(),
  longitude: z.number().optional().nullable(),
  location_hint: z.string().max(200).optional().nullable(),
});

router.post('/', async (req: Request, res: Response) => {
  const parsed = createSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_REQUEST', details: parsed.error.flatten() });

  const { device_uuid, title, content, price, barcode, image_url, share_location, latitude, longitude, location_hint } = parsed.data;
  const post = await prisma.post.create({
    data: {
      deviceUuid: device_uuid, title, content, price,
      barcode: barcode ?? null,
      imageUrl: image_url ?? null,
      shareLocation: share_location,
      latitude: share_location && latitude != null ? latitude : null,
      longitude: share_location && longitude != null ? longitude : null,
      locationHint: share_location ? (location_hint ?? null) : null,
    },
    include: { priceLookups: true, _count: { select: { comments: true } } },
  });

  const searchQuery = barcode ?? title;
  if (searchQuery) triggerPriceLookup(post.id, searchQuery);

  res.status(201).json(serializePost(post));
});

// PUT /api/v1/posts/:id
const updateSchema = z.object({
  device_uuid: z.string().uuid(),
  title: z.string().min(1).max(200).optional(),
  content: z.string().min(1).optional(),
  price: z.number().int().positive().optional(),
  barcode: z.string().max(20).optional().nullable(),
  image_url: z.string().url().optional().nullable(),
  share_location: z.boolean().optional(),
  latitude: z.number().optional().nullable(),
  longitude: z.number().optional().nullable(),
  location_hint: z.string().max(200).optional().nullable(),
});

router.put('/:id', async (req: Request, res: Response) => {
  const parsed = updateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: 'INVALID_REQUEST', details: parsed.error.flatten() });

  const id = BigInt(req.params.id as string);
  const { device_uuid, title, content, price, barcode, image_url, share_location, latitude, longitude, location_hint } = parsed.data;

  const post = await prisma.post.findUnique({ where: { id } });
  if (!post) return res.status(404).json({ error: 'NOT_FOUND' });
  if (post.deviceUuid !== device_uuid) return res.status(403).json({ error: 'FORBIDDEN' });

  const updated = await prisma.post.update({
    where: { id },
    data: {
      ...(title && { title }),
      ...(content && { content }),
      ...(price && { price }),
      ...(barcode !== undefined && { barcode: barcode ?? null }),
      ...(image_url !== undefined && { imageUrl: image_url ?? null }),
      ...(share_location !== undefined && {
        shareLocation: share_location,
        latitude: share_location && latitude != null ? latitude : null,
        longitude: share_location && longitude != null ? longitude : null,
        locationHint: share_location ? (location_hint ?? null) : null,
      }),
    },
    include: { priceLookups: true, _count: { select: { comments: true } } },
  });

  res.json(serializePost(updated));
});

// DELETE /api/v1/posts/:id
router.delete('/:id', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const { device_uuid } = req.body;
  if (!device_uuid) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const post = await prisma.post.findUnique({ where: { id } });
  if (!post) return res.status(404).json({ error: 'NOT_FOUND' });
  if (post.deviceUuid !== device_uuid) return res.status(403).json({ error: 'FORBIDDEN' });

  await prisma.post.delete({ where: { id } });
  res.json({ ok: true });
});

// POST /api/v1/posts/:id/like
router.post('/:id/like', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const { device_uuid } = req.body;
  if (!device_uuid) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const existing = await prisma.postLike.findUnique({
    where: { postId_deviceUuid: { postId: id, deviceUuid: device_uuid } },
  });

  if (existing) {
    await prisma.postLike.delete({ where: { id: existing.id } });
  } else {
    await prisma.postLike.create({ data: { postId: id, deviceUuid: device_uuid } });
  }

  const likeCount = await prisma.postLike.count({ where: { postId: id } });
  await prisma.post.update({ where: { id }, data: { likeCount } });

  res.json({ liked: !existing, like_count: likeCount });
});

// POST /api/v1/posts/:id/report
router.post('/:id/report', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const { device_uuid } = req.body;
  if (!device_uuid) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const existing = await prisma.postReport.findUnique({
    where: { postId_deviceUuid: { postId: id, deviceUuid: device_uuid } },
  });

  if (existing) {
    const post = await prisma.post.findUnique({ where: { id }, select: { reportCount: true } });
    return res.json({ reported: true, report_count: post?.reportCount ?? 0 });
  }

  await prisma.postReport.create({ data: { postId: id, deviceUuid: device_uuid } });
  const reportCount = await prisma.postReport.count({ where: { postId: id } });
  await prisma.post.update({ where: { id }, data: { reportCount } });

  res.json({ reported: true, report_count: reportCount });
});

// GET /api/v1/posts/:id/comments
router.get('/:id/comments', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const device_uuid = req.query.device_uuid as string | undefined;

  const comments = await prisma.postComment.findMany({
    where: { postId: id },
    orderBy: { createdAt: 'asc' },
  });

  res.json(comments.map((c) => ({
    id: c.id.toString(),
    author_id: c.deviceUuid.substring(0, 8),
    content: c.content,
    is_owner: device_uuid ? c.deviceUuid === device_uuid : false,
    created_at: c.createdAt,
  })));
});

// POST /api/v1/posts/:id/comments
router.post('/:id/comments', async (req: Request, res: Response) => {
  const id = BigInt(req.params.id as string);
  const { device_uuid, content } = req.body;
  if (!device_uuid || !content?.trim()) return res.status(400).json({ error: 'INVALID_REQUEST' });
  if (content.length > 500) return res.status(400).json({ error: 'CONTENT_TOO_LONG' });

  const post = await prisma.post.findUnique({ where: { id } });
  if (!post) return res.status(404).json({ error: 'NOT_FOUND' });

  const comment = await prisma.postComment.create({
    data: { postId: id, deviceUuid: device_uuid, content: content.trim() },
  });

  res.status(201).json({
    id: comment.id.toString(),
    author_id: comment.deviceUuid.substring(0, 8),
    content: comment.content,
    is_owner: true,
    created_at: comment.createdAt,
  });
});

// DELETE /api/v1/posts/:id/comments/:commentId
router.delete('/:id/comments/:commentId', async (req: Request, res: Response) => {
  const commentId = BigInt(req.params.commentId as string);
  const { device_uuid } = req.body;
  if (!device_uuid) return res.status(400).json({ error: 'INVALID_REQUEST' });

  const comment = await prisma.postComment.findUnique({ where: { id: commentId } });
  if (!comment) return res.status(404).json({ error: 'NOT_FOUND' });
  if (comment.deviceUuid !== device_uuid) return res.status(403).json({ error: 'FORBIDDEN' });

  await prisma.postComment.delete({ where: { id: commentId } });
  res.json({ ok: true });
});

export default router;
