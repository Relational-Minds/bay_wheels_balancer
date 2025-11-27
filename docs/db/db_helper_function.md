# 📘 Sections : Database Helper Functions

# 🔧  Database Helper Functions

## `refresh_balancer_materialized_views()`

A PostgreSQL helper function used to refresh the system’s analytical materialized views.

### **Purpose**
The system relies on two materialized views for analytics:
- `station_flows` – inflow/outflow trends based on historical trips  
- `imbalance_scores` – real-time scoring based on latest live status  

These views can become outdated as new data arrives.  
This function refreshes them **without blocking reads**, using `CONCURRENTLY`.

### **Function Definition**
```sql
CREATE OR REPLACE FUNCTION refresh_balancer_materialized_views()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY station_flows;
  REFRESH MATERIALIZED VIEW CONCURRENTLY imbalance_scores;
END;
$$;
