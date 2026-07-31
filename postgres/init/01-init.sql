-- Demo schema for the CDC pipeline

CREATE TABLE IF NOT EXISTS public.customers (
    id          SERIAL PRIMARY KEY,
    full_name   VARCHAR(255) NOT NULL,
    email       VARCHAR(255) NOT NULL,
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.orders (
    id          SERIAL PRIMARY KEY,
    customer_id INTEGER NOT NULL REFERENCES public.customers(id),
    amount      NUMERIC(10, 2) NOT NULL,
    status      VARCHAR(50) NOT NULL DEFAULT 'pending',
    created_at  TIMESTAMP NOT NULL DEFAULT now(),
    updated_at  TIMESTAMP NOT NULL DEFAULT now()
);

-- Debezium needs to see the full old row on UPDATE/DELETE to unwrap events correctly
ALTER TABLE public.customers REPLICA IDENTITY FULL;
ALTER TABLE public.orders REPLICA IDENTITY FULL;

-- Publication that the Debezium connector will consume via pgoutput
CREATE PUBLICATION dbz_publication FOR TABLE public.customers, public.orders;

-- Seed data so there is something to see immediately after startup
INSERT INTO public.customers (full_name, email) VALUES
    ('Ada Lovelace', 'ada@example.com'),
    ('Alan Turing', 'alan@example.com');

INSERT INTO public.orders (customer_id, amount, status) VALUES
    (1, 49.99, 'pending'),
    (2, 120.00, 'shipped');
