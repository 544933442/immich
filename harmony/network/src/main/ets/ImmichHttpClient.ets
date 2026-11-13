import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ImmichApiConfig } from './ImmichApiConfig';
import { ImmichApiError } from './model/ApiModels';

/**
 * Thin wrapper over @ohos.net.http providing JSON, binary and multipart
 * requests with automatic auth header injection and error normalization.
 */
export class ImmichHttpClient {
  /** Perform a JSON request and return the raw response body text. */
  static async requestJsonText(method: http.RequestMethod, path: string, body?: object): Promise<string> {
    const headers: Record<string, string> = ImmichApiConfig.authHeaders();
    if (body !== undefined) {
      headers['Content-Type'] = 'application/json';
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 60000
    };
    if (body !== undefined) {
      options.extraData = JSON.stringify(body);
    }
    return ImmichHttpClient.execute(ImmichApiConfig.url(path), options);
  }

  /** Download binary content (images / videos). */
  static async requestBinary(method: http.RequestMethod, path: string): Promise<ArrayBuffer> {
    const options: http.HttpRequestOptions = {
      method: method,
      header: ImmichApiConfig.authHeaders(),
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 15000,
      readTimeout: 120000
    };
    const url: string = ImmichApiConfig.url(path);
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, options);
      if (response.responseCode >= 400) {
        throw new ImmichApiError(`HTTP ${response.responseCode} for ${path}`, response.responseCode);
      }
      const result: ArrayBuffer = response.result as ArrayBuffer;
      return result;
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * Multipart upload of a single file with extra form fields.
   */
  static async uploadMultipart(path: string, fields: Record<string, string>, fileFieldName: string,
    fileName: string, filePath: string, contentType: string,
    onProgress?: (sent: number, total: number) => void): Promise<string> {
    const url: string = ImmichApiConfig.url(path);
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      if (onProgress !== undefined) {
        httpRequest.on('dataSendProgress', (info: http.DataSendProgressInfo) => {
          onProgress(info.sendSize, info.totalSize);
        });
      }
      const formDataList: Array<http.MultiFormData> = [];
      const keys: string[] = Object.keys(fields);
      for (const key of keys) {
        formDataList.push({
          name: key,
          contentType: 'text/plain',
          data: fields[key]
        });
      }
      formDataList.push({
        name: fileFieldName,
        contentType: contentType,
        remoteFileName: fileName,
        filePath: filePath
      });
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        // netstack only honours multiFormDataList when the request declares a
        // multipart content-type; without it the body is silently dropped.
        header: ImmichApiConfig.authHeaders({
          'Accept': 'application/json',
          'Content-Type': 'multipart/form-data'
        }),
        expectDataType: http.HttpDataType.STRING,
        multiFormDataList: formDataList,
        connectTimeout: 15000,
        readTimeout: 300000
      };
      const response: http.HttpResponse = await httpRequest.request(url, options);
      if (response.responseCode >= 400) {
        const text: string = response.result as string;
        hilog.error(0x0001, 'ImmichHttp',
          'upload HTTP %{public}d body: %{public}s', response.responseCode,
          text.slice(0, 1000));
        throw new ImmichApiError(`HTTP ${response.responseCode}: ${text.slice(0, 200)}`, response.responseCode);
      }
      return response.result as string;
    } finally {
      httpRequest.destroy();
    }
  }

  private static async execute(url: string, options: http.HttpRequestOptions): Promise<string> {
    const httpRequest: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await httpRequest.request(url, options);
      if (response.responseCode >= 400) {
        let detail: string = '';
        if (typeof response.result === 'string') {
          detail = response.result.slice(0, 200);
        }
        throw new ImmichApiError(`HTTP ${response.responseCode}: ${detail}`, response.responseCode);
      }
      return response.result as string;
    } catch (err) {
      if (err instanceof ImmichApiError) {
        throw err;
      }
      const error: BusinessError = err as BusinessError;
      throw new ImmichApiError(`network error: ${error.message}`, -1);
    } finally {
      httpRequest.destroy();
    }
  }
}
