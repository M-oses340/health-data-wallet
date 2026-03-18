import { Request, Response, NextFunction } from 'express';
import { verifyJWT } from './jwt';

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) { res.status(401).json({ error: 'Unauthorized' }); return; }
  try {
    (req as any).jwtPayload = verifyJWT(auth.slice(7));
    next();
  } catch (e: unknown) {
    const msg = (e instanceof Error) ? e.message : '';
    res.status(401).json({ error: msg === 'Token expired' ? 'Token expired' : 'Invalid token' });
  }
}

export function requireRole(role: string) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const payload = (req as any).jwtPayload as Record<string, unknown>;
    if (payload?.role !== role) {
      res.status(403).json({ error: `Forbidden: ${role} role required` });
      return;
    }
    next();
  };
}
