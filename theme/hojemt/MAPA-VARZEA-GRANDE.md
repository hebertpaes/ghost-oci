# Documentação Técnica — Mapa "Mato Grosso Ao Vivo"
**Arquivo:** `assets/mapa-varzea-grande.html` • **Template de integração:** `custom-mapa-vg.hbs`
*Central de geomonitoramento embutida no tema Hoje MT (Ghost CMS): câmeras públicas, radares de velocidade, utilidade pública, clima, qualidade do ar, radar de chuva e tráfego aéreo.*

---

## 📑 Índice

1. [Visão Geral](#1-visão-geral)
2. [Integração com o Tema Ghost](#2-integração-com-o-tema-ghost)
3. [Arquitetura do Arquivo](#3-arquitetura-do-arquivo)
4. [Bases de Dados Internas (Schemas)](#4-bases-de-dados-internas-schemas)
5. [APIs Externas e Feeds em Tempo Real](#5-apis-externas-e-feeds-em-tempo-real)
6. [Funcionalidades e Interface](#6-funcionalidades-e-interface)
7. [Referência das Principais Funções JS](#7-referência-das-principais-funções-js)
8. [Guia de Manutenção (Como Editar)](#8-guia-de-manutenção-como-editar)
9. [⚠️ Análise de Melhores Práticas — Pontos Críticos](#9-️-análise-de-melhores-práticas--pontos-críticos)
10. [Checklist de Publicação](#10-checklist-de-publicação)
11. [Solução de Problemas (FAQ)](#11-solução-de-problemas-faq)

---

## 1. Visão Geral

O mapa é uma **aplicação single-file** (HTML + CSS + JavaScript em um único arquivo, ~142 KB / 3.600 linhas) construída sobre **Leaflet 1.9.4**, sem etapa de build e sem chave de API. Cobre todo o Estado de Mato Grosso com foco inicial em Várzea Grande.

| Item | Valor |
|---|---|
| Biblioteca de mapa | Leaflet 1.9.4 (unpkg, com SRI) |
| Ícones | Font Awesome 6.5.1 (cdnjs) |
| Fontes | Inter, Plus Jakarta Sans, JetBrains Mono (Google Fonts) |
| Mapas base | 7 opções gratuitas (OSM, Esri ×4, OpenTopoMap, CyclOSM) |
| Dados estáticos | 24 câmeras, 20 radares, 10 POIs (hardcoded no próprio arquivo) |
| Feeds ao vivo | Open-Meteo (clima + ar), RainViewer (chuva), OpenSky (voos ADS-B) |
| Tema | Claro/escuro com persistência em `localStorage` (`vg_theme`) |
| Mobile | Sidebar vira *bottom sheet* deslizante abaixo de 900 px |

---

## 2. Integração com o Tema Ghost

O mapa **não é uma página Ghost comum** — é um arquivo estático servido de `assets/` e embutido por iframe no template customizado:

```handlebars
{{!-- custom-mapa-vg.hbs --}}
<iframe
    src="/assets/mapa-varzea-grande.html"
    style="width: 100%; height: 100%; border: none; flex: 1;"
    title="Mapa Interativo de Utilidade Pública de Várzea Grande - MT"
    allow="geolocation">
</iframe>
```

### Como publicar a página no Ghost Admin
1. Crie um **Post** (o template usa `{{#post}}`) com o título desejado (ex.: "Mapa Ao Vivo").
2. No painel lateral do editor (⚙️), em **Template**, selecione **custom-mapa-vg**.
3. Publique. A página renderiza o iframe em `calc(100vh - 120px)`.

### Pontos de atenção da integração
- **`allow="geolocation"` é obrigatório** no iframe — sem ele o botão "Meu GPS" falha silenciosamente em navegadores modernos.
- Por ser iframe, o mapa **não herda o tema claro/escuro do site**: ele mantém o próprio toggle e o próprio `localStorage` (chave `vg_theme`, independente do tema Hoje MT).
- O arquivo é servido pelo Ghost como asset estático — **qualquer alteração exige reenviar o .zip do tema** (ou reiniciar o Ghost em dev). Não há cache-busting: em produção considere renomear o arquivo ou configurar cabeçalhos de cache ao atualizar.

---

## 3. Arquitetura do Arquivo

O arquivo segue a ordem: metadados/preconnect → CSS → HTML → dados → lógica JS.

| Bloco | Linhas (aprox.) | Conteúdo |
|---|---|---|
| `<head>` + preconnect | 1–27 | SEO, dns-prefetch/preconnect para tiles e APIs, CDNs |
| CSS (design tokens + componentes) | 28–1040 | Variáveis `:root`, dark mode `[data-theme="dark"]`, todos os componentes, media query mobile (≤ 900 px) |
| Barra de emergência + header | 1044–1088 | Telefones úteis (192, 193, 190…), marca, GPS, perímetro, tema |
| Sidebar com 6 abas | 1094–1421 | Tempo Real, Câmeras, Radares, Utilidade, SOS/Alertas, Camadas |
| Canvas do mapa + controles flutuantes | 1424–1504 | Barra de regiões, filtros de ícones, botões flutuantes, status bar |
| Modal CCTV | 1509–1548 | Player de câmera com HUD estilo CFTV |
| `ALL_CAMERAS` | 1557–1955 | Base de câmeras |
| `ALL_RADARS` | 1960–2306 | Base de radares |
| `POIS` | 2311–2462 | Utilidade pública |
| Estado + `initMap()` | 2467–2583 | Coordenadas regionais, camadas Leaflet, timers |
| Lógica de UI e feeds | 2585–3596 | Filtros, renderização, APIs, ferramentas, boot no `DOMContentLoaded` |

### Camadas Leaflet (`L.layerGroup`)
| Variável | Conteúdo | Toggle na UI |
|---|---|---|
| `camerasLayer` | Pins de câmeras (azul pulsante) | Botão "Câmeras" |
| `radarsLayer` | Pins de radares (laranja) | Botão "Radares" |
| `markersLayer` | POIs por categoria (cores por tipo) | Botão "Serviços" |
| `flightMarkersLayer` | Aviões rotacionados pelo rumo | Botão "Voos" |
| `incidentMarkersLayer` | Ocorrências reportadas pelo usuário | (junto do "Limpar Ícones") |
| `boundaryLayer` | Polígono do perímetro de VG (**aproximado/ilustrativo**) | Botão "Perímetro" |
| `radarLayers[]` | Tiles do RainViewer (1 frame por vez) | Widget/botão de radar de chuva |

---

## 4. Bases de Dados Internas (Schemas)

Todos os dados de câmeras, radares e POIs são **arrays JS hardcoded** dentro do próprio HTML. Não há backend.

### 4.1 `ALL_CAMERAS` (câmera pública)
```js
{
  id: "cam-vg-01",            // único; prefixos: cam-vg, cam-cb, cam-bx, cam-nt, cam-sul, cam-oe, cam-le
  name: "Av. da FEB x ...",
  city: "vg",                 // filtro: vg | cuiaba | baixada | norte | sul | oeste | leste
  cityName: "Várzea Grande",  // exibição
  status: "online",           // online | offline (offline exibe overlay de manutenção)
  statusLabel: "Disponível (Ao Vivo)",
  type: "ocr",                // ocr | transito | seguranca | turismo (filtro OCR/LPR usa type === 'ocr')
  typeName: "OCR Leitura de Placas (LPR) + Domo 360°",
  lat: -15.6545, lng: -56.1215,
  location: "Avenida da FEB - Jardim Aeroporto, VG",
  code: "CAM-VG-01 // SESP-CIOSP",
  img: "https://images.unsplash.com/...",  // ⚠️ imagem ilustrativa (ver seção 9.1)
  desc: "Monitoramento de tráfego..."
}
```

### 4.2 `ALL_RADARS` (radar de velocidade)
```js
{
  id: "rad-vg-01",
  name: "Av. da FEB - Frente ...",
  city: "vg",                 // filtro: vg | cuiaba | rodovias | br070 | estaduais
  cityName: "Várzea Grande",
  speed: 60,                  // número; filtros: 40 | 50 | 60 | 80 (80 usa >= 80)
  type: "fixo",               // fixo | lombada | rodoviario (apenas descritivo)
  typeName: "Radar Fixo de Velocidade",
  status: "online",           // "offline" cai no filtro "Desativados"
  statusLabel: "Ativo / Fiscalizando",
  lat: -15.6520, lng: -56.1235,
  location: "Avenida da FEB - Sentido Centro / Aeroporto",
  agency: "Guarda Municipal / Prefeitura VG",
  desc: "Velocidade máxima: 60 km/h. ..."
}
```

### 4.3 `POIS` (utilidade pública)
```js
{
  id: "hpsmvg",
  name: "Hospital e Pronto-Socorro Municipal de VG",
  category: "saude",          // saude | seguranca | transporte | cidadania | turismo | educacao
  categoryName: "Saúde & Urgência 24h",
  icon: "fa-hospital",        // classe Font Awesome (sem o "fa-solid")
  color: "#ef4444",           // cor do pin/cabeçalho do popup
  lat: -15.6517, lng: -56.1418,
  address: "Av. Alzira Santana, 728 - Nova Várzea Grande",
  phone: "(65) 3632-8300",    // exibição
  phoneRaw: "+556536328300",  // usado no link tel:
  hours: "Atendimento 24 Horas (SUS)",
  desc: "Principal centro de urgência..."
}
```
> A busca da aba Utilidade filtra por `name`, `address` e `desc` (case-insensitive). As cores dos pins vêm das classes CSS `.marker-<categoria>` (linhas ~985–990) — ao criar uma categoria nova, crie também a classe.

### 4.4 `COORDS` (regiões de foco rápido)
```js
const COORDS = { mt: [-12.68, -55.42, 6], vg: [-15.6467, -56.1325, 13], ... };
// formato: [lat, lng, zoom] — usado por focusRegion()
```
`focusRegion()` também troca o clima do widget para a região (Sinop, Rondonópolis, Sorriso, Cáceres, Barra); regiões sem mapeamento explícito voltam ao clima metropolitano.

---

## 5. APIs Externas e Feeds em Tempo Real

Nenhuma API exige chave. Todas são chamadas via `fetch` direto do navegador (o IP do visitante é quem consome a cota).

| Serviço | Endpoint | Uso | Atualização | Fallback em erro |
|---|---|---|---|---|
| **Open-Meteo Forecast** | `api.open-meteo.com/v1/forecast` | Temperatura, sensação, umidade, vento, UV, condição (timezone America/Cuiaba) | a cada **60 s** | Valores fixos "35°C / Ensolarado" ⚠️ |
| **Open-Meteo Air Quality** | `air-quality-api.open-meteo.com/v1/air-quality` | PM2.5, PM10, CO, US AQI (ponteiro na régua colorida) | a cada **120 s** | Badge fixo "AQI: 48 (Boa)" ⚠️ |
| **RainViewer** | `api.rainviewer.com/public/weather-maps.json` | Frames de radar de chuva (últimas ~2 h), animação play/pause a cada 800 ms | sob demanda (ao ativar) | Aviso no console apenas |
| **OpenSky Network** | `opensky-network.org/api/states/all?lamin=-18.5&lomin=-61.5&lamax=-9.0&lomax=-50.0` | Aeronaves ADS-B na bounding box de MT | a cada **30 s** | `SIMULATED_FLIGHTS` (6 voos fictícios) ⚠️ |
| **Tiles** | OSM, Esri (×4), OpenTopoMap, CyclOSM | Mapas base | contínuo | — |

### Observações operacionais
- **OpenSky anônimo tem limite de requisições baixo** (~400 créditos/dia por IP; a API pública anônima é frequentemente limitada ou indisponível). Com o polling de 30 s, o limite estoura rápido e o mapa passa a exibir **voos simulados sem nenhum aviso ao usuário** — ver seção 9.1.
- **Tiles OSM**: a [política de uso](https://operations.osmfoundation.org/policies/tiles/) exige atribuição (✅ presente) e proíbe uso pesado; para um portal com tráfego real, considere um provedor comercial ou os tiles Esri como padrão.
- O radar de chuva usa `maxNativeZoom: 7` (os tiles do RainViewer são ampliados acima do zoom 7 — intencional, evita erros 404).
- `preconnect`/`dns-prefetch` já estão configurados para todos os hosts críticos (✅ boa prática).

---

## 6. Funcionalidades e Interface

### As 6 abas da sidebar
| Aba | ID | Conteúdo |
|---|---|---|
| **Tempo Real** | `tab-live` | Widgets: clima, qualidade do ar, radar de chuva (controles), voos ADS-B, nível do Rio Cuiabá (**valor fixo hardcoded "2,42 m"** ⚠️) |
| **Câmeras** | `tab-cameras` | Filtros por macrorregião (8) × status (todos/online/offline/OCR) + lista de cards |
| **Radares** | `tab-radars` | Filtros por região (6) × velocidade (40/50/60/80/desativados) + lista |
| **Utilidade** | `tab-pois` | Busca textual + filtro por categoria + lista |
| **SOS / Alertas** | `tab-emergency` | Telefones de emergência, formulário de ocorrência, feed de alertas (1 alerta estático) |
| **Camadas** | `tab-layers` | 7 mapas base, régua de medição, raio de proximidade 2 km, imprimir |

### Ferramentas do mapa
- **Barra de regiões** (topo esquerdo): `flyTo` animado para 10 regiões de MT.
- **Filtro de ícones / "Limpar Ícones"** (declutter): liga/desliga cada camada ou todas de uma vez; a status bar inferior resume o estado.
- **Régua**: cliques sucessivos somam distância (m/km) via `latlng.distanceTo`.
- **Raio de proximidade**: círculo de 2 km centrado no GPS do usuário (ou centro do mapa).
- **GPS**: `navigator.geolocation` com marcador + círculo de precisão.
- **Modal CCTV**: abre a "transmissão" da câmera (imagem estática) com HUD estilo CFTV; câmeras `offline` mostram overlay de manutenção.
- **Tema claro/escuro**: além das variáveis CSS, troca automaticamente o mapa base (OSM/claro ↔ Esri Dark).

---

## 7. Referência das Principais Funções JS

| Função | Papel |
|---|---|
| `initMap()` | Cria o mapa, listeners, renderiza tudo e agenda os timers (60 s clima, 120 s ar, 30 s voos) |
| `renderCameras()` / `renderRadars()` / `renderMarkers()` + `renderPlacesList()` | Aplicam filtros, limpam e reconstroem camada + lista lateral (re-render completo) |
| `setCameraCity/Status`, `setRadarCity/Speed`, `setCategory`, `handleSearch` | Atualizam o estado do filtro e disparam o re-render |
| `focusCamera/Radar/Place(id, lat, lng)` | `flyTo` + abre popup (delay 600 ms) + destaca card; fecha a sidebar no mobile |
| `openCCTVModal(camId)` / `closeCCTVModal()` | Modal do player |
| `fetchLiveWeather()` / `fetchAirQuality()` | Feeds Open-Meteo (com fallback fixo em erro) |
| `initRainViewer()` / `toggleRainRadar()` / `loadRadarFrame()` / `playPauseRadar()` | Radar de chuva animado |
| `refreshFlights()` | OpenSky → fallback `SIMULATED_FLIGHTS` |
| `submitIncident(e)` | Cria marcador **local** de ocorrência em coordenada **aleatória** perto do centro do mapa (ver 9.1) |
| `toggleLayerCategory()` / `toggleAllIcons()` | Sistema de declutter |
| `toggleRuler()` / `addMeasurePoint()` / `clearMeasure()` | Régua |
| `focusRegion(reg, btn)` | Voa para a região e atualiza o clima |
| `toggleTheme()` | Dark mode + troca do mapa base |

---

## 8. Guia de Manutenção (Como Editar)

### Adicionar uma câmera
1. Copie um objeto de `ALL_CAMERAS` (linha ~1557) e ajuste `id` (único), `city` (um dos 7 valores válidos), `lat/lng`, `status`, `type` e textos.
2. Nada mais é necessário — filtros, contadores, pin e card são gerados automaticamente.

### Adicionar um radar
Igual, em `ALL_RADARS` (~1960). `speed` deve ser número; use `city` entre `vg | cuiaba | rodovias | br070 | estaduais`.

### Adicionar um POI
Em `POIS` (~2311). Se criar uma **categoria nova**: adicione a classe CSS `.marker-<categoria>` com a cor, e um `filter-pill` na aba Utilidade (`setCategory('<categoria>', this)`).

### Adicionar uma região de foco rápido
1. Nova entrada em `COORDS` (`chave: [lat, lng, zoom]`).
2. Novo `<button class="quick-region-btn" onclick="focusRegion('chave', this)">` na `.quick-region-bar`.
3. (Opcional) novo `else if` em `focusRegion()` para o clima regional.

### Alterar visual
- Cores/tema: variáveis em `:root` e `[data-theme="dark"]` (linhas 29–63). A cor institucional `#00a859` é a mesma do tema Hoje MT.
- Largura da sidebar: `--sidebar-width: 450px`.
- Breakpoint mobile: `@media (max-width: 900px)` (linha ~1010) — deve casar com o `window.innerWidth <= 900` usado no JS.

### Alterar cadências de atualização
No fim de `initMap()` (linhas ~2580–2582): `setInterval` de clima (60 000 ms), ar (120 000 ms) e voos (30 000 ms).

---

## 9. ⚠️ Análise de Melhores Práticas — Pontos Críticos

Análise honesta do estado atual, em ordem de gravidade. Itens 9.1 são **bloqueantes para publicação em um portal jornalístico**; os demais são melhorias recomendadas.

### 9.1 🔴 Integridade editorial — conteúdo simulado apresentado como real
Este é o risco mais sério do arquivo, especialmente por estar dentro de um **portal de notícias**:

1. **"Câmeras ao vivo" são fotos de banco de imagens.** O modal CCTV exibe imagens estáticas do Unsplash com HUD "**SINAL AO VIVO • CIOSP MT**", carimbo de hora atual e códigos como "CAM-VG-01 // SESP-CIOSP", atribuindo o sinal a órgãos reais (SESP, CIOSP, Vigia Mais MT, PRF, DNIT, Nova Rota do Oeste). Para o leitor, isso é indistinguível de uma transmissão oficial real — o que expõe o portal a dano de credibilidade e a questionamento pelos órgãos citados.
   **Correção mínima:** trocar o selo para "IMAGEM ILUSTRATIVA" / "DEMONSTRAÇÃO" e adicionar um aviso permanente no modal e no rodapé do mapa. **Correção ideal:** integrar feeds reais (quando existirem publicamente) ou remover a simulação de "ao vivo".
2. **Voos simulados sem aviso.** Quando o OpenSky falha (frequente no plano anônimo), o mapa cai silenciosamente em `SIMULATED_FLIGHTS` — 6 voos fictícios com callsigns reais de companhias (AZU, GLO, TAM) exibidos como tráfego ADS-B ao vivo. Adicionar badge "dados simulados" quando o fallback for usado.
3. **Nível do Rio Cuiabá é fixo.** O widget mostra "2,42 m (Estável) / Normal" hardcoded no HTML — nunca muda. Ou integrar uma fonte real (ex.: dados da ANA/CEMADEN) ou rotular como exemplo.
4. **Clima/AQI com fallback fixo.** Em erro de rede, o widget mostra "35°C Ensolarado" e "AQI: 48 (Boa)" como se fossem medições. Preferível exibir "indisponível".
5. **Formulário de ocorrência é enganoso.** `submitIncident()` diz "Alerta publicado com sucesso no mapa estadual!", mas o marcador (a) existe só no navegador de quem enviou, (b) é posicionado em **coordenada aleatória** perto do centro do mapa — não no endereço informado, e (c) some no reload. Rotular como demonstração, ou implementar backend + geocodificação, ou remover.
6. **Perímetro de VG é um polígono ilustrativo** de 13 pontos desenhado à mão, não o limite oficial do IBGE. Para uso real, carregar o GeoJSON da malha municipal do IBGE.

### 9.2 🟠 Segurança
- **XSS via `innerHTML`:** `submitIncident()` injeta `addr` e `desc` (input do usuário) direto em `bindPopup()` sem sanitização. Hoje o impacto é só self-XSS (dados não persistem), mas vira XSS armazenado no dia em que houver backend. Sanitizar/escapar desde já (ex.: `textContent` ou função de escape).
- **SRI ausente no Font Awesome e Google Fonts.** O Leaflet tem `integrity` (✅); o CSS do FA no cdnjs não. Adicionar o hash `integrity` + `crossorigin` (o cdnjs fornece).
- **Links externos:** os `target="_blank"` para o Google Maps devem levar `rel="noopener noreferrer"`.
- **Sem CSP.** Como asset do Ghost, uma meta CSP restringindo `script-src`/`connect-src` aos hosts usados custaria pouco e limitaria bastante o dano de qualquer injeção.

### 9.3 🟡 Performance
- **Arquivo monolítico de 142 KB** sem minificação. Separar em `mapa.css`, `mapa-dados.js` (as 3 bases) e `mapa-app.js` melhora cache, diff em git e manutenção — os dados são o que mais muda.
- **Re-render completo a cada filtro:** cada clique reconstrói todos os markers e todo o HTML das listas (`clearLayers()` + `innerHTML = ''`). Na escala atual (54 itens) é aceitável; se a base crescer (metas do título falam em "todas as câmeras/radares de MT"), migrar para mostrar/ocultar markers já criados e usar `Leaflet.markercluster`.
- **Busca sem debounce:** `handleSearch` re-renderiza a cada tecla. Um debounce de ~150 ms elimina trabalho inútil.
- **Polling de voos a cada 30 s** mesmo com a camada de voos desligada e com a aba em segundo plano. Pausar quando `layerVisibility.flights === false` e usar `document.visibilitychange`.
- Pontos positivos já presentes: `preferCanvas: true`, `keepBuffer: 6`, `updateWhenIdle: true`, preconnect nos CDNs, fontes com `display=swap`.

### 9.4 🟡 Acessibilidade
- **`user-scalable=no` + `maximum-scale=1.0`** no viewport bloqueia zoom por pinça — falha WCAG 1.4.4 e péssimo para leitores idosos. Remover.
- **Modal sem gestão de foco:** não fecha com `Esc`, não prende o foco, não tem `role="dialog"`/`aria-modal`.
- Abas sem `role="tablist"`/`aria-selected`; botões de ícone (tema, régua) sem `aria-label`; contraste de textos `0.66–0.72rem` em cinza deve ser conferido.
- **Handlers inline (`onclick="..."`)** em ~60 elementos: funciona, mas dificulta CSP com `script-src` sem `unsafe-inline` e a manutenção. Migrar gradualmente para `addEventListener` + delegação.

### 9.5 🔵 Manutenibilidade
- **Dados devem sair do HTML:** mover `ALL_CAMERAS`, `ALL_RADARS` e `POIS` para JSON em `assets/js/` (padrão que o tema já usa com `articles-data.js`). Editar dado sem tocar em lógica é o maior ganho de manutenção possível aqui.
- **Duplicação de filtro:** `renderMarkers()` e `renderPlacesList()` repetem o mesmo bloco de filtragem — extrair `getFilteredPOIs()`.
- **Strings soltas:** o tema Hoje MT tem convenção de i18n/strings; o mapa concentra tudo inline. Aceitável para página única em pt-BR, mas documente que o mapa está fora do fluxo de tradução.
- **Seletores frágeis:** `.categories-scroll:first-of-type` / `:last-of-type` quebram se alguém inserir uma terceira linha de pills — preferir IDs.

---

## 10. Checklist de Publicação

Antes de colocar o mapa no ar em produção:

- [ ] **Rotular todo conteúdo simulado** (câmeras, voos fallback, rio, ocorrências) como demonstração/ilustrativo — ver 9.1.
- [ ] Confirmar autorização/adequação do uso dos nomes de órgãos (SESP, CIOSP, Vigia Mais MT, SEMOB, PRF, DNIT, concessionárias) na interface.
- [ ] Validar coordenadas dos pontos em campo ou via imagem de satélite (várias são aproximações).
- [ ] Remover `user-scalable=no` do viewport.
- [ ] Adicionar `rel="noopener noreferrer"` nos `target="_blank"`.
- [ ] Adicionar SRI ao Font Awesome.
- [ ] Testar: GPS dentro do iframe (permissão `allow="geolocation"`), tema claro/escuro, mobile ≤ 900 px (bottom sheet), impressão, e os 7 mapas base.
- [ ] Testar comportamento com rede bloqueada (os 4 feeds em erro) — verificar o que o usuário vê.
- [ ] Verificar volume de tráfego esperado × política de tiles do OSM.

---

## 11. Solução de Problemas (FAQ)

**O botão "Meu GPS" não faz nada.**
O iframe precisa de `allow="geolocation"` (já presente em `custom-mapa-vg.hbs`) **e** o site precisa estar em HTTPS (ou localhost). Em HTTP a Geolocation API é bloqueada pelo navegador.

**A aba de voos mostra sempre os mesmos 6 voos.**
O OpenSky anônimo está rate-limitado ou fora do ar; o mapa caiu no fallback `SIMULATED_FLIGHTS`. Veja o console de rede. Para dados reais consistentes, é preciso conta OpenSky (OAuth) ou outro provedor ADS-B.

**O radar de chuva fica "borrado" ao aproximar.**
Comportamento esperado: os tiles do RainViewer só existem até o zoom 7 (`maxNativeZoom: 7`) e são esticados acima disso.

**Editei o HTML mas o site não mudou.**
O Ghost serve os assets do tema ativo. Reenvie o .zip do tema (produção) ou reinicie o Ghost (dev), e force refresh sem cache (Cmd+Shift+R).

**O tema escuro do mapa não acompanha o do portal.**
Correto — o iframe tem estado próprio (`localStorage.vg_theme`). Para sincronizar seria preciso `postMessage` entre a página Ghost e o iframe (não implementado).

**O contador da status bar diz "Exibindo todos os ícones" mas escondi camadas pela aba.**
A status bar reflete apenas os toggles da barra flutuante (`layerVisibility`), não os filtros das abas (cidade/status/velocidade), que são independentes.

---

*Documentação gerada em 01/09/2026 a partir da análise do arquivo `assets/mapa-varzea-grande.html` (3.600 linhas). Mantenha este documento atualizado ao alterar schemas, APIs ou a integração com o tema.*
