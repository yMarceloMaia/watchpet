import * as ImagePicker from 'expo-image-picker';
import React, { useState } from 'react';
import { ActivityIndicator, Alert, Image, Modal, ScrollView, TextInput, View } from 'react-native';
import { Api } from './api';
import { Btn, Header, Meter, Panel, T, Txt, s, usePoll } from './ui';

const IDEAL = 15;

export default function Cats({ api }: { api: Api }) {
  const [cats, setCats] = useState<{ name: string; photos: number }[]>([]);
  const [cams, setCams] = useState<string[]>([]);
  const [name, setName] = useState('');
  const [bust, setBust] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);          // o que está sendo processado
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);

  const load = async () => { setCats(await api.cats()); setCams((await api.cameras()).map(c => c.name)); };
  usePoll(load, 15000, [api]);
  const guard = async (text: string, fn: () => Promise<unknown>) => {
    setBusy(text);
    try { await fn(); setBust(Date.now()); await load(); } catch (e: any) { Alert.alert('Não deu certo', e.message); }
    setBusy(null);
    setProgress(null);
  };

  async function pick(n: string) {
    const r = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: true, quality: 0.8 });
    if (r.canceled) return;
    const total = r.assets.length;
    await guard(`Processando fotos de ${n}`, async () => {
      setProgress({ done: 0, total });
      for (let i = 0; i < total; i++) {
        await api.addPhoto(n, r.assets[i].uri);
        setProgress({ done: i + 1, total });
      }
    });
  }
  async function shoot(n: string) {
    const p = await ImagePicker.requestCameraPermissionsAsync();
    if (!p.granted) return Alert.alert('Sem permissão da câmera', 'Libere a câmera para o Catwatch nas configurações do celular.');
    const r = await ImagePicker.launchCameraAsync({ quality: 0.8 });
    if (!r.canceled) await guard(`Processando a foto de ${n}`, () => api.addPhoto(n, r.assets[0].uri));
  }
  const fromCam = (n: string) =>
    Alert.alert('Foto de qual câmera?', 'O gato precisa estar à vista agora.', [
      ...cams.map(c => ({ text: c, onPress: () => guard(`Procurando ${n} na câmera ${c}`, () => api.catFromCamera(n, c)) })),
      { text: 'Cancelar', style: 'cancel' as const },
    ]);
  const remove = (n: string) =>
    Alert.alert(`Apagar ${n}?`, 'As fotos dele somem e o Catwatch deixa de reconhecê-lo.', [
      { text: 'Apagar', style: 'destructive', onPress: () => guard(`Apagando ${n}`, () => api.delCat(n)) },
      { text: 'Cancelar', style: 'cancel' },
    ]);
  const newName = name.trim();

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Header title="Gatos" subtitle="O Catwatch reconhece cada gato comparando com estas fotos. Fotos variadas (ângulo, luz, perto da caixa e do pote) ajudam." />
      {cats.map(c => {
        const q = Math.min(1, c.photos / IDEAL);
        return (
          <Panel key={c.name} style={{ gap: T.s16 }}>
            <View style={{ flexDirection: 'row', gap: T.s16, alignItems: 'center' }}>
              <Image source={{ uri: api.thumb(c.name, bust) }} style={{ width: 64, height: 64, borderRadius: T.r4, backgroundColor: T.haze }} />
              <View style={{ flex: 1, gap: T.s8 }}>
                <Txt v="title" numberOfLines={1}>{c.name}</Txt>
                <Meter value={q} color={q >= 1 ? T.ok : T.warn} />
                <Txt v="caption" color={T.fog}>
                  {c.photos} {c.photos === 1 ? 'foto' : 'fotos'}{c.photos < IDEAL ? `, faltam ${IDEAL - c.photos} para o ideal` : ''}
                </Txt>
              </View>
            </View>
            <View style={s.row}>
              <Btn kind="ghost" icon="camera" label="Tirar foto" onPress={() => shoot(c.name)} />
              <Btn kind="ghost" icon="image-multiple" label="Galeria" onPress={() => pick(c.name)} />
              <Btn kind="ghost" icon="cctv" label="Da câmera" onPress={() => fromCam(c.name)} disabled={!cams.length} />
              <Btn kind="danger" icon="delete-outline" label="Apagar" onPress={() => remove(c.name)} />
            </View>
          </Panel>
        );
      })}
      <Panel title={cats.length ? 'Cadastrar outro gato' : 'Cadastrar o primeiro gato'}
        subtitle="Dê um nome e tire uma foto ou escolha da galeria. Depois, adicione mais fotos até chegar a 15.">
        <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Nome do gato" placeholderTextColor={T.fog} />
        <View style={s.row}>
          <Btn icon="camera" label="Tirar foto" disabled={!newName} onPress={() => shoot(newName).then(() => setName(''))} />
          <Btn kind="ghost" icon="image-multiple" label="Da galeria" disabled={!newName} onPress={() => pick(newName).then(() => setName(''))} />
        </View>
      </Panel>

      {/* Bloqueia a tela enquanto processa, para ninguém tocar de novo achando que travou. */}
      <Modal visible={busy !== null} transparent animationType="fade" onRequestClose={() => {}}>
        <View style={{ flex: 1, backgroundColor: T.scrim, justifyContent: 'center', padding: T.s32 }}>
          <Panel style={{ gap: T.s16 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s16 }}>
              <ActivityIndicator color={T.iris} size="large" />
              <View style={{ flex: 1, gap: T.s2 }}>
                <Txt v="strong">{busy}</Txt>
                <Txt v="caption" color={T.fog}>O servidor procura o gato em cada foto.</Txt>
              </View>
            </View>
            {progress && (
              <>
                <Meter value={progress.done / progress.total} color={T.iris} />
                <Txt v="caption" color={T.fog} style={{ fontVariant: ['tabular-nums'] }}>{progress.done} de {progress.total}</Txt>
              </>
            )}
          </Panel>
        </View>
      </Modal>
    </ScrollView>
  );
}
