import { ImmichAsset, ImmichMemory } from 'network';

/** One renderable row of the timeline: month header, photo row or memories lane. */
export class TimelineRow {
  isHeader: boolean = false;
  /** Marks the horizontal memories lane rendered above the timeline. */
  isMemories: boolean = false;
  /** Memories shown when isMemories is true. */
  memories: ImmichMemory[] = [];
  title: string = '';
  /** Exactly three slots; null slots render as blank cells. */
  cells: Array<ImmichAsset | null> = [];
  /** Time bucket this row belongs to (empty for headers). */
  bucket: string = '';
  /** Index of the first cell inside its bucket (for viewer params). */
  startIndex: number = 0;
}

/**
 * LazyForEach data source over the flat timeline row list.
 */
export class TimelineDataSource implements IDataSource {
  private rows: TimelineRow[] = [];
  private listeners: DataChangeListener[] = [];

  /** Replace all content (reload). */
  clear(): void {
    this.rows = [];
    this.notifyAll();
  }

  /** Append rows at the end. */
  pushRows(rows: TimelineRow[]): void {
    if (rows.length === 0) {
      return;
    }
    const start: number = this.rows.length;
    this.rows = this.rows.concat(rows);
    for (const listener of this.listeners) {
      listener.onDataAdd(start);
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): TimelineRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** Build the memories lane row (single horizontal scroller). */
  static buildMemoriesRow(memories: ImmichMemory[]): TimelineRow[] {
    const row: TimelineRow = new TimelineRow();
    row.isMemories = true;
    row.memories = memories;
    row.bucket = '__memories__';
    return [row];
  }

  /** Build header + 3-per-row chunks for one bucket's assets. */
  static buildRows(bucket: string, title: string, assets: ImmichAsset[]): TimelineRow[] {
    const rows: TimelineRow[] = [];
    const header: TimelineRow = new TimelineRow();
    header.isHeader = true;
    header.title = title;
    header.bucket = bucket;
    rows.push(header);
    for (let i = 0; i < assets.length; i += 3) {
      const row: TimelineRow = new TimelineRow();
      row.isHeader = false;
      row.bucket = bucket;
      row.startIndex = i;
      for (let k = 0; k < 3; k++) {
        row.cells.push(i + k < assets.length ? assets[i + k] : null);
      }
      rows.push(row);
    }
    return rows;
  }

  private notifyAll(): void {
    for (const listener of this.listeners) {
      listener.onDataReloaded();
    }
  }
}
