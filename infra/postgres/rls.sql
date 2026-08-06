-- Row-Level Security: defence-in-depth tenant isolation (dissertation §4.5.3).
-- The API sets `app.tenant_id` per request (see app/core/deps.py::bind_tenant);
-- these policies make cross-tenant reads impossible even if an application-
-- layer filter is ever missed. Applied on first container init; run manually
-- after Alembic migrations in existing deployments.
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename IN ('shops','roles','users','categories','products',
                            'suppliers','stock_movements','customers','sales',
                            'sale_lines','payments','exchange_rates','expenses',
                            'employees','audit_log','change_log','sync_ops')
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format(
            'CREATE POLICY tenant_isolation ON %I USING '
            '(tenant_id = current_setting(''app.tenant_id'', true)::text)', t);
    END LOOP;
END $$;
