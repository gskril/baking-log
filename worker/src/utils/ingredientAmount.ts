import { Ingredient } from '../types';

const AMOUNT_WITH_UNIT_PATTERN = /^(\d+(?:\.\d+)?)(?:\s*)([a-zA-Z]+)$/;

export const MEASUREMENT_ABBREVIATION_MAP: Record<string, string> = {
  g: 'grams',
  gram: 'grams',
  grams: 'grams',
  kg: 'kilograms',
  tsp: 'teaspoons',
  tbsp: 'tablespoons',
  oz: 'ounces',
  lb: 'pounds',
  lbs: 'pounds',
  ml: 'milliliters',
  l: 'liters',
};

export function normalizeIngredientAmount(amount: string): string {
  const trimmedAmount = amount.trim();
  const match = trimmedAmount.match(AMOUNT_WITH_UNIT_PATTERN);
  if (!match) return trimmedAmount;

  const [, value, unit] = match;
  const normalizedUnit = unit.toLowerCase();
  const expandedUnit = MEASUREMENT_ABBREVIATION_MAP[normalizedUnit] ?? unit;

  return `${value} ${expandedUnit}`;
}

export function normalizeIngredientRows(ingredients: Ingredient[]): Ingredient[] {
  return ingredients.map((ingredient) => ({
    ...ingredient,
    amount: normalizeIngredientAmount(ingredient.amount),
  }));
}
