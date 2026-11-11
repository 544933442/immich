import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { AssetResponseRaw, ImmichAsset, ImmichMemory, ImmichMemoryRaw } from '../model/ApiModels';

/** Server memories API ("on this day" cards). */
export class ImmichMemoryApi {
  /** GET /memories — all memories with their assets, newest memory first. */
  static async getMemories(): Promise<ImmichMemory[]> {
    const text: string =
      await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/memories');
    const raw: ImmichMemoryRaw[] = JSON.parse(text) as ImmichMemoryRaw[];
    const memories: ImmichMemory[] = [];
    for (const entry of raw) {
      const memory: ImmichMemory = ImmichMemoryApi.mapMemory(entry);
      if (memory.assets.length > 0) {
        memories.push(memory);
      }
    }
    return memories;
  }

  private static mapMemory(raw: ImmichMemoryRaw): ImmichMemory {
    const memory: ImmichMemory = new ImmichMemory();
    memory.id = raw.id;
    memory.type = raw.type ?? 'on_this_day';
    memory.year = raw.data?.year ?? 0;
    const currentYear: number = new Date().getFullYear();
    const yearsAgo: number = memory.year > 0 ? currentYear - memory.year : 0;
    if (yearsAgo > 0) {
      memory.title = `${yearsAgo}`;
    } else if (memory.year > 0) {
      memory.title = `${memory.year}`;
    } else {
      memory.title = raw.data?.personName ?? '';
    }
    const entries: AssetResponseRaw[] = raw.assets ?? [];
    for (const entry of entries) {
      memory.assets.push(ImmichAsset.fromResponseRaw(entry));
    }
    return memory;
  }
}
