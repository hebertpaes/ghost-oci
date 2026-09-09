# Eleições 2026 — Apuração 1º e 2º Turno
**Página:** `https://hojemt.com.br/apuracao-2026/` • **Arquivos:** `assets/apuracao-2026.html`, `custom-apuracao-2026.hbs`, `partials/eleicoes.hbs`

## O que foi criado

### 1. Central de Apuração (`/apuracao-2026/`)
Página dedicada (mesmo padrão do mapa: template + iframe) com:
- **1º turno — 4 de outubro de 2026** e **2º turno — 25 de outubro de 2026** (cards clicáveis com contagem regressiva → votação em andamento → apuração ao vivo → concluído);
- **Presidente** (Brasil), **Governador** e **Senador** por estado — as 26 UFs + **Distrito Federal** (seletor, padrão Mato Grosso, lembrado no navegador);
- Aba **Municípios**: explica que em 2026 não há eleição municipal (próxima: 2028) e leva à consulta por município no TSE;
- Barras de resultado por candidato (nº, nome, coligação, %, votos, selo Eleito/2º turno), % de seções totalizadas, votos válidos/brancos/nulos, carimbo de data/hora do TSE;
- Tema claro/escuro **sincronizado com o portal** (mesma chave `hojemt_theme`).

### 2. Fonte de dados: TSE oficial (zero dados inventados)
- Os resultados vêm de `resultados.tse.jus.br` (CORS liberado, sem chave), atualizados a cada 60 s durante a apuração.
- **Auto-descoberta de códigos:** o TSE só publica os códigos das eleições de 2026 no `ele-c.json` perto do pleito (hoje o arquivo ainda aponta o ciclo 2024). A página consulta esse config e detecta sozinha os códigos do 1º/2º turno (federal e estaduais) quando saírem. Se precisar forçar manualmente, edite o objeto `TSE.override` no topo do script em `assets/apuracao-2026.html`.
- Antes da apuração, a página mostra contagem regressiva e aviso "aguardando divulgação oficial" — **nunca números simulados**.

### 3. Faixa na capa
`partials/eleicoes.hbs` exibe na home uma faixa com contagem regressiva dinâmica (muda para "votação em andamento" e "APURAÇÃO AO VIVO" nos dias certos) linkando para `/apuracao-2026/`. Liga/desliga em **Settings → Design → Theme → `eleicoes_ativa`**.

### 4. Aba 📊 Pesquisas — só registradas no TSE
A central tem uma aba de **pesquisas eleitorais** com regras aplicadas pelo próprio código:
- **Só publica pesquisa com nº de registro no TSE** (campo `registroTSE`); sem ele, a pesquisa não aparece (fica um aviso no console).
- **Escopo: Brasil e Mato Grosso.** Pesquisa de outro estado só aparece com `extraordinaria: true` **e** justificativa em `notaExtraordinaria` (exibida no card).
- O **rodapé legal** (Lei 9.504/97, art. 33) é montado automaticamente: registro, contratante, instituto, período, entrevistados, margem de erro e nível de confiança.
- Card com selo "✔ Registro TSE", barras por cenário e link para a divulgação oficial.

**Como cadastrar uma pesquisa:** edite `assets/js/pesquisas-2026.js` — o modelo completo de preenchimento está comentado no topo do arquivo. Confira os dados no registro público do TSE (PesqEle: https://apps.tse.jus.br/pesqele-consulta/) antes de publicar. O painel nunca inventa nem importa números sozinho: a divulgação é uma decisão editorial.

## Como publicar a página no Ghost Admin
1. **Posts → New post** (o template usa `{{#post}}`), título "Apuração Eleições 2026".
2. Painel ⚙️ → **Post URL**: `apuracao-2026` → **Template**: `custom-apuracao-2026`.
3. Publish. (O menu do site já pode apontar para `/apuracao-2026/`.)

## Como testar
1. Abra `/apuracao-2026/`: deve mostrar a contagem regressiva para 04/10/2026.
2. Troque cargo para Governador/Senador → aparece o seletor de UF (padrão MT).
3. Alterne o tema escuro no portal → a página acompanha.
4. No dia da eleição, após as 17h (Brasília), a apuração começa a preencher sozinha.

## Datas e regras (referência)
- 1º turno: **04/10/2026**, 2º turno: **25/10/2026**, votação 8h–17h (horário de Brasília).
- Cargos 2026: Presidente, Governador, Senador (2/3 das vagas), Dep. Federal, Dep. Estadual/Distrital. Os proporcionais (deputados) não são exibidos em barras — consulta no TSE.
- Municípios: próximas eleições municipais em outubro de **2028**; o DF não possui municípios.
