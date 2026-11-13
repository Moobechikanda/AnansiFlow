# AnansiFlow Deployment Checklist

## Isolated local recovery test

The local recovery test uses a disposable copy of the recovered database, not
the restored production volume. It has separate Redis and storage volumes,
and Rails is attached only to an internal network. A reverse proxy publishes
the test app only at `http://localhost:9001`. Test emails are captured locally
at `http://localhost:9002` and are not delivered to real inboxes. External
integrations cannot be tested in this configuration, and Sidekiq is disabled
by default. Starting Sidekiq runs scheduled jobs against the disposable data.

With the restricted `.env.anansiflow.production.local` file, the
`anansiflow:local` image, and the `anansiflow_credcheck_pg_20261111` test
volume already available, start the local test with:

```powershell
docker compose --env-file .env.anansiflow.production.local -f docker-compose.local-test.yaml up -d --no-build --pull never postgres redis rails mailpit proxy
```

Stop the test without deleting its volumes:

```powershell
docker compose --env-file .env.anansiflow.production.local -f docker-compose.local-test.yaml stop
```

This is not a production deployment. Once a public domain is ready, configure
the public HTTPS `FRONTEND_URL` and Caddy `SITE_DOMAIN` separately, and review
database freshness, Sidekiq, integrations, secrets and backups before cutover.

## Local startup

Run from the repository root:

```powershell
npm run dev
```

The terminal prints plain, account-independent links: `http://localhost:9000/` for the dashboard and `http://localhost:9000/zedreply-customer-test.html` for the sample customer chat. To test a real business, sign in, select its website inbox under **Settings > Inboxes**, and click **Open live test chat**. That link uses the selected inbox's own assistant and business settings.

Docker Desktop must be running. `npm run dev` starts the Docker services in the background. It prints both local URLs before starting Docker and opens the dashboard when Rails is ready.

`npm run dev` runs the code in this repository. It reuses the pulled `chatwoot/chatwoot` image for gems and the Ruby runtime, and bind-mounts `app/`, `enterprise/`, `config/`, `lib/`, `db/` and `public/vite` over it, so no image build is needed. Image builds fail whenever Docker Desktop cannot reach Alpine, RubyGems or the npm registry.

For Oracle Cloud, create one **Always Free eligible Ampere A1 Flex VM** in your tenancy's home region, using Ubuntu ARM64. Keep it within the current Always Free limit (2 OCPUs and 12 GB memory for Always Free tenancies). Check Oracle's current storage allowance in Console before creating volumes. Free-shape capacity can be unavailable in a home region, and Oracle may require a payment card to verify the account. Oracle may reclaim idle Always Free compute instances, so this is suitable for an early pilot but does not provide a production uptime guarantee. Do not choose paid resources if you need to stay at $0. [Oracle Always Free limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) · [Oracle Always Free resources](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)

When creating the VM, choose `VM.Standard.A1.Flex`, set it to 2 OCPUs and 12 GB RAM, and select an Ubuntu ARM64 image. Keep its boot volume and any extra block volumes within the combined free storage allowance. In the VCN security list or Network Security Group, allow inbound TCP 80/443 publicly and SSH 22 only from your own IP; don't expose app, Postgres, or Redis ports. Create the VM and note its public IP.

You do not need to buy a domain to start a pilot. Create a free DuckDNS subdomain and point its DNS record to the VM public IP, then use that hostname for `SITE_DOMAIN` and `FRONTEND_URL=https://<hostname>` in `.env`. Caddy needs the hostname to resolve to the VM and inbound ports 80/443 to be open to get a trusted HTTPS certificate. A DuckDNS hostname is a temporary pilot address; replace it with your purchased domain later. Do not expose account signup over plain HTTP. Install Docker Engine, Docker Compose, and Git on the Ubuntu VM, then build and run the AnansiFlow source image with the Caddy HTTPS proxy:

```bash
docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml -f docker-compose.caddy.yaml build rails
docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml -f docker-compose.caddy.yaml up -d postgres redis
docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml -f docker-compose.caddy.yaml run --rm rails bundle exec rails db:chatwoot_prepare
docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml -f docker-compose.caddy.yaml up -d --remove-orphans
```

Caddy obtains and renews HTTPS certificates automatically when the hostname resolves to the VM and inbound ports 80 and 443 are open. The database preparation step is required; the Rails entrypoint does not automatically run migrations. The Compose Rails port remains bound to `127.0.0.1:9000`; public traffic goes through Caddy. Telegram webhooks need this stable HTTPS hostname and must be re-registered after deployment. The Dockerfile builds native Ruby/Node dependencies on the VM's ARM64 architecture; allow extra time for the first build.

After changing Ruby, view or config files, run `npm run dev` again to pick them up.
## Signup confirmation email

In the local setup, signup mail is captured by Mailpit at `http://localhost:55324/`; the local `.env` sends SMTP to `host.docker.internal:55325`. Open Mailpit to get the message. Local confirmation links must use `FRONTEND_URL=http://localhost:9000`; links already sent with an old ngrok URL cannot work after that tunnel is offline. Request a fresh confirmation email after changing the setting.

For a no-domain pilot, a dedicated personal Gmail account can send low-volume AnansiFlow signup mail from `smtp.gmail.com:587` with STARTTLS. Turn on Google 2-Step Verification and create an app password for AnansiFlow; use the full Gmail address as `SMTP_USERNAME` and the app password as `SMTP_PASSWORD`. Set `SMTP_DOMAIN=gmail.com`, `SMTP_AUTHENTICATION=login`, `SMTP_ENABLE_STARTTLS_AUTO=true`, and `MAILER_SENDER_EMAIL=AnansiFlow <your-address@gmail.com>`. Do not use the normal Google account password. Gmail's personal accounts have sending limits, so treat this as a pilot/testing path, not a long-term SaaS mail system. [Google app-password requirements](https://support.google.com/accounts/answer/185833?hl=en) · [Gmail sending limits](https://support.google.com/mail/answer/22839?hl=en-GB)

Zoho does not offer a free mailbox tier in the user's location, so it is not required for this pilot. SMTP2GO is another possible free SMTP relay (up to 1,000 emails/month and 200/day), but it is for sending only and requires sender verification; Gmail SMTP is the simpler no-domain starter. For connected company inboxes, customers connect their own mailbox separately in **Settings > Inboxes > Add Inbox > Email**. Oracle blocks outbound TCP port 25 for many newer tenancies; use an authenticated submission port such as 587. Restart Rails and Sidekiq after changing mail environment values. [SMTP2GO free plan](https://support.smtp2go.com/hc/en-gb/articles/223087947-Free-Plan) · [Oracle outbound port 25 restriction](https://docs.oracle.com/en-us/iaas/releasenotes/changes/f7e95770-9844-43db-916c-6ccbaf2cfe24/)

SMTP2GO only sends email. Incoming customer email is fetched from each connected mailbox through IMAP; connect a provider that offers IMAP or use its supported OAuth connection. A consumer Gmail mailbox commonly uses `imap.gmail.com:993` with SSL, while login may require Google OAuth or an app password. [Google app-password requirements](https://support.google.com/accounts/answer/185833?hl=en)

Public account creation is controlled by `ENABLE_ACCOUNT_SIGNUP`. Set it to `true` in the service environment and restart Rails. The current local `.env` previously disabled this, which hid signup and rejected account creation requests.

## Incoming connected-channel messages

- **Telegram:** The webhook is registered as `FRONTEND_URL/webhooks/telegram/<bot-token>`. Telegram requires a public HTTPS URL and supports webhook ports 443, 80, 88, and 8443. A localhost URL cannot receive Telegram updates. A temporary tunnel works only while its public URL and tunnel stay active; for production, set `FRONTEND_URL` to the app's stable HTTPS domain, then edit and save each Telegram inbox once to register its webhook again. [Telegram webhook requirements](https://core.telegram.org/bots/webhooks)
- **Email inboxes:** Incoming messages are fetched from the inbox's IMAP connection by the `Inboxes::FetchImapEmailInboxesJob`, scheduled every minute and processed by Sidekiq. Keep the Sidekiq worker, Redis, and its `scheduled_jobs` queue running. For Google or Microsoft inboxes, reconnect the account if its OAuth authorization has expired. Outbound SMTP for signup/agent replies is separate from this IMAP connection.
- **Website:** The web widget posts directly to the app's public HTTPS domain. The customer's browser must be able to reach that same domain and the widget SDK.

AnansiFlow itself provides the dashboard and customer-test demo page; you do not need to buy or host a separate marketing website to run the app. Each company can install its own website inbox widget on its existing website. That company's messages and assistant knowledge stay scoped to its account/inbox. The AnansiFlow customer-test page is a demo only; it is not the widget every company should share with its customers.

### Public webhook endpoints to configure with channel providers

Every callback must use the deployed HTTPS domain, for example `https://chat.example.com`; do not use `localhost`, the VM IP, or port 9000 in a provider dashboard. Port 9000 is only the private app port behind the HTTPS proxy.

| Provider/channel | Callback URL | Provider setup |
| --- | --- | --- |
| Telegram bot | `https://chat.example.com/webhooks/telegram/<bot-token>` | Save the Telegram inbox after setting `FRONTEND_URL`; AnansiFlow registers this webhook with Telegram. Keep the bot token private. |
| WhatsApp Cloud API | `https://chat.example.com/webhooks/whatsapp/<phone-number>` | Configure the Meta app's WhatsApp webhook subscription and verify token to match the channel setup. Subscribe to message events and confirm the app is subscribed to the WhatsApp Business Account. |
| Facebook Messenger | `https://chat.example.com/bot` | Configure the Facebook app Messenger webhook, use the same verify token configured in AnansiFlow, and subscribe the Page to message events. |
| Instagram messaging | `https://chat.example.com/webhooks/instagram` | Configure the Meta app Instagram webhook, matching verify token/app secret, and subscribe the Instagram account to message events. Instagram must be eligible and connected to the Meta app/Page as required by Meta. |
| SMS/Twilio | `https://chat.example.com/webhooks/sms/<phone-number-without-plus>` | Use the callback configured for the number/messaging service; voice callbacks, when enabled, use the separate Twilio callback paths. |
| Website chat | No provider webhook | Install the Website inbox's generated widget snippet on the business site and allow the deployed app domain in the inbox's website domain settings. |

Meta's Facebook, Instagram, and WhatsApp callback URLs are separate subscriptions. Configuring one does not automatically configure the others. Enter the Meta app ID, app secret, verify tokens, page/account permissions, and callback subscriptions in the app's Super Admin configuration and the Meta developer dashboard as applicable. Use the values generated for the same Meta app and channel; never commit them to Git.

Email does not use a public inbound webhook in this setup. Configure the actual mailbox's IMAP host, port, TLS, username, and app password/OAuth connection in the Email inbox settings. Configure SMTP server credentials separately for AnansiFlow account verification and outbound agent replies. The host environment's SMTP values do not configure inbox IMAP.

## Local frontend changes

`public/vite` holds the compiled dashboard, widget and portal bundles, and it is not tracked by Git. Build it on the host after changing anything under `app/javascript`:

```powershell
npm run dev:assets
```

The build needs roughly 4 GB of heap and takes around 20 minutes on a memory constrained machine. Override with `NODE_OPTIONS` if needed, then run `npm run dev` again.

## Verifying the Captain business knowledge feature

Run Captain's self-check against the live database:

```powershell
npm run verify:business-knowledge
```

For a full picture of the whole feature set:

```powershell
npm run verify:zedreply
```

This is read-only and reports, per feature: the business profile fields and product catalog prompt, the v1 and v2 prompts, the API strong params, the compiled frontend bundle, whether the website was crawled and how many knowledge responses were generated, and whether every fork feature (WhatsApp manual setup, inbox health, call recording, etc.) is loaded.

## Getting the AI chat working on the customer page

1. On a fresh database, Chatwoot runs its seeds and provisions an idempotent, fictional sample business and public chat widget so the customer test page works before anyone signs up. On an existing database, run `bundle exec rails db:seed` once after deploying this change. In development, the regular Chatwoot seed data is also created.
2. Set the OpenAI key. In the app go to **Super Admin > Settings > Config** and add:
   - Name: `CAPTAIN_OPEN_AI_API_KEY`, Value: `sk-...` (default model is `gpt-4.1-mini`).
3. For a real company, finish signup. The Captain assistant, feature flags, and website crawl are provisioned automatically during onboarding. For an account that already exists, run:
   ```powershell
   npm run captain:provision
   ```
4. Complete the **Business knowledge** fields and add products or services to the catalog on the assistant (Captain > the assistant > Settings > Basic). Archived catalog items remain saved but are excluded from answers. The assistant can use configured business profile/catalog data and approved, synced website knowledge; it cannot infer company details that have not been provided.
5. Send a test message from the assistant Playground. To test a real company website inbox, open **Settings > Inboxes > [website inbox] > Open live test chat**. The plain `/zedreply-customer-test.html` URL is the fictional sample business demo; company-specific links are generated inside the signed-in dashboard and are not printed in the terminal.

After Captain hands a conversation to an agent, a background check returns an unanswered conversation to the pending queue after five minutes. Captain waits for the customer's next message before responding. The typed Captain-assignee rollout flag remains locked off in this deployment config; enable it only after all web and worker processes have been upgraded to read typed assignees.
## AI

Configure the OpenAI Project API key through the Chatwoot Super Admin configuration or the protected Rails database configuration. Do not commit API keys or place them in a public file.

Recommended starting model: `gpt-4.1-mini`.

Create one Captain assistant per business or support policy, assign it to the correct inbox, and add the company's verified services, prices, hours, policies, and escalation rules before enabling customer replies.

For a company website, register it with the assistant from PowerShell:

```powershell
.\scripts\zedreply-add-website.ps1 -WebsiteUrl https://company.example
```

Captain queues the crawl and makes the synced website available to the assistant. Review the sync status and remove inaccurate pages before enabling automatic replies.

The assistant distinguishes the AnansiFlow platform from the current customer company. Company-specific answers must come from approved account knowledge or synced website documents.

## Channel credentials

Each channel has separate credentials. AnansiFlow does not use one universal social-media key.

| Channel | Credentials needed | Configuration location |
| --- | --- | --- |
| Website chat | Website domain and generated website token | Chatwoot Settings > Inboxes > Website |
| WhatsApp | Meta Business account, WhatsApp Business phone number, permanent access token, phone number ID, business account ID, webhook verification token | Chatwoot Settings > Inboxes > WhatsApp |
| Email | SMTP host, port, username, password, TLS mode, sender address; optional IMAP/inbound settings | `.env` for server mail settings and Chatwoot email inbox settings |
| SMS | Twilio or Bandwidth account SID, auth token, sender phone number, webhook URL | Chatwoot Settings > Inboxes > SMS |
| Telegram | Bot token from BotFather | Chatwoot Settings > Inboxes > Telegram |
| Facebook Messenger | Meta app ID, app secret, verify token, page access token | `.env` and Chatwoot Facebook inbox setup |
| Instagram | Meta app/page credentials and Instagram professional account | Meta setup and Chatwoot inbox setup |
| Slack | Client ID, client secret, signing secret, redirect URL | `.env` and Chatwoot Integrations |
| Google OAuth | Client ID, client secret, callback URL | `.env` |
| Cloud storage | S3 bucket, access key, secret key, region | `.env` |

Only configure channels a company actually uses. Empty optional values are expected for unused channels.

## Backups

For an early pilot, use a VPS provider with managed Postgres and S3-compatible object storage. Good options include:

- Oracle Cloud Always Free VM + backups stored outside the VM, while staying inside the account's free allowances
- AWS Lightsail or EC2 + RDS + S3
- Render or Railway for the application and managed PostgreSQL, where Chatwoot's runtime requirements are supported

Back up both PostgreSQL and `/app/storage`. Database backups alone do not protect uploaded attachments.

Recommended minimum policy:

- Daily automated PostgreSQL backups
- Object-storage versioning for uploaded files
- One weekly backup copied to a separate account or region
- Monthly restore test
- Secrets stored in the hosting provider's secret manager, not Git

## Production readiness

Before serving real customers:

1. Deploy behind HTTPS with a real domain.
2. Set `FRONTEND_URL` to that stable public HTTPS origin and configure Google/Microsoft OAuth callback URLs for the same domain.
3. Set `ENABLE_ACCOUNT_SIGNUP=true` if customers should be able to create accounts, and configure production SMTP with a sender on a domain you control.
4. Run Rails and Sidekiq continuously against the same Postgres and Redis services; configure durable object storage for attachments.
5. Re-save Telegram inboxes after setting the production URL, then send a real message to each channel and confirm it appears in the correct inbox.
6. Confirm inbound email IMAP settings and send a test email; verify it appears in the correct inbox.
7. Replace the demo AnansiFlow knowledge with verified company information.
8. Add real agents and define escalation ownership.
9. Set OpenAI spending limits and usage alerts.
10. Enable database and storage backups.
11. Run a pilot with one company before adding more accounts.

## Account offboarding

To begin the existing delayed account-deletion workflow:

```powershell
.\scripts\zedreply-delete-account.ps1 -AccountId 2
```

The command requires typing `DELETE` and marks the account for deletion in seven days. This gives an administrator time to cancel the request before permanent cleanup runs.
