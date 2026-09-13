# Landing do TokenBar

Página estática servida pelo Caddy, pensada para o Railway. O instalador é servido
**pelo próprio container** — não depende de Release do GitHub, então funciona igual com
o repositório privado.

```
landing/
  index.html      a página inteira (HTML, CSS e JS num arquivo só)
  icon.svg        o ícone do app em vetor
  versions.json   lista de versões e changelog — alimenta o download e a seção Novidades
  download/       o .zip da versão atual, embarcado na imagem
  sync.sh         embarca o instalador e registra a versão no versions.json
  Caddyfile       servidor; escuta em $PORT
  Dockerfile      imagem final
```

## Publicar uma versão nova

```bash
./version.sh minor          # na raiz: sobe a versão, commita e cria a tag
./landing/sync.sh           # embarca o instalador e registra no versions.json
git push origin main --follow-tags
```

O Railway reconstrói sozinho ao receber o push. As notas de cada versão ficam em
`versions.json` — o `sync.sh` preserva o que já estiver escrito ali, então dá para editar
o texto à mão sem medo de perder no próximo sync.

## Configuração no Railway

Ao criar o serviço a partir deste repositório:

| Campo | Valor |
|---|---|
| Root Directory | *(deixe vazio)* |
| Dockerfile Path | `landing/Dockerfile` |

O `Root Directory` precisa ficar vazio porque os `COPY` do Dockerfile partem da raiz do
repositório — é o que permite a imagem enxergar `landing/` e, se um dia for preciso,
qualquer outro arquivo do projeto. Se você definir `landing` como root, os `COPY` precisam
perder o prefixo `landing/`.

Não há variável de ambiente a configurar: o Caddy lê a `PORT` que o Railway injeta.

## Rodar local

```bash
DOCKER_BUILDKIT=0 docker build -f landing/Dockerfile -t tokenbar-landing .
docker run --rm -p 8099:8080 -e PORT=8080 tokenbar-landing
```

Abra <http://localhost:8099>.

O build falha de propósito em dois casos, para não subir uma página quebrada: se o
`Caddyfile` tiver erro de sintaxe, e se não houver nenhum `.zip` em `landing/download/`
— uma landing de download sem o arquivo é pior do que nenhuma.
