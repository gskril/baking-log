// Canonical format matches the iOS picker output: "h:mm a" (e.g. "1:05 PM").
const TWENTY_FOUR_HOUR = /^(\d{1,2}):(\d{2})$/;
const TWELVE_HOUR_WITH_MINUTES = /^(\d{1,2}):(\d{2})\s*([ap])\.?m\.?$/i;
const TWELVE_HOUR_HOUR_ONLY = /^(\d{1,2})\s*([ap])\.?m\.?$/i;

function format(hour12: number, minute: number, meridiem: 'AM' | 'PM'): string {
  return `${hour12}:${minute.toString().padStart(2, '0')} ${meridiem}`;
}

export function normalizeScheduleTime(time: string): string {
  const trimmed = time.trim();
  if (!trimmed) return trimmed;

  const twelveWithMinutes = trimmed.match(TWELVE_HOUR_WITH_MINUTES);
  if (twelveWithMinutes) {
    const hour = Number(twelveWithMinutes[1]);
    const minute = Number(twelveWithMinutes[2]);
    if (hour >= 1 && hour <= 12 && minute >= 0 && minute <= 59) {
      const meridiem = twelveWithMinutes[3].toUpperCase() === 'A' ? 'AM' : 'PM';
      return format(hour, minute, meridiem);
    }
  }

  const twelveHourOnly = trimmed.match(TWELVE_HOUR_HOUR_ONLY);
  if (twelveHourOnly) {
    const hour = Number(twelveHourOnly[1]);
    if (hour >= 1 && hour <= 12) {
      const meridiem = twelveHourOnly[2].toUpperCase() === 'A' ? 'AM' : 'PM';
      return format(hour, 0, meridiem);
    }
  }

  const twentyFour = trimmed.match(TWENTY_FOUR_HOUR);
  if (twentyFour) {
    const hour24 = Number(twentyFour[1]);
    const minute = Number(twentyFour[2]);
    if (hour24 >= 0 && hour24 <= 23 && minute >= 0 && minute <= 59) {
      const meridiem = hour24 < 12 ? 'AM' : 'PM';
      const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
      return format(hour12, minute, meridiem);
    }
  }

  return trimmed;
}
