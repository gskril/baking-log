export interface Env {
  DB: D1Database;
  PHOTOS: R2Bucket;
  API_KEY?: string;
}

export interface Bake {
  id: string;
  title: string;
  bake_date: string;
  ingredients: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export interface BakeWithDetails extends Bake {
  schedule: ScheduleEntry[];
  photos: Photo[];
}

export interface ScheduleEntry {
  id: string;
  bake_id: string;
  time: string;
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
  events: string;
  secret: string | null;
  active: number;
  created_at: string;
}

export interface CreateBakeRequest {
  title: string;
  bake_date: string;
  ingredients?: string;
  notes?: string;
  schedule?: { time: string; action: string; note?: string }[];
}

export interface UpdateBakeRequest extends Partial<CreateBakeRequest> {}
