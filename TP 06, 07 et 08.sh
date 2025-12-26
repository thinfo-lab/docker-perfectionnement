#!/usr/bin/env bash
# ============================================================
#  DOCKER AVANCÉ - TP06 + TP07 + TP08 (PENSE-BÊTE COPY/PASTE)
#  Formateur: Halim BOUHOUI
#  OS: Debian (CLI)
# ============================================================

# ------------------------------------------------------------
# OBJECTIFS TP06 (Gouvernance type DTR/RBAC)
#  - Mettre en place une registry “enterprise-like” avec RBAC (équivalent DTR)
#  - Créer projets / utilisateurs / rôles (push/pull contrôlés)
#  - Tester les droits (pull OK / push refusé)
#
# OBJECTIFS TP07 (Docker Machine)
#  - Provisionner / gérer des hôtes Docker distants via SSH
#  - Basculer de contexte (eval env) et exécuter des commandes à distance
#  - Automatiser le cycle de vie (create / ls / ssh / rm)
#
# OBJECTIFS TP08 (Docker Swarm - orchestration avancée)
#  - Déployer services (replicas), réseaux overlay, publication (ingress)
#  - Rolling update / rollback
#  - Secrets + configs
#  - Placement constraints + drain + haute dispo (test panne)
# ------------------------------------------------------------

# -----------------------------
# VARIABLES (COMMUNES)
# -----------------------------
# IPs (adapte si besoin)
MGR_IP="192.168.1.1"     # VM01
WRK1_IP="192.168.1.2"    # VM02
WRK2_IP="192.168.1.3"    # VM03

# Registry (déjà utilisé TP05). A faire sur les 3 vm's.

echo 'export REG_HOST="registry.local" REG_PORT="5000" REG_FQDN="registry.local:5000"' | tee /etc/profile.d/registry.sh >/dev/null

# ------------------------------------------------------------
# PRÉ-REQUIS (VM01/VM02/VM03) : docker + curl + openssl + jq
# ------------------------------------------------------------
# VM01/VM02/VM03 - paquets utiles
sudo apt-get update
sudo apt-get install -y docker.io ca-certificates curl openssl jq

# VM01/VM02/VM03 - démarrage docker
sudo systemctl enable --now docker

# ============================================================
# ========================= TP06 =============================
#  Gouvernance des images avec RBAC (RBAC = Role-Based Access Control) (équivalent DTR via Harbor)
#  NOTE: Docker Trusted Registry (DTR) est un produit Enterprise.
#        En TP, on reproduit la gouvernance (RBAC) avec Harbor.
#Harbor est une registry Docker/OCI d’entreprise avec des fonctionnalités de sécurité avancées
#Harbor = Docker Registry + sécurité + RBAC + scan + audit. Harbor utilise Trivy (scan d'image).
# ============================================================

# -----------------------------
# TP06.1 - Installation Harbor (VM01)
# -----------------------------
# VM01 - dossier de travail
mkdir -p /opt/tp06-harbor
cd /opt/tp06-harbor

# VM01 - télécharger l’installeur offline Harbor (version stable à adapter si besoin)
# (si vous voulez figer une version, remplace "vX.Y.Z" par la version choisie)
# Exemple: v2.10.0 => https://github.com/goharbor/harbor/releases/download/v2.10.0/harbor-offline-installer-v2.10.0.tgz
# Ici on récupère la “latest” n’existe pas toujours, donc à fixer si besoin.
# 
HARBOR_VER="2.10.0"
curl -fsSL -o harbor.tgz "https://github.com/goharbor/harbor/releases/download/v${HARBOR_VER}/harbor-offline-installer-v${HARBOR_VER}.tgz"

# VM01 - extraire
tar -xzf harbor.tgz
cd harbor

# VM01 - générer une conf simple en HTTP (TP) (pour prod: TLS + FQDN)
cp -f harbor.yml.tmpl harbor.yml

# VM01 - définir hostname (ici IP manager pour lab)
# (Harbor préfère un hostname stable; en lab on utilise l’IP)
sed -i "s/^hostname: .*/hostname: ${MGR_IP}/" harbor.yml

# VM01 - définir le mot de passe admin
sed -i 's/^harbor_admin_password: .*/harbor_admin_password: Harbor@2025!/' harbor.yml

# VM01 - désactiver https (lab)
sed -i "s/^https:$/# https:/" harbor.yml
sed -i "s/^[[:space:]]*port: 443/#  port: 443/" harbor.yml
sed -i "s/^[[:space:]]*certificate: .*$/#  certificate: /" harbor.yml
sed -i "s/^[[:space:]]*private_key: .*$/#  private_key: /" harbor.yml


#Installation docker-compose nécissaire pour Hardor
apt-get remove -y docker-buildx
apt-get -f install -y

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg


echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian trixie stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt-get install -y docker-buildx-plugin docker-compose-plugin

ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

docker buildx version
docker compose version
docker-compose version


# VM01 - installer (utilise docker compose interne)
sudo ./install.sh

# VM01 - vérifier que Harbor est up
sudo docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | sed -n '1,20p'

# -----------------------------
# TP06.2 - Accès UI + tests RBAC
# -----------------------------
# NOTE POUR LES ÉTUDIANTS:
#  - Ouvrir : http://MGR_IP  (ex: http://192.168.1.1)
#  - Login admin / Harbor@2025!
#  - Créer un projet "dev" (Public: OFF = privé)
#  - Créer un user "dev1" (role: Developer sur projet dev) => allez dans projet dev => member => ajoutez dev1 en tant que developper.
#  - Créer un user "reader1" (role: Guest/Reader sur projet dev)

# VM01 - test API Harbor (doit répondre 200/401 selon endpoint)
curl -sS "http://${MGR_IP}/api/v2.0/health" | head -c 200; echo

# -----------------------------
# TP06.3 - Push/Pull contrôlés (VM02)
# -----------------------------
# VM02 - login Harbor en tant que dev1 (créé via UI)
# (Harbor en HTTP: Docker refuse parfois sans config, on force “insecure registry” en lab)
# VM02 - config daemon pour autoriser insecure registry vers MGR_IP
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "insecure-registries": ["192.168.1.1"]
}
EOF

# VM02 - restart docker
sudo systemctl restart docker

# VM02 - login (remplace mot de passe dev1)
docker login 192.168.1.1 -u dev1 -p 'Harbor@2025!'

# VM02 - créer une image test
mkdir -p /tmp/tp06 && cd /tmp/tp06
cat > Dockerfile <<'EOF'
FROM alpine:3.20
CMD ["sh","-c","echo TP06 OK; uname -a; sleep 2"]
EOF

# VM02 - build
docker build -t tp06-img:1.0 .

# VM02 - tag vers Harbor projet dev (format: <registry>/<project>/<repo>:tag)
docker tag tp06-img:1.0 "192.168.1.1/dev/tp06-img:1.0"

# VM02 - push (dev1 doit avoir le droit)
docker push "192.168.1.1/dev/tp06-img:1.0"

#VM02 - afficher le projet sur le dépot distant via les droits du user dev1

curl -sS -u dev1:'Harbor@2025!' \
  http://192.168.1.1/v2/dev/tp06-img/tags/list

#Identifier le registry sur lequel on est connecté
jq '.auths | keys' ~/.docker/config.json


# VM02 - pull test
docker rmi "${MGR_IP}/dev/tp06-img:1.0" || true # supprime l'mage localmeent
docker pull "${MGR_IP}/dev/tp06-img:1.0" # pull de l'image a partir du registry

# VM02 - exécuter
docker run --rm "${MGR_IP}/dev/tp06-img:1.0"

# VM02 - test RBAC: login en reader1 puis tentative push (doit échouer)

cat ~/.docker/config.json  ## identification du registry sur lequel on est connecter.
echo 'ZGV2MTpIYXJib3JAMjAyNSE=' | base64 -d    # decodage de l'identité du user. 

docker logout "${MGR_IP}"
docker login 192.168.1.1 -u reader1 -p 'Harbor@2025!'
docker push "${MGR_IP}/dev/tp06-img:1.0" || true


# ============================================================
# ========================= TP07 =============================
#  Docker Machine (gestion d’hôtes distants via SSH)
#  NOTE: Docker Machine est legacy, mais utile pédagogiquement.
# ============================================================

# -----------------------------
# TP07.1 - Installation docker-machine (VM01)
# -----------------------------
# VM01 - télécharger binaire docker-machine
sudo curl -fsSL -o /usr/local/bin/docker-machine \
  "https://github.com/docker/machine/releases/download/v0.16.2/docker-machine-$(uname -s)-$(uname -m)"

# VM01 - droits d’exécution
sudo chmod +x /usr/local/bin/docker-machine

# VM01 - vérifier version
docker-machine --version

# -----------------------------
# TP07.2 - Pré-requis SSH (VM02/VM03)
# -----------------------------
# VM02/VM03 - installer ssh serveur si absent
sudo apt-get install -y openssh-server

# VM02/VM03 - activer ssh
sudo systemctl enable --now ssh

# VM01 - générer une clé SSH (si non existante)
test -f ~/.ssh/id_rsa || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

# VM01 - copier la clé sur VM02/VM03 (adapter user si besoin)
ssh-copy-id -o StrictHostKeyChecking=no root@"${WRK1_IP}"
ssh-copy-id -o StrictHostKeyChecking=no root@"${WRK2_IP}"

# -----------------------------
# TP07.3 - Créer des machines “generic” (VM01 -> VM02/VM03)
# -----------------------------

#sur vm02 et vm03. purge d'un env docker existant

# Config Docker
rm -rf /etc/docker

# Overrides systemd (CAUSE PRINCIPALE DES BUGS)
rm -rf /etc/systemd/system/docker.service.d
rm -f /etc/systemd/system/docker.service
rm -f /etc/systemd/system/docker.socket

# Données Docker
rm -rf /var/lib/docker
rm -rf /var/lib/containerd

# Socket runtime
rm -f /var/run/docker.sock

# Reload systemd (important)
systemctl daemon-reexec
systemctl daemon-reload

#Vérification
dpkg -l | egrep 'docker|containerd|runc' || echo "OK: aucun paquet Docker"



# VM01 - créer machine wrk1 via driver generic (utilise SSH). dm-wrk1 Un objet logique local créé par docker-machine a qui on associe ip wrk1, certicat etc ...

docker-machine create -d generic \
  --generic-ip-address="${WRK1_IP}" \
  --generic-ssh-user=root \
  dm-wrk1

# VM01 - créer machine wrk2 via driver generic
docker-machine create -d generic \
  --generic-ip-address="${WRK2_IP}" \
  --generic-ssh-user=root \
  dm-wrk2

# VM01 - lister
docker-machine ls  #normale pour le non affichage de la version docker serveur.
docker-machine ssh dm-wrk1 "docker version"

# VM01 - basculer contexte sur dm-wrk1
eval "$(docker-machine env dm-wrk1)"
docker info | egrep -i 'Name:|NodeID:|Server Version:|Docker Root Dir:'

# VM01 - vérifier qu’on parle au Docker de VM02
docker info | sed -n '1,25p'

# VM01 - lancer un conteneur sur VM02 via le contexte docker-machine
docker run --rm alpine:3.20 sh -c 'echo "TP07 OK sur dm-wrk1"; hostname; ip a | head'

# VM01 - basculer sur dm-wrk2 (VM03)
eval "$(docker-machine env dm-wrk2)"
docker run --rm alpine:3.20 sh -c 'echo "TP07 OK sur dm-wrk2"; hostname; ip a | head'

# VM01 - revenir en local (désactiver env)
eval "$(docker-machine env -u)"

# VM01 - ssh via docker-machine
docker-machine ssh dm-wrk1 'docker ps'

# VM01 - nettoyage (si besoin)
# docker-machine rm -f dm-wrk1 dm-wrk2


# ============================================================
# ========================= TP08 =============================
#  Orchestration avec Docker Swarm (avancé)
# ============================================================

# -----------------------------
# TP08.1 - Init Swarm (VM01)
# -----------------------------
# VM01 - s’assurer qu’on a l’IP manager dans la variable
MGR_IP="$(ip -4 -o addr show | awk '/192\.168\.1\./{print $4}' | head -n1 | cut -d/ -f1)"
echo "$MGR_IP"

# VM01 - init swarm
docker swarm init --advertise-addr "${MGR_IP}" || true

# VM01 - récupérer tokens (manager/worker)
docker swarm join-token worker
docker swarm join-token manager

# -----------------------------
# TP08.2 - Join workers (VM02/VM03)
# -----------------------------
# VM01 - stocker token worker
WRK_TOKEN="$(docker swarm join-token -q worker)"
echo "$WRK_TOKEN"

# VM02 - joindre le cluster (à exécuter sur VM02)
# docker swarm join --token <WRK_TOKEN> <MGR_IP>:2377

# VM03 - joindre le cluster (à exécuter sur VM03)
# docker swarm join --token <WRK_TOKEN> <MGR_IP>:2377

# VM01 - vérifier nœuds
docker node ls

# -----------------------------
# TP08.3 - Réseau overlay + service web (VM01)
# -----------------------------
# VM01 - créer un réseau overlay attachable (tests avec docker run)
docker network create -d overlay --attachable net_tp08_overlay || true

# VM01 - déployer un service nginx en replicas=3
docker service create \
  --name web_tp08 \
  --replicas 3 \
  --network net_tp08_overlay \
  --publish published=8088,target=80 \
  nginx:alpine

# VM01 - vérifier services
docker service ls
docker service ps web_tp08

# VM01 - tester accès (ingress routing mesh)
curl -sS "http://${MGR_IP}:8088" | head -n 5

# -----------------------------
# TP08.4 - Rolling update + rollback (VM01)
# -----------------------------
# VM01 - update image (rolling)
docker service update --image nginx:1.27-alpine --update-parallelism 1 --update-delay 5s web_tp08

# VM01 - suivre rollout
docker service ps web_tp08

# VM01 - rollback si souci
# docker service rollback web_tp08

# -----------------------------
# TP08.5 - Placement constraints + drain manager (VM01)
# -----------------------------
# VM01 - éviter d’exécuter les workloads sur le manager (bonne pratique prod)
docker node update --availability drain vm01

# VM01 - forcer le service à ne tourner que sur workers
docker service update --constraint-add 'node.role==worker' web_tp08

# VM01 - vérifier placement
docker service ps web_tp08

# -----------------------------
# TP08.6 - Secrets + Configs (VM01)
# -----------------------------
# VM01 - créer un secret
printf 'DB_PASS=SwarmSecret@2025!\n' | docker secret create tp08_db_pass -

# VM01 - créer une config
printf 'APP_ENV=prod\nAPP_NAME=tp08\n' | docker config create tp08_app_env -

# VM01 - déployer un service qui lit secret+config
docker service create \
  --name app_tp08 \
  --replicas 2 \
  --config source=tp08_app_env,target=/etc/app.env \
  --secret source=tp08_db_pass,target=db_pass.txt \
  alpine:3.20 \
  sh -c 'echo "===CONFIG==="; cat /etc/app.env; echo "===SECRET==="; cat /run/secrets/db_pass.txt; sleep 3600'

# VM01 - logs service
docker service logs --tail 50 app_tp08

# -----------------------------
# TP08.7 - Test résilience (panne d’un worker)
# -----------------------------
# VM01 - repérer où tournent les tasks
docker service ps web_tp08

# VM02 - simuler panne docker (à exécuter sur VM02)
# sudo systemctl stop docker

# VM01 - constater rescheduling (tasks déplacées sur VM03)
docker service ps web_tp08

# VM02 - remettre docker (à exécuter sur VM02)
# sudo systemctl start docker

# -----------------------------
# TP08.8 - Nettoyage (VM01)
# -----------------------------
# VM01 - supprimer services
# docker service rm web_tp08 app_tp08

# VM01 - supprimer secret/config
# docker secret rm tp08_db_pass
# docker config rm tp08_app_env

# VM01 - supprimer réseau overlay
# docker network rm net_tp08_overlay

echo "TP06 + TP07 + TP08 terminés."
