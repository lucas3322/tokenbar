# Landing do TokenBar — HTML estático servido pelo Caddy.
#
# ATENÇÃO AO CONTEXTO: os caminhos partem da **raiz do repositório**, não de
# `landing/`. É assim que o Railway constrói quando se aponta "Dockerfile Path"
# para /landing/Dockerfile sem definir "Root Directory". Se um dia o Root
# Directory virar `landing`, estes COPY precisam perder o prefixo.
FROM caddy:2-alpine

COPY landing/Caddyfile /etc/caddy/Caddyfile
COPY landing/index.html landing/icon.svg landing/versions.json /srv/
COPY landing/download/ /srv/download/

# Falha o build se o Caddyfile tiver erro de sintaxe, em vez de subir quebrado.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# Falha o build se o instalador não foi embarcado — uma landing de download
# sem o arquivo é pior do que nenhuma.
RUN test -n "$(ls /srv/download/*.zip 2>/dev/null)" || \
    (echo 'ERRO: nenhum .zip em landing/download/. Rode ./landing/sync.sh antes.' && exit 1)

EXPOSE 8080
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
