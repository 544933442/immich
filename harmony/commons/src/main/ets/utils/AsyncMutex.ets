/**
 * Simple promise-based mutex, used to serialize database and upload operations.
 */
export class AsyncMutex {
  private chain: Promise<void> = Promise.resolve();

  run<T>(task: () => Promise<T>): Promise<T> {
    const result: Promise<T> = this.chain.then(task);
    this.chain = result.then((): void => {
    }, (): void => {
    });
    return result;
  }
}
