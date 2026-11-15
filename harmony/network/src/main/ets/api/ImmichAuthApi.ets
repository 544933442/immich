import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { ImmichApiConfig } from '../ImmichApiConfig';
import {
  ImmichLoginResponseRaw,
  ImmichPingRaw,
  ImmichUserRaw,
  ImmichValidateTokenRaw
} from '../model/ApiModels';

/** Login request body of POST /auth/login. */
export interface LoginCredentials {
  email: string;
  password: string;
}

/** User profile subset used across the app. */
export class ImmichUser {
  id: string = '';
  name: string = '';
  email: string = '';
  profileImagePath: string = '';
}

/** Authentication and account APIs. */
export class ImmichAuthApi {
  /** Ping a server (no auth needed). Returns "pong" on success. */
  static async ping(serverUrl: string): Promise<string> {
    const saved: string = ImmichApiConfig.getServer();
    const savedToken: string = ImmichApiConfig.getToken();
    ImmichApiConfig.setServer(serverUrl);
    ImmichApiConfig.setToken('');
    try {
      const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/server/ping');
      const raw: ImmichPingRaw = JSON.parse(text) as ImmichPingRaw;
      return raw.res;
    } finally {
      ImmichApiConfig.setServer(saved);
      ImmichApiConfig.setToken(savedToken);
    }
  }

  /** Login with email + password; returns the access token response. */
  static async login(serverUrl: string, email: string, password: string): Promise<ImmichLoginResponseRaw> {
    const saved: string = ImmichApiConfig.getServer();
    const savedToken: string = ImmichApiConfig.getToken();
    ImmichApiConfig.setServer(serverUrl);
    ImmichApiConfig.setToken('');
    try {
      const body: LoginCredentials = { email: email, password: password };
      const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.POST, '/auth/login', body);
      return JSON.parse(text) as ImmichLoginResponseRaw;
    } finally {
      ImmichApiConfig.setServer(saved);
      ImmichApiConfig.setToken(savedToken);
    }
  }

  /** Validate the current access token. */
  static async validateToken(): Promise<boolean> {
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.POST, '/auth/validateToken');
    const raw: ImmichValidateTokenRaw = JSON.parse(text) as ImmichValidateTokenRaw;
    return raw.authStatus;
  }

  /** Fetch the current user profile. */
  static async getMyUser(): Promise<ImmichUser> {
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/users/me');
    const raw: ImmichUserRaw = JSON.parse(text) as ImmichUserRaw;
    const user: ImmichUser = new ImmichUser();
    user.id = raw.id;
    user.name = raw.name;
    user.email = raw.email;
    user.profileImagePath = raw.profileImagePath;
    return user;
  }
}
