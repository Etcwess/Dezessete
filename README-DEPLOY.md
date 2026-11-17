# Dezessete — deploy

## Arquivos

| Arquivo | O que é |
|---|---|
| `dezessete.html` | O site inteiro (HTML + CSS + JS + cliente Supabase) |
| `vercel.json` | Headers de segurança e rewrites |
| `supabase/schema.sql` | Schema, RLS, triggers e RPCs |
| `supabase/fix-grants-min.sql` | Correção de grants (já executada) |

## Estado atual

- Supabase: schema executado, RLS ativo, RPCs protegidas, Auth por e-mail habilitado.
- Site: refatorado para Supabase, testado com cadastro/evento/RSVP/comentário/logout.
- Vercel: pendente.

## Publicar na Vercel

### Opção A — pelo dashboard (mais fácil)

1. Crie um repositório no GitHub e envie `dezessete.html` e `vercel.json` para a raiz.
2. Acesse <https://vercel.com/new> e importe esse repositório.
3. Framework: **Other**. Build command: vazio. Output directory: `.` (raiz).
4. Clique em **Deploy**.
5. Em **Settings → Domains**, adicione seu domínio se quiser.

### Opção B — pela CLI

```bash
npm i -g vercel
cd "C:\Users\MARIA SAMPAIO\OneDrive\Documentos\Projeto Padrão"
vercel --prod
```

## Depois do deploy

1. Abra a URL da Vercel e teste cadastro + login.
2. Em **Supabase → Authentication → URL Configuration**, adicione a URL da Vercel em:
   - **Site URL**
   - **Redirect URLs** (inclua `https://dez17.vercel.app/**`)
3. Se usar domínio próprio, configure o DNS conforme instruído pela Vercel.

## Configuração sensível

Não há variáveis de ambiente obrigatórias: a URL do Supabase e a chave `sb_publishable_...` são públicas e já estão no HTML. A chave `sb_secret_...` **não** deve ser usada no frontend nem configurada na Vercel.

Se precisar trocar a chave pública, edite no topo do `<script>` em `dezessete.html`:

```js
const SUPABASE_URL='https://mlxgfkhtezlccxkohhlo.supabase.co';
const SUPABASE_KEY='sb_publishable_...';
```

## Limpeza recomendada

Apagar a conta de teste criada durante a validação:
Supabase → Authentication → Users → `teste1794941952292@exemplo.com` → Delete.

Também rotacionar a chave secreta que foi colada na conversa:
Supabase → Settings → API → Rotate secret key.
