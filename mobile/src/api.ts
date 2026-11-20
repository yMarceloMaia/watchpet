import AsyncStorage from '@react-native-async-storage/async-storage';

export type Zone = { name: string; kind: 'litter' | 'food' | 'water'; polygon: number[][] };
export type Cam = { name: string; source: string; zones: Zone[]; online: boolean };
export type Visit = {
  id: number; cat: string; kind: string; zone: string; camera: string; start: number; end: number;
  score: number | null; conf: number | null; frames: number; votes: Record<string, number>; photo: boolean;
  presence?: number | null;  // segundos em que o gato foi visto de fato
};
export type Count = { cat: string; kind: string; n: number; seconds: number };
export type Event = { id: number; ts: number; type: string; level: string; message: string; cat: string | null; camera: string | null };
export type Stat = { day: string; cat: string; kind: string; n: number };


export type Conn = { url: string; token: string };
const KEY = 'catwatch.conn';

export const loadConn = async (): Promise<Conn | null> => {
  try { const s = await AsyncStorage.getItem(KEY); return s ? JSON.parse(s) : null; } catch { return null; }
};
export const saveConn = (c: Conn | null) =>
  c ? AsyncStorage.setItem(KEY, JSON.stringify(c)) : AsyncStorage.removeItem(KEY);

export const normalizeUrl = (u: string) => {
  u = u.trim().replace(/\/+$/, '');
  return /^https?:\/\//.test(u) ? u : `http://${u}`;
};

export class Api {
  /** onUnauthorized: o token deixou de valer (foi trocado no PC); o app volta para a tela de conexão. */
  constructor(public c: Conn, private onUnauthorized?: () => void) {}
  url = (path: string) => `${this.c.url}${path}${path.includes('?') ? '&' : '?'}token=${encodeURIComponent(this.c.token)}`;

  async req<T>(path: string, init: RequestInit = {}): Promise<T> {
    const r = await fetch(this.c.url + path, { ...init, headers: { 'X-Token': this.c.token, ...(init.headers || {}) } });
    if (r.status === 401 && this.onUnauthorized) this.onUnauthorized();
    if (!r.ok) {
      let d = ''; try { d = (await r.json()).detail; } catch {}
      throw new Error(d || `Erro ${r.status}`);
    }
    return r.json();
  }
  json = (method: string, body: unknown) =>
    ({ method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

  alertsToday = () => {
    const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
    return this.req<Event[]>(`/api/events?type=alert&since=${Math.floor(midnight.getTime() / 1000)}`);
  };
  check = () => this.req<{ ok: boolean }>('/api/check');
  today = () => this.req<Count[]>('/api/today');
  stats = (days = 7) => this.req<Stat[]>(`/api/stats?days=${days}`);
  recent = (limit = 100) => this.req<Visit[]>(`/api/recent?limit=${limit}`);
  visitPhoto = (id: number) => this.url(`/api/visits/${id}/photo`);
  fixVisit = (id: number, cat: string) => this.req(`/api/visits/${id}`, this.json('PATCH', { cat }));
  delVisit = (id: number) => this.req(`/api/visits/${id}`, { method: 'DELETE' });

  cameras = () => this.req<Cam[]>('/api/cameras');
  addCamera = (name: string, source: string) => this.req('/api/cameras', this.json('POST', { name, source }));
  delCamera = (n: string) => this.req(`/api/cameras/${encodeURIComponent(n)}`, { method: 'DELETE' });
  setZones = (n: string, z: Zone[]) => this.req(`/api/cameras/${encodeURIComponent(n)}/zones`, this.json('PUT', z));
  snapshot = (n: string, raw = false) => this.url(`/snapshot/${encodeURIComponent(n)}.jpg?raw=${raw}&t=${Date.now()}`);
  push = (n: string, base64: string) =>
    this.req(`/api/push/${encodeURIComponent(n)}`, { method: 'POST', body: base64, headers: { 'Content-Type': 'text/plain' } });

  cats = () => this.req<{ name: string; photos: number }[]>('/api/cats');
  thumb = (n: string, bust = 0) => this.url(`/api/cats/${encodeURIComponent(n)}/thumb?b=${bust}`);
  delCat = (n: string) => this.req(`/api/cats/${encodeURIComponent(n)}`, { method: 'DELETE' });
  catFromCamera = (n: string, cam: string) =>
    this.req(`/api/cats/${encodeURIComponent(n)}/from-camera/${encodeURIComponent(cam)}`, { method: 'POST' });
  async addPhoto(n: string, uri: string) {
    const fd = new FormData();
    fd.append('photo', { uri, name: 'photo.jpg', type: 'image/jpeg' } as any);
    return this.req(`/api/cats/${encodeURIComponent(n)}/photos`, { method: 'POST', body: fd });
  }
}

/** Lê o QR code do app de PC: catwatch://pair?u=<endereço>&t=<token>. */
export function parsePairCode(data: string): Conn | null {
  const m = /^catwatch:\/\/pair\?(.*)$/.exec(data.trim());
  if (!m) return null;
  const params: Record<string, string> = {};
  for (const part of m[1].split('&')) {
    const [k, v = ''] = part.split('=');
    params[k] = decodeURIComponent(v);
  }
  return params.u && params.t ? { url: normalizeUrl(params.u), token: params.t } : null;
}
