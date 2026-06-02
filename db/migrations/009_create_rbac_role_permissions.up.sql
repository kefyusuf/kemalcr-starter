CREATE TABLE IF NOT EXISTS rbac_role_permissions (
    id VARCHAR(36) PRIMARY KEY DEFAULT gen_random_uuid()::text,
    role_name VARCHAR(50) NOT NULL,
    permission_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(role_name, permission_name)
);

CREATE INDEX IF NOT EXISTS idx_rbac_role_permissions_role
    ON rbac_role_permissions (role_name);

CREATE INDEX IF NOT EXISTS idx_rbac_role_permissions_permission
    ON rbac_role_permissions (permission_name);
