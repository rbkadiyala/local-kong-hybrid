# Proof Of technology (Docker) — Copy / Paste

Follow these exact commands in a terminal to bring up the lab.

---

## 1) Prepare working directory

```bash
mkdir -p ~/local-kong-hybrid/certs
cd ~/local-kong-hybrid
```

---

## 2) Generate certificates

```bash
cd certs
openssl genrsa -out cluster.key 2048
openssl req -new -x509 -key cluster.key -out cluster.crt -days 365 -subj "/CN=kong_clustering"
cd ..
```

---

## 3) Create `kong.env.example`

```bash
cat > kong.env.example <<'EOF'
# Database
KONG_DATABASE=postgres
KONG_PG_HOST=postgres
KONG_PG_PASSWORD=changeme
KONG_PG_USER=kong
KONG_PG_DATABASE=kong

# Hybrid mode certs
KONG_CLUSTER_CERT=/certs/cluster.crt
KONG_CLUSTER_CERT_KEY=/certs/cluster.key
KONG_CLUSTER_MTLS=shared

# Ports
KONG_ADMIN_LISTEN=0.0.0.0:8001
KONG_CLUSTER_LISTEN=0.0.0.0:8005
KONG_PROXY_LISTEN=0.0.0.0:8000
EOF
```

---

## 4) Create `kong.env` by copying `kong.env.example` and updating password

```bash
cp kong.env.example kong.env
sed -i 's/KONG_PG_PASSWORD=changeme/KONG_PG_PASSWORD=<yourocalpassword>/' kong.env
```

---

## 5) Create `docker-compose-migrations.yml`

```bash
cat > docker-compose-migrations.yml <<'EOF'
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: kong
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong
    volumes:
      - kong_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "kong"]
      interval: 2s
      timeout: 5s
      retries: 10

  kong-migrations:
    image: kong:3.9.1
    env_file: kong.env
    depends_on:
      postgres:
        condition: service_healthy
    command: >
      sh -c "kong migrations bootstrap && kong migrations up && kong migrations finish"
    volumes:
      - ./certs:/certs

volumes:
  kong_pgdata:
EOF
```

---

## 6) Create `docker-compose.yml`

```bash
cat > docker-compose.yml <<'EOF'
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: kong
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong
    volumes:
      - kong_pgdata:/var/lib/postgresql/data

  kong-cp:
    image: kong:3.9.1
    env_file: kong.env
    environment:
      KONG_ROLE: control_plane
    ports:
      - "8001:8001"
      - "8005:8005"
    volumes:
      - ./certs:/certs
    depends_on:
      - postgres

  kong-dp:
    image: kong:3.9.1
    env_file: kong.env
    environment:
      KONG_ROLE: data_plane
      KONG_DATABASE: "off"
      KONG_CLUSTER_CONTROL_PLANE: kong-cp:8005
    ports:
      - "8000:8000"
    volumes:
      - ./certs:/certs
    depends_on:
      - kong-cp

volumes:
  kong_pgdata:
EOF
```

---

## 7) Start Kong migrations

```bash
docker compose -f docker-compose-migrations.yml up --abort-on-container-exit
docker rm kong-hybrid-kong-migrations-1
```

---

## 8) Start Kong

```bash
docker compose up -d
```

---

## 9) Verify Control Plane (CP) status

```bash
curl http://localhost:8001/status
```

Expected fields: `database.reachable = true` and `role = control_plane`.

---

## 10) Verify Data Plane (DP) logs

```bash
docker logs  kong-hybrid-kong-dp-1 --tail 100
```

Look for lines similar to `connected to control plane`.

---

## 11) Create a test service and route

```bash
curl -X POST http://localhost:8001/services --data name=httpbin --data url=http://httpbin.org

curl -X POST http://localhost:8001/services/httpbin/routes --data paths[]=/test
```

---

## 12) Test via Kong

```bash
curl http://localhost:8000/test/get
```

---

## 13) Enable key-auth plugin and create consumer

```bash
# List services, routes, and cluster status
curl http://localhost:8001/services
curl http://localhost:8001/routes
curl -s http://localhost:8001/clustering/status | jq

# Add key-auth plugin to the httpbin service
curl -X POST http://localhost:8001/services/httpbin/plugins --data "name=key-auth"

# Create a consumer and generate an API key
curl -X POST http://localhost:8001/consumers --data "username=testuser"
curl -X POST http://localhost:8001/consumers/testuser/key-auth

# Test unauthorized request (should fail 401)
curl http://localhost:8000/test/get

# Test authorized request using API key
curl -H "apikey: <api-key>" curl http://localhost:8000/test/get
```

---

## 14) Cleanup

```bash
docker compose down -v
```
