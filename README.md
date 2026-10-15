# Maratón

*Tu diario de series.* A TV diary: track the episode you're on, rate and review shows, and pin your all-time Top 4. Built by Patricia for the Wiz Technical Exercise.

> This environment is **intentionally insecure** to meet the exercise requirements (public SSH, outdated OS and MongoDB, cluster-admin pod, public backup bucket). Do not reuse it for anything real.

## Repo layout

```
app/                 Node.js + Express + MongoDB web app and its Dockerfile
docker-compose.yml   Local dev: app + MongoDB 4.4
terraform/           AWS infrastructure, deployed through HCP Terraform (see terraform/README.md)
k8s/                 Kubernetes manifests (see k8s/README.md)
.github/workflows/   iac.yml (scan + HCP Terraform) and app.yml (build, scan, push, deploy)
.trivyignore         Accepted risks: the exercise's intentional weaknesses, each justified
```

## Run it locally

You need Docker Desktop.

```bash
docker compose up --build              # starts MongoDB 4.4 and the app
docker compose run --rm app node seed.js   # loads 4 demo users and their shows
```

Open http://localhost:3000 and sign in as `patricia@maraton.demo` with password `maraton-demo`.

Check the exercise file inside the container:

```bash
docker compose exec app cat /app/wizexercise.txt
```

Peek at the data in MongoDB:

```bash
docker compose exec mongo mongo -u admin -p local-dev-only --authenticationDatabase admin maraton \
  --eval 'db.shows.find({}, {title: 1, status: 1, progress: 1}).forEach(printjson)'
```

## How the app is configured

| Variable | Purpose |
| --- | --- |
| `MONGODB_URI` | Connection string, set from a Kubernetes environment variable (required) |
| `SESSION_SECRET` | Signs the login cookie |
| `PORT` | Defaults to 3000 |

Health checks for Kubernetes: `/healthz` (process is up) and `/readyz` (MongoDB is reachable).
