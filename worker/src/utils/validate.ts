import { z } from 'zod';
import { INGREDIENT_UNITS } from '../types';

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const OCCURS_AT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/;

const ingredientSchema = z.object({
  name: z.string().refine((s) => s.trim().length > 0, 'must not be empty'),
  amount_value: z.number().min(0, 'must be a non-negative number').nullish(),
  unit: z.enum(INGREDIENT_UNITS).nullish(),
  note: z.string().nullish(),
});

const scheduleEntrySchema = z.object({
  /** Local wall-clock ISO 8601, no timezone. */
  occurs_at: z.string().regex(OCCURS_AT_PATTERN, 'must be YYYY-MM-DDTHH:MM[:SS]'),
  action: z.string().refine((s) => s.trim().length > 0, 'must not be empty'),
  note: z.string().nullish(),
});

export const createBakeSchema = z.object({
  title: z.string().nullish(),
  bake_date: z.string().regex(DATE_PATTERN, 'must be YYYY-MM-DD'),
  notes: z.string().nullish(),
  ingredients: z.array(ingredientSchema).optional(),
  schedule: z.array(scheduleEntrySchema).optional(),
});

/**
 * Partial update: an absent key leaves the field unchanged, while title/notes
 * present with an explicit null clear the field (`.optional()` vs
 * `.nullable()`). bake_date stays non-nullable — null is rejected.
 */
export const updateBakeSchema = createBakeSchema.partial();

export const createWebhookSchema = z.object({
  // The same-host check lives in the route handler — it needs the request URL.
  url: z.string().superRefine((value, ctx) => {
    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      ctx.addIssue({ code: 'custom', message: 'must be a valid absolute URL' });
      return;
    }
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      ctx.addIssue({ code: 'custom', message: 'must use http or https' });
    }
  }),
  secret: z.string().nullish(),
});

export type CreateBakeRequest = z.infer<typeof createBakeSchema>;
export type UpdateBakeRequest = z.infer<typeof updateBakeSchema>;

/** Flattens Zod issues into one concise human-readable string. */
function formatIssues(error: z.ZodError): string {
  return error.issues
    .map((issue) => {
      const path = issue.path.map(String).join('.');
      return path ? `${path}: ${issue.message}` : issue.message;
    })
    .join('; ');
}

/**
 * Parses and validates a JSON request body. Returns `{ data }` on success, or
 * `{ error }` (malformed JSON or failed validation) for a 400 response.
 */
export async function parseBody<S extends z.ZodType>(
  req: Request,
  schema: S
): Promise<{ data: z.output<S>; error?: never } | { data?: never; error: string }> {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return { error: 'Invalid JSON body' };
  }

  const result = schema.safeParse(raw);
  if (!result.success) return { error: formatIssues(result.error) };
  return { data: result.data };
}
