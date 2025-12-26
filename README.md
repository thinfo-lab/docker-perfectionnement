<<<<<<< HEAD
# docker-perfectionnement
=======
# Docker – Perfectionnement & usages avancés

🎓 **Support de cours et travaux pratiques avancés Docker**  
Ce dépôt regroupe un cours de **perfectionnement Docker**, accompagné de **TP progressifs, concrets et opérationnels**, utilisés en contexte de formation professionnelle.


---

## 🎯 Objectifs pédagogiques

Ce projet permet de :
- Maîtriser **Docker au-delà des bases**
- Comprendre les **mécanismes internes** (réseau, volumes, images)
- Mettre en œuvre Docker dans des **contextes proches de la production**
- Automatiser, sécuriser et industrialiser les déploiements


## Public cible
- Admin systèmes / réseaux
- DevOps / Cloud
- Développeurs avec bases Docker
- Bac+3 à Bac+5

## Contenu
- Support de cours PDF
- TP progressifs et commentés (scripts exécutables)


## Détail des TP (contenu des scripts)

### TP01 — Paramétrage avancé du démon Docker
- Configuration du démon via `daemon.json`
- Configuration des logs + rotation
- Exposition de l’API Docker sur TCP (**démo volontairement insecure, sans TLS**)
- Connexion d’un client Docker à un démon distant

### TP02 — Sécurisation de l’API Docker (TLS / mTLS)
- Sécurisation de l’API Docker via TLS (auth mutuelle mTLS)
- Tests d’accès autorisé / refusé
- Mise en évidence du risque d’une API Docker exposée sans TLS
- Copies certificats client + tests TLS

### TP03 — Docker Swarm (multi-nœuds)
- Manager/worker, Raft
- Différence **service vs conteneur**
- Réseau overlay, routing mesh, rescheduling
- Validations : `node ls`, `service ps`, `curl` sur port publié, DNS interne (nom du service), drain/reschedule

### TP04 — Docker Content Trust (DCT)
- Images signées / non signées, metadata de confiance
- Enforcement côté client
- Validations : pull KO si non signé (`DCT=1`), push/pull OK après signature

### TP05 — Registry privée sécurisée (TLS + htpasswd)
- Registry v2
- TLS (CA + cert serveur + SAN)
- Authentification `htpasswd`
- Déploiement “enterprise-like” : confiance CA côté clients

### TP06 — Gouvernance registry type DTR/RBAC
- Mettre en place une registry “enterprise-like” avec RBAC (équivalent DTR)
- Créer projets / utilisateurs / rôles (push/pull contrôlés)
- Tester les droits (pull OK / push refusé)

### TP07 — Docker Machine
- Provisionner et gérer des hôtes Docker distants via SSH
- Basculer de contexte (`eval env`) et exécuter à distance
- Automatiser le cycle de vie (create / ls / ssh / rm)

### TP08 — Docker Swarm (orchestration avancée)
- Déployer des services (replicas), réseau overlay, publication ingress
- Rolling update / rollback
- Secrets + configs
- Placement constraints + drain + tests de haute dispo / panne

### TP09 — Déploiement WordPress via Docker Compose (bind-mount)
- Déploiement WordPress + DB avec `docker-compose`
- Dossiers persistants côté hôte (bind-mount)
- Test : création d’une page `info.php` depuis l’hôte pour valider la réplication dans le conteneur


## Environnement
- Linux (Debian/Ubuntu)
- Docker ≥ 24
- Docker Compose v2


## Auteur
Halim BOUHOUI
Docker • Cloud • DevOps • Cybersécurité
>>>>>>> 110a7ab (Publication du cours Docker perfectionnement avec TP avancés)
