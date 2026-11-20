import React, { useState } from 'react';
import { Image, ScrollView, View } from 'react-native';
import { Api, Count, Event, Stat, Visit } from './api';
import { Btn, Chips, Header, Icon, ThemeMode, KINDS, KindTag, Panel, Txt, T, hhmm, kindColor, KIND_NAME, levelColor, pt, s, usePoll } from './ui';

const midnight = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() / 1000; };

/**
 * Um dia de um gato em 24 horas: cada visita é um traço na cor do tipo, na hora em que aconteceu.
 * O trecho do dia que ainda não chegou fica apagado; a linha clara marca agora.
 */
function DayStrip({ visits, dayStart }: { visits: Visit[]; dayStart: number }) {
  const [w, setW] = useState(0);
  const now = Date.now() / 1000;
  const x = (t: number) => Math.max(0, Math.min(1, (t - dayStart) / 86400)) * w;
  return (
    <View>
      <View onLayout={e => setW(e.nativeEvent.layout.width)}
        style={{ height: T.s32, borderRadius: T.r4, backgroundColor: T.haze, overflow: 'hidden' }}>
        <View style={{ position: 'absolute', left: x(now), right: 0, top: 0, bottom: 0, backgroundColor: T.night, opacity: 0.55 }} />
        {[6, 12, 18].map(h => <View key={h} style={{ position: 'absolute', left: (w * h) / 24, width: 1, top: 0, bottom: 0, backgroundColor: T.seam }} />)}
        {visits.map(v => (
          <View key={v.id} style={{ position: 'absolute', left: Math.min(w - T.s4, Math.max(0, x(v.start) - T.s2)), top: T.s4, bottom: T.s4,
            width: T.s4, borderRadius: T.r2, backgroundColor: kindColor(v.kind) }} />
        ))}
        <View style={{ position: 'absolute', left: x(now) - 1, width: T.s2, top: 0, bottom: 0, backgroundColor: T.moon, opacity: 0.8 }} />
      </View>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginTop: T.s4 }}>
        {[0, 6, 12, 18, 24].map(h => <Txt key={h} v="caption" color={T.fog} style={{ fontVariant: ['tabular-nums'] }}>{h}h</Txt>)}
      </View>
    </View>
  );
}

export default function Today({ api, onLogout, mode, onMode }: { api: Api; onLogout: () => void; mode: ThemeMode; onMode: (m: ThemeMode) => void }) {
  const [today, setToday] = useState<Count[]>([]);
  const [stats, setStats] = useState<Stat[]>([]);
  const [alerts, setAlerts] = useState<Event[]>([]);
  const [recent, setRecent] = useState<Visit[]>([]);
  const [cats, setCats] = useState<string[]>([]);
  const [err, setErr] = useState('');

  usePoll(async () => {
    try {
      setToday(await api.today()); setStats(await api.stats(7)); setRecent(await api.recent(300));
      setCats((await api.cats()).map(c => c.name)); setErr('');
      setAlerts(await api.alertsToday().catch(() => []));  // servidor antigo não tem alertas
    } catch (e: any) { setErr(e.message); }
  }, 8000, [api]);

  const day0 = midnight();
  const count: Record<string, Record<string, number>> = {};
  today.forEach(x => ((count[x.cat] ??= {})[x.kind] = x.n));
  const byCat: Record<string, Visit[]> = {};
  recent.filter(v => v.start >= day0).forEach(v => (byCat[v.cat] ??= []).push(v));
  const names = [...new Set([...Object.keys(count), ...cats])];
  const week: Record<string, Record<string, Record<string, number>>> = {};
  stats.forEach(x => (((week[x.day] ??= {})[x.cat] ??= {})[x.kind] = x.n));

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Header title="Hoje" subtitle={pt(new Date(), { weekday: 'long', day: 'numeric', month: 'long' })} />
      {err ? <Txt color={T.alert}>Sem conexão com o servidor: {err}</Txt> : null}

      {[...alerts].reverse().map(a => (
        <View key={a.id} style={{ flexDirection: 'row', gap: T.s8, alignItems: 'flex-start', padding: T.s16, paddingLeft: T.s8,
          borderRadius: T.r8, backgroundColor: T.dusk, borderWidth: 1, borderColor: T.seam }}>
          <View style={{ width: T.s4, alignSelf: 'stretch', borderRadius: T.r2, backgroundColor: levelColor(a.level), marginRight: T.s8 }} />
          <Icon name={a.level === 'error' ? 'alert' : 'alert-circle'} size={20} color={levelColor(a.level)} />
          <View style={{ flex: 1, gap: T.s2 }}>
            <Txt v="strong" style={{ fontFamily: 'Recursive_400Regular' }}>{a.message}</Txt>
            <Txt v="caption" color={T.fog}>{hhmm(a.ts)}</Txt>
          </View>
        </View>
      ))}

      {names.length === 0 && (
        <Panel title="Nenhum gato cadastrado ainda"
          subtitle="Cadastre cada gato na aba Gatos para o Catwatch saber quem é quem. Depois, desenhe as zonas da caixa, da comida e da água nas câmeras." />
      )}

      {names.map(cat => {
        const list = byCat[cat] ?? [];
        const last = list.reduce<Visit | null>((a, b) => (!a || b.start > a.start ? b : a), null);
        return (
          <Panel key={cat} style={{ gap: T.s16 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s16 }}>
              <Image source={{ uri: api.thumb(cat) }} style={{ width: 40, height: 40, borderRadius: T.r4, backgroundColor: T.haze }} />
              <View style={{ flex: 1 }}>
                <Txt v="title" numberOfLines={1}>{cat}</Txt>
                <Txt v="caption" color={T.fog}>
                  {last ? `Última visita: ${KIND_NAME[last.kind].toLowerCase()} às ${hhmm(last.start)}` : 'Nenhuma visita hoje'}
                </Txt>
              </View>
            </View>
            <View style={{ flexDirection: 'row', gap: T.s16 }}>
              {KINDS.map(k => <KindTag key={k} kind={k} count={count[cat]?.[k] ?? 0} />)}
            </View>
            <DayStrip visits={list} dayStart={day0} />
          </Panel>
        );
      })}

      {Object.keys(week).length > 0 && (
        <Panel title="Últimos 7 dias">
          <View style={{ flexDirection: 'row', gap: T.s8 }}>
            <Txt v="caption" color={T.fog} style={{ flex: 1 }}>Dia e gato</Txt>
            {KINDS.map(k => <View key={k} style={{ width: 64 }}><KindTag kind={k} /></View>)}
          </View>
          <View style={{ height: 1, backgroundColor: T.seam }} />
          {Object.entries(week).reverse().map(([d, byC]) =>
            Object.entries(byC).map(([cat, v]) => (
              <View key={d + cat} style={{ flexDirection: 'row', gap: T.s8, alignItems: 'center' }}>
                <View style={{ flex: 1 }}>
                  <Txt numberOfLines={1}>{cat}</Txt>
                  <Txt v="caption" color={T.fog}>{pt(new Date(d + 'T12:00:00'), { weekday: 'short', day: 'numeric', month: 'numeric' })}</Txt>
                </View>
                {KINDS.map(k => (
                  <Txt key={k} v="strong" color={v[k] ? kindColor(k) : T.fog} style={{ width: 64, fontVariant: ['tabular-nums'] }}>{v[k] ?? 0}</Txt>
                ))}
              </View>
            )))}
        </Panel>
      )}

      <Panel title="Aparência">
        <Chips value={mode} onChange={onMode}
          options={[{ value: 'auto', label: 'Automático' }, { value: 'light', label: 'Claro' }, { value: 'dark', label: 'Escuro' }]} />
      </Panel>
      <View style={{ gap: T.s8 }}>
        <Txt v="caption" color={T.fog}>Conectado a {api.c.url.replace(/^https?:\/\//, '')}</Txt>
        <Btn kind="ghost" icon="lan-disconnect" label="Trocar servidor" onPress={onLogout} />
      </View>
    </ScrollView>
  );
}
