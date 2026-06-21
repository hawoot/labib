# Handoff: enable push-notification sending on the labib backend

You are an agent running on the **server** that hosts the labib backend. Your job
is to switch on **push-notification sending** by giving the backend its Firebase
**service-account** credentials, then verifying it works. All the application code
is already written and merged to `main`; this is a **deployment/config task only**.

---

## 1. Background — what already exists (no code changes needed)

The labib app now has native push notifications (Android/FCM). The full chain was
implemented and merged in PR #29 on `main`:

- **Phone side (done):** the Android app gets an FCM token and registers it via
  `POST /notifications/register-device`. The client config `google-services.json`
  is committed at `frontend/firebase/google-services.json`.
- **Server side (code done, credential missing):** the backend can send pushes,
  but only once it has a Firebase **service-account key**. Relevant code:
  - `backend/app/push.py` — FCM sender. Lazily initializes `firebase-admin`.
    If no credential is configured it raises `PushNotConfigured`, and the API
    returns **HTTP 503 "push isn't configured"** instead of crashing.
  - `backend/app/routers/notifications.py` — endpoints:
    `POST /notifications/register-device`, `/unregister-device`, `/test`.
  - `backend/app/config.py` — reads two settings (from env / `.env`):
    - `FIREBASE_CREDENTIALS_FILE` — path to the service-account `.json`, **or**
    - `FIREBASE_CREDENTIALS_JSON` — the whole JSON as a single-line string.
    If both are empty → push is **disabled**.
  - `backend/requirements.txt` — now includes **`firebase-admin>=6.5`** (NEW dep).

**The human has already downloaded the service-account JSON** from the Firebase
console (Project settings → Service accounts → Generate new private key). It is a
file named like `labib-190ad-firebase-adminsdk-XXXXX.json`. It is a SECRET (it is
NOT a single API key — the whole file is the credential).

---

## 2. The task

1. Make sure the deployed backend is on the **latest `main`** (which contains the
   push code + the new `firebase-admin` dependency).
2. Install/refresh Python deps so **`firebase-admin` is installed** (this is the
   #1 thing people forget — see gotchas).
3. Place the service-account JSON on the server, readable by the backend process,
   **without committing it to git**.
4. Configure **one** of:
   - `FIREBASE_CREDENTIALS_FILE=<path to the json>`  (recommended), or
   - `FIREBASE_CREDENTIALS_JSON='<minified one-line json>'`
   in the same place other secrets like `LLM_API_KEY` are set.
5. **Restart** the backend.
6. **Verify** (see section 5). Report back the result.

Recommended approach: the **file** option. Save the key as
`firebase-service-account.json` next to the backend's `.env`, set
`FIREBASE_CREDENTIALS_FILE=./firebase-service-account.json`. (`.gitignore` already
excludes `firebase-service-account.json` and `*-firebase-adminsdk-*.json`.)

---

## 3. Investigation questions (figure these out on the box)

1. **How is the backend run?** docker-compose? a systemd service? bare
   `uvicorn`? a deploy script (the repo has `deploy/` — e.g. `deploy/vps.sh`,
   `deploy/container.sh`, `docker-compose.yml`)? Identify the actual runtime.
2. **Where is the live `.env`** that the running process reads, and what is the
   process's **working directory**? (`FIREBASE_CREDENTIALS_FILE=./...` is resolved
   relative to the CWD of the uvicorn process — confirm a relative path resolves,
   or just use an absolute path.)
3. **How are dependencies installed on deploy?** Does the pipeline run
   `pip install -r backend/requirements.txt`, or rebuild a Docker image? You must
   ensure `firebase-admin` actually gets installed, not just listed.
4. If **dockerized**: is the backend dir the build context, and will the
   credential file be **inside the container** at the path you configure? You may
   need a volume mount or to bake it into a mounted secrets dir. Prefer mounting
   over baking secrets into the image.
5. **How do you restart** the service so it picks up new env + deps?
6. Where are the **logs**, so you can confirm a clean startup (no Firebase init
   errors)?

---

## 4. Critical gotchas

- **`firebase-admin` must be installed.** `requirements.txt` changed; a restart
  alone won't install it. Run the install / image rebuild. If it's missing, the
  first send attempt fails at import time.
- **The new DB table auto-creates.** On startup the app runs
  `Base.metadata.create_all`, which creates the new `device_tokens` table
  automatically. **Do NOT set `RESET_DB=1`** (that wipes all data). No migration
  needed.
- **Path resolution / container boundaries.** A relative
  `FIREBASE_CREDENTIALS_FILE` is relative to the uvicorn CWD. Inside Docker the
  file must exist at that path *inside the container*. When in doubt, use an
  absolute path and confirm the process can read it.
- **Secret hygiene.** `chmod 600` the key file. Don't commit it, don't echo its
  contents into logs. The repo already git-ignores the standard names.
- **If using `FIREBASE_CREDENTIALS_JSON` (inline):** it must be a single line,
  wrapped in single quotes; the `private_key` field's `\n` sequences stay as
  literal backslash-n inside the JSON string (do not expand them).

---

## 5. Verification (no phone required for the first check)

**A. Credential loads and Firebase initializes.** From the backend directory,
with the same env the server uses (so `.env` is picked up):

```bash
cd backend
python -c "from app import push; print('configured:', push.is_configured()); push._get_app(); print('firebase-admin init OK')"
```

- `configured: True` confirms the env var is seen.
- `firebase-admin init OK` confirms the key is valid and the SDK initializes.
- Any exception here means a bad/incorrect key or a missing `firebase-admin`
  install — report the exact error.

**B. Endpoint stops returning 503.** With the server running, the
`POST /notifications/test` endpoint should no longer return the
"push isn't configured" 503. (It needs an `X-User-Id` header and a registered
device to return 200 with `sent>0`; without a device it returns 404
"No devices registered" — which still proves push is now *configured*.)

**C. Full end-to-end (human, with the phone):** human opens the app →
**Profile → "Send a test notification"** → a notification should arrive.

Report back: which runtime you found, where you put the key, the env var you set,
and the output of check **A**.

---

## 6. Optional housekeeping

There's a tiny docs-only branch `claude/env-firebase-section` that adds the
Firebase block to `.env.example` and the `.gitignore` entries for the key. It can
be merged to `main` or ignored — it does not affect runtime behavior.
