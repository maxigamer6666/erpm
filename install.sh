#!/bin/bash

# Verifica si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root."
  exit 1
fi

# Configuración inicial
IP_ADDRESS="192.168.8.100"
GATEWAY="192.168.8.1"
DNS="8.8.8.8"
DOMAIN="program.com"
SUBDOMAIN="www.erpm"
HOSTNAME="server"

# Configurar IP estática
echo "Configurando IP estática..."
cat <<EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    enp0s3:
      addresses:
        - $IP_ADDRESS/24
      gateway4: $GATEWAY
      nameservers:
        addresses:
          - $DNS
EOF
netplan apply

# Cambiar hostname
echo "$HOSTNAME" > /etc/hostname
hostnamectl set-hostname "$HOSTNAME"

# Actualizar repositorios
echo "Actualizando repositorios..."
apt update -y && apt upgrade -y

# Instalar y configurar SSH
echo "Instalando y configurando SSH..."
apt install -y openssh-server
systemctl enable ssh
systemctl start ssh

# Instalar y configurar Apache2
echo "Instalando Apache2..."
apt install -y apache2
systemctl enable apache2
systemctl start apache2

# Crear un VirtualHost para Apache
echo "Configurando Apache para $SUBDOMAIN.$DOMAIN..."
mkdir -p /var/www/$SUBDOMAIN.$DOMAIN
echo "<h1>Bienvenido a $SUBDOMAIN.$DOMAIN</h1>" > /var/www/$SUBDOMAIN.$DOMAIN/index.html

cat <<EOF > /etc/apache2/sites-available/$SUBDOMAIN.$DOMAIN.conf
<VirtualHost *:80>
    ServerName $SUBDOMAIN.$DOMAIN
    DocumentRoot /var/www/$SUBDOMAIN.$DOMAIN

    <Directory /var/www/$SUBDOMAIN.$DOMAIN>
        AllowOverride All
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/$SUBDOMAIN.$DOMAIN-error.log
    CustomLog ${APACHE_LOG_DIR}/$SUBDOMAIN.$DOMAIN-access.log combined
</VirtualHost>
EOF

a2ensite $SUBDOMAIN.$DOMAIN.conf
systemctl reload apache2

# Instalar y configurar BIND9
echo "Instalando BIND9..."
apt install -y bind9

echo "Configurando BIND9 para $DOMAIN..."
mkdir -p /etc/bind/zones

# Archivo de zona para el dominio
cat <<EOF > /etc/bind/zones/db.$DOMAIN
\$TTL    604800
@       IN      SOA     ns.$DOMAIN. admin.$DOMAIN. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMAIN.
ns      IN      A       $IP_ADDRESS
$SUBDOMAIN IN    A       $IP_ADDRESS
EOF

# Configurar la zona en named.conf.local
cat <<EOF >> /etc/bind/named.conf.local
zone "$DOMAIN" {
    type master;
    file "/etc/bind/zones/db.$DOMAIN";
};
EOF

# Configurar opciones de BIND
sed -i "s/\/\/ listen-on-v6 { any; };/listen-on-v6 { none; };/" /etc/bind/named.conf.options
sed -i "s/allow-query { localhost; };/allow-query { any; };/" /etc/bind/named.conf.options

# Reiniciar BIND
echo "Reiniciando BIND9..."
systemctl restart bind9

# Verificar configuración
echo "Verificando configuración..."
named-checkconf
named-checkzone $DOMAIN /etc/bind/zones/db.$DOMAIN

echo "¡Servidor configurado exitosamente!"
echo "Detalles de configuración:"
echo " - IP estática: $IP_ADDRESS"
echo " - Dominio local: $SUBDOMAIN.$DOMAIN"
echo " - Apache está en ejecución."
echo " - BIND9 está configurado y activo."
