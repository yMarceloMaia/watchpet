import React, { useState } from 'react';
import { Alert, FlatList, Image, Modal, Pressable, View } from 'react-native';
import { Api, Visit } from './api';
import { Btn, Chips, Header, Icon, KINDS, KIND_NAME, KIND_SHORT, Meter, Swatch, T, Txt, dec, kindColor, pt, s, usePoll } from './ui';

// Quão confiável é o nome: a similaridade média dos quadros em que o gato foi reconhecido.
const level = (x: number) => (x >= 0.85 ? 'alta' : x >= 0.75 ? 'média' : 'baixa');
const levelTone = (x: number) => (x >= 0.85 ? T.ok : x >= 0.75 ? T.warn : T.alert);

export default function History({ api }: { api: Api }) {
  const [rows, setRows] = useState<Visit[]>([]);
  const [zoom, setZoom] = useState<string | null>(null);
  const [kind, setKind] = useState<string>('');
  const [cats, setCats] = useState<string[]>([]);
  const load = async () => {
    setRows(await api.recent(200));
    setCats((await api.cats()).map(c => c.name));
  };
  usePoll(load, 10000, [api]);

  // Confirmar ou trocar o gato ensina o servidor: as fotos da visita entram no cadastro do gato.
  async function assign(v: Visit, cat: string) {
    try {
      const r = await api.fixVisit(v.id, cat);
      if (r.learned) Alert.alert(`Visita de ${cat}`, `${r.learned} fotos desta câmera entraram no cadastro de ${cat}.`);
      await load();
    } catch (e: any) { Alert.alert('Não deu certo', e.message); }
  }
  function fix(v: Visit) {
    Alert.alert('Qual gato era?', `${KIND_NAME[v.kind]}, ${pt(new Date(v.start * 1000), { hour: '2-digit', minute: '2-digit' })}`, [
      ...cats.map(c => ({ text: c, onPress: () => assign(v, c) })),
      { text: 'Cancelar', style: 'cancel' as const },
    ]);
  }
  const del = (v: Visit) =>
    Alert.alert('Apagar essa visita?', 'Ela sai das contagens do dia.', [
      { text: 'Apagar', style: 'destructive', onPress: () => api.delVisit(v.id).then(load) },
      { text: 'Cancelar', style: 'cancel' },
    ]);
  const data = rows.filter(v => !kind || v.kind === kind);

  return (
    <>
      <FlatList
        style={s.screen} contentContainerStyle={s.content} data={data} keyExtractor={v => String(v.id)}
        ListHeaderComponent={
          <View style={{ gap: T.s16 }}>
            <Header title="Histórico" subtitle="Cada visita com a foto do momento. Confirme as certas e troque as erradas: o Catwatch aprende com as fotos desta câmera." />
            <Chips value={kind} onChange={setKind}
              options={[{ value: '', label: 'Tudo' }, ...KINDS.map(k => ({ value: k, label: KIND_SHORT[k], color: kindColor(k) }))]} />
          </View>
        }
        ListEmptyComponent={<Txt color={T.fog}>{rows.length ? 'Nenhuma visita com esse filtro.' : 'Nenhuma visita ainda. Elas aparecem aqui quando um gato passa por uma zona.'}</Txt>}
        renderItem={({ item: v }) => {
          const votes = Object.entries(v.votes || {}).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(', ');
          return (
            <View style={{ backgroundColor: T.dusk, borderRadius: T.r8, borderWidth: 1, borderColor: T.seam, overflow: 'hidden' }}>
              {v.photo ? (
                <Pressable onPress={() => setZoom(api.visitPhoto(v.id))} accessibilityLabel="Ampliar a foto">
                  <Image source={{ uri: api.visitPhoto(v.id) }} style={{ width: '100%', aspectRatio: 4 / 3, backgroundColor: T.night }} resizeMode="cover" />
                </Pressable>
              ) : null}
              <View style={{ padding: T.s16, gap: T.s8 }}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8 }}>
                  <Swatch color={kindColor(v.kind)} />
                  <Txt v="label" color={kindColor(v.kind)}>{KIND_NAME[v.kind]}</Txt>
                  <Txt v="strong" style={{ flex: 1 }} numberOfLines={1}>{v.cat}</Txt>
                </View>
                <View style={{ flexDirection: 'row', gap: T.s16, flexWrap: 'wrap' }}>
                  <Txt color={T.fog} style={{ fontVariant: ['tabular-nums'] }}>
                    {pt(new Date(v.start * 1000), { weekday: 'short', day: 'numeric', month: 'numeric', hour: '2-digit', minute: '2-digit' })}
                  </Txt>
                  <Txt color={T.fog}>ficou {Math.round(v.presence ?? v.end - v.start)} s</Txt>
                  <Txt color={T.fog}>{v.camera}, {v.zone}</Txt>
                </View>
                {v.frames > 0 ? (
                  <>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8 }}>
                      <Txt v="caption" color={T.fog}>Certeza</Txt>
                      <Meter value={v.score ?? 0} color={levelTone(v.score ?? 0)} width={T.s64} />
                      <Txt v="caption" style={{ fontVariant: ['tabular-nums'] }}>{v.score == null ? 'sem dado' : `${dec(v.score)} (${level(v.score)})`}</Txt>
                    </View>
                    <Txt v="caption" color={T.fog}>{v.frames} quadros analisados. Votos: {votes || 'nenhum'}</Txt>
                  </>
                ) : (
                  <Txt v="caption" color={T.fog}>Visita registrada antes das fotos: sem certeza nem votos.</Txt>
                )}
                <View style={[s.row, { marginTop: T.s8 }]}>
                  {cats.includes(v.cat) && <Btn kind="ghost" icon="check" label="Está certo" onPress={() => assign(v, v.cat)} />}
                  <Btn kind="ghost" icon="swap-horizontal" label="Trocar gato" onPress={() => fix(v)} disabled={!cats.length} />
                  <Btn kind="danger" icon="delete-outline" label="Apagar" onPress={() => del(v)} />
                </View>
              </View>
            </View>
          );
        }}
      />
      <Modal visible={!!zoom} transparent animationType="fade" onRequestClose={() => setZoom(null)}>
        <Pressable style={{ flex: 1, backgroundColor: T.scrim, justifyContent: 'center', gap: T.s16 }} onPress={() => setZoom(null)}>
          {zoom && <Image source={{ uri: zoom }} style={{ width: '100%', height: '80%' }} resizeMode="contain" />}
          <View style={{ flexDirection: 'row', justifyContent: 'center', gap: T.s8, alignItems: 'center' }}>
            <Icon name="close" color={T.fog} />
            <Txt color={T.fog}>Toque para fechar</Txt>
          </View>
        </Pressable>
      </Modal>
    </>
  );
}
