# n8n + WhatsApp Automation

> Automate WhatsApp messages and workflows without writing complex code — powered by n8n, PostgreSQL, and Redis, all running inside Docker.

---

## What is this project?

This project sets up a **self-hosted automation platform** that can send and receive WhatsApp messages as part of automated workflows.

Think of it like building your own version of Zapier or Make — but running entirely on your own computer or server, so your data never leaves your control.

### The pieces that make it work

| Piece | What it does | Think of it as... |
|---|---|---|
| **n8n** | Runs your automation workflows | The brain |
| **PostgreSQL** | Stores all workflow data and history | The filing cabinet |
| **Redis** | Queues jobs so nothing gets lost | The waiting room |
| **pgAdmin** | A web page to look inside the database | A window into the filing cabinet |
| **Docker** | Runs everything in neat, isolated boxes | The Lego base plate |

---

## Requirements

Before you start, you need two things installed:

### 1. Docker Desktop
Docker is the tool that runs all the services for you. You do not need to install PostgreSQL or Redis manually — Docker handles everything.

Download it from the official Docker website and follow the installer.

### 2. WSL2 (Windows only)

> **If you are on Windows, this step is mandatory.**

WSL2 (Windows Subsystem for Linux 2) lets you run Linux commands on Windows. The startup script for this project is written in Bash, which requires WSL2.

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

Restart your computer when prompted. After restarting, open the **Ubuntu** app (or whichever Linux distribution was installed) and use that terminal for all the steps below.

**Mac and Linux users:** WSL2 is not needed. Just open your normal terminal.

---

## Setup — step by step

### Step 1 — Get the project files

```bash
git clone <repository-url>
cd e2e_n8n_whatsapp_automation
```

### Step 2 — Set up your configuration

The project uses a file called `.env` to store settings. This file is **not included in the repository** because it contains passwords and secret keys. You need to create it from the example template:

```bash
cp .env.example .env
nano .env
```

You **must** change these values before running anything:

#### Change your database password

Find these two lines and replace `n8n` with a strong password of your choice. **Both must match.**

```dotenv
POSTGRES_PASSWORD=your-strong-password-here
DB_POSTGRESDB_PASSWORD=your-strong-password-here
```

#### Set your pgAdmin login (optional)

pgAdmin is a web page for looking inside the database. By default it logs in with `admin@example.com` / `change_me`. Update these to your own values:

```dotenv
PGADMIN_DEFAULT_EMAIL=you@example.com
PGADMIN_DEFAULT_PASSWORD=your-strong-password-here
```

#### Generate a secret encryption key

n8n uses this key to protect your saved credentials. Generate one by running:

```bash
openssl rand -hex 32
```

Copy the result and paste it into your `.env`:

```dotenv
N8N_ENCRYPTION_KEY=paste-your-generated-key-here
```

> Keep this key safe. If you lose it, you will lose access to all credentials stored in n8n. Never share it with anyone.

#### Set your timezone (optional)

```dotenv
GENERIC_TIMEZONE=Europe/London
```

Replace `Europe/London` with your own timezone if needed. A full list is available at [en.wikipedia.org/wiki/List_of_tz_database_time_zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones).

#### Secure cookie (optional)

```dotenv
N8N_SECURE_COOKIE=false
```

Set to `false` when running locally (HTTP). Set to `true` in production when your n8n is accessible via HTTPS — browsers will refuse to store the login cookie otherwise.

### Step 3 — Start the services

Run the startup script:

```bash
./start_services.sh
```

A menu will appear. Choose a number to start a specific service, press `a` to start everything at once, or press `q` to quit.

That is it. n8n will be available at **http://localhost:5678** in your browser.

---

## Project structure

```
.
├── .env                        # Your configuration (passwords, keys, settings)
├── start_services.sh           # Interactive startup script (requires Bash / WSL2)
├── stop_services.sh            # Interactive shutdown script (requires Bash / WSL2)
├── export_workflows.sh         # Saves a copy of all your n8n workflows as JSON files
├── README.md                   # This file
└── build/
    ├── docker-compose.yml      # Defines all services and how they connect
    ├── n8n/
    │   ├── local-files/        # Files placed here are accessible inside n8n at /files
    │   ├── redact_workflow.js  # Masks secrets in workflows, run inside the n8n container
    │   └── workflows_backup/   # JSON copies of your workflows, created by export_workflows.sh
    ├── pgadmin/
    │   └── servers.json        # Pre-configures the connection to the postgres database
    ├── postgres/
    │   └── init/               # SQL scripts here run automatically when the database is created
    └── redis/
        └── redis.conf          # Redis configuration (persistence, memory limits, security)
```

---

## Useful commands

### Start services

```bash
./start_services.sh
```

A menu will appear. Choose a number to start a specific service, or press `a` to start everything at once.

### Stop services

```bash
./stop_services.sh
```

The same menu style — choose a service to stop individually, or press `a` to stop everything.

### Back up your workflows

```bash
./export_workflows.sh --all      # every workflow, including archived ones
./export_workflows.sh --active   # only workflows that are not archived
```

Saves a JSON copy of your workflows into `build/n8n/workflows_backup/`, one file per workflow, named after the workflow itself (e.g. `My workflow.json`). Run this whenever you want to save your progress, then commit the folder to git so your workflows are backed up.

**Sensitive values are masked automatically, inside the n8n container.** If a workflow has API keys, tokens, passwords, names, emails, phone numbers or other personal/company details typed directly into it, a small script runs inside the n8n container and replaces them with `*******` before the files ever reach your computer — so it is safe to commit the result to GitHub. The script also masks the workflow owner's name and email (the `project.name (workflow owner)` field n8n adds automatically). The script prints the name of every masked field, e.g.:

```
⚠ Masked sensitive value(s) in 'My workflow.json':
    - cal_api_key
    - profissional_nome
    - profissional_email
    - project.name (workflow owner)
    - 1 additional value(s) matched known secret formats
```

> **Restoring after re-import:** open the workflow's JSON file and search for `*******` — each one sits next to its original field name (e.g. `"name": "cal_api_key", "value": "*******"`), so you know exactly which value to paste back in after importing it into n8n. The `project.name (workflow owner)` field is the exception — it is just ownership metadata, n8n reassigns it automatically on import, so it does not need to be restored.

### Delete all data (full reset)

```bash
docker compose -f build/docker-compose.yml --env-file .env down -v
```

> The `-v` flag removes all saved data, including your workflows and credentials. Only use this if you want to start completely from scratch.

### Check what is running

```bash
docker compose -f build/docker-compose.yml --env-file .env ps
```

---

## Accessing n8n

Once the services are running, open your browser and go to:

```
http://localhost:5678
```

The first time you open it, n8n will ask you to create an account. This account is stored locally — it is not connected to any external service.

---

## Accessing pgAdmin

pgAdmin lets you look inside the PostgreSQL database using a web page. Once the services are running, open your browser and go to:

```
http://localhost:5050
```

Log in using the email and password you set in `PGADMIN_DEFAULT_EMAIL` and `PGADMIN_DEFAULT_PASSWORD`.

A connection to the database (called **n8n Postgres**) is already set up for you. The first time you open it, pgAdmin will ask for the database password — this is the value you set in `POSTGRES_PASSWORD`.

---

## Troubleshooting

**The script says `docker not found`**
Install Docker Desktop and make sure it is running before trying again.

**n8n does not open in the browser**
Wait 30 seconds after starting the services — n8n waits for PostgreSQL and Redis to be fully ready before it starts.

**pgAdmin asks for a "master password"**
This is a separate password used only by pgAdmin itself, not your database password. You can set any password you like — it is just used to encrypt saved connection details on your machine.

**I lost my encryption key**
Unfortunately there is no way to recover it. You will need to reset n8n by running `down -v` and starting again from Step 2.

**Permission denied when running the script on Mac/Linux**
Make the script executable:
```bash
chmod +x start_services.sh
```
