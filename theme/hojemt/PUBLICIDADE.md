# Sistema de Publicidade — LAR & CIA News

O portal exibe banners de publicidade em **três zonas**, gerenciadas
inteiramente dentro do **Ghost Admin** (sem backend extra). Cada anúncio
contratado por uma agência é cadastrado como um **post**.

## Zonas disponíveis

| Zona         | Onde aparece                          | Tamanho ideal | Tag interna           |
|--------------|---------------------------------------|---------------|-----------------------|
| Leaderboard  | Topo de todas as páginas              | 970×90        | `#ad-leaderboard`     |
| No vídeo     | Abaixo do "Ao Vivo" (ao lado do slider)| 300×250      | `#ad-video`           |
| Vertical     | Coluna da home (skyscraper)           | 300×600       | `#ad-vertical`        |
| Retângulo    | Trilho lateral (artigos e editorias)  | 300×250       | `#ad-sidebar`         |
| In-article   | Dentro das matérias / entre editorias | 728×90        | `#ad-inarticle`       |

## Como publicar um banner contratado (passo a passo)

1. No Ghost Admin, vá em **Posts → New post**.
2. **Título**: nome do anunciante ou da campanha (ex.: "Loja X — Junho/2026").
   *(O título não aparece no banner; é só controle interno.)*
3. **Feature image**: faça upload do **banner** da agência (a imagem que será exibida).
4. **Post settings (engrenagem) → Excerpt**: cole a **URL de destino** do clique
   (ex.: `https://anunciante.com.br/promo`). Se ficar vazio, o clique abre o próprio post.
5. **Tags**: adicione **duas** tags:
   - `#ad`  (marca como anúncio — some das listagens de notícia)
   - `#ad-leaderboard` **ou** `#ad-sidebar` **ou** `#ad-inarticle` (a zona)
6. **Publish**. O banner entra no ar na zona escolhida na hora.

> Se houver mais de um anúncio na mesma zona, o tema mostra o mais recente
> (`limit="1"`). Para rodízio, aumente o `limit` no partial `partials/ad.hbs`.

## Encerrar / pausar uma campanha

- **Despublicar** o post (volta para Draft) tira o banner do ar imediatamente.
- Ou **remover a tag de zona** (`#ad-sidebar`, etc.) — o banner deixa de aparecer.

## Banners por UPLOAD direto (sem criar post)

Além das campanhas via post, dá para subir banners fixos direto em
**Settings → Design → Theme** — ideais para permutas, banners da casa ou
campanhas longas. Cada campo tem o upload da imagem e o link do clique:

| Campo no Design        | Onde aparece                                   | Tamanho ideal |
|------------------------|------------------------------------------------|---------------|
| `banner_home` (+link)  | Topo da **CAPA** (home)                        | 970×90        |
| `banner_post` (+link)  | Topo das **MATÉRIAS** e páginas internas       | 970×90        |
| `banner_sidebar` (+link)| Trilho lateral de artigos e editorias         | 300×250 / 300×600 |
| `banner_inarticle` (+link)| Dentro das matérias                         | 728×90        |
| `banner_casa`          | Fallback genérico de todas as zonas (clique → WhatsApp comercial) | 970×90 |

**Ordem de prioridade em cada zona:**
1. Campanha paga ativa (post com `#ad` + tag da zona) — sempre vence;
2. Banner enviado por upload na zona (campos acima);
3. Banner padrão da zona embutido no tema — **Sidebar** e **In-article** exibem o
   banner da **ABACS Cursos Online** (`assets/img/banner-abacs-300x250.png` e
   `assets/img/banner-abacs-728x90.png`, link para a loja virtual da ABACS);
4. `banner_casa` (banner institucional genérico) / cartão "Anuncie aqui" (zonas topo).

> Para trocar o banner padrão da ABACS: substitua os PNGs em `assets/img/` ou
> simplesmente envie outro banner nos campos `banner_sidebar` / `banner_inarticle`
> do Design (o upload tem prioridade sobre o embutido).

> Se o link ficar vazio, o clique abre o WhatsApp comercial da redação
> (`whatsapp_redacao`) com mensagem de interesse em anunciar.

## House ad (quando não há campanha)

Se uma zona não tiver nenhum anúncio ativo, o tema exibe automaticamente um
**"Anuncie aqui"** que leva à página `/anuncie/`. Assim nenhuma zona fica vazia.

## Observações técnicas

- As tags `#ad*` são **internas** (começam com `#`): os posts de anúncio não
  aparecem na home, nas editorias nem no ticker (todas as queries usam `tag:-hash-ad`).
- O link do banner usa `rel="nofollow sponsored noopener"` (boa prática de SEO).
- A página **/anuncie/** traz o mídia kit (formatos, zonas e contato comercial).
