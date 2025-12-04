# 🚲 Bay Wheels — Deliverables by Role  
## Station Balancer Project

---

# Person A — Data Engineering & Forecasting Lead

## 🛠 Technical Deliverables

### 1. Historical Data Pipeline
- Scripts/DAGs for ingesting Bay Wheels CSVs into PostgreSQL  
- Station ID normalization logic  
- Validated schemas for:  
  - `trip_history`  
  - `station`  
  - `station_flow_features`

### 2. Feature Engineering Outputs
- `mv_station_flow_15min` materialized view  
- Rolling averages, net flows, time-based patterns  
- Annotated SQL scripts

### 3. Forecasting System
- `forecast_station_status` table  
- Mixed forecast model (historical + short-term live trend)  
- Accuracy evaluation charts

### 4. Suggestion Candidate Generator
- SQL + Python logic generating:  
  `suggestion_candidates(suggestion_id, from_station_id, to_station_id, qty, reason, created_at)`  
- Documentation on suggestion formation methodology

---

## 📘 Documentation Deliverables
- README: *Data Pipeline & Forecasting*  
- ERD for ingestion tables  
- Forecasting methodology overview  
- Comments for complex SQL aggregations

## 🎥 Demo Deliverables
- Show ingestion pipeline  
- Show materialized views + query plans  
- Display forecast table and example predictions  

---

# Person B — Backend Orchestration & Task Dispatch Lead

## 🛠 Technical Deliverables

### 1. Backend API Endpoints (FastAPI/Flask)
- `/suggestions` — fetch suggestion candidates  
- `/task/approve` — convert suggestion → task  
- `/dispatch/next` — SKIP LOCKED dispatcher  
- `/task/{id}/complete` — transactional update

### 2. Task Lifecycle Logic
- Deduplication to prevent duplicate tasks  
- Tasks only created on approval  
- Status flow: *ready → assigned → completed*

### 3. Concurrency & Transaction Handling
- `FOR UPDATE SKIP LOCKED` dispatching  
- `SERIALIZABLE` isolation level  
- Advisory locks on station IDs  
- Retry logic for serialization failures (40001)

### 4. Database Logic
- Schemas for task + assignment  
- Indexes for fast lookup  
- Station inventory adjustment logic

---

## 📘 Documentation Deliverables
- README: *Backend Architecture & Transaction Handling*  
- Sequence diagrams for suggestion approval + dispatch lifecycle  
- Annotated SQL for transactions  
- API documentation (OpenAPI)

## 🎥 Demo Deliverables
- Deduplication demonstration  
- Two-worker concurrency demo  
- Transaction + advisory lock behavior showcase  

---

# Person C — Live Data Integration & Dashboard Lead

## 🛠 Technical Deliverables

### 1. GBFS Integration
- Polling scripts for station status/information  
- Storage to `station_status_snap`  
- Query logic for latest snapshot per station

### 2. Frontend Dashboard
- Map visualization (Leaflet/Mapbox)  
- Suggestion list with **Approve Task** buttons  
- Live task list  
- Imbalance indicators  
- Trend charts (stockout %, flows, etc.)

---

## 📘 Documentation Deliverables
- README: *Dashboard + Live Data Integration*  
- GBFS poller instructions  
- Dashboard UI screenshots

## 🎥 Demo Deliverables
- Real-time station view  
- Approving a suggestion live (UI → backend → DB)

---

# Person D — Infrastructure, Optimization & Testing Lead

## 🛠 Technical Deliverables

### 1. Deployment
- Docker Compose (DB + Backend + UI)  
- Cloud deployment setup  
- Environment configuration scripts

### 2. Database Performance
- Indexing strategies  
- `EXPLAIN ANALYZE` benchmarks  
- Partitioning for large tables  
- Query tuning and caching

### 3. Testing & QA
- End-to-end flow tests  
- Data integrity tests  
- Load testing for dispatch concurrency  
- GBFS polling resilience tests

---

## 📘 Documentation Deliverables
- README: *Deployment + Performance Optimization*  
- Query optimization summary  
- EXPLAIN plan screenshots  
- Testing instructions  
- CI/CD notes

## 🎥 Demo Deliverables
- Indexing impact demo  
- Grafana metrics  
- Running test cases  
- Full containerized demo  
