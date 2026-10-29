# EX288 Prep — Questions

Run the prep script for the question you want to practice from the `prep/` folder, then solve it without opening [`KUNCI.md`](KUNCI.md).

Once, before you start, store the lab Git credentials on the workstation:

```bash
git config --global credential.helper store
echo "https://developer:d3v3lop3r@git.ocp4.example.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
```

## Question 1 — S2I Node.js: JSON error and module not found

Preparation: `bash prep/prep-q1.sh`

- Build and deploy the application from `https://git.ocp4.example.com/developer/metrics-api.git`, branch `release-v1`, subdirectory `apps/metrics`.
- The application must be deployed to the project `metrics-prod`. All resources must be named `metrics-api`.
- The application must be based on the image stream tag `nodejs:18-ubi9` from the `openshift` namespace.
- The application's npm dependencies are available at `http://nexus-infra.apps.ocp4.example.com/repository/npm`.
- The Git server requires authentication (`developer` / `d3v3lop3r`). The credentials must be stored as a secret and made available to the build process.
- The application must run without errors and be accessible at both `http://metrics-api-metrics-prod.apps.ocp4.example.com` and `https://metrics-api-metrics-prod.apps.ocp4.example.com`.
- The `/metrics` endpoint must return Prometheus metrics.

Hint: any source code fix must be pushed to Git. Do not patch files directly inside the Pod.

## Question 2 — Docker build from a base image with Nexus environment

Preparation: `bash prep/prep-q2.sh` (optional: `BASE_IMAGE=<image> bash prep/prep-q2.sh`)

- Build and deploy the application from `https://git.ocp4.example.com/developer/legacy-web.git`, branch `main`, subdirectory `apps/legacy`.
- The application must be deployed to the project `legacy-prod`. All resources must be named `legacy-web`.
- The build must use the Dockerfile provided in the repository (Docker strategy).
- During the build, npm must use the Nexus registry through the `npm_config_registry` environment variable.
- At runtime, the container must have the environment variable `APP_ENV=legacy-prod`.
- The image must be OpenShift compatible: it must not run as root and must listen on port 8080.
- The application must be accessible on the default route hostname and return `legacy-web running in mode: legacy-prod`.

## Question 3 — S2I httpd: SERVER_PORT 8081 through the S2I script

Preparation: `bash prep/prep-q3.sh`

- Build and deploy the application from `https://git.ocp4.example.com/developer/portal-s2i.git`, branch `main`, subdirectory `site`.
- The application must be deployed to the project `deploy-portal`. All resources must be named `portal-web`.
- The application must use the `httpd:2.4-ubi9` builder image from the `openshift` namespace.
- The build must modify the existing S2I scripts in the repository so that the `SERVER_PORT` environment variable is set to `8081`. Do not use `--build-env` or `oc set env`.
- The Git credentials must be stored as a secret and used by the build.
- The application must be accessible at both `http://portal.apps.ocp4.example.com` and `https://portal.apps.ocp4.example.com`.

## Question 4 — httpd Docker build from a binary tar

Preparation: `bash prep/prep-q4.sh` → creates `/home/student/ex288-set2/q4/docs-site-v1.tar` and `docs-site-v2.tar`

- The application must be deployed to the project `deploy-docs`. All resources must be named `docs-site`.
- Create a Docker strategy BuildConfig with a **Binary** source. The build input is the file `docs-site-v1.tar`.
- The build must use the image stream tag `httpd:2.4-ubi9` from the `openshift` namespace as its base image.
- Deploy the built image and expose it on the default hostname. `curl` must return `EX288 Docs Site v1`.
- Then start a new build from `docs-site-v2.tar` without creating a new BuildConfig. The deployment must update automatically and return `EX288 Docs Site v2`.

## Question 5 — ConfigMap and Secret for a PostgreSQL backend

Preparation: `bash prep/prep-q5.sh` → creates the `inventory-db` database and an `inventory-api` backend that cannot connect yet.

- Work in the project `inventory`.
- Create a ConfigMap `inventory-db-config` containing `DB_HOST=inventory-db`, `DB_USER=inventory`, and `DB_NAME=inventorydb`.
- Create a Secret `inventory-db-secret` with the key `database-password` set to `Inv3nt0ry`.
- All ConfigMap keys must be exposed to the `inventory-api` Deployment as environment variables with the same names.
- The password from the Secret must be exposed to `inventory-api` as the environment variable `DB_PASSWORD` (not `DATABASE_PASSWORD`).
- Adding new keys to the ConfigMap in the future must not require reconfiguring the Deployment.
- Expose the `inventory-api` Pod name as the environment variable `POD_NAME`. Its value must match the name of the running Pod.
- `oc logs deploy/inventory-api` must show `DB connection OK`.

## Question 6 — Templates for build and deployment

Preparation: `bash prep/prep-q6.sh`

All work is done in the project `lion`. Use these values exactly as written:

| Item | Value |
| --- | --- |
| Git repository | `https://git.ocp4.example.com/developer/shop-ui.git` |
| Branch | `v2` |
| Application context directory | `app` |
| Build template | `templates/shop-build.yaml` in that repository |
| Deployment template | `templates/shop-deploy.yaml` in that repository |
| Git credentials | `developer` / `d3v3lop3r` |
| NPM registry | `http://nexus-infra.apps.ocp4.example.com/repository/npm` |
| Container image registry (`REGISTRY_URL`) | `image-registry.openshift-image-registry.svc:5000` |
| Image namespace in the registry | `lion` |
| Built image | `image-registry.openshift-image-registry.svc:5000/lion/shop-ui:latest` |
| Backend URL | `https://shop-api-lion.apps.ocp4.example.com/` |
| Frontend hostname | `shop-ui-lion.apps.ocp4.example.com` |

Build template:

- The template already uses `${REGISTRY_URL}` in the build output, but the parameter is not defined. Define a new required parameter `REGISTRY_URL` with the description `My shop image registry`.
- Define a new required parameter `GIT_SECRET` with the description `Git source secret`, and use it as the BuildConfig source secret.
- The template must have the label `template: shop-ui`.
- All created resources must be named `shop-ui`. The build must push the image to the "Built image" address in the table.

Deployment template:

- All created resources must be named `shop-ui`, with 2 replicas, using the image from the registry and namespace in the table.
- The `BACKEND_URL` environment variable must contain the Backend URL from the table.
- Create an HTTPS route with the frontend hostname from the table.
- The Deployment must actually manage its Pods.

Both templates:

- All resources created from the templates must be selectable with the selector `app=shop-ui,tier=frontend`.
- You must commit and push the template changes to the `v2` branch.

## Question 7 — Helm for lab and production

Preparation: `bash prep/prep-q7.sh`

The chart is in `https://git.ocp4.example.com/developer/webstore-helm.git`, folder `webstore`. The chart version must be `2.1.0`, and all changes must be pushed to Git.

**For the Lab environment**, fulfill the following requirements:

- Deploy the application to the project `webstore-lab`.
- Use the Helm release name `webstore-lab`.
- Use the values file `webstore/values-lab.yaml`.
- Image: `registry.ocp4.example.com:8443/redhattraining/hello-world-nginx:v1.0`.
- Number of Pods: `2`.
- Resource limits: CPU `200m`, memory `256Mi`.
- The application is available at `https://webstore-lab.apps.ocp4.example.com` with edge TLS. HTTP access must still be allowed.
- Pod label: `stage=lab`.
- Container environment variable: `APP_ENV=lab`.

**For the Production environment**, fulfill the following requirements:

- Deploy the application to the project `webstore-prod`.
- Use the Helm release name `webstore-prod`.
- Use the values file `webstore/values-prod.yaml`.
- Image: `registry.ocp4.example.com:8443/redhattraining/hello-world-nginx:v1.0`.
- Number of Pods: `4`.
- Resource limits: CPU `500m`, memory `512Mi`. Resource requests: CPU `250m`, memory `256Mi`.
- The application is available at `https://webstore.apps.ocp4.example.com` with edge TLS. HTTP access must be redirected to HTTPS.
- Pod label: `stage=production`.
- Container environment variable: `APP_ENV=production`.

Hint: make sure the values in the values files actually appear in the created objects. Check with `helm template` before installing.

## Question 8 — Startup, liveness, and readiness probes

Preparation: `bash prep/prep-q8.sh` → the `health-app` Deployment already has a wrong readiness probe, so the Pod never becomes Ready.

In the project `deploy-health`, configure the `hello-world-nginx` container of the `health-app` Deployment:

| Probe | Check | Settings |
| --- | --- | --- |
| Startup | HTTP GET `/` on port 8080 | period 5s, failure threshold 12 |
| Liveness | TCP socket on port 8080 | initial delay 15s, period 10s, timeout 3s, failure threshold 3 |
| Readiness | HTTP GET `/` on port 8080 | period 10s, timeout 2s, success threshold 2, failure threshold 3 |

The old, wrong probe must not remain. The Pod must be `1/1 Running`, and the `health-app` route must respond.

## Question 9 — Deploy with OpenShift Pipelines (Tekton)

Preparation: `bash prep/prep-q9.sh` → creates the `tekton-web` repository and the skeleton `/home/student/ex288-set2/q9/pipeline-skeleton.yaml`

All work is done in the project `pipeline-lab`. Use these values exactly as written:

| Item | Value |
| --- | --- |
| Git repository (`GIT_URL`) | `https://git.ocp4.example.com/developer/tekton-web.git` |
| Git revision (`GIT_REVISION`) | `main` |
| Git credentials | `developer` / `d3v3lop3r` |
| Build file | `Containerfile` at the repository root |
| Built image (`IMAGE`) | `image-registry.openshift-image-registry.svc:5000/pipeline-lab/tekton-web:latest` |
| Application name (`APP_NAME`) | `tekton-web` |
| Service account | `pipeline` |
| Task namespace | `openshift-pipelines` (cluster resolver) |

- Create the Pipeline `build-and-deploy` from the skeleton with three sequential tasks: `fetch-source` (git-clone), `build-image` (buildah), and `deploy` (openshift-client).
- `fetch-source` must clone `GIT_URL` at `GIT_REVISION` from the table.
- `build-image` must build the `Containerfile` and push it to the image address in the table.
- `deploy` must create the `tekton-web` Deployment, Service, and Route if they do not exist. If they already exist, it must restart the rollout.
- The Git repository is private: the credentials must be stored as a secret and used by the `pipeline` service account.
- The workspace must use a 1Gi PVC from a volumeClaimTemplate.
- Run a PipelineRun with the `GIT_URL`, `GIT_REVISION`, `IMAGE`, and `APP_NAME` parameters from the table until it is `Succeeded`. The `tekton-web` Pod must be Running with the environment variable `BUILT_BY=tekton`.

**Trigger and EventListener** (Tekton Triggers):

| Item | Value |
| --- | --- |
| TriggerBinding | `tekton-web-binding`, param `git-url` from `$(body.git_url)` and `git-revision` from `$(body.revision)` |
| TriggerTemplate | `tekton-web-template`, params `git-url` and `git-revision` (default `main`) |
| EventListener | `tekton-web-listener`, service account `pipeline`, using the binding and template above |
| EventListener route | default hostname for the `el-tekton-web-listener` service |
| Event payload | `{"git_url": "https://git.ocp4.example.com/developer/tekton-web.git", "revision": "main"}` |

- The TriggerTemplate must create a `build-and-deploy` PipelineRun with `GIT_URL` and `GIT_REVISION` taken from the trigger params, while `IMAGE`, `APP_NAME`, the service account, and the workspace follow the first table.
- Expose the EventListener through a route so it can be called from outside the cluster.
- Send the payload above to the EventListener route with an HTTP POST. The event must create a new PipelineRun that ends `Succeeded`.

## Question 10 — Expose the internal registry and push an image

Preparation: `bash prep/prep-q10.sh` → the registry default route is disabled, and the Containerfile is in `/home/student/ex288-set2/q10/`.

Credentials:

| Registry | Username | Password |
| --- | --- | --- |
| Classroom registry `registry.ocp4.example.com:8443` (base image in `FROM`) | `admin` | `redhatocp` |
| OpenShift internal registry (default route) | your OpenShift user (`developer`) | your OpenShift token (`oc whoami -t`) |

- As `admin`, expose the OpenShift internal image registry through its default route.
- As `developer`, build an image named `custom-nginx:1.0` from that Containerfile using podman.
- Push the image to the `registry-lab` project in the internal registry through that route.
- Make sure the image stream `custom-nginx` with tag `1.0` appears in `registry-lab`.
- Remove the local image, then pull it again from the internal registry to prove the push succeeded.
- Deploy `custom-nginx:1.0` from the image stream, expose it on the default hostname, and make sure the Pod has the environment variable `APP_TIER=registry-lab`.
