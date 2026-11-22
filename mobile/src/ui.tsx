import { MaterialCommunityIcons } from '@expo/vector-icons';
import React from 'react';
import { Platform, Pressable, StatusBar, StyleSheet, Text, TextProps, TextStyle, View, ViewStyle } from 'react-native';

/**
 * Tokens visuais do Catwatch ("vigília noturna"). Os mesmos valores estão em
 * catwatch-desktop/src/T.qml; mude nos dois lugares.
 */
const DARK = {
  // Superfícies: índigo noturno, do fundo para a frente.
  night: '#171A2B', dusk: '#1F2338', haze: '#2A2F4A', seam: '#363C5E', moon: '#ECEAF4', fog: '#9EA1BD',
  // As três necessidades do dia: a mesma cor em todo lugar.
  sand: '#D8BE8A', paw: '#F2899B', pool: '#66C6F2',
  alert: '#FF6B6B', warn: '#F4C152', ok: '#6EDC9A',
  // Destaque do celular (no PC, o accent vem do tema do sistema).
  iris: '#B9A8FF', irisDown: '#9C8AF0', onIris: '#171A2B',
  scrim: '#0b0d18cc',
};
// Claro: manhã, um cinza-azulado frio; as cores dos tipos mais fundas para ler sobre o branco.
const LIGHT: typeof DARK = {
  night: '#F3F4F9', dusk: '#FFFFFF', haze: '#E7E9F2', seam: '#D5D8E6', moon: '#1E2236', fog: '#626783',
  sand: '#A27A2C', paw: '#CC4A66', pool: '#1B86BE',
  alert: '#D23C3C', warn: '#A9780A', ok: '#25915A',
  iris: '#6A55E0', irisDown: '#5844C8', onIris: '#FFFFFF',
  scrim: '#1e2236aa',
};

/**
 * Tokens visuais do Catwatch ("vigília noturna"). Os mesmos valores estão em
 * catwatch-desktop/src/T.qml; mude nos dois lugares. As cores mudam com applyTheme().
 */
export const T = {
  ...DARK,
  dark: true,
  // Escala binária: espaços e cantos só nestes valores.
  s2: 2, s4: 4, s8: 8, s16: 16, s32: 32, s64: 64,
  r2: 2, r4: 4, r8: 8,
};

export const F = {
  regular: 'Recursive_400Regular',
  medium: 'Recursive_500Medium',
  semibold: 'Recursive_600SemiBold',
  bold: 'Recursive_700Bold',
};

export type ThemeMode = 'auto' | 'light' | 'dark';
export type Kind = 'litter' | 'food' | 'water';
export const KINDS: Kind[] = ['litter', 'food', 'water'];
export const KIND_NAME: Record<string, string> = { litter: 'Caixa de areia', food: 'Comida', water: 'Água' };
export const KIND_SHORT: Record<string, string> = { litter: 'Caixa', food: 'Comida', water: 'Água' };
export const kindColor = (k: string) => (k === 'litter' ? T.sand : k === 'food' ? T.paw : k === 'water' ? T.pool : T.fog);
export const levelColor = (l: string) => (l === 'error' ? T.alert : l === 'warn' ? T.warn : T.fog);

const TYPE: Record<string, TextStyle> = {
  display: { fontFamily: F.bold, fontSize: 24, lineHeight: 32 },
  title: { fontFamily: F.semibold, fontSize: 20, lineHeight: 24 },
  strong: { fontFamily: F.semibold, fontSize: 16, lineHeight: 24 },
  label: { fontFamily: F.medium, fontSize: 14, lineHeight: 16 },
  body: { fontFamily: F.regular, fontSize: 14, lineHeight: 20 },
  caption: { fontFamily: F.regular, fontSize: 12, lineHeight: 16 },
};
export type TextVariant = keyof typeof TYPE;

export function Txt({ v = 'body', color = T.moon, style, ...rest }: TextProps & { v?: TextVariant; color?: string }) {
  return <Text {...rest} style={[TYPE[v], { color }, style]} />;
}

export type IconName = React.ComponentProps<typeof MaterialCommunityIcons>['name'];
export const Icon = ({ name, size = 16, color = T.moon }: { name: IconName; size?: number; color?: string }) => (
  <MaterialCommunityIcons name={name} size={size} color={color} />
);

/** primary: preenchido com o destaque; ghost: contorno; danger: contorno e texto vermelhos. */
export function Btn({ label, icon, onPress, kind = 'primary', disabled, style }: {
  label: string; icon?: IconName; onPress: () => void; kind?: 'primary' | 'ghost' | 'danger'; disabled?: boolean; style?: ViewStyle;
}) {
  const fg = kind === 'primary' ? T.onIris : kind === 'danger' ? T.alert : T.moon;
  return (
    <Pressable
      onPress={onPress} disabled={disabled} accessibilityRole="button" accessibilityLabel={label}
      style={({ pressed }) => [{
        flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: T.s8,
        minHeight: 40, paddingHorizontal: T.s16, borderRadius: T.r4,
        backgroundColor: kind === 'primary' ? (pressed ? T.irisDown : T.iris) : pressed ? T.haze : 'transparent',
        borderWidth: kind === 'primary' ? 0 : 1, borderColor: T.seam, opacity: disabled ? 0.4 : 1,
      }, style]}>
      {icon && <Icon name={icon} size={16} color={fg} />}
      <Txt v="label" color={fg}>{label}</Txt>
    </Pressable>
  );
}

export function IconBtn({ icon, onPress, label, color = T.moon }: { icon: IconName; onPress: () => void; label: string; color?: string }) {
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={label} hitSlop={T.s8}
      style={({ pressed }) => ({ width: 32 + T.s8, height: 32 + T.s8, borderRadius: T.r4, alignItems: 'center', justifyContent: 'center',
        backgroundColor: pressed ? T.haze : 'transparent' })}>
      <Icon name={icon} size={20} color={color} />
    </Pressable>
  );
}

/** Superfície de um grupo de conteúdo: cantos de 8, borda de 1 px, respiro de 16. */
export function Panel({ title, subtitle, children, style, padding = T.s16 }: {
  title?: string; subtitle?: string; children?: React.ReactNode; style?: ViewStyle; padding?: number;
}) {
  return (
    <View style={[{ backgroundColor: T.dusk, borderRadius: T.r8, borderWidth: 1, borderColor: T.seam, padding, gap: T.s8 }, style]}>
      {title ? (
        <View style={{ gap: T.s2, marginBottom: T.s4 }}>
          <Txt v="strong">{title}</Txt>
          {subtitle ? <Txt v="caption" color={T.fog}>{subtitle}</Txt> : null}
        </View>
      ) : null}
      {children}
    </View>
  );
}

export function Header({ title, subtitle, right }: { title: string; subtitle?: string; right?: React.ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'flex-end', gap: T.s16 }}>
      <View style={{ flex: 1, gap: T.s4 }}>
        <Txt v="display">{title}</Txt>
        {subtitle ? <Txt color={T.fog}>{subtitle}</Txt> : null}
      </View>
      {right}
    </View>
  );
}

export const Swatch = ({ color, size = T.s8 }: { color: string; size?: number }) => (
  <View style={{ width: size, height: size, borderRadius: T.r2, backgroundColor: color }} />
);
export const Dot = ({ color }: { color: string }) => <View style={{ width: T.s8, height: T.s8, borderRadius: T.r4, backgroundColor: color }} />;

/** Marca de um tipo de visita: quadradinho na cor, número opcional e nome curto. */
export function KindTag({ kind, count, showName = true }: { kind: string; count?: number; showName?: boolean }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.s4 }}>
      <Swatch color={kindColor(kind)} />
      {count !== undefined && <Txt v="strong" style={{ fontVariant: ['tabular-nums'] }}>{count}</Txt>}
      {showName && <Txt v="caption" color={T.fog}>{KIND_SHORT[kind] ?? kind}</Txt>}
    </View>
  );
}

/** Barra fina de 0 a 1 (fotos do gato, certeza da identificação). */
export const Meter = ({ value, color, width }: { value: number; color: string; width?: number }) => (
  <View style={{ height: T.s4, borderRadius: T.r2, backgroundColor: T.haze, width: width ?? '100%', overflow: 'hidden' }}>
    <View style={{ height: T.s4, borderRadius: T.r2, backgroundColor: color, width: `${Math.max(0, Math.min(1, value)) * 100}%` }} />
  </View>
);

/** Fileira de opções (filtros, tipo de zona). A escolhida ganha fundo e contorno claros. */
export function Chips<V extends string>({ options, value, onChange }: {
  options: { value: V; label: string; color?: string }[]; value: V; onChange: (v: V) => void;
}) {
  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: T.s8 }}>
      {options.map(o => {
        const on = o.value === value;
        return (
          <Pressable key={o.value} onPress={() => onChange(o.value)} accessibilityRole="button" accessibilityState={{ selected: on }}
            style={{ flexDirection: 'row', alignItems: 'center', gap: T.s8, minHeight: 32, paddingHorizontal: T.s16, borderRadius: T.r4,
              borderWidth: 1, borderColor: on ? T.fog : T.seam, backgroundColor: on ? T.haze : 'transparent' }}>
            {o.color && <Swatch color={o.color} />}
            <Txt color={on ? T.moon : T.fog}>{o.label}</Txt>
          </Pressable>
        );
      })}
    </View>
  );
}

// No Android o SafeAreaView do React Native não desconta a barra de status; fazemos à mão.
export const topInset = Platform.OS === 'android' ? StatusBar.currentHeight ?? 0 : 0;

const makeStyles = () => StyleSheet.create({
  screen: { flex: 1, backgroundColor: T.night },
  safe: { flex: 1, backgroundColor: T.night, paddingTop: topInset },
  content: { padding: T.s16, gap: T.s16, paddingBottom: T.s32 },
  row: { flexDirection: 'row', alignItems: 'center', gap: T.s8, flexWrap: 'wrap' },
  input: {
    color: T.moon, fontFamily: F.regular, fontSize: 14, minHeight: 40, borderWidth: 1, borderColor: T.seam,
    borderRadius: T.r4, paddingHorizontal: T.s16, paddingVertical: T.s8, backgroundColor: T.haze,
  },
});
export const s = makeStyles();

/** Troca a paleta e refaz os estilos; o App remonta as telas em seguida para todas lerem as cores novas. */
export function applyTheme(dark: boolean) {
  if (T.dark === dark) return;
  Object.assign(T, dark ? DARK : LIGHT, { dark });
  Object.assign(s, makeStyles());
}

export const pt = (d: Date, opts: Intl.DateTimeFormatOptions) => d.toLocaleString('pt-BR', opts);
export const hhmm = (ts: number) => pt(new Date(ts * 1000), { hour: '2-digit', minute: '2-digit' });
export const dec = (n: number, digits = 2) => n.toFixed(digits).replace('.', ',');

/** Atualiza `fn` a cada `ms` enquanto o componente estiver montado. Com o servidor lento, não
 *  começa outra rodada antes de a anterior terminar (elas se acumulavam). */
export function usePoll(fn: () => Promise<void>, ms: number, deps: unknown[] = []) {
  React.useEffect(() => {
    let alive = true;
    let busy = false;
    const run = () => {
      if (!alive || busy) return;
      busy = true;
      fn().catch(() => {}).finally(() => { busy = false; });
    };
    run();
    const id = setInterval(run, ms);
    return () => { alive = false; clearInterval(id); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
}
