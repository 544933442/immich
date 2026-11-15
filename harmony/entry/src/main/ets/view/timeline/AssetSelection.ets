/**
 * Reactive multi-selection state shared by the asset picker and the
 * timeline selection mode.
 */
@ObservedV2
export class AssetSelection {
  @Trace ids: string[] = [];

  isSelected(id: string): boolean {
    return this.ids.indexOf(id) >= 0;
  }

  toggle(id: string): void {
    const pos: number = this.ids.indexOf(id);
    if (pos >= 0) {
      this.ids.splice(pos, 1);
    } else {
      this.ids.push(id);
    }
  }

  clear(): void {
    this.ids = [];
  }

  count(): number {
    return this.ids.length;
  }

  selectedIds(): string[] {
    return this.ids.slice();
  }
}
