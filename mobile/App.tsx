import { MaterialCommunityIcons } from '@expo/vector-icons';
import {
  Recursive_400Regular, Recursive_500Medium, Recursive_600SemiBold, Recursive_700Bold, useFonts,
} from '@expo-google-fonts/recursive';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake';
import { StatusBar } from 'expo-status-bar';
import React, { useEffect, useMemo, useState } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Pressable, SafeAreaView, ScrollView, TextInput, View, useColorScheme } from 'react-native';
import Cameras from './src/Cameras';
import Cats from './src/Cats';
import History from './src/History';
import PhoneCam from './src/PhoneCam';
import Today from './src/Today';
import { Api, Conn, loadConn, normalizeUrl, parsePairCode, saveConn } from './src/api';
import { Btn, Header, Icon, IconName, Panel, T, ThemeMode, Txt, applyTheme, s } from './src/ui';

function Connect({ onDone }: { onDone: (c: Conn) => void }) {
  const [url, setUrl] = useState('');
  const [token, setToken] = useState('');
  const [err, setErr] = useState('');
  const [scanning, setScanning] = useState(false);
  const [busy, setBusy] = useState(false);
  const [perm, askPerm] = useCameraPermissions();

  async function go(c: Conn) {
    setBusy(true);
    setErr('');
    try {
      const info = await fetch(c.url + '/api/info').then(r => r.json());
      if (info.app !== 'catwatch') throw new Error('esse endereço não é um servidor Catwatch');
      await new Api(c).check();
      await saveConn(c); onDone(c);
    } catch (e: any) {
      setErr(e.message.includes('401') || e.message.includes('token')
        ? 'Token inválido. Leia o QR code de novo no app de PC.'
        : `Não consegui conectar: ${e.message}. Confira se o celular está no mesmo Wi-Fi do PC.`);
    }
    setBusy(false);
  }

  async function startScan() {
    setErr('');
    if (!perm?.granted && !(await askPerm()).granted) return setErr('Sem permissão da câmera para ler o QR code.');
    setScanning(true);
  }

  if (scanning)
    return (
      <SafeAreaView style={s.safe}>
        <View style={[s.content, { flex: 1 }]}>
          <Header title="Ler QR code" subtitle="No app de PC: Servidor, Conectar o celular." />
          <View style={{ flex: 1, borderRadius: T.r8, overflow: 'hidden', borderWidth: 1, borderColor: T.seam }}>
            <CameraView
              style={{ flex: 1 }}
              facing="back"
              barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
              onBarcodeScanned={({ data }) => {
                const c = parsePairCode(data);
                if (!c) return setErr('Esse QR code não é do Catwatch.');
                setScanning(false); setUrl(c.url); setToken(c.token); go(c);
              }}
            />
          </View>
          {err ? <Txt color={T.alert}>{err}</Txt> : null}
          <Btn kind="ghost" label="Cancelar" onPress={() => setScanning(false)} />
        </View>
      </SafeAreaView>
    );

  return (
    <SafeAreaView style={s.safe}>
      <ScrollView contentContainerStyle={[s.content, { flexGrow: 1, justifyContent: 'center' }]} keyboardShouldPersistTaps="handled">
        <View style={{ gap: T.s4, marginBottom: T.s16 }}>
          <Icon name="cat" size={T.s32} color={T.iris} />
          <Txt v="display">Catwatch</Txt>
          <Txt color={T.fog}>Caixa, comida e água de cada gato, ao longo do dia.</Txt>
        </View>
        <Btn icon="qrcode-scan" label="Ler QR code do app de PC" onPress={startScan} />
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8 }}>
          <View style={{ flex: 1, height: 1, backgroundColor: T.seam }} />
          <Txt v="caption" color={T.fog}>ou digite</Txt>
          <View style={{ flex: 1, height: 1, backgroundColor: T.seam }} />
        </View>
        <Panel>
          <TextInput style={s.input} value={url} onChangeText={setUrl} autoCapitalize="none" keyboardType="url"
            placeholder="Servidor, ex: 192.168.0.10:8000" placeholderTextColor={T.fog} />
          <TextInput style={s.input} value={token} onChangeText={setToken} autoCapitalize="none" secureTextEntry
            placeholder="Token" placeholderTextColor={T.fog} />
          {err ? <Txt color={T.alert}>{err}</Txt> : null}
          <Btn kind="ghost" label={busy ? 'Conectando' : 'Conectar'} disabled={busy || !url.trim() || !token.trim()}
            onPress={() => go({ url: normalizeUrl(url), token: token.trim() })} />
        </Panel>
      </ScrollView>
    </SafeAreaView>
  );
}

type Tab = 'today' | 'cams' | 'cats' | 'hist' | 'phone';
const TABS: { key: Tab; icon: IconName; label: string }[] = [
  { key: 'today', icon: 'paw', label: 'Hoje' },
  { key: 'cams', icon: 'cctv', label: 'Câmeras' },
  { key: 'cats', icon: 'cat', label: 'Gatos' },
  { key: 'hist', icon: 'history', label: 'Histórico' },
  { key: 'phone', icon: 'cellphone', label: 'Câmera' },
];

export default function App() {
  const [fontsLoaded] = useFonts({
    Recursive_400Regular, Recursive_500Medium, Recursive_600SemiBold, Recursive_700Bold,
    ...MaterialCommunityIcons.font,
  });
  const [conn, setConn] = useState<Conn | null | undefined>(undefined);
  // Aparência: automático segue o tema do Android/iOS.
  const scheme = useColorScheme();
  const [mode, setModeState] = useState<ThemeMode>('auto');
  useEffect(() => { AsyncStorage.getItem('catwatch.theme').then(m => m && setModeState(m as ThemeMode)).catch(() => {}); }, []);
  const setMode = (m: ThemeMode) => { setModeState(m); AsyncStorage.setItem('catwatch.theme', m).catch(() => {}); };
  const dark = mode === 'dark' || (mode === 'auto' && scheme !== 'light');
  applyTheme(dark);
  const [tab, setTab] = useState<Tab>('today');
  useEffect(() => { loadConn().then(setConn); }, []);
  const logout = () => { saveConn(null); setConn(null); };
  const api = useMemo(() => (conn ? new Api(conn, logout) : null), [conn]);
  useEffect(() => {
    if (tab === 'phone') activateKeepAwakeAsync('phonecam'); else deactivateKeepAwake('phonecam');
    return () => { deactivateKeepAwake('phonecam'); };
  }, [tab]);

  if (!fontsLoaded || conn === undefined) return <View style={s.screen} />;
  const bar = <StatusBar style={dark ? 'light' : 'dark'} />;
  if (!conn || !api) return <React.Fragment key={String(dark)}>{bar}<Connect onDone={setConn} /></React.Fragment>;

  return (
    // key: trocar o tema remonta as telas, para todas lerem a paleta nova.
    <SafeAreaView style={s.safe} key={String(dark)}>
      {bar}
      <View style={{ flex: 1 }}>
        {tab === 'today' && <Today api={api} onLogout={logout} mode={mode} onMode={setMode} />}
        {tab === 'cams' && <Cameras api={api} />}
        {tab === 'cats' && <Cats api={api} />}
        {tab === 'hist' && <History api={api} />}
        {tab === 'phone' && <PhoneCam api={api} />}
      </View>
      <View style={{ flexDirection: 'row', borderTopWidth: 1, borderColor: T.seam, backgroundColor: T.dusk }}>
        {TABS.map(t => {
          const on = tab === t.key;
          return (
            <Pressable key={t.key} onPress={() => setTab(t.key)} accessibilityRole="tab" accessibilityState={{ selected: on }}
              style={{ flex: 1, alignItems: 'center', gap: T.s4, paddingTop: T.s8, paddingBottom: T.s8 }}>
              {/* Marca da aba atual: um traço de 2 px no topo, como no trilho do PC. */}
              <View style={{ position: 'absolute', top: 0, height: T.s2, width: T.s16 + T.s8, borderRadius: T.r2,
                backgroundColor: on ? T.iris : 'transparent' }} />
              <Icon name={t.icon} size={24} color={on ? T.iris : T.fog} />
              <Txt v="caption" color={on ? T.moon : T.fog}>{t.label}</Txt>
            </Pressable>
          );
        })}
      </View>
    </SafeAreaView>
  );
}
