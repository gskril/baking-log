export interface Env {
  DB: D1Database;
  PHOTOS: R2Bucket;
  API_KEY?: string;
}

export const INGREDIENT_UNITS = ['g', 'tsp', 'tbsp', 'cup'] as const;
export type IngredientUnit = (typeof INGREDIENT_UNITS)[number];

export interface Bake {
  id: string;
  title: string | null;
  bake_date: string;

  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface BakeListItem extends Bake {
  ingredient_count: number;
}

export interface Ingredient {
  id: string;
  bake_id: string;
  name: string;
  amount_value: number | null;
  unit: IngredientUnit | null;
  note: string | null;
  sort_order: number;
  created_at: string;
}

export interface BakeWithDetails extends Bake {
  ingredients: Ingredient[];
  schedule: ScheduleEntry[];
  photos: Photo[];
}

export interface ScheduleEntry {
  id: string;
  bake_id: string;
  /** Local wall-clock ISO 8601 ("YYYY-MM-DDTHH:MM:SS"), no timezone. */
  occurs_at: string | null;
  action: string;
  note: string | null;
  sort_order: number;
  created_at: string;
}

export interface Photo {
  id: string;
  bake_id: string;
  r2_key: string;
  url?: string;
  caption: string | null;
  created_at: string;
}

export interface Webhook {
  id: string;
  url: string;
  secret: string | null;
  active: number;
  created_at: string;
}

export interface CreateBakeRequest {
  title?: string;
  bake_date: string;
  ingredients?: { name: string; amount_value?: number | null; unit?: string | null; note?: string }[];
  notes?: string;
  schedule?: { occurs_at?: string | null; action: string; note?: string }[];
}

export interface UpdateBakeRequest extends Partial<CreateBakeRequest> {}
