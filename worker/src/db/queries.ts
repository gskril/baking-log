import { Bake, BakeWithDetails, Ingredient, Photo, ScheduleEntry } from '../types';

export function withPhotoURL(photo: Photo): Photo {
  return { ...photo, url: `/api/photos/${photo.id}/image` };
}

export async function getBakeWithDetails(db: D1Database, id: string): Promise<BakeWithDetails | null> {
  // One D1 round trip instead of four — batch statements execute together
  const [bakeRes, scheduleRes, ingredientsRes, photosRes] = await db.batch([
    db.prepare('SELECT id, title, bake_date, notes, created_at, updated_at FROM bakes WHERE id = ?').bind(id),
    db.prepare('SELECT * FROM schedule_entries WHERE bake_id = ? ORDER BY occurs_at ASC, sort_order ASC').bind(id),
    db.prepare('SELECT * FROM ingredients WHERE bake_id = ? ORDER BY sort_order ASC').bind(id),
    db.prepare('SELECT * FROM photos WHERE bake_id = ? ORDER BY created_at ASC').bind(id),
  ]);

  const bake = bakeRes.results?.[0] as Bake | undefined;
  if (!bake) return null;

  return {
    ...bake,
    ingredients: (ingredientsRes.results ?? []) as Ingredient[],
    schedule: (scheduleRes.results ?? []) as ScheduleEntry[],
    photos: ((photosRes.results ?? []) as Photo[]).map(withPhotoURL),
  };
}
