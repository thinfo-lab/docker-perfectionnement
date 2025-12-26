#!/bin/bash

# --- Configuration ---
PROJECT_DIR="mon_site_wordpress"
DB_PASSWORD="Harbor@2025!" # Changez-le !

echo "Préparation du déploiement WordPress..."

# 1. Création des dossiers sur la machine physique
# Ces dossiers seront mappés à l'intérieur des containers
mkdir -p $PROJECT_DIR/wp_data
mkdir -p $PROJECT_DIR/db_data

cd $PROJECT_DIR

sudo apt update
sudo apt install ca-certificates curl gnupg
sudo apt install docker-compose-plugin
docker compose version

# 2. Création du fichier docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  db:
    image: mariadb:10.6
    container_name: wp_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $DB_PASSWORD
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wp_user
      MYSQL_PASSWORD: $DB_PASSWORD
    volumes:
      - ./db_data:/var/lib/mysql

  wordpress:
    image: wordpress:latest
    container_name: wp_app
    restart: always
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wp_user
      WORDPRESS_DB_PASSWORD: $DB_PASSWORD
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./wp_data:/var/www/html
    depends_on:
      - db

EOF

# 3. Lancement du déploiement
echo "Lancement des containers Docker..."
docker-compose up -d

# 4. Test du Bind Mount (Tes lignes intégrées)
echo "==[6/8] Test bind mount : création d'une page phpinfo() depuis l'hôte =="
echo '<?php phpinfo(); ?>' > "${WP_DIR}/info.php"

echo "OK: ${WP_DIR}/info.php créé"

echo "WordPress est en cours d'exécution !"
echo "Accès au site : http://localhost:8080"
echo "Tes fichiers sont ici : $(pwd)/wp_data"