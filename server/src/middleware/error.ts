import { Request, Response, NextFunction } from 'express';

export function errorHandler(err: Error, _req: Request, res: Response, _next: NextFunction) {
  console.error('[Error]', err.message);
  res.status(500).json({
    error: 'INTERNAL_SERVER_ERROR',
    message: '서버 오류가 발생했습니다.',
  });
}
