                               ┌────────────────────────┐
                               │  Historical Trip CSVs  │
                               └──────────────┬─────────┘
                                              │
                               (ETL Pipeline Loads Trips)
                                              │
                                              ▼
                                      ┌───────────────┐
                                      │     trips     │
                                      └───────────────┘
                                              │
                     ┌────────────────────────┴────────────────────────┐
                     │                                                 │
                     ▼                                                 ▼
         ┌────────────────────┐                          ┌─────────────────────────┐
         │  station_flows MV  │   (inflow/outflow)       │   station_status table  │
         └────────────────────┘                          └─────────────────────────┘
                                                                ▲
                                                                │
                                       (worker-gbfs polls GBFS feed every 30–60 sec)
                                                                │
                                                                ▼
                                 ┌──────────────────────────────────────────┐
                                 │   imbalance_scores MV (real-time view)  │
                                 └──────────────────────────────────────────┘
                                                │             │
                             ┌──────────────────┘             └──────────────────┐
                             ▼                                                 ▼
                ┌──────────────────────┐                         ┌──────────────────────────┐
                │    Backend API       │   (creates tasks)       │   Frontend Dashboard     │
                └──────────────────────┘                         └──────────────────────────┘
                             │                                                 │
                             ▼                                                 ▼
                ┌──────────────────────┐                         ┌──────────────────────────┐
                │ Rebalancing Tasks DB │                         │    Critical Stations     │
                └──────────────────────┘                         └──────────────────────────┘

## 🚲 Bike-Sharing System Architecture Summary

This system integrates real-time and historical data to optimize bike distribution.

* **Real-Time Data Ingestion:** A **GBFS worker** polls the General Bikeshare Feed Specification to bring in **real-time bike availability** data.
* **Historical Data Ingestion:** **ETL pipelines** are responsible for loading and processing **historical trip data**.
* **Data Transformation:** **Materialized views** (MVs) are used to transform the raw data from both sources into **actionable insights** (e.g., station flows, imbalance scores).
* **Backend Operations:** The **Backend API** utilizes the imbalance scores to programmatically create and assign **rebalancing tasks** to field teams.
* **Visualization and Monitoring:** The **Frontend dashboard** visualizes **critical stations**, active **tasks**, and overall system health for operational monitoring.
