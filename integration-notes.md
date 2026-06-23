# Integration Notes

## Challenge A: Service Protection and Configuration Access

### Conflict

Strong filesystem protection can prevent services from reading their configuration.

### Options Considered

1. Move configuration.
2. Create explicit access exceptions.

### Decision

Configuration remained in a dedicated application configuration location with permissions allowing read access.

### Reasoning

This preserved service functionality while maintaining a hardened environment.

---

## Challenge B: Health Monitoring Ownership

### Conflict

Provisioning creates monitoring files as an administrator while monitoring services require access.

### Decision

Ownership transferred to the monitoring service.

### Reasoning

Monitoring systems can access health information without elevated privileges.

---

## Challenge C: Log Rotation and Service Monitoring

### Conflict

Rotated logs require monitoring services to continue reading current files.

### Options Considered

1. Reload service.
2. Restart service.

### Decision

Service restart was selected.

### Reasoning

The monitoring service does not support reload operations.

---

## Challenge D: Existing Package State

### Conflict

Previously modified systems may not match expected versions.

### Decision

The script validates existing state and converges safely.

### Reasoning

Reducing unexpected changes lowers operational risk.
