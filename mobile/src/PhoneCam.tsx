import { CameraView, useCameraPermissions } from 'expo-camera';
import React, { useEffect, useRef, useState } from 'react';
import { ScrollView, TextInput, View } from 'react-native';
import { Api } from './api';
import { Btn, Dot, Header, Panel, T, Txt, s } from './ui';

/** Usa este celular como uma câmera do Catwatch: envia um JPEG ~1,5x por segundo ao servidor. */
export default function PhoneCam({ api }: { api: Api }) {
  const [perm, ask] = useCameraPermissions();
  const [name, setName] = useState('celular');
  const [on, setOn] = useState(false);
  const [sent, setSent] = useState(0);
  const [err, setErr] = useState('');
  const ref = useRef<CameraView>(null);

  useEffect(() => {
    if (!on) return;
    let alive = true;
    (async () => {
      while (alive) {
        const t = Date.now();
        try {
          const pic = await ref.current?.takePictureAsync({ quality: 0.4, base64: true, skipProcessing: false, shutterSound: false });
          if (pic?.base64 && alive) {
            await api.push(name.trim(), pic.base64);
            setSent(n => n + 1); setErr('');
          }
        } catch (e: any) { setErr(e.message); await new Promise(r => setTimeout(r, 2000)); }
        await new Promise(r => setTimeout(r, Math.max(0, 650 - (Date.now() - t))));
      }
    })();
    return () => { alive = false; };
  }, [on, api, name]);

  if (!perm) return <View style={s.screen} />;
  if (!perm.granted)
    return (
      <View style={[s.screen, s.content]}>
        <Header title="Câmera" subtitle="Transforme este celular numa câmera do Catwatch. Para isso, ele precisa usar a câmera." />
        <Btn icon="camera" label="Permitir a câmera" onPress={ask} />
      </View>
    );

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Header title="Câmera" subtitle="Deixe o celular parado, apontado para a caixa ou o pote, e na tomada. A tela fica ligada enquanto transmite." />
      <View style={{ borderRadius: T.r8, overflow: 'hidden', borderWidth: 1, borderColor: on ? T.ok : T.seam }}>
        <CameraView ref={ref} style={{ width: '100%', aspectRatio: 3 / 4 }} facing="back" animateShutter={false} />
      </View>
      <Panel>
        <Txt v="caption" color={T.fog}>Nome desta câmera no Catwatch</Txt>
        <TextInput style={s.input} value={name} onChangeText={setName} editable={!on} placeholder="ex: caixa de areia" placeholderTextColor={T.fog} />
        {on && (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8 }}>
            <Dot color={err ? T.alert : T.ok} />
            <Txt style={{ fontVariant: ['tabular-nums'] }}>Transmitindo como {name}: {sent} quadros enviados</Txt>
          </View>
        )}
        {err ? <Txt color={T.alert}>{err}</Txt> : null}
        <Btn kind={on ? 'danger' : 'primary'} icon={on ? 'stop' : 'play'} label={on ? 'Parar de transmitir' : 'Começar a transmitir'}
          disabled={!name.trim()} onPress={() => setOn(!on)} />
      </Panel>
    </ScrollView>
  );
}
