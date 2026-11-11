/**
 * Global auth state shared across pages, observed by V2 components.
 */
@ObservedV2
export class AuthStateHolder {
  @Trace loggedIn: boolean = false;
  @Trace userName: string = '';
  @Trace userEmail: string = '';
  @Trace serverUrl: string = '';
}

/** Process-wide auth state singleton. */
export const authState: AuthStateHolder = new AuthStateHolder();
