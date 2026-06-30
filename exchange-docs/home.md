# Platform Lifecycle Orchestrator

Automates MuleSoft application platform migrations (runtime upgrades, Java version bumps) via an AI-agent-friendly REST API.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/v1/jobs/assess` | Assess an app's current runtime and produce a migration plan |
| `POST` | `/api/v1/jobs` | Submit an approved migration job (async, returns 202 + jobId) |
| `GET` | `/api/v1/jobs/{jobId}` | Poll job status (PROCESSING → COMMITTED → PR_OPEN → DEPLOYED) |
| `POST` | `/api/v1/webhook` | Receive GitHub PR merge events to transition jobs to DEPLOYED |

## Project Structure

```
platform-lifecycle-orchestrator/
├── pom.xml                                     Mule 4.9.18 / Java 17 / CloudHub 2.0
├── mule-artifact.json
├── platform-lifecycle-orchestrator.raml         Canonical RAML spec (root)
└── src/
    ├── main/
    │   ├── mule/
    │   │   ├── common/
    │   │   │   ├── global-config.xml            HTTP listener, APIkit, autodiscovery
    │   │   │   ├── global-secured-config.xml    Secure properties config
    │   │   │   └── global-error-handler.xml     Centralised error → HTTP status mapping
    │   │   ├── implementation/
    │   │   │   ├── post-jobs-assess.xml          POST /jobs/assess logic
    │   │   │   ├── post-jobs.xml                 POST /jobs + Object Store write
    │   │   │   ├── get-job-status.xml            GET /jobs/{jobId} + Object Store read
    │   │   │   └── post-webhook.xml              POST /webhook GitHub event handler
    │   │   └── platform-lifecycle-orchestrator-main.xml  Main listener + APIkit router
    │   └── resources/
    │       ├── api/platform-lifecycle-orchestrator.raml  (local copy for APIkit)
    │       ├── properties/
    │       │   ├── config.yaml                   Global non-sensitive defaults
    │       │   ├── config-dev.yaml               Dev environment overrides
    │       │   ├── config-prod.yaml              Prod environment overrides
    │       │   ├── config-secure-dev.yaml        Encrypted dev secrets
    │       │   └── config-secure-prod.yaml       Encrypted prod secrets
    │       └── log4j2.xml
    └── test/
        ├── munit/                                MUnit test suites (to be added)
        └── resources/log4j2-test.xml
```

## Prerequisites

### 1. Maven settings.xml — Anypoint Exchange credentials

The `mule-objectstore-connector` and other MuleSoft EE artifacts are hosted on Anypoint Exchange
and require authenticated Maven access. Add the following server entry to your `~/.m2/settings.xml`:

```xml
<servers>
  <server>
    <id>anypoint-exchange-v3</id>
    <username>~~~Client~~~</username>
    <password>YOUR_CONNECTED_APP_CLIENT_ID~?~YOUR_CONNECTED_APP_CLIENT_SECRET</password>
  </server>
  <server>
    <id>mulesoft-releases</id>
    <username>YOUR_ANYPOINT_USERNAME</username>
    <password>YOUR_ANYPOINT_PASSWORD</password>
  </server>
</servers>
```

> **Tip:** Use a Connected App (Client Credentials) for CI/CD pipelines instead of personal credentials.

### 2. Runtime / Java

- Mule runtime: **4.9.18**
- Java: **17** (Amazon Corretto or Azul Zulu recommended)

## Encryption Key (`encrypt.key`)

Sensitive values in `config-secure-{env}.yaml` are encrypted using **AES-256 / CBC mode**.

| Rule | Detail |
|------|--------|
| Algorithm | AES-256 (CBC) — built into Java 17, no JCE policy files required |
| Key length | **Exactly 32 characters** (256 bits). Shorter or longer keys cause startup failure. |
| Storage | **Never committed to source control.** The key is always injected at runtime. |

**Where to supply the key:**

| Environment | How |
|-------------|-----|
| Local run | `-Dencrypt.key=<32chars>` JVM argument, or `ENCRYPT_KEY` env var mapped in `config.yaml` |
| CloudHub 2.0 | Add `encrypt.key` as an **app property** in Runtime Manager → mark it **Hidden** |
| CI/CD pipeline | Retrieve from your secrets manager (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault) and pass as `-Dencrypt.key=...` to the Maven deploy command |

**Generating a 32-character key locally:**
```bash
# macOS / Linux
openssl rand -base64 32 | tr -d '=+/' | cut -c1-32

# PowerShell
-join ((65..90 + 97..122 + 48..57) * 10 | Get-Random -Count 32 | % {[char]$_})
```

## Certificates / TLS

**No certificates are needed in this project.** TLS termination is handled by the CloudHub 2.0
shared load balancer before traffic reaches the Mule app. The HTTP listener runs plain HTTP
internally (`0.0.0.0:${http.port}`). There are no:
- `.p12` / `.jks` keystores
- `tls:context` configurations
- `src/main/resources/certs/` directory

If you ever need to make **outbound HTTPS calls** (e.g. to GitHub API, Anypoint ARM API),
the JVM on CloudHub 2.0 already trusts standard public CAs — no additional trust-store
configuration is required for standard TLS endpoints.

## Running Locally

```bash
# Required at startup — never hard-code these values
export env=dev
export encrypt.key=<your-32-character-aes-key>

# Build and run
mvn clean package -DskipTests
mvn mule:run -Denv=dev -Dencrypt.key=$encrypt.key
```

The API will be available at: `http://localhost:8081/api/v1/`

## Deployment to CloudHub 2.0

```bash
mvn deploy -DmuleDeploy \
  -Danypoint.username=YOUR_USERNAME \
  -Danypoint.password=YOUR_PASSWORD \
  -Denv=dev \
  -Dencrypt.key=YOUR_32_CHAR_AES_KEY
```

The pom.xml targets environment `dev` in business group `2e14f8c6-4d60-481b-bfb6-798695efc8f4`
on the `Cloudhub-US-East-2` shared space with `0.1 vCore / 1 replica`.

> **CloudHub 2.0 tip:** Add `encrypt.key` as a **hidden** app property in Runtime Manager
> instead of passing it on the command line — it will then be injected automatically on every
> deployment without exposing the value in CI/CD logs.

## Publishing the RAML to Exchange (deferred step)

Once you are ready to publish the API spec:

1. Publish `platform-lifecycle-orchestrator.raml` to Anypoint Exchange as a RAML asset
2. In `pom.xml` add the RAML dependency:
   ```xml
   <dependency>
       <groupId>2e14f8c6-4d60-481b-bfb6-798695efc8f4</groupId>
       <artifactId>platform-lifecycle-orchestrator</artifactId>
       <version>1.0.0</version>
       <classifier>raml</classifier>
       <type>zip</type>
   </dependency>
   ```
3. In `global-config.xml` update the APIkit `api` attribute to:
   ```
   api="resource::2e14f8c6-4d60-481b-bfb6-798695efc8f4:platform-lifecycle-orchestrator:1.0.0:raml:zip:platform-lifecycle-orchestrator.raml"
   ```

## Object Store Notes

Job records are persisted using the **default persistent Object Store** (`_defaultPersistentObjectStore`),
which is fully managed and durable on CloudHub 2.0. No additional Object Store configuration is required.

Each job key: `job-{uuid}`
Branch-to-job index key: `branch::{branchName}`

## Known IDE Validation Warnings

The Anypoint Code Builder / VS Code Mule extension may show schema validation errors on
`os:store`, `os:retrieve`, etc. until the Object Store connector JAR is downloaded into
the local Maven cache. Run `mvn dependency:resolve` after configuring `settings.xml`
to download all connector artifacts and clear the warnings.