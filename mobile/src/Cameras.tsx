import React, { useEffect, useRef, useState } from 'react';
import { Alert, Image, ScrollView, TextInput, View } from 'react-native';
import { Api, Cam } from './api';
import { Btn, Dot, Header, Icon, IconBtn, Panel, Swatch, T, Txt, kindColor, s, usePoll } from './ui';
import ZoneEditor from './ZoneEditor';

const FILL = { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 } as const;

/**
 * Imagem ao vivo, quadro a quadro (o React Native não mostra MJPEG de forma confiável).
 *
 * O próximo quadro só é pedido depois que o anterior chegou. Com um relógio fixo, quando o
 * quadro demorava mais que o intervalo (Wi-Fi fraco, servidor ocupado, imagem noturna mais
 * pesada), cada pedido cancelava o anterior e a imagem sumia. Duas imagens se revezam: o
 * quadro novo carrega na escondida, que só aparece quando está pronta, sem piscar.
 */
function Live({ api, cam }: { api: Api; cam: Cam }) {
  const [uris, setUris] = useState<[string | null, string | null]>([null, null]);
  const [front, setFront] = useState<0 | 1 | null>(null);  // qual das duas está à mostra
  const loading = useRef<0 | 1>(0);                          // qual está carregando o próximo quadro
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const request = (slot: 0 | 1) => {
    loading.current = slot;
    const uri = api.snapshot(cam.name);
    setUris(u => (slot === 0 ? [uri, u[1]] : [u[0], uri]));
  };
  useEffect(() => {
    setFront(null);
    setUris([null, null]);
    if (cam.online) request(0);
    return () => clearTimeout(timer.current);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [api, cam.name, cam.online]);

  const done = (slot: 0 | 1, ok: boolean) => {
    if (slot !== loading.current) return;
    clearTimeout(timer.current);
    if (ok) {
      setFront(slot);
      timer.current = setTimeout(() => request(slot === 0 ? 1 : 0), 300);
    } else {
      // Servidor fora ou câmera sem quadro: tenta de novo com mais calma.
      timer.current = setTimeout(() => request(slot), 2000);
    }
  };
  // Pedido que nunca responde: desiste dele e pede outro.
  const pending = uris[loading.current];
  useEffect(() => {
    if (!pending) return;
    const id = setTimeout(() => request(loading.current), 15000);
    return () => clearTimeout(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pending]);

  return (
    <View style={{ aspectRatio: 16 / 9, borderRadius: T.r4, backgroundColor: T.night, overflow: 'hidden', alignItems: 'center', justifyContent: 'center' }}>
      {cam.online ? (
        <>
          {([0, 1] as const).map(slot => uris[slot] && (
            <Image key={slot} source={{ uri: uris[slot]! }} style={[FILL, { opacity: front === slot ? 1 : 0 }]}
              resizeMode="contain" fadeDuration={0} onLoad={() => done(slot, true)} onError={() => done(slot, false)} />
          ))}
        </>
      ) : (
        <View style={{ alignItems: 'center', gap: T.s8, padding: T.s16 }}>
          <Icon name="cctv" size={32} color={T.fog} />
          <Txt v="caption" color={T.fog} style={{ textAlign: 'center' }}>
            {cam.source === 'push' ? 'Sem imagem. Abra a aba Câmera no celular que transmite.' : 'Sem imagem. Confira se a câmera está ligada.'}
          </Txt>
        </View>
      )}
    </View>
  );
}

export default function Cameras({ api }: { api: Api }) {
  const [cams, setCams] = useState<Cam[]>([]);
  const [edit, setEdit] = useState<Cam | null>(null);
  const [name, setName] = useState('');
  const [src, setSrc] = useState('');
  const load = async () => setCams(await api.cameras());
  usePoll(load, 8000, [api]);

  async function add() {
    try { await api.addCamera(name.trim(), src.trim()); setName(''); setSrc(''); await load(); }
    catch (e: any) { Alert.alert('Não deu para adicionar', e.message); }
  }
  const remove = (c: Cam) =>
    Alert.alert(`Remover a câmera ${c.name}?`, 'As zonas dela também são removidas.', [
      { text: 'Remover', style: 'destructive', onPress: () => api.delCamera(c.name).then(load) },
      { text: 'Cancelar', style: 'cancel' },
    ]);
  const online = cams.filter(c => c.online).length;

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Header title="Câmeras"
        subtitle={cams.length ? `${online} de ${cams.length} com imagem` : 'Adicione uma câmera da rede, um celular ou uma webcam.'} />
      {cams.map(c => (
        <Panel key={c.name} padding={T.s8}>
          <Live api={api} cam={c} />
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8, paddingLeft: T.s8 }}>
            <Dot color={c.online ? T.ok : T.alert} />
            <Txt v="strong" style={{ flex: 1 }} numberOfLines={1}>{c.name}</Txt>
            <IconBtn icon="vector-polygon" label="Desenhar zonas" onPress={() => setEdit(c)} />
            <IconBtn icon="delete-outline" label="Remover câmera" onPress={() => remove(c)} />
          </View>
          <View style={[s.row, { gap: T.s4, paddingHorizontal: T.s8, paddingBottom: T.s4 }]}>
            {c.zones.map(z => (
              <View key={z.name} style={{ flexDirection: 'row', alignItems: 'center', gap: T.s4, paddingHorizontal: T.s8, height: 24,
                borderRadius: T.r2, backgroundColor: T.haze }}>
                <Swatch color={kindColor(z.kind)} />
                <Txt v="caption">{z.name}</Txt>
              </View>
            ))}
            {c.zones.length === 0 && <Txt v="caption" color={T.warn}>Sem zonas: nada é contado nesta câmera ainda.</Txt>}
          </View>
        </Panel>
      ))}
      <Panel title="Adicionar câmera"
        subtitle="Câmera IP: rtsp://usuário:senha@ip/stream. Celular com IP Webcam: http://ip:8080/video. Este app em outro celular: push.">
        <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Nome (ex: cozinha)" placeholderTextColor={T.fog} />
        <TextInput style={s.input} value={src} onChangeText={setSrc} autoCapitalize="none" placeholder="Endereço ou fonte" placeholderTextColor={T.fog} />
        <Btn icon="plus" label="Adicionar" onPress={add} disabled={!name.trim() || !src.trim()} />
      </Panel>
      {edit && <ZoneEditor api={api} cam={edit} onClose={() => { setEdit(null); load(); }} />}
    </ScrollView>
  );
}
