import { describe, expect, it, vi } from 'vitest';
import { lookup } from 'node:dns/promises';
import type { LookupAddress } from 'node:dns';
import { isBlockedHostname, validateBaseUrl } from 'src/ai-dedup/openai-compatible.provider.js';

// QA 补充：SSRF 绕过边界。DNS 默认 mock 为不可用，全部用例无外网依赖、可重复；
// 需要 DNS 行为的用例用 mockResolvedValueOnce 覆盖。
vi.mock('node:dns/promises', () => ({ lookup: vi.fn().mockRejectedValue(new Error('offline')) }));

// vi.mocked() resolves to the single-address overload of `lookup`; cast to the
// all-addresses shape actually used by validateBaseUrl.
const mockLookup = vi.mocked(lookup) as unknown as {
  mockResolvedValueOnce: (value: LookupAddress[]) => unknown;
};

const expectReject = async (url: string, reason: string, allowedHosts: readonly string[] = []) => {
  await expect(validateBaseUrl(url, allowedHosts), url).resolves.toMatchObject({ ok: false, reason });
};

describe('SSRF 绕过边界：userinfo / IP 编码 / 协议', () => {
  it('userinfo 与 @ 混淆不能把私网地址伪装成公网主机名', async () => {
    await expectReject('https://user:pass@127.0.0.1/v1', 'BLOCKED_HOST');
    await expectReject('https://api.example.com@127.0.0.1/v1', 'BLOCKED_HOST');
  });

  it('十进制 / 十六进制 / IPv6 / IPv4-mapped IP 字面量经 URL 规范化后全部拦截', async () => {
    await expectReject('https://2130706433/v1', 'BLOCKED_HOST');
    await expectReject('https://0x7f000001/v1', 'BLOCKED_HOST');
    await expectReject('https://[::1]/v1', 'BLOCKED_HOST');
    await expectReject('https://[::ffff:127.0.0.1]/v1', 'BLOCKED_HOST');
    await expectReject('https://10.0.0.1/v1', 'BLOCKED_HOST');
  });

  it('尾点、端口、大写本地名、local/internal 后缀均不能绕过', async () => {
    await expectReject('https://localhost./v1', 'BLOCKED_HOST');
    await expectReject('https://127.0.0.1:8080/v1', 'BLOCKED_HOST');
    await expectReject('https://METADATA.GOOGLE.INTERNAL/v1', 'BLOCKED_HOST');
    await expectReject('https://printer.local/v1', 'BLOCKED_HOST');
  });

  it('非 https 协议（ftp / file / 未放行 http）一律 INSECURE_PROTOCOL', async () => {
    await expectReject('ftp://api.example.com/v1', 'INSECURE_PROTOCOL');
    await expectReject('file:///etc/passwd', 'INSECURE_PROTOCOL');
    await expectReject('http://localhost/v1', 'INSECURE_PROTOCOL');
  });

  it('畸形 URL 被拒，空主机名在同步层被拒', async () => {
    await expectReject('not a url', 'INVALID_URL');
    expect(isBlockedHostname('')).toBe(true);
  });

  it('未放行主机在 DNS 之前即返回 HOST_NOT_ALLOWED', async () => {
    await expectReject('https://api.example.com/v1', 'HOST_NOT_ALLOWED', ['other.example.com']);
  });
});

describe('SSRF allowlist 归一化（Q17 自建服务）', () => {
  it('大小写与通配符在 isBlockedHostname 中归一化', () => {
    expect(isBlockedHostname('API.EXAMPLE.COM', ['*.EXAMPLE.COM'])).toBe(false);
    expect(isBlockedHostname('api.other.com', ['*.example.com'])).toBe(false);
    expect(isBlockedHostname('api.other.com', ['api.example.com'])).toBe(false);
  });

  it('显式放行的 IP 字面量允许 http 自建端点，且跳过 DNS', async () => {
    await expect(validateBaseUrl('http://127.0.0.1/v1', ['127.0.0.1'])).resolves.toEqual({ ok: true });
    await expect(validateBaseUrl('https://127.0.0.1/v1', ['127.0.0.1'])).resolves.toEqual({ ok: true });
  });

  it('已登记的 https 公网主机名解析到公网地址后放行', async () => {
    mockLookup.mockResolvedValueOnce([{ address: '93.184.216.34', family: 4 as const }]);
    await expect(validateBaseUrl('https://api.example.com/v1', ['api.example.com'])).resolves.toEqual({ ok: true });
  });

  it('allowlist 命中的域名解析到私网地址仍被拒绝（DNS rebinding）', async () => {
    mockLookup.mockResolvedValueOnce([{ address: '192.168.0.10', family: 4 as const }]);
    await expectReject('https://api.example.com/v1', 'PRIVATE_DNS_RESULT', ['api.example.com']);
  });
  it('DNS 解析失败按拒绝处理，而不是放行', async () => {
    await expectReject('https://api.example.com/v1', 'DNS_LOOKUP_FAILED', ['api.example.com']);
  });
});
