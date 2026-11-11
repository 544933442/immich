import { Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Continuous "dataTransfer" background task so uploads survive screen-off
 * while the app is foreground-started.
 */
export class ImmichBackgroundTask {
  private static running: boolean = false;

  static isRunning(): boolean {
    return ImmichBackgroundTask.running;
  }

  static async start(context: Context, bundleName: string, abilityName: string): Promise<void> {
    if (ImmichBackgroundTask.running) {
      return;
    }
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName
    };
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    const agent: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
    await backgroundTaskManager.startBackgroundRunning(context,
      backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
    ImmichBackgroundTask.running = true;
  }

  static async stop(context: Context): Promise<void> {
    if (!ImmichBackgroundTask.running) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      throw new Error(`stop background task failed: ${error.message}`);
    } finally {
      ImmichBackgroundTask.running = false;
    }
  }
}
