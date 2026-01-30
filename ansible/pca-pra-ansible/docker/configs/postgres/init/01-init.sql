-- Initialisation de la base de données FinSecure
-- Ce script s'exécute au premier démarrage du conteneur PostgreSQL

-- Création de l'utilisateur de réplication
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'R3pl1c@t0r!';

-- Création de l'utilisateur applicatif
CREATE USER app_user WITH ENCRYPTED PASSWORD 'App_Us3r_P@ss!';

-- Création des bases de données
CREATE DATABASE finsecure_transactions OWNER app_user;
CREATE DATABASE finsecure_backoffice OWNER app_user;

-- Connexion à la base transactions
\c finsecure_transactions

-- Schéma pour les transactions
CREATE SCHEMA IF NOT EXISTS transactions AUTHORIZATION app_user;

-- Table des transactions de paiement
CREATE TABLE transactions.payments (
    id BIGSERIAL PRIMARY KEY,
    transaction_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    amount DECIMAL(15, 2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'EUR',
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    merchant_id VARCHAR(50) NOT NULL,
    customer_id VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    metadata JSONB
);

-- Index pour les recherches fréquentes
CREATE INDEX idx_payments_merchant ON transactions.payments(merchant_id);
CREATE INDEX idx_payments_status ON transactions.payments(status);
CREATE INDEX idx_payments_created_at ON transactions.payments(created_at);

-- Table d'audit
CREATE TABLE transactions.audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    user_name VARCHAR(100),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Fonction de trigger pour l'audit
CREATE OR REPLACE FUNCTION transactions.audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO transactions.audit_log(table_name, operation, old_data, user_name)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), current_user);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO transactions.audit_log(table_name, operation, old_data, new_data, user_name)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD), row_to_json(NEW), current_user);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO transactions.audit_log(table_name, operation, new_data, user_name)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(NEW), current_user);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Application du trigger
CREATE TRIGGER payments_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON transactions.payments
FOR EACH ROW EXECUTE FUNCTION transactions.audit_trigger_func();

-- Droits
GRANT ALL PRIVILEGES ON SCHEMA transactions TO app_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA transactions TO app_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA transactions TO app_user;

-- Création du slot de réplication pour Lyon
SELECT pg_create_physical_replication_slot('lyon_replica');

-- Extension pour les UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- Connexion à la base backoffice
\c finsecure_backoffice

-- Schéma backoffice
CREATE SCHEMA IF NOT EXISTS backoffice AUTHORIZATION app_user;

-- Tables backoffice (moins critiques)
CREATE TABLE backoffice.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);

CREATE TABLE backoffice.reports (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50) NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    data JSONB
);

GRANT ALL PRIVILEGES ON SCHEMA backoffice TO app_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA backoffice TO app_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA backoffice TO app_user;
