# Laravel Production Deploy

An interactive, modular bash script that sets up a **production-ready Laravel application** on a fresh **Ubuntu 24.04 LTS** server from scratch — fully automated, with resume support if anything breaks mid-run.

---

## Features

- Single command deploys a complete Laravel stack
- Modular scripts — each concern is isolated in its own file
- **Resume support** — if a step fails, re-run and pick up from where it broke
- Interactive prompts with sensible defaults
- Private repo support via GitHub Personal Access Token (PAT)
- Cloudflare Origin Certificate SSL (paste-in)
- Optional Node.js + frontend asset build
- Optional swap memory (recommended for servers with ≤ 1 GB RAM)
- Supervisor queue worker + Laravel scheduler cron auto-configured

---

## What Gets Installed

| Software                 | Version / Notes                                                   |
| ------------------------ | ----------------------------------------------------------------- |
| **Nginx**                | Latest stable, from Ubuntu repo                                   |
| **PHP-FPM**              | Configurable (default: 8.5), via `ppa:ondrej/php`                 |
| **PHP Extensions**       | `pgsql`, `mbstring`, `xml`, `curl`, `zip`, `bcmath`, `intl`, `gd` |
| **Composer**             | Latest stable (installed globally)                                |
| **PostgreSQL**           | Latest stable, from Ubuntu repo                                   |
| **Supervisor**           | Queue worker process manager                                      |
| **Node.js** _(optional)_ | Configurable major version (default: 22), via NodeSource          |
| **npm** _(optional)_     | Bundled with Node.js                                              |
| **UFW**                  | Firewall — allows SSH, HTTP (80), HTTPS (443)                     |

---

## Requirements

- A fresh **Ubuntu 24.04 LTS** server (VPS, cloud VM, dedicated)
- Root or sudo access
- A domain name pointed at the server's IP
- A Cloudflare account with **Origin Certificate** generated for the domain
- Your Laravel project in a Git repository (public or private)

---

## Repository Structure

```
deploy.sh               ← main entry point — run this
scripts/
  00_config.sh          ← interactive prompts and configuration
  01_system_tools.sh    ← system packages, UFW, Nginx, PHP, Composer, Node.js
  02_database.sh        ← PostgreSQL install, password, database creation
  03_app_setup.sh       ← git clone/pull, .env, Composer, artisan commands
  04_ssl.sh             ← Cloudflare Origin Certificate install
  05_services.sh        ← Supervisor queue worker + cron scheduler
  06_nginx.sh           ← Nginx virtual-host config + reload
  07_frontend.sh        ← swap memory, npm build, final permission fix
```

---

## Usage

### 1. Clone this repository onto your server

```bash
git clone https://github.com/dransidu/laravel_deploy.git
cd laravel_deploy
```

### 2. Make the script executable

```bash
chmod +x deploy.sh scripts/*.sh
```

### 3. Run as root

```bash
sudo bash deploy.sh
```

### 4. Answer the prompts

The script will ask you for the following:

| Prompt                                | Description                                                   |
| ------------------------------------- | ------------------------------------------------------------- |
| **App name**                          | Identifier used for file paths, DB name, log names (required) |
| **Domain**                            | Your domain, e.g. `app.example.com` (required)                |
| **Git repo URL**                      | SSH or HTTPS URL of your Laravel project                      |
| **Branch**                            | Git branch to deploy (default: `main`)                        |
| **Database name**                     | PostgreSQL database name (default: app name)                  |
| **Database user**                     | PostgreSQL user (default: `postgres`)                         |
| **Database password**                 | Leave blank to auto-generate a secure password                |
| **PHP version**                       | PHP version to install (default: `8.5`)                       |
| **Node.js major version**             | Only used if you enable Node.js (default: `22`)               |
| **App environment**                   | `production` / `staging` etc. (default: `production`)         |
| **App debug**                         | `true` or `false` (default: `false`)                          |
| **Node heap memory MB**               | Max RAM for npm build (default: `1536`)                       |
| **Add swap memory?**                  | Recommended if server RAM is 1 GB or less                     |
| **Full DB reset?**                    | ⚠️ Drops and recreates the database — **deletes all data**    |
| **Install Node.js + frontend build?** | Only needed if your app has a frontend build step (Vite, Mix) |

After answering, a summary is shown and you must confirm before anything runs.

---

## Private Repository

If your Laravel project is in a **private GitHub repository**, use HTTPS with a Personal Access Token (PAT):

```
https://<YOUR_PAT>@github.com/your-username/your-repo.git
```

To generate a PAT:

1. Go to **GitHub → Settings → Developer settings → Personal access tokens**
2. Create a token with `repo` (read) scope
3. Paste the URL above when prompted for the repo URL

> **Security note:** The PAT is embedded in the Git remote URL stored on the server. After deploy you can remove it from the remote with:
>
> ```bash
> git -C /var/www/<appname> remote set-url origin git@github.com:your-username/your-repo.git
> ```

---

## SSL — Cloudflare Origin Certificate

This script uses **Cloudflare Origin Certificates** (not Let's Encrypt). This is designed for setups where Cloudflare sits in front of your server as the proxy/CDN.

**Before running the script, generate your certificate:**

1. Cloudflare Dashboard → your domain → **SSL/TLS → Origin Server**
2. Click **Create Certificate**
3. Choose key type (RSA recommended) and set validity
4. Copy the **Origin Certificate** and **Private Key** — you will need to paste them during the deploy

During **Step 4**, the script will ask you to paste each one into the terminal followed by a sentinel word (`ENDCERT` / `ENDKEY`).

---

## Resume Support

If the script fails partway through (e.g. a network timeout, a migration error), **just run it again**:

```bash
sudo bash deploy.sh
```

It will detect the previous run and ask:

```
A previous deployment state was found.
Resume from last run? (y/N):
```

- **y** — reloads your previous configuration and skips all steps that already completed successfully
- **N** — wipes the state and starts a full fresh deployment

State is stored in `/var/tmp/laravel_deploy_state/` and is automatically deleted when the full deployment completes.

---

## What Happens After Deployment

| Item                   | Location                                      |
| ---------------------- | --------------------------------------------- |
| App files              | `/var/www/<appname>/`                         |
| Nginx site config      | `/etc/nginx/sites-available/<appname>`        |
| SSL certificate        | `/etc/ssl/certs/<appname>.crt`                |
| SSL private key        | `/etc/ssl/private/<appname>.key`              |
| Queue worker log       | `/var/log/<appname>-queue.log`                |
| Supervisor config      | `/etc/supervisor/conf.d/<appname>-queue.conf` |
| Laravel scheduler cron | `/etc/cron.d/<appname>-scheduler`             |

### Useful commands after deploy

```bash
# Check queue worker
sudo supervisorctl status

# Restart queue worker
sudo supervisorctl restart <appname>-queue:*

# Check PHP-FPM
systemctl status php8.5-fpm

# Check Nginx
systemctl status nginx
nginx -t

# Check swap
swapon --show

# Tail queue log
tail -f /var/log/<appname>-queue.log
```

---

## Re-deploy / Update Application

To pull new code and re-run artisan commands without touching server config, you can run just the app setup step manually (after sourcing your config):

```bash
# Quick code update only (git pull + composer + artisan)
cd /var/www/<appname>
git pull origin main
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
sudo supervisorctl restart <appname>-queue:*
```

Or run the full deploy script — it will detect the existing git repo and do a `git fetch + reset --hard` instead of a fresh clone.

---

## Tested On

- Ubuntu 24.04 LTS (x86_64)
- DigitalOcean, Hetzner, Vultr droplets/VPS

---

## License

MIT — free to use, modify, and distribute.
