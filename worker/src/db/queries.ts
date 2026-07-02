import { Bake, BakeWithDetails, Ingredient, Photo, ScheduleEntry } from '../types';

export async function getBakeWithDetails(db: D1Database, id: string): Promise<BakeWithDetails | null> {
  const bake = await db
    .prepare('SELECT id, title, bake_date, notes, created_at, updated_at FROM bakes WHERE id = ?')
    .bind(id)
    .first<Bake>();

  if (!bake) return null;

  const [schedule, ingredients, photos] = await Promise.all([
    db
      .prepare('SELECT * FROM schedule_entries WHERE bake_id = ? ORDER BY occurs_at ASC, sort_order ASC')
      .bind(id)
      .all<ScheduleEntry>(),
    db
      .prepare('SELECT * FROM ingredients WHERE bake_id = ? ORDER BY sort_order ASC')
      .bind(id)
      .all<Ingredient>(),
    db
      .prepare('SELECT * FROM photos WHERE bake_id = ? ORDER BY created_at ASC')
      .bind(id)
      .all<Photo>(),
  ]);

  return {
    ...bake,
    ingredients: ingredients.results ?? [],
    schedule: schedule.results ?? [],
    photos: (photos.results ?? []).map((p) => ({
      ...p,
      url: `/api/photos/${p.id}/image`,
    })),
  };
}
