import React, { useEffect, useState } from 'react';
import { Alert, Image, LayoutChangeEvent, Modal, Pressable, SafeAreaView, ScrollView, TextInput, View } from 'react-native';
import Svg, { Circle, Polygon, Polyline } from 'react-native-svg';
import { Api, Cam, Zone } from './api';
import { Btn, Chips, Header, IconBtn, KINDS, KIND_NAME, Swatch, T, Txt, kindColor, s } from './ui';

export default function ZoneEditor({ api, cam, onClose }: { api: Api; cam: Cam; onClose: () => void }) {
  const [zones, setZones] = useState<Zone[]>(cam.zones);
  const [cur, setCur] = useState<number[][]>([]);
  const [name, setName] = useState('');
  const [kind, setKind] = useState<Zone['kind']>('litter');
  const [size, setSize] = useState({ w: 1, h: 1 });
  const [aspect, setAspect] = useState(16 / 9);
  const [uri] = useState(() => api.snapshot(cam.name, true));
  // Usa a proporção real da câmera, para o desenho cair exatamente onde o gato pisa.
  useEffect(() => { Image.getSize(uri, (w, h) => h && setAspect(w / h), () => {}); }, [uri]);

  const onLayout = (e: LayoutChangeEvent) => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height });
  const pts = (p: number[][]) => p.map(([x, y]) => `${x * size.w},${y * size.h}`).join(' ');

  function close() {
    if (cur.length < 3 || !name.trim()) return Alert.alert('Falta pouco', 'Marque 3 cantos ou mais e dê um nome à zona.');
    setZones([...zones, { name: name.trim(), kind, polygon: cur }]);
    setCur([]); setName('');
  }
  async function save() {
    try { await api.setZones(cam.name, zones); onClose(); } catch (e: any) { Alert.alert('Não deu para salvar', e.message); }
  }

  return (
    <Modal animationType="slide" onRequestClose={onClose}>
      <SafeAreaView style={s.screen}>
        <ScrollView contentContainerStyle={s.content}>
          <Header title="Zonas" subtitle={`Câmera ${cam.name}. Toque nos cantos da área; com 3 ou mais, dê um nome e feche a zona.`} />
          <View onLayout={onLayout} style={{ borderRadius: T.r4, overflow: 'hidden' }}>
            <Image source={{ uri }} style={{ width: '100%', aspectRatio: aspect, backgroundColor: T.dusk }} resizeMode="stretch" />
            <Svg style={{ position: 'absolute', top: 0, left: 0 }} width={size.w} height={size.h}>
              {zones.map((z, i) => (
                <Polygon key={i} points={pts(z.polygon)} fill={kindColor(z.kind)} fillOpacity={0.33} stroke={kindColor(z.kind)} strokeWidth={2} />
              ))}
              {cur.length > 1 && <Polyline points={pts(cur)} fill="none" stroke={T.moon} strokeWidth={2} />}
              {cur.map(([x, y], i) => <Circle key={i} cx={x * size.w} cy={y * size.h} r={T.s4} fill={T.moon} />)}
            </Svg>
            <Pressable style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }}
              onPress={e => setCur([...cur, [e.nativeEvent.locationX / size.w, e.nativeEvent.locationY / size.h]])} />
          </View>
          <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Nome da zona (ex: bebedouro)" placeholderTextColor={T.fog} />
          <Chips value={kind} onChange={setKind} options={KINDS.map(k => ({ value: k, label: KIND_NAME[k], color: kindColor(k) }))} />
          <View style={s.row}>
            <Btn kind="ghost" icon="vector-polygon" label="Fechar zona" onPress={close} />
            <Btn kind="ghost" icon="restart" label="Desfazer ponto" onPress={() => setCur(cur.slice(0, -1))} disabled={!cur.length} />
          </View>
          {zones.map((z, i) => (
            <View key={i} style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8 }}>
              <Swatch color={kindColor(z.kind)} />
              <Txt style={{ flex: 1 }}>{z.name}</Txt>
              <Txt v="caption" color={T.fog}>{KIND_NAME[z.kind]}</Txt>
              <IconBtn icon="close" label={`Remover a zona ${z.name}`} color={T.alert} onPress={() => setZones(zones.filter((_, j) => j !== i))} />
            </View>
          ))}
          <View style={s.row}>
            <Btn icon="content-save" label="Salvar zonas" onPress={save} />
            <Btn kind="ghost" label="Cancelar" onPress={onClose} />
          </View>
        </ScrollView>
      </SafeAreaView>
    </Modal>
  );
}
