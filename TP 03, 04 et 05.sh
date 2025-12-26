#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OBJECTIFS + CONCEPTS À ÉTUDIER
# ============================================================
# TP03 (Swarm / Multi-nœuds)
# - Concepts: manager/worker, Raft, service vs conteneur, overlay network, routing mesh, rescheduling
# - Validations: node ls, service ps, curl sur port publié, DNS interne (nom du service), drain/reschedule
#
# TP04 (Docker Content Trust - DCT)
# - Concepts: image signée/non signée, metadata de confiance, enforcement côté client
# - Validations: pull échoue si non signé (DCT=1), push+pull OK après signature
#
# TP05 (Registry privée sécurisée)
# - Concepts: registry v2, TLS (CA + cert serveur + SAN), auth htpasswd, trust CA côté clients
# - Validations: /v2/ en HTTPS, login OK, push/pull OK, catalogue _catalog accessible avec auth
# ============================================================

# --- Variables (adapter si besoin) ---
# IP du manager Swarm
MGR_IP="192.168.1.1"
# IP workers (si 2 workers)
WRK1_IP="192.168.1.2"
WRK2_IP="192.168.1.3"

# sur les 3 vm's
# Nom DNS de la registry (DNS ou /etc/hosts)
echo 'export REG_HOST="registry.local" REG_PORT="5000" REG_FQDN="registry.local:5000"' >> /etc/profile.d/registry.sh
source /etc/profile.d/registry.sh
echo "$REG_HOST $REG_PORT $REG_FQDN"

# Répertoires sur VM01 (registry)
echo 'export REG_DIR="/opt/registry" REG_AUTH_DIR="/opt/registry/auth" REG_CERT_DIR="/opt/registry/certs" REG_DATA_DIR="/opt/registry/data"' >> /etc/profile.d/registry.sh
source /etc/profile.d/registry.sh
echo "$REG_DIR | $REG_AUTH_DIR | $REG_CERT_DIR | $REG_DATA_DIR"

# ============================================================
# TP03 – DOCKER MULTI-NŒUDS (SWARM)
# ============================================================

# [VM01] Vérifier Docker
docker version
# [VM01] Vérifier l’état du service Docker
systemctl is-active docker

# [VM01] Initialiser le Swarm (manager) + annoncer l’IP de management
docker swarm init --advertise-addr 192.168.1.1

# [VM01] Validation: Swarm activé + manager OK
docker info | egrep "Swarm:|Is Manager:|NodeID"

# [VM01] Validation: liste des nœuds (pour l’instant 1 manager)
docker node ls

# [VM01] Afficher la commande de join worker (à copier sur VM02/VM03)
docker swarm join-token worker

# [VM02/VM03] (à exécuter sur chaque worker) Join au Swarm
# Remplacer <TOKEN_WORKER> par le token affiché sur VM01
# docker swarm join --token <TOKEN_WORKER> ${MGR_IP}:2377

# [VM01] Validation: les workers apparaissent
docker node ls

# [VM01] Créer un réseau overlay (multi-host) attachable (pour docker run + services). avec --attachable  les conteneur lancés avec docker run et aussi ceux swarm 
#peuvent se connecter sur le réseau net_tp03_overlay 
#--attachable = autoriser docker run à rejoindre un réseau Swarm
docker network create -d overlay --attachable net_tp03_overlay

# [VM01] Validation: le réseau existe
docker network ls | grep net_tp03_overlay

# [VM01] Déployer un service (réplicas) sur l’overlay
docker service create \
  --name web_tp03 \
  --replicas 3 \
  --network net_tp03_overlay \
  --publish published=8083,target=80 \
  nginx:alpine


# [VM01] Validation: service créé
docker service ls

# [VM01] Validation: placement des tâches (sur quels nœuds)
docker service ps web_tp03

# [VM01] Validation “routing mesh”: accès via port publié sur le manager
export MGR_IP="192.168.1.1"
curl -sS http://${MGR_IP}:8083 | head -n 5

# [VM02/VM03] (optionnel) Validation “routing mesh”: le port publié répond aussi via IP d’un worker
# curl -sS http://${WRK1_IP}:8083 | head -n 5
# curl -sS http://${WRK2_IP}:8083 | head -n 5

# [VM01] Test concept DNS interne Swarm: le nom du service “web_tp03” doit résoudre et répondre
# lance un conteneur avec l'image alpine, le suprimea la sortie avec --rm, le place sur le réseau net_tp03_overlay, install curl et test la résolution dns
#de web_tp03
docker run --rm -it --network net_tp03_overlay alpine:3.20 sh -c \
 'apk add --no-cache curl >/dev/null; \
  echo "DNS:"; getent hosts web_tp03 || true; \
  echo "HTTP:"; curl -sS http://web_tp03 | head -n 5'
  
#Faire un test de résolution dns de la chaine "web_tp03" a partir d'un conteneur deployer sur vm02 par exemple.

# [VM01] Test résilience: mettre un worker en DRAIN (les tâches doivent être replanifiées ailleurs)
docker node ls 
docker node update --availability drain vm02

# [VM01] Validation: les tâches se déplacent => important dans docker swarm le manager est aussi un worker par défaut. 
#la tache tourne aussi sur le manager contraireemnt a K8S.
docker service ps web_tp03

# [VM01] Remettre le worker en ACTIVE
docker node update --availability active vm02

# [VM01] Validation: le cluster est stable
docker node ls
docker service ps web_tp03

#voir leslogs d'un service
docker service logs web_tp03

# [VM01] Nettoyage TP03
docker service rm web_tp03
docker network rm net_tp03_overlay


# ============================================================
# TP04 – DOCKER CONTENT TRUST (DCT) via (Docker Hub)
# ============================================================

# [VM01] Login Docker Hub (nécessaire pour push)
docker login

# [VM01] Définir ton Docker Hub user + repo. Creer un compte docker hub.
export DH_USER="labiform"
export APP_REPO="${DH_USER}/lab"
export IMG_LOCAL="dct-demo:1.0"
export IMG_REMOTE="${APP_REPO}:1.0"

# [VM01] Créer un contexte de build
mkdir -p /tmp/tp04 && cd /tmp/tp04

# [VM01] Créer une image très simple
cat > Dockerfile <<'EOF'
FROM alpine:3.20
RUN echo "Hello DCT - $(date)" > /hello.txt
CMD ["sh","-c","cat /hello.txt && sleep 3600"]
EOF

# [VM01] Build de l’image
docker build -t ${IMG_LOCAL} .

#check bonne création de l'image et son tag
docker image ls

# [VM01] Tag pour Docker Hub. Copie de l'image initiale avec un nouveau tag.
docker tag ${IMG_LOCAL} ${IMG_REMOTE}
docker image ls

# [VM01] DCT OFF: push d’une image NON signée
export DOCKER_CONTENT_TRUST=0
docker push ${IMG_REMOTE}

#Analyse en cas de soucis. push failled
docker info | grep -i Username
export DH_USER="labiform"  # on met bien le bon username docker hub
#se reconecter avec le bon username.
docker logout
docker login

# [VM01] Validation: pull classique OK (même si non signé)
docker rmi ${IMG_REMOTE} ${IMG_LOCAL} || true
docker pull ${IMG_REMOTE}

# [VM01] DCT ON: enforcement côté client (exiger signature)
export DOCKER_CONTENT_TRUST=1

# [VM01] Validation: si image non signée => pull doit échouer (ou “no trust data”)
docker rmi ${IMG_REMOTE} || true
docker pull ${IMG_REMOTE} || true
#se termine en echec. car DCT non respecter. 

# [VM01] Re-tagger local (si supprimé)
docker build -t dct-demo:1.0 .
docker tag ${IMG_LOCAL} ${IMG_REMOTE} 2>/dev/null || true

# [VM01] Push avec DCT ON => signature + metadata trust générées
docker push ${IMG_REMOTE}

# [VM01] Validation: inspection de la confiance/signature
docker trust inspect --pretty ${IMG_REMOTE} || true

# [VM01] Validation: pull OK car image signée
docker rmi ${IMG_REMOTE} || true
docker pull ${IMG_REMOTE}

###Conclusion pour sécuriser l'infra docker il faut mettre le DCT a 1, tout pull d'image passe par uen vrification de l'authenticité et l'intégrité des images.
 
# [VM01] (optionnel) Revenir à DCT OFF
export DOCKER_CONTENT_TRUST=0


# ============================================================
# TP05 – REGISTRY PRIVÉE SÉCURISÉE (TLS + htpasswd)
# ============================================================

# --------------------------
# Partie A: VM01 (serveur registry)
# --------------------------

# [VM01] Installer outils nécessaires (htpasswd + openssl)
apt-get update
apt-get install -y apache2-utils openssl ca-certificates

# [VM01] Créer les dossiers persistants. Vir ligne 34 de ce scrip. C'est là oû ces variables sont déclarées.
mkdir -p "${REG_AUTH_DIR}" "${REG_CERT_DIR}" "${REG_DATA_DIR}"

# [VM01] Créer l’utilisateur registry (auth basic)
htpasswd -Bbc "${REG_AUTH_DIR}/htpasswd" reguser 'Thinfo@2025%'

# [VM01] Se placer dans le dossier des certificats
cd "${REG_CERT_DIR}"

# [VM01] Générer une CA interne (autorité de certification)
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -subj "/CN=TP-Registry-CA" -out ca.crt

# [VM01] Générer la clé privée du serveur registry
openssl genrsa -out registry.key 4096

# [VM01] Générer la CSR (demande de certificat) pour registry.local
openssl req -new -key registry.key -subj "/CN=${REG_HOST}" -out registry.csr

# [VM01] Définir les SAN (obligatoire): DNS + IP (pour éviter erreurs TLS modernes)
cat > ext-registry.cnf <<EOF
subjectAltName = DNS:${REG_HOST},IP:${MGR_IP}
extendedKeyUsage = serverAuth
EOF
#Le fichier ext-registry.cnf permet de déclarer l'identité DNS et IP du serveur pour lequel le certificat va ètre généré. Ainsi que l'action pour laquelle il a été généré. 
#Sans cela le TLS moderne utilisé dans docker va se casser.

# [VM01] Signer le certificat serveur avec la CA interne
openssl x509 -req -days 3650 \
  -in registry.csr \
  -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out registry.crt \
  -extfile ext-registry.cnf

# [VM01] Sécuriser les permissions des clés
chmod 600 registry.key ca.key
chmod 644 registry.crt ca.crt

# [VM01] Validation: vérifier SAN DNS/IP dans le certificat
openssl x509 -in registry.crt -noout -text | egrep "Subject:|DNS:|IP Address" -n

# [VM01] Lancer la registry en HTTPS + htpasswd + stockage persistant
docker rm -f registry_tp05 2>/dev/null || true

#Mise de DCT=0 car # DCT=0 : TP05 utilise l’image registry:2 qui peut ne pas être signée via Docker Content Trust (Notary) ; sinon le pull peut échouer.
DOCKER_CONTENT_TRUST=0  ou export DOCKER_CONTENT_TRUST=0

docker run -d --name registry_tp05 \
  -p ${REG_PORT}:5000 \
  -v "${REG_DATA_DIR}:/var/lib/registry" \
  -v "${REG_AUTH_DIR}:/auth" \
  -v "${REG_CERT_DIR}:/certs" \
  -e "REGISTRY_AUTH=htpasswd" \
  -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd" \
  -e "REGISTRY_HTTP_ADDR=0.0.0.0:5000" \
  -e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt" \
  -e "REGISTRY_HTTP_TLS_KEY=/certs/registry.key" \
  registry:2

# [VM01] Validation: le port écoute
ss -lntp | grep ":${REG_PORT}" || true

# [VM01] Validation: endpoint Docker Registry V2 répond (TLS ok mais CA non trust => utilisation de -k qui ignore la vérification CA)
# C'est normale car on utilise une CA interne.

curl -vk "https://127.0.0.1:${REG_PORT}/v2/" || true

# --------------------------
# Partie B: VM02/VM03 (clients)
# --------------------------

# [VM02/VM03] Créer le dossier de confiance Docker pour cette registry
mkdir -p "/etc/docker/certs.d/${REG_FQDN}"

# [VM02/VM03] Récupérer la CA depuis VM01 (adapter user/ssh si besoin). Sur VM02  en premier.
scp root@192.168.1.1:/opt/registry/certs/ca.crt "/etc/docker/certs.d/${REG_FQDN}/ca.crt"

# [VM02/VM03] Restart Docker pour prendre en compte la CA
systemctl restart docker

# [VM02/VM03] Validation: appel HTTPS sans -k (doit répondre /v2/)
nano -c /etc/hosts
#ajouter 192.168.1.1 registry.local

curl -sS --cacert "/etc/docker/certs.d/${REG_FQDN}/ca.crt" "https://${REG_FQDN}/v2/" || true
###UNAUTHORIZED comme resultat mais l'api répond. C'est normale car l'api est protégée par uth Basic (htpasswd) → sans identifiants → 401 UNAUTHORIZED
curl -sS --cacert "/etc/docker/certs.d/${REG_FQDN}/ca.crt" \
  -u reguser:'Thinfo@2025%' \
  "https://${REG_FQDN}/v2/"
##  {} => TLS OK, Auth OK => registry accessible.

# [VM02/VM03] Login registry (auth basic)
docker login ${REG_FQDN}

# [VM02/VM03] Créer une image de test
mkdir -p /tmp/tp05 && cd /tmp/tp05
cat > Dockerfile <<'EOF'
FROM alpine:3.20
RUN echo "Hello Private Registry - $(date)" > /hello.txt
CMD ["sh","-c","cat /hello.txt && sleep 1"]
EOF

# [VM02/VM03] Build de l’image
docker build -t tp05-img:1.0 .

# [VM02/VM03] Tag vers la registry privée
docker tag tp05-img:1.0 ${REG_FQDN}/tp05-img:1.0

# [VM02/VM03] Push vers la registry privée (doit réussir)
docker push ${REG_FQDN}/tp05-img:1.0

# [VM02/VM03] Validation: catalogue (nécessite auth) => doit contenir tp05-img.  https://${REG_FQDN}/v2/_catalog => affiche uniquelent les répo du registry
#on doit voir le répo {"repositories":["tp05-img"]} qui s'affiche. 
curl -sS --cacert "/etc/docker/certs.d/${REG_FQDN}/ca.crt" \
  -u reguser:'Thinfo@2025%' \
  "https://${REG_FQDN}/v2/_catalog" | head -c 400; echo

# [VM02/VM03] Validation: pull + run depuis la registry (doit afficher Hello Private Registry)
docker rmi ${REG_FQDN}/tp05-img:1.0 || true
docker pull ${REG_FQDN}/tp05-img:1.0
docker run --rm ${REG_FQDN}/tp05-img:1.0
