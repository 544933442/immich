/**
 * Date and time helpers for timeline grouping and display.
 * Mirrors the grouping behaviour of the Immich mobile app:
 * monthly time buckets with sub-sections of up to 3 calendar days.
 */
export class ImmichDateUtils {
  private static readonly MONTH_NAMES_EN: string[] =
    ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November',
      'December'];

  /** '2024-06' -> 'June 2024' or '2024年6月' */
  static formatBucketTitle(timeBucket: string, chinese: boolean): string {
    const parts: string[] = timeBucket.split('-');
    if (parts.length < 2) {
      return timeBucket;
    }
    const year: number = Number(parts[0]);
    const month: number = Number(parts[1]);
    if (chinese) {
      return `${year}年${month}月`;
    }
    const monthName: string = ImmichDateUtils.MONTH_NAMES_EN[month - 1] ?? String(month);
    return `${monthName} ${year}`;
  }

  /** ISO date string -> 'Jul 12 - 15' style day-group title (range across the days present). */
  static formatDayGroupTitle(days: number[], chinese: boolean): string {
    if (days.length === 0) {
      return '';
    }
    const sorted: number[] = days.slice().sort((a: number, b: number): number => a - b);
    const first: number = sorted[0];
    const last: number = sorted[sorted.length - 1];
    const date: Date = new Date(first);
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    if (last - first <= 24 * 3600 * 1000) {
      return chinese ? `${month}月${day}日` : ImmichDateUtils.monthDayEn(date);
    }
    const lastDate: Date = new Date(last);
    const lastDay: number = lastDate.getDate();
    if (chinese) {
      return `${month}月${day}日 - ${lastDay}日`;
    }
    return `${ImmichDateUtils.monthDayEn(date)} - ${lastDate.getDate()}`;
  }

  private static monthDayEn(date: Date): string {
    const shortMonths: string[] =
      ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return `${shortMonths[date.getMonth()]} ${date.getDate()}`;
  }

  /** Group index (0-9) for the 3-day section within a month. */
  static dayGroupIndex(isoOrMs: string | number): number {
    const date: Date = typeof isoOrMs === 'string' ? new Date(isoOrMs) : new Date(isoOrMs);
    const day: number = date.getDate();
    return Math.floor((day - 1) / 3);
  }

  /** Milliseconds -> ISO 8601 UTC string, e.g. 2024-06-01T12:00:00.000Z */
  static msToIso(ms: number): string {
    return new Date(ms).toISOString();
  }

  /** Format duration milliseconds as m:ss / h:mm:ss */
  static formatDurationMs(ms: number): string {
    const totalSeconds: number = Math.floor(ms / 1000);
    const seconds: number = totalSeconds % 60;
    const minutes: number = Math.floor(totalSeconds / 60) % 60;
    const hours: number = Math.floor(totalSeconds / 3600);
    const two: string = seconds < 10 ? `0${seconds}` : `${seconds}`;
    if (hours > 0) {
      const twoMin: string = minutes < 10 ? `0${minutes}` : `${minutes}`;
      return `${hours}:${twoMin}:${two}`;
    }
    return `${minutes}:${two}`;
  }

  /** '2024-06-01T12:00:00.000Z' -> localized date string for detail panels. */
  static formatFullDate(iso: string, chinese: boolean): string {
    const date: Date = new Date(iso);
    if (chinese) {
      return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
    }
    return `${ImmichDateUtils.monthDayEn(date)}, ${date.getFullYear()}`;
  }
}
