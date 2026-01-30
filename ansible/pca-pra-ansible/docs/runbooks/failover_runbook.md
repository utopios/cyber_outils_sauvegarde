# Runbook - Procédure de Failover PCA/PRA

## Informations Générales

| Élément | Valeur |
|---------|--------|
| **Document** | Procédure de Failover |
| **Version** | 1.0 |
| **Dernière mise à jour** | 2024 |
| **Propriétaire** | Équipe Infrastructure |
| **Classification** | Confidentiel |

---

## 1. Conditions de Déclenchement

### 1.1 Critères de déclenchement automatique
- Perte de connectivité avec DC-PARIS > 5 minutes
- Indisponibilité PostgreSQL Primary > 2 minutes
- Taux d'erreur API > 50% pendant 5 minutes

### 1.2 Critères de déclenchement manuel
- Maintenance planifiée du datacenter
- Incident majeur déclaré par le NOC
- Décision de la cellule de crise

---

## 2. Pré-requis

### 2.1 Vérifications avant failover
- [ ] Confirmer l'indisponibilité réelle de DC-PARIS
- [ ] Vérifier l'état de réplication de DC-LYON
- [ ] S'assurer que le lag de réplication < 5 minutes (RPO)
- [ ] Informer les parties prenantes

### 2.2 Accès requis
- Accès SSH aux serveurs DC-LYON
- Accès à la console Ansible
- Accès aux notifications Slack/Email

---

## 3. Procédure de Failover

### 3.1 Failover Base de Données (RTO: 15 min)

```bash
# Connexion au serveur Ansible
ssh ansible@ansible-controller

# Vérification de l'état actuel
ansible-playbook playbooks/dr_test/partial_dr_test.yml

# Exécution du failover database
ansible-playbook playbooks/failover/database_failover.yml
```

**Points de contrôle :**
1. Vérifier la promotion du standby : `SELECT pg_is_in_recovery();` → doit retourner `f`
2. Tester la connectivité : `psql -h 192.168.56.20 -U postgres -c "SELECT 1;"`
3. Vérifier le slot de réplication supprimé

### 3.2 Failover Applicatif (RTO: 15 min)

```bash
# Exécution du failover applicatif
ansible-playbook playbooks/failover/application_failover.yml
```

**Points de contrôle :**
1. Applications démarrées sur DC-LYON
2. Health checks OK : `curl http://192.168.56.20/health`
3. HAProxy actif : `curl http://192.168.56.20:8404/stats`

### 3.3 Failover Complet (Orchestré)

```bash
# Exécution du failover complet
ansible-playbook playbooks/failover/full_failover.yml -e confirm_failover=true
```

---

## 4. Validation Post-Failover

### 4.1 Tests de validation
```bash
# Test API
curl -X GET http://192.168.56.20/api/payments

# Test santé globale
curl http://192.168.56.20/health

# Vérification PostgreSQL
docker exec postgres-standby psql -U postgres -c "SELECT count(*) FROM transactions.payments;"
```

### 4.2 Checklist de validation
- [ ] API de paiement accessible
- [ ] Transactions enregistrées correctement
- [ ] HAProxy distribue le trafic
- [ ] Redis répond aux requêtes
- [ ] Logs sans erreurs critiques
- [ ] Métriques Prometheus collectées

---

## 5. Communication

### 5.1 Notifications automatiques
Le système envoie automatiquement :
- Notification Slack : #infrastructure-alerts
- Email : sre-team@finsecure.com

### 5.2 Communication manuelle requise
1. Informer le management (T+5 min)
2. Notifier les équipes métier (T+10 min)
3. Mise à jour du status page (T+15 min)

---

## 6. Rollback

### 6.1 Si le failover échoue
```bash
# Annuler et revenir à l'état initial
ansible-playbook playbooks/failback/emergency_rollback.yml
```

### 6.2 Critères de rollback
- Échec de promotion PostgreSQL
- Applications non fonctionnelles après 10 minutes
- Corruption de données détectée

---

## 7. Post-Incident

### 7.1 Actions immédiates
1. Documenter l'incident dans le système de ticketing
2. Conserver les logs de failover
3. Planifier le failback

### 7.2 Analyse post-mortem
- Réunion de débriefing sous 48h
- Rapport d'incident
- Actions correctives identifiées

---

## 8. Contacts d'Urgence

| Rôle | Nom | Téléphone |
|------|-----|-----------|
| On-Call SRE | Astreinte | +33 1 XX XX XX XX |
| Manager Infra | - | +33 1 XX XX XX XX |
| DBA | - | +33 1 XX XX XX XX |
| RSSI | - | +33 1 XX XX XX XX |

---

## Annexes

### A. Commandes utiles

```bash
# Vérifier l'état de réplication
docker exec postgres-primary psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Vérifier le lag
docker exec postgres-standby psql -U postgres -c \
  "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()));"

# Promouvoir manuellement
docker exec postgres-standby pg_ctl promote -D /var/lib/postgresql/data/pgdata

# Vérifier HAProxy
echo "show servers state" | socat stdio /var/run/haproxy.sock
```

### B. Schéma de décision

```
                    ┌─────────────────┐
                    │ Incident détecté│
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │DC-Paris accessible?│
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
         ┌────▼────┐                   ┌────▼────┐
         │   OUI   │                   │   NON   │
         └────┬────┘                   └────┬────┘
              │                             │
    ┌─────────▼─────────┐          ┌────────▼────────┐
    │ Réparer sur place │          │ Déclencher      │
    │ (si possible)     │          │ FAILOVER        │
    └───────────────────┘          └─────────────────┘
```
