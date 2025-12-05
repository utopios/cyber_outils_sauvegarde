# **TP PRA/PCA – Mise en place d’un stockage objet haute disponibilité avec MinIO pour assurer la continuité d’activité d’une application sensible**

Application cible :
**Shlink – URL shortener open source**
[https://github.com/shlinkio/shlink](https://github.com/shlinkio/shlink)

---

# 1. **Scénario professionnel**

Votre entreprise utilise **Shlink** comme service interne de raccourcissement d’URL pour toutes ses campagnes marketing, ses rapports de cybersécurité, ainsi que pour la génération de liens temporaires entre équipes.

Le service est critique :

* les métriques de clics sont utilisées pour des décisions stratégiques,
* certains liens expirables contiennent des accès sensibles,
* des équipes opérationnelles l’utilisent quotidiennement.

La direction cybersécurité vous confie la mission suivante :

> **Construire une architecture PCA/PRA minimaliste dans Docker, reposant sur MinIO en mode cluster, afin de garantir la continuité de l’activité même en cas de perte du site primaire.**

Vous devez fournir un système **fonctionnel**, **résilient**, et **documenté**.

---

# **Objectifs PCA/PRA**

Votre architecture doit permettre :

* la continuité de service si un nœud Shlink tombe,
* la persistance des données dans un cluster MinIO réparti,
* la capacité à **basculer (failover)** vers un second site MinIO,
* la restauration d’un nœud Shlink à partir du stockage objet uniquement,
* la simulation d’un incident majeur (perte du site primaire).

---

# 2. **Environnement imposé**

Vous devez obligatoirement utiliser Docker et construire l’environnement suivant :

### **Site principal**

* 1 conteneur **Shlink** (application)
* 1 conteneur **PostgreSQL / MariaDB** (au choix)
* 4 conteneurs **MinIO Server** (cluster distribué en erasure coding)
* 1 conteneur **MinIO Console** (visualisation administrative)

### **Site secondaire (PRA)**

* 4 conteneurs **MinIO Server** (cluster miroir ou répliqué)
* 1 conteneur vide destiné à devenir **Shlink-PRA** (restauration)
* 1 conteneur vide destiné à devenir **Database-PRA**

Vous devez définir **un réseau Docker par site** + une zone d’échange contrôlée.

---

# 3. **Contraintes générales du TP**

1. **Aucune donnée sensible (clés MinIO, mot de passe DB) ne doit être versionnée en clair.**
2. **Les deux sites doivent être isolés**, sauf une passerelle réseau contrôlée.
3. Le stockage objet doit être **haute disponibilité + tolérance à la perte d’au moins 1 conteneur MinIO**.
4. La réplication entre les deux clusters doit être **automatisée** (site A → site B).
5. Il doit être possible de **détruire complètement le site principal** et redémarrer Shlink depuis le PRA.
6. Toute la configuration doit être **scriptée et reproductible** (docker-compose, scripts init…).
7. Une documentation professionnelle doit être fournie (architecture, risques, procédures PRA).

---

# 4. **Étape 1 — Déploiement de Shlink (site principal)**

Objectifs :

* Installer Shlink dans Docker
* Exposer son API
* Connecter l'application à la base
* Documenter les points critiques de sécurité (tokens, API keys, admin UI)

---

# 5. **Étape 2 — Déploiement d’un cluster MinIO en erasure coding (site principal)**

Objectifs :

* Construire un cluster de 4 nœuds MinIO (S3-compatible)
* Configurer un bucket dédié `shlink-data`
* Appliquer :

  * Versioning
  * Encryption-at-rest
  * Policies (read/write strictes)
* Vérifier le fonctionnement en cas de perte d’un nœud.

---

# 6. **Étape 3 — Intégration Shlink ↔ MinIO**

Objectifs :

* Configurer Shlink pour stocker ses assets/statistiques dans MinIO
* Ajouter des scripts d’export régulier vers MinIO
* Démontrer que Shlink continue de fonctionner lors d’une perte temporaire d’un nœud MinIO.

---

# 7. **Étape 4 — Mise en place du **site PRA** (cluster MinIO secondaire)**

Objectifs :

* Déployer un second cluster MinIO distribué
* Créer un bucket miroir
* Configurer la **réplication inter-site** (MinIO → MinIO)
* Définir les politiques réseau (isolation + routes strictes)

---

# 8. **Étape 5 — Simulation d’un incident majeur**

Scénario :

> Un incendie dans le datacenter primaire rend les conteneurs Shlink, PostgreSQL et les nœuds MinIO **totalement inaccessibles**.

Vous devez :

* Détruire les conteneurs du site principal
* Vérifier que les données existent toujours dans le PRA
* Documenter l'impact sur la continuité d'activité.

---

# 9. **Étape 6 — Redémarrage du service depuis le PRA**

Objectifs :

* Déployer Shlink-PRA en ne s’appuyant **que sur le cluster MinIO secondaire**
* Restaurer la base depuis MinIO
* Vérifier la cohérence des raccourcis, statistiques et métadonnées
* Documenter la procédure de bascule (failover)
* Mesurer le RTO et le RPO obtenus

---

# 10. **Étape 7 — Test de tolérance et validation PRA**

Vous devez vérifier :

* Tolérance aux pannes MinIO (perte 1 nœud)
* Tolérance applicative (Shlink redémarre correctement)
* Capacité à revenir au site principal lorsque celui-ci est reconstruit
* Cohérence des données après plusieurs cycles réplication → failover → retour arrière

---

# 11. **Livrables attendus**

1. **Architecture détaillée** (schéma obligatoire)
2. **Procédure PRA écrite** :

   * Déclenchement
   * Bascule
   * Redémarrage
   * Retour arrière
3. **Analyse de risque (PCA/PRA)** :

   * Menaces
   * Impact
   * Mesures compensatoires
4. **Documentation technique complète** :

   * Déploiement
   * Scripts
   * Politiques MinIO
   * Contraintes réseau
5. **Journal d’incident** simulé
6. **Évaluation RTO/RPO** obtenus réellement
