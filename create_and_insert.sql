-- Active: 1720658787214@@127.0.0.1@5432@mydb
-- DROP DATABASE mydb --
DROP DATABASE IF EXISTS mydb;
-- DROP TYPE operation IF EXISTS --
CREATE DATABASE mydb;
DROP TYPE IF EXISTS operation;
-- ADD TYPE operation --
CREATE TYPE operation AS ENUM ('withdraw', 'deposit', 'transfer');
-- DROP TRANSACTION TABLE IF EXISTS --
DROP TABLE IF EXISTS transaction;
-- DROP ACCOUNT TABLE IF EXISTS --
DROP TABLE IF EXISTS "account";
-- DROP CUSTOMER TABLE IF EXISTS --
DROP TABLE IF EXISTS customer;
-- ADD CUSTOMER TABLE --
CREATE TABLE customer (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    NIK INTEGER NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    phone_number VARCHAR(15) NOT NULL,
    address VARCHAR(255) NOT NULL
);

-- ADD ACCOUNT TABLE --
CREATE TABLE account (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id UUID REFERENCES customer(id),
    password VARCHAR(255) NOT NULL,
    balance INTEGER NOT NULL,
    created_at DATE DEFAULT NOW()
);

-- ADD TRANSACTION TABLE --
CREATE TABLE transaction (
    account_id UUID REFERENCES account(id),
    operation VARCHAR(8) NOT NULL,
    amount INTEGER NOT NULL,
    to_acccount UUID,
    from_account UUID,
    date timestamptz DEFAULT NOW()
);
-- CREATE INDEX ON TRANSACTION TABLE --
CREATE INDEX IF NOT EXISTS account_id ON transaction(account_id);

-- CREATE withdraw FUNCTIONS --
CREATE OR REPLACE FUNCTION withdraw(id_account UUID, amount INTEGER) RETURNS text AS $$
DECLARE
    result BOOLEAN;
BEGIN
    IF amount <= 0 THEN
        ROLLBACK;
    END IF;
    
    INSERT INTO transaction VALUES (id_account, 'withdraw', amount, null, null);

    WITH enough AS (
        SELECT balance,
        CASE
            WHEN balance - amount < 0 THEN TRUE
            ELSE FALSE
        END AS enough
        FROM account
        WHERE id = id_account
    )
    SELECT enough INTO result FROM enough;

    IF result THEN
        ROLLBACK;
    ELSE 
        UPDATE account SET balance = balance - amount WHERE id = id_account;
        RETURN 'success';
    END IF;
END
$$ LANGUAGE plpgsql;

-- CREATE transfer FUNCTION --
CREATE OR REPLACE FUNCTION transfer(id_account UUID, to_account UUID, amount INTEGER) RETURNS text AS $$
DECLARE
    result BOOLEAN;
BEGIN
    IF id_account = to_account THEN
        ROLLBACK;
    END IF;

    IF amount <= 0 THEN
        ROLLBACK;
    END IF;

    SELECT
    CASE
        WHEN COUNT(id) = 0 THEN TRUE
        ELSE FALSE
    END AS result
     INTO result FROM "account" WHERE id = to_account;
    IF result THEN
        ROLLBACK;
    END IF;

    INSERT INTO transaction VALUES (id_account, 'transfer', amount, to_account, null);
    INSERT INTO transaction VALUES (to_account, 'transfer', amount, null, id_account);

    WITH enough AS (
        SELECT balance,
        CASE
            WHEN balance - amount < 0 THEN TRUE
            ELSE FALSE
        END AS enough
        FROM account
        WHERE id = id_account
    )
    SELECT enough INTO result FROM enough;

    IF result THEN
        ROLLBACK;
    ELSE 
        UPDATE account SET balance = balance - amount WHERE id = id_account;
        UPDATE account SET balance = balance + amount WHERE id = to_account;
        RETURN 'success';
    END IF;
END
$$ LANGUAGE plpgsql;

-- DELETE ACCOUNT --
CREATE OR REPLACE PROCEDURE delete_account(id_account UUID) AS $$
BEGIN
    ALTER TABLE transaction DROP CONSTRAINT transaction_account_id_fkey, ADD CONSTRAINT transaction_account_id_fkey FOREIGN KEY (account_id) REFERENCES account(id) ON DELETE CASCADE;
    DELETE FROM account WHERE id = id_account;
    ALTER TABLE transaction DROP CONSTRAINT transaction_account_id_fkey, ADD CONSTRAINT transaction_account_id_fkey FOREIGN KEY (account_id) REFERENCES account(id) ON DELETE RESTRICT;
END
$$ LANGUAGE plpgsql;

-- INSERT DATA & UPDATE DATA --
INSERT INTO customer(id, NIK, name, phone_number, address) VALUES
('0190a778-ad24-7560-bc12-92e2df286fca','1234567890', 'John Doe', '1234567890', '123 Main St');
INSERT INTO customer(id, NIK, name, phone_number, address) VALUES
('0190a778-ad24-7d08-a536-a59d5b6b88a6', '1234567891', 'John Do', '1234567890', '123 Main St');

INSERT INTO account(id, customer_id, password, balance) VALUES
('0190a77a-9b0f-7fa1-ad7f-1a55051aeeb3', '0190a778-ad24-7560-bc12-92e2df286fca', 'password', 500);
INSERT INTO account(id, customer_id, password, balance) VALUES
('0190a77a-9b0f-793f-b673-d31ce24b474c','0190a778-ad24-7560-bc12-92e2df286fca', 'password', 500);
INSERT INTO account(id, customer_id, password, balance) VALUES
('0190a778-ad24-7d08-a536-a59d5b6b88a6','0190a778-ad24-7d08-a536-a59d5b6b88a6', 'password', 100);

BEGIN;
INSERT INTO "transaction" VALUES
('0190a778-ad24-7d08-a536-a59d5b6b88a6', 'deposit', 500, null, null);
UPDATE "account" SET balance = balance + 500 WHERE id = '0190a778-ad24-7d08-a536-a59d5b6b88a6';
COMMIT;

SELECT withdraw('0190a77a-9b0f-7fa1-ad7f-1a55051aeeb3', 100);
SELECT transfer('0190a77a-9b0f-7fa1-ad7f-1a55051aeeb3', '0190a778-ad24-7d08-a536-a59d5b6b88a6', 100);
SELECT transfer('0190a778-ad24-7d08-a536-a59d5b6b88a6', '0190a77a-9b0f-793f-b673-d31ce24b474c', 100);

-- SELECT DATA --
SELECT name, operation, "date", SUM(amount) AS total_deposit FROM customer INNER JOIN "account" ON customer.id = customer_id INNER JOIN transaction ON "account".id = account_id GROUP BY name, operation, "date";

-- SHOWING SENDER AND RECEIVER NAME --
SELECT name, "date", SUM(amount) AS total_transfer, (SELECT name FROM customer INNER JOIN "account" ON customer.id = customer_id WHERE account.id = to_acccount) FROM customer INNER JOIN "account" ON customer.id = customer_id INNER JOIN transaction ON "account".id = account_id WHERE account_id = '0190a778-ad24-7d08-a536-a59d5b6b88a6' AND operation = 'transfer' AND from_account IS NULL GROUP BY "date", name, to_acccount;

-- SHOWING RECEIVER AND SENDER NAME --
SELECT name, SUM(amount) AS total_transfer, (SELECT name FROM customer INNER JOIN account ON customer.id = customer_id WHERE account.id = from_account) FROM customer INNER JOIN account ON customer.id = customer_id INNER JOIN transaction ON account.id = account_id WHERE account_id = '0190a77a-9b0f-793f-b673-d31ce24b474c' AND operation = 'transfer' AND from_account IS NOT NULL GROUP BY amount, name, from_account, account_id, transaction."date";

-- DELETE ACCOUNT --
CALL delete_account('0190a77a-9b0f-7fa1-ad7f-1a55051aeeb3');
