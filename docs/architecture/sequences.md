# Sequence diagrams

How the components talk to each other in the four main scenarios. The
diagrams are Mermaid: Azure DevOps wikis, GitHub and VS Code render them.

## Watching a film

The page and the video are two separate requests. nginx caches video in
1 MB slices, so only the first viewer of a slice reaches Blob Storage.

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant N as nginx
    participant W as Web app
    participant S as Azure SQL
    participant T as Table Storage
    participant BL as Blob Storage

    B->>N: GET /films/sintel-2010 (HTTPS)
    N->>W: proxy to 127.0.0.1:3000
    W->>S: SELECT film (managed identity token)
    W->>T: views + 1 (ETag, optimistic concurrency)
    W-->>B: HTML + CSP, no JavaScript
    B->>N: GET /media/videos/sintel-2010.mp4 (Range)
    N->>W: 1 MB slice (cache MISS)
    W->>BL: download(offset, 1 MB) via private endpoint
    BL-->>W: video bytes
    N-->>B: 206 Partial Content, slice cached
    Note over B,N: next viewers: cache HIT, no Web app or Blob
```

## Admin sign-in

OpenID Connect authorization code flow with PKCE. No tokens are stored; the
signed session cookie holds only the name and object ID.

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant W as Web app
    participant KV as Key Vault
    participant E as Entra ID

    W->>KV: at start-up: entra-client-secret, session-secret
    B->>W: GET /auth/login
    W-->>B: 302 to Entra (state + code_challenge)
    B->>E: sign-in and MFA
    E-->>B: 302 /auth/callback?code&state
    B->>W: GET /auth/callback
    Note over W: state matches the session cookie?
    W->>E: code + code_verifier + client secret
    E-->>W: ID token
    Note over W: oid = admin and tid = our tenant?
    W-->>B: session cookie (HttpOnly, Secure), redirect to /admin
```

## Importing a film

The web app only queues the job; the worker does the slow part.

```mermaid
sequenceDiagram
    autonumber
    participant A as Admin
    participant W as Web app
    participant S as Azure SQL
    participant Q as Queue
    participant K as Worker
    participant TM as TMDB
    participant AR as archive.org
    participant BL as Blob Storage

    A->>W: POST /admin/import-starter
    W->>S: INSERT film (status queued)
    W->>Q: sendMessage {filmId}
    K->>Q: receive (invisible for 1 hour)
    K->>TM: search + details + trailer
    K->>BL: poster JPEG + WebP thumbnail
    K->>AR: GET mp4 (https, allow-listed hosts only)
    K->>BL: uploadStream in 8 MB blocks
    K->>S: status = ready
    K->>Q: deleteMessage
    Note over K: on error: retry; after 5 attempts status = failed
```

## Deploying the app

From `git push` to a new release, with automatic rollback.

```mermaid
sequenceDiagram
    autonumber
    participant D as Developer
    participant R as Azure Repos
    participant P as Pipeline
    participant AG as Agent
    participant KV as Key Vault
    participant S as Azure SQL
    participant VM as App VM

    D->>R: git push main
    R->>P: trigger app.yml
    AG->>P: long polling on 443, takes the job
    Note over AG: gitleaks, eslint, tests, npm audit, tarball
    AG->>S: migrate.sh (agent managed identity)
    AG->>KV: SSH key (workload identity federation)
    AG->>VM: scp tarball + ssh :22 over peering
    Note over VM: switch symlink, restart services
    Note over VM: GET /healthz up to 24 times, else roll back
    VM-->>AG: release healthy
    AG-->>P: smoke test over the Internet passed
```
