#!/usr/bin/env bash
# ============================================================
#  DOCKER AVANCÉ - TP01 + TP02 (PENSE-BÊTE COPY/PASTE)
#  Formateur: Halim BOUHOUI
#  OS: Debian 13 (sans interface graphique)
# ============================================================

# ------------------------------------------------------------
# RÔLES DES MACHINES
# VM01 : docker-mgr   (192.168.1.1)
# VM02 : docker-wrk1  (192.168.1.2)
# VM03 : docker-wrk2  (192.168.1.3) (non utilisé TP01/TP02)
# ------------------------------------------------------------

# Objectif TP01:
#  - Paramétrage du démon Docker (daemon.json)
#  - Configuration des logs (rotation)
#  - Exposition de l'API Docker sur TCP (DEMO: sans TLS)
#  - Connexion d'un client Docker à un démon distant
#
# Objectif TP02:
#  - Sécurisation de l'API Docker via TLS (mTLS)
#  - Tests d'accès autorisé/refusé
#  - Mise en évidence du risque de l'API Docker exposée sans TLS
# ============================================================

# -----------------------------
# VARIABLES (COMMUNES)
# -----------------------------
MGR_IP="192.168.1.1"     # VM01
WRK1_IP="192.168.1.2"    # VM02
WRK2_IP="192.168.1.3"    # VM03

#uniquement sur vm01

DOCKER_TCP_INSECURE="2375"
DOCKER_TCP_TLS="2376"
TLS_DIR="/etc/docker/tls"

# ============================================================
# MISE À JOUR DES DÉPÔTS – À FAIRE SUR VM01, VM02, VM03
# ============================================================

# VM01 / VM02 / VM03
nano -c /etc/apt/sources.list.d/debian.sources

# Contenu :
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# VM01 / VM02 / VM03
apt update

# ============================================================
# PRÉ-REQUIS – À FAIRE SUR VM01 ET VM02
# ============================================================

# VM01 / VM02
ip a

# VM01 / VM02
sudo apt-get update
sudo apt-get install -y docker.io ca-certificates curl openssl

# VM01 / VM02
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager

# VM01 / VM02 => vérifier la bonne installation de docker.
sudo docker run --rm hello-world

# ============================================================
# ========================= TP01 =============================
# ============================================================

# ============================================================
# TP01.1 – CONFIGURATION DU DÉMON DOCKER
# VM01 UNIQUEMENT
# ============================================================

# VM01
sudo mkdir -p /etc/docker

# VM01.  taille max des fichiers de logs a 10Mo et max 3 fichiers. Mise en place de la rotation des fichiers de logs par conteneur.

sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Override systemd pour remplacer -H fd:// par nos sockets (unix + tcp)
sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:${DOCKER_TCP_INSECURE}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# VM01 – Vérifier écoute sur 2375
sudo ss -lntp | grep ":${DOCKER_TCP_INSECURE}" || true

# ============================================================
# TP01.2 – TEST DES LOGS ET DE LA ROTATION
# VM01 UNIQUEMENT
# ============================================================

# VM01 – conteneur générant beaucoup de logs
sudo docker run -d --name logdemo busybox sh -c 'i=0; while true; do echo "log line $i"; i=$((i+1)); sleep 0.2; done'

# VM01 – vérifier logs
sudo docker logs --tail 10 logdemo

# VM01 – localiser fichier de logs
CID="$(sudo docker inspect -f '{{.Id}}' logdemo)"
echo "Container ID: $CID"
sudo ls -lh "/var/lib/docker/containers/${CID}/" | sed -n '1,8p'

#vérifier la taille des logs du container labdemo
sudo ls -lh "/var/lib/docker/containers/${CID}/${CID}-json.log" || true

# VM01 – nettoyage
sudo docker rm -f logdemo

# ============================================================
# TP01.3 – CONNEXION DISTANTE AU DÉMON (INSECURE)
# VM02 UNIQUEMENT
# ============================================================

# VM02 – test réseau
ping -c 2 "${MGR_IP}"

DOCKER_TCP_INSECURE="2375"
echo "$DOCKER_TCP_INSECURE"

# VM02 – test API Docker brute
curl -s "http://${MGR_IP}:${DOCKER_TCP_INSECURE}/version" | head -c 200; echo

# VM02 – client Docker distant
sudo docker -H "tcp://${MGR_IP}:${DOCKER_TCP_INSECURE}" info | sed -n '1,40p'

# VM02 – exécution distante (conteneur lancé sur VM01)
sudo docker -H "tcp://${MGR_IP}:${DOCKER_TCP_INSECURE}" run --rm alpine sh -c 'echo "OK depuis VM02"; uname -a'

#Depuis VM02 - Création d'un conteneur pesistant
sudo docker -H "tcp://${MGR_IP}:${DOCKER_TCP_INSECURE}" run -d --name demo_persistant alpine sh -c 'while true; do sleep 30; done'


# ============================================================
# ========================= TP02 =============================
# ============================================================

# ============================================================
# TP02.1 – GÉNÉRATION DES CERTIFICATS TLS
# VM01 UNIQUEMENT
# ============================================================

# VM01
sudo mkdir -p "${TLS_DIR}"
cd "${TLS_DIR}"

# VM01 – Conf de notre CA  
sudo openssl genrsa -out ca-key.pem 4096
sudo openssl req -new -x509 -days 3650 \
  -key ca-key.pem \
  -subj "/CN=Docker-Training-CA" \
  -out ca.pem

# VM01 – certificat serveur
sudo openssl genrsa -out server-key.pem 4096
sudo openssl req -new \
  -key server-key.pem \
  -subj "/CN=docker-mgr" \
  -out server.csr

# Force l’identité du serveur pour lequel le certificat est valide :
# - IP du serveur Docker : 192.168.1.1
# - Nom DNS : docker-mgr
#
# extendedKeyUsage = serverAuth
# Spécifie que ce certificat est destiné à être utilisé par un SERVEUR TLS
# (ici le démon Docker) pour prouver son identité aux clients.
 
sudo tee extfile-server.cnf >/dev/null <<EOF
subjectAltName = IP:${MGR_IP},DNS:docker-mgr
extendedKeyUsage = serverAuth
EOF

sudo openssl x509 -req -days 3650 \
  -in server.csr \
  -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem \
  -extfile extfile-server.cnf

# VM01 – certificat client
sudo openssl genrsa -out client-key.pem 4096
sudo openssl req -new \
  -key client-key.pem \
  -subj "/CN=docker-client-wrk1" \
  -out client.csr

sudo tee extfile-client.cnf >/dev/null <<EOF
extendedKeyUsage = clientAuth
EOF

sudo openssl x509 -req -days 3650 \
  -in client.csr \
  -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem \
  -extfile extfile-client.cnf

# VM01 – permissions
sudo chmod 600 ca-key.pem server-key.pem client-key.pem
sudo chmod 644 ca.pem server-cert.pem client-cert.pem
sudo ls -l

# ============================================================
# TP02.2 – ACTIVER TLS ET DÉSACTIVER 2375
# VM01 UNIQUEMENT
# ============================================================

# VM01
sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "tls": true,
  "tlsverify": true,
  "tlscacert": "${TLS_DIR}/ca.pem",
  "tlscert": "${TLS_DIR}/server-cert.pem",
  "tlskey": "${TLS_DIR}/server-key.pem"
}
EOF

tee /etc/systemd/system/docker.service.d/override.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/dockerd -H unix:///var/run/docker.sock -H tcp://0.0.0.0:${DOCKER_TCP_TLS}
EOF

# VM01
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl status docker --no-pager

# VM01 – vérifier ports. 


sudo ss -lntp | egrep ":(2375|2376)" || true

#2376 en LISTEN
#2375 absent

# ============================================================
# TP02.3 – COPIE DES CERTIFICATS CLIENT
# VM02 UNIQUEMENT
# ============================================================

# VM02
sudo mkdir -p /etc/docker/certs-wrk1
sudo chmod 700 /etc/docker/certs-wrk1

# VM02 – récupération depuis VM01
scp root@"${MGR_IP}:${TLS_DIR}/ca.pem" /tmp/ca.pem
scp root@"${MGR_IP}:${TLS_DIR}/client-cert.pem" /tmp/client-cert.pem
scp root@"${MGR_IP}:${TLS_DIR}/client-key.pem" /tmp/client-key.pem

# VM02
sudo mv /tmp/ca.pem /etc/docker/certs-wrk1/ca.pem
sudo mv /tmp/client-cert.pem /etc/docker/certs-wrk1/cert.pem
sudo mv /tmp/client-key.pem /etc/docker/certs-wrk1/key.pem

sudo chmod 600 /etc/docker/certs-wrk1/key.pem
sudo chmod 644 /etc/docker/certs-wrk1/ca.pem /etc/docker/certs-wrk1/cert.pem

# ============================================================
# TP02.4 – TESTS TLS
# VM02 UNIQUEMENT
# ============================================================

# VM02 – test refus sans cert
curl -k "https://${MGR_IP}:${DOCKER_TCP_TLS}/version" | head -c 120; echo

# VM02 – test OK avec cert client
curl --cacert /etc/docker/certs-wrk1/ca.pem \
     --cert  /etc/docker/certs-wrk1/cert.pem \
     --key   /etc/docker/certs-wrk1/key.pem \
     "https://${MGR_IP}:${DOCKER_TCP_TLS}/version" 2>/dev/null | head -c 200; echo

# VM02 – test via docker client TLS
sudo docker --tlsverify \
  --tlscacert=/etc/docker/certs-wrk1/ca.pem \
  --tlscert=/etc/docker/certs-wrk1/cert.pem \
  --tlskey=/etc/docker/certs-wrk1/key.pem \
  -H "tcp://${MGR_IP}:${DOCKER_TCP_TLS}" info | sed -n '1,40p'

# VM02 – exécution distante sécurisée
sudo docker --tlsverify \
  --tlscacert=/etc/docker/certs-wrk1/ca.pem \
  --tlscert=/etc/docker/certs-wrk1/cert.pem \
  --tlskey=/etc/docker/certs-wrk1/key.pem \
  -H "tcp://${MGR_IP}:${DOCKER_TCP_TLS}" run --rm alpine sh -c 'echo "OK TLS"; uname -a'
  
# depuis VM02 - Supprimé tous les conteneurs qui se base sur une image alpine via une commade TLS

#identification des conteneur.

IDS=$(docker --tlsverify \
  --tlscacert=/etc/docker/certs-wrk1/ca.pem \
  --tlscert=/etc/docker/certs-wrk1/cert.pem \
  --tlskey=/etc/docker/certs-wrk1/key.pem \
  -H tcp://192.168.1.1:2376 \
  ps -aq --filter ancestor=alpine)

#suppression des conteneur
docker --tlsverify \
  --tlscacert=/etc/docker/certs-wrk1/ca.pem \
  --tlscert=/etc/docker/certs-wrk1/cert.pem \
  --tlskey=/etc/docker/certs-wrk1/key.pem \
  -H tcp://192.168.1.1:2376 \
  rm -f $IDS
  

echo "TP01 + TP02 terminés."
