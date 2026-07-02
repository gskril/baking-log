import { CreateBakeRequest, INGREDIENT_UNITS } from '../types';

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const OCCURS_AT_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/;

/** Returns an error message, or null if the request is valid. */
export function validateBakeRequest(body: Partial<CreateBakeRequest>, requireDate: boolean): string | null {
  if (body.bake_date === undefined) {
    if (requireDate) return 'bake_date is required (YYYY-MM-DD)';
  } else if (typeof body.bake_date !== 'string' || !DATE_PATTERN.test(body.bake_date)) {
    return 'bake_date must be YYYY-MM-DD';
  }

  for (const ing of body.ingredients ?? []) {
    if (typeof ing.name !== 'string' || !ing.name.trim()) {
      return 'ingredient name is required';
    }
    if (ing.amount_value != null && (typeof ing.amount_value !== 'number' || !Number.isFinite(ing.amount_value) || ing.amount_value < 0)) {
      return `ingredient "${ing.name}": amount_value must be a non-negative number`;
    }
    if (ing.unit != null && !INGREDIENT_UNITS.includes(ing.unit as (typeof INGREDIENT_UNITS)[number])) {
      return `ingredient "${ing.name}": unit must be one of ${INGREDIENT_UNITS.join(', ')}`;
    }
  }

  for (const entry of body.schedule ?? []) {
    if (typeof entry.action !== 'string' || !entry.action.trim()) {
      return 'schedule entry action is required';
    }
    if (typeof entry.occurs_at !== 'string' || !OCCURS_AT_PATTERN.test(entry.occurs_at)) {
      return `schedule entry "${entry.action}": occurs_at is required (YYYY-MM-DDTHH:MM[:SS])`;
    }
  }

  return null;
}
