#!/bin/bash
set -euo pipefail

echo "================================================="
echo "   SIMET EDUCAÇÃO CONECTADA - INSTALAÇÃO LIMPA   "
echo "================================================="

### 1. Detectar INEP
INEP=$(hostname | grep -oE '[0-9]{8}' | head -1 || true)

if [[ -z "$INEP" ]]; then
  echo "ERRO: INEP não encontrado no hostname"
  exit 1
fi

echo "[1/16] INEP detectado: $INEP"

### 2. Parar serviços
echo "[2/16] Parando serviços..."
systemctl stop simet-ma simet-lmapd 2>/dev/null || true

sleep 2

### 3. Remover pacotes antigos
echo "[3/16] Removendo pacotes antigos..."
dpkg --remove --force-remove-reinstreq simet-ma-mec simet-ma simet-lmapd 2>/dev/null || true

### 4. Remover usuário antigo
echo "[4/16] Removendo usuário..."
deluser --remove-home nicbr-simet 2>/dev/null || true

### 5. Limpeza de arquivos
echo "[5/16] Limpando sistema..."
rm -rf /opt/simet /etc/simet* /var/simet /var/lock/simet 2>/dev/null || true

### 6. Dependências básicas
echo "[6/16] Instalando dependências..."
apt-get update -qq
apt-get install -y wget curl expect file

### 7. Diretório temporário
cd /tmp
rm -f m1.run

### 8. Download dependência (libjson-c)
echo "[7/16] Baixando libjson-c..."
wget -q http://ftp.de.debian.org/debian/pool/main/j/json-c/libjson-c5_0.15-2+deb11u1_arm64.deb -O /tmp/libjson.deb || true
dpkg -i /tmp/libjson.deb 2>/dev/null || true

### 9. Download instalador SIMET
echo "[8/16] Baixando instalador SIMET..."

wget -q https://download.simet.nic.br/medidores/educ-conectada/linux/MedidorEducacaoConectada-linux.run -O m1.run \
  || wget -q https://raw.githubusercontent.com/amarquesjp/Simet/main/m1.run -O m1.run

chmod +x m1.run

### 10. Verificação do arquivo
echo "[9/16] Verificando instalador..."
file m1.run || true

### 11. Preparar ambiente
export TMPDIR=/var/tmp

### 12. Instalar expect (caso necessário)
echo "[10/16] Garantindo expect..."
apt-get install -y expect

### 13. Execução automatizada do instalador
echo "[11/16] Executando instalador (modo automático)..."

printf "%s\n%s\n" "$INEP" "yes" | /tmp/m1.run

### 14. Corrigir pacotes quebrados
echo "[12/16] Corrigindo dpkg..."
dpkg --configure -a 2>/dev/null || true

### 15. Estrutura final
echo "[13/16] Ajustando permissões..."
mkdir -p /var/lock/simet /var/simet
chown -R nicbr-simet:nicbr-simet /var/lock/simet /var/simet 2>/dev/null || true

su -s /bin/bash - nicbr-simet -c '/opt/simet/bin/simet_register_ma.sh --boot' 2>/dev/null || true

cp /opt/simet/etc/simet/agent-id-v2 /opt/simet/etc/simet/agent-v2.jwt /var/simet/ 2>/dev/null || true
chown nicbr-simet:nicbr-simet /var/simet/* 2>/dev/null || true

### 16. Cron + serviços + teste final
echo "[14/16] Configurando cron..."

cat > /etc/cron.d/simet-keepalive <<EOF2
*/15 * * * * root mkdir -p /var/simet && chown nicbr-simet:nicbr-simet /var/simet; \
if [ -f /opt/simet/etc/simet/agent-id-v2 ]; then \
cp /opt/simet/etc/simet/agent-id-v2 /opt/simet/etc/simet/agent-v2.jwt /var/simet/ 2>/dev/null; \
chown nicbr-simet:nicbr-simet /var/simet/* 2>/dev/null; fi; \
systemctl is-active --quiet simet-ma || systemctl restart simet-ma; \
systemctl is-active --quiet simet-lmapd || systemctl restart simet-lmapd
EOF2

cat > /etc/cron.d/simet-medicao <<EOF3
0 */4 * * * nicbr-simet /opt/simet/bin/simet-ma_run.sh
EOF3

echo "[15/16] Reiniciando serviços..."
systemctl restart simet-ma simet-lmapd 2>/dev/null || true

sleep 10

echo "[16/16] Status final:"
systemctl is-active simet-ma || true
systemctl is-active simet-lmapd || true

echo ""
echo "RESULTADO:"
su -s /bin/bash - nicbr-simet -c '/opt/simet/bin/simet-ma_run.sh && /opt/simet/bin/simet_view_results.sh --url' 2>/dev/null || true

echo "================================================="
echo "INSTALAÇÃO CONCLUÍDA"
echo "================================================="
