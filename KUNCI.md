# EX288 Prep — Kunci Jawaban

Buka file ini hanya setelah mencoba sendiri. Semua perintah diasumsikan login sebagai `developer` kecuali disebut lain.

Sebelum mengerjakan soal yang memakai repo Git lab (Soal 1, 2, 3, 6, 7, 9), pastikan kredensial Git tersimpan di workstation. Tanpa ini, `oc new-app` gagal membaca repo private:

```bash
git config --global credential.helper store
echo "https://developer:d3v3lop3r@git.ocp4.example.com" > ~/.git-credentials
chmod 600 ~/.git-credentials
git ls-remote https://git.ocp4.example.com/developer/legacy-web.git   # harus tampil hash
```

Kredensial di workstation hanya dipakai `oc new-app` dan `git` lokal. Build di cluster tetap butuh secret Git sendiri (basic-auth, di-link ke `builder` atau dipasang sebagai `--source-secret`).

## Kunci Soal 1

Dua bug: koma hilang di `package.json` (build gagal `EJSONPARSE`), dan `prom-client` tidak ada di dependencies (Pod `CrashLoopBackOff` dengan `Cannot find module 'prom-client'`).

```bash
oc project metrics-prod
oc create secret generic metrics-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret metrics-git 'build.openshift.io/source-secret-match-uri-1=https://git.ocp4.example.com/*'
oc secrets link builder metrics-git

oc new-app --name=metrics-api \
  --build-env npm_config_registry=http://nexus-infra.apps.ocp4.example.com/repository/npm \
  openshift/nodejs:18-ubi9~https://git.ocp4.example.com/developer/metrics-api.git#release-v1 \
  --context-dir=apps/metrics
oc logs -f bc/metrics-api          # npm error code EJSONPARSE

git clone https://git.ocp4.example.com/developer/metrics-api.git
cd metrics-api && git checkout release-v1 && cd apps/metrics
python3 -m json.tool package.json  # tunjukkan baris yang rusak
grep require server.js             # lihat module yang dipakai
```

Perbaiki `package.json`:

```json
  "dependencies": {
    "express": "^4.20.0",
    "prom-client": "^15.1.0"
  },
  "license": "MIT"
```

```bash
python3 -m json.tool package.json >/dev/null && echo valid
git commit -am "Fix package.json syntax and add prom-client" && git push
oc start-build metrics-api --follow
oc get pods                        # metrics-api-xxxx 1/1 Running
oc create route edge metrics-api --service=metrics-api \
  --hostname=metrics-api-metrics-prod.apps.ocp4.example.com --insecure-policy=Allow
curl http://metrics-api-metrics-prod.apps.ocp4.example.com/
curl -k https://metrics-api-metrics-prod.apps.ocp4.example.com/metrics | head -3
```

## Kunci Soal 2

Dockerfile asli memakai port 80 dan `USER root`. Di OpenShift container berjalan dengan UID acak non-root, jadi bind ke port 80 gagal (`EACCES`). Perbaiki Dockerfile di repo:

```dockerfile
FROM registry.ocp4.example.com:8443/ubi10/nodejs-22-minimal:10.0

ENV PORT=8080
EXPOSE 8080

USER root
COPY . /opt/app-root/src
WORKDIR /opt/app-root/src
RUN npm install --omit=dev && rm -rf .npm && \
    chgrp -R 0 /opt/app-root/src && chmod -R g=u /opt/app-root/src
USER 1001

CMD ["npm", "start"]
```

```bash
oc project legacy-prod
git clone https://git.ocp4.example.com/developer/legacy-web.git && cd legacy-web
vi apps/legacy/Dockerfile
git commit -am "Run as non-root on port 8080" && git push

oc create secret generic legacy-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret legacy-git 'build.openshift.io/source-secret-match-uri-1=https://git.ocp4.example.com/*'
oc secrets link builder legacy-git

oc new-app --name=legacy-web --strategy=docker \
  --build-env npm_config_registry=http://nexus-infra.apps.ocp4.example.com/repository/npm \
  --env APP_ENV=legacy-prod \
  https://git.ocp4.example.com/developer/legacy-web.git#main --context-dir=apps/legacy
oc logs -f bc/legacy-web
oc expose service legacy-web
curl legacy-web-legacy-prod.apps.ocp4.example.com   # legacy-web running in mode: legacy-prod
```

Alternatif kalau `oc new-app` dengan URL masih gagal membaca repo: jalankan dari root folder hasil clone, `oc` akan memakai URL `origin`:

```bash
cd ~/legacy-web
oc new-app . --name=legacy-web --strategy=docker --context-dir=apps/legacy \
  --build-env npm_config_registry=http://nexus-infra.apps.ocp4.example.com/repository/npm \
  --env APP_ENV=legacy-prod
```

Jika build gagal menarik base image (`unauthorized`), buat pull secret untuk registry kelas lalu link ke `builder`:

```bash
oc create secret docker-registry class-reg --docker-server=registry.ocp4.example.com:8443 \
  --docker-username=admin --docker-password=redhatocp
oc secrets link builder class-reg
oc start-build legacy-web --follow
```

Ingat: `--build-env` masuk ke `dockerStrategy.env` (tersedia saat `RUN`), sedangkan `--env` masuk ke Deployment (runtime).

## Kunci Soal 3

```bash
oc project deploy-portal
oc auth can-i get imagestreams/layers --as=system:serviceaccount:deploy-portal:builder -n openshift

git clone https://git.ocp4.example.com/developer/portal-s2i.git && cd portal-s2i
vi site/.s2i/bin/run
```

Tambahkan `export SERVER_PORT=8081` sebelum `exec run-httpd`:

```bash
#!/bin/bash
source ${HTTPD_CONTAINER_SCRIPTS_PATH}/common.sh
export HTTPD_RUN_BY_S2I=1
export SERVER_PORT=8081

echo "---> Starting portal, SERVER_PORT=${SERVER_PORT:-not-set}"

# Make Apache show 'debug' level logs during start up
exec run-httpd -e debug $@
```

```bash
git commit -am "Set SERVER_PORT in S2I run script" && git push
oc create secret generic portal-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc new-app --name=portal-web --strategy=source --source-secret=portal-git \
  openshift/httpd:2.4-ubi9~https://git.ocp4.example.com/developer/portal-s2i.git#main \
  --context-dir=site
oc logs -f bc/portal-web
oc logs deploy/portal-web | grep SERVER_PORT      # ---> Starting portal, SERVER_PORT=8081
oc create route edge portal-web --service=portal-web --port=8080 \
  --hostname=portal.apps.ocp4.example.com --insecure-policy=Allow
curl -I http://portal.apps.ocp4.example.com
curl -kI https://portal.apps.ocp4.example.com
```

`--port=8080` penting karena Service dari image httpd punya dua port (8080 dan 8443).

## Kunci Soal 4

```bash
oc project deploy-docs
oc new-build --name=docs-site --binary --strategy=docker \
  --image-stream=openshift/httpd:2.4-ubi9
oc get bc docs-site -o jsonpath='{.spec.strategy.dockerStrategy.from}{"\n"}'
```

Kalau output kosong, set base image secara eksplisit. Tanpa ini, `FROM httpd:2.4-ubi9` di Dockerfile dicari ke registry luar dan build gagal:

```bash
oc patch bc/docs-site --type=merge -p \
  '{"spec":{"strategy":{"dockerStrategy":{"from":{"kind":"ImageStreamTag","namespace":"openshift","name":"httpd:2.4-ubi9"}}}}}'
```

```bash
oc start-build docs-site --from-archive=/home/student/ex288-set2/q4/docs-site-v1.tar --follow
oc new-app --name=docs-site --image-stream=docs-site:latest
oc expose service docs-site --port=8080
curl docs-site-deploy-docs.apps.ocp4.example.com      # EX288 Docs Site v1

oc start-build docs-site --from-archive=/home/student/ex288-set2/q4/docs-site-v2.tar --follow
oc rollout status deployment/docs-site
curl docs-site-deploy-docs.apps.ocp4.example.com      # EX288 Docs Site v2
```

Deployment ikut terupdate karena `oc new-app` dari image stream memasang image trigger. Cek dengan `oc get deploy docs-site -o yaml | grep -A3 image.openshift.io/triggers`.

## Kunci Soal 5

Jebakan: `oc set env --from=configmap/...` membuat entri `env` satu per satu (bukan `envFrom`), jadi key baru tidak otomatis ikut. `oc set env --from=secret/...` akan menamai variabel `DATABASE_PASSWORD`, bukan `DB_PASSWORD`. Pakai `envFrom` untuk ConfigMap, `secretKeyRef` untuk password, dan `fieldRef: metadata.name` untuk `POD_NAME`.

```bash
oc project inventory
oc logs deploy/inventory-api --tail=2               # DB connection FAILED (DB_HOST=unset ...)

oc create configmap inventory-db-config \
  --from-literal=DB_HOST=inventory-db \
  --from-literal=DB_USER=inventory \
  --from-literal=DB_NAME=inventorydb
oc create secret generic inventory-db-secret --from-literal=database-password=Inv3nt0ry

oc explain deployment.spec.template.spec.containers.envFrom
oc explain deployment.spec.template.spec.containers.env.valueFrom.secretKeyRef
oc explain deployment.spec.template.spec.containers.env.valueFrom.fieldRef

oc patch deployment/inventory-api --type=json -p '[
  {"op":"add","path":"/spec/template/spec/containers/0/envFrom",
   "value":[{"configMapRef":{"name":"inventory-db-config"}}]},
  {"op":"add","path":"/spec/template/spec/containers/0/env",
   "value":[{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"inventory-db-secret","key":"database-password"}}},
            {"name":"POD_NAME","valueFrom":{"fieldRef":{"fieldPath":"metadata.name"}}}]}
]'
oc rollout status deployment/inventory-api
oc logs deploy/inventory-api --tail=2               # DB connection OK (inventory@inventory-db/inventorydb)

POD=$(oc get pods -l app=inventory-api -o jsonpath='{.items[0].metadata.name}')
oc exec "$POD" -- printenv POD_NAME                 # harus sama dengan $POD
echo "$POD"
```

Bentuk YAML-nya kalau lewat `oc edit deployment/inventory-api` (cari contoh `valueFrom` di dokumentasi: Nodes → Working with containers):

```yaml
        envFrom:
        - configMapRef:
            name: inventory-db-config
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: inventory-db-secret
              key: database-password
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
```

Bukti key baru tidak butuh edit Deployment:

```bash
oc set data configmap/inventory-db-config DB_PORT=5432
oc rollout restart deployment/inventory-api
oc exec deploy/inventory-api -- printenv DB_PORT    # 5432
```

## Kunci Soal 6

Dua celah di build template: `${REGISTRY_URL}` dipakai di `spec.output.to.name` tapi tidak dideklarasikan, dan belum ada source secret. Di deploy template, `selector.matchLabels` (`app: shop`) tidak cocok dengan label Pod, sehingga `oc apply` ditolak API.

```bash
oc project lion
git clone https://git.ocp4.example.com/developer/shop-ui.git && cd shop-ui && git checkout v2
oc process --parameters -f templates/shop-build.yaml     # REGISTRY_URL belum ada
oc process --parameters -f templates/shop-deploy.yaml
grep -n REGISTRY_URL templates/*.yaml
```

Perubahan di `templates/shop-build.yaml`:

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: shop-ui-build
  labels:
    template: shop-ui
labels:
  app: ${NAME}
  tier: frontend
objects:
# ... ImageStream tetap ...
- apiVersion: build.openshift.io/v1
  kind: BuildConfig
  metadata:
    name: ${NAME}
  spec:
    source:
      type: Git
      git:
        uri: ${GIT_URL}
        ref: ${GIT_REF}
      contextDir: ${CONTEXT_DIR}
      sourceSecret:
        name: ${GIT_SECRET}
    # ... strategy tetap ...
    output:
      to:
        kind: DockerImage
        name: ${REGISTRY_URL}/${IMAGE_NAMESPACE}/${NAME}:latest
# ... triggers tetap ...
parameters:
# ... parameter lama tetap ...
- name: REGISTRY_URL
  description: My shop image registry
  required: true
- name: GIT_SECRET
  description: Git source secret
  required: true
```

Perubahan di `templates/shop-deploy.yaml`:

```yaml
labels:
  app: ${NAME}
  tier: frontend
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: ${NAME}
  spec:
    replicas: ${{REPLICAS}}
    selector:
      matchLabels:
        app: ${NAME}
        tier: frontend
    template:
      metadata:
        labels:
          app: ${NAME}
          tier: frontend
# ... sisanya tetap; image: ${REGISTRY_URL}/${IMAGE_NAMESPACE}/${NAME}:latest
```

```bash
git add templates/ && git commit -m "Add REGISTRY_URL, GIT_SECRET and labels" && git push origin v2

oc create secret generic shop-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r

oc process -f templates/shop-build.yaml \
  -p NAME=shop-ui \
  -p GIT_URL=https://git.ocp4.example.com/developer/shop-ui.git \
  -p GIT_REF=v2 \
  -p CONTEXT_DIR=app \
  -p GIT_SECRET=shop-git \
  -p NPM_REGISTRY=http://nexus-infra.apps.ocp4.example.com/repository/npm \
  -p REGISTRY_URL=image-registry.openshift-image-registry.svc:5000 \
  -p IMAGE_NAMESPACE=lion \
  | oc apply -f -
oc logs -f bc/shop-ui        # akhir log: Successfully pushed image-registry.../lion/shop-ui

oc process -f templates/shop-deploy.yaml \
  -p NAME=shop-ui \
  -p REGISTRY_URL=image-registry.openshift-image-registry.svc:5000 \
  -p IMAGE_NAMESPACE=lion \
  -p REPLICAS=2 \
  -p BACKEND_URL=https://shop-api-lion.apps.ocp4.example.com/ \
  -p APP_HOST=shop-ui-lion.apps.ocp4.example.com \
  | oc apply -f -

oc get all,route -l app=shop-ui,tier=frontend
curl -k https://shop-ui-lion.apps.ocp4.example.com/   # shop-ui frontend. Backend: https://shop-api-lion...
```

Tips: jalankan `oc process ... | oc apply --dry-run=server -f -` dulu untuk melihat error tanpa membuat objek. Kalau push ke registry ditolak (`unauthorized`), set push secret builder: `oc set build-secret --push bc/shop-ui $(oc get sa builder -o jsonpath='{.secrets[0].name}')` lalu `oc start-build shop-ui --follow`.

## Kunci Soal 7

Dua celah di chart: `Chart.yaml` masih versi `0.1.0`, dan `templates/deployment.yaml` tidak me-render `resources`. Tanpa perbaikan template, limit di values file diam-diam diabaikan.

```bash
git clone https://git.ocp4.example.com/developer/webstore-helm.git && cd webstore-helm/webstore
sed -i 's/^version: 0.1.0/version: 2.1.0/' Chart.yaml
```

Tambahkan di akhir container pada `templates/deployment.yaml` (indentasi sejajar `env`):

```yaml
        {{- with .Values.resources }}
        resources:
          {{- toYaml . | nindent 10 }}
        {{- end }}
```

`values-lab.yaml`:

```yaml
replicaCount: 2
podLabels:
  stage: lab
env:
- name: APP_ENV
  value: lab
resources:
  limits:
    cpu: 200m
    memory: 256Mi
route:
  enabled: true
  host: webstore-lab.apps.ocp4.example.com
  tls:
    enabled: true
    termination: edge
    insecureEdgeTerminationPolicy: Allow
```

`values-prod.yaml`:

```yaml
replicaCount: 4
podLabels:
  stage: production
env:
- name: APP_ENV
  value: production
resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 250m
    memory: 256Mi
route:
  enabled: true
  host: webstore.apps.ocp4.example.com
  tls:
    enabled: true
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

```bash
helm lint . -f values-lab.yaml
helm template webstore-lab . -f values-lab.yaml | grep -A3 resources:
helm upgrade --install webstore-lab . -n webstore-lab -f values-lab.yaml
helm upgrade --install webstore-prod . -n webstore-prod -f values-prod.yaml
cd .. && git add -A && git commit -m "Chart 2.1.0 with lab and production values" && git push

helm list -A                                        # CHART webstore-2.1.0
oc get deploy,pod,route -n webstore-lab --show-labels    # stage=lab, 2 pod
oc get deploy,pod,route -n webstore-prod --show-labels   # stage=production, 4 pod
oc get deploy webstore-prod -n webstore-prod \
  -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
curl -I  http://webstore-lab.apps.ocp4.example.com    # 200
curl -kI https://webstore.apps.ocp4.example.com       # 200
curl -I  http://webstore.apps.ocp4.example.com        # 302 ke https
```

## Kunci Soal 8

```bash
oc project deploy-health
oc get pods                                         # 0/1 Running: readiness ke port 9090
oc set probe deployment/health-app --readiness --remove

oc set probe deployment/health-app --startup \
  --get-url=http://:8080/ --period-seconds=5 --failure-threshold=12
oc set probe deployment/health-app --liveness \
  --open-tcp=8080 --initial-delay-seconds=15 --period-seconds=10 \
  --timeout-seconds=3 --failure-threshold=3
oc set probe deployment/health-app --readiness \
  --get-url=http://:8080/ --period-seconds=10 --timeout-seconds=2 \
  --success-threshold=2 --failure-threshold=3

oc rollout status deployment/health-app
oc get deploy health-app -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}{"\n"}'
oc describe deploy health-app | grep -E 'Liveness|Readiness|Startup'
curl health-app-deploy-health.apps.ocp4.example.com
```

`--remove` dulu supaya field lama (port 9090, path `/healthz`, period 5) tidak tersisa saat probe ditulis ulang.

## Kunci Soal 9

Cek dulu nama parameter task di cluster kamu, karena bisa berbeda antar versi OpenShift Pipelines:

```bash
oc get tasks -n openshift-pipelines
tkn task describe git-clone -n openshift-pipelines
tkn task describe buildah -n openshift-pipelines
tkn task describe openshift-client -n openshift-pipelines
```

Nilai yang dipakai: `GIT_URL=https://git.ocp4.example.com/developer/tekton-web.git`, `GIT_REVISION=main`, `IMAGE=image-registry.openshift-image-registry.svc:5000/pipeline-lab/tekton-web:latest`, `APP_NAME=tekton-web`.

Kredensial Git untuk service account `pipeline`:

```bash
oc project pipeline-lab
oc create secret generic tekton-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret tekton-git tekton.dev/git-0=https://git.ocp4.example.com
oc secrets link pipeline tekton-git
```

Tambahkan dua task ini ke skeleton, di bawah `fetch-source`:

```yaml
  - name: build-image
    runAfter:
    - fetch-source
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: buildah
      - name: namespace
        value: openshift-pipelines
    params:
    - name: IMAGE
      value: $(params.IMAGE)
    - name: DOCKERFILE
      value: ./Containerfile
    - name: TLSVERIFY
      value: "false"
    workspaces:
    - name: source
      workspace: shared-workspace
  - name: deploy
    runAfter:
    - build-image
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: openshift-client
      - name: namespace
        value: openshift-pipelines
    params:
    - name: SCRIPT
      value: |
        oc get deployment $(params.APP_NAME) >/dev/null 2>&1 || \
          oc create deployment $(params.APP_NAME) --image=$(params.IMAGE) --port=8080
        oc rollout restart deployment/$(params.APP_NAME)
        oc rollout status deployment/$(params.APP_NAME) --timeout=180s
        oc get service $(params.APP_NAME) >/dev/null 2>&1 || \
          oc expose deployment $(params.APP_NAME) --port=8080
        oc get route $(params.APP_NAME) >/dev/null 2>&1 || \
          oc expose service $(params.APP_NAME)
```

Simpan sebagai `pipeline.yaml`, lalu buat `pipelinerun.yaml`:

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: build-and-deploy-run-
spec:
  pipelineRef:
    name: build-and-deploy
  taskRunTemplate:
    serviceAccountName: pipeline
  params:
  - name: GIT_URL
    value: https://git.ocp4.example.com/developer/tekton-web.git
  - name: GIT_REVISION
    value: main
  - name: IMAGE
    value: image-registry.openshift-image-registry.svc:5000/pipeline-lab/tekton-web:latest
  - name: APP_NAME
    value: tekton-web
  workspaces:
  - name: shared-workspace
    volumeClaimTemplate:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
```

```bash
oc apply -f pipeline.yaml
oc create -f pipelinerun.yaml                       # generateName butuh create, bukan apply
tkn pipelinerun logs -f --last
tkn pipelinerun list                                # STATUS Succeeded
oc get is tekton-web
oc exec deploy/tekton-web -- printenv BUILT_BY      # tekton
curl tekton-web-pipeline-lab.apps.ocp4.example.com
```

Jika `build-image` gagal menarik base image (`unauthorized`), buat secret `docker-registry` untuk `registry.ocp4.example.com:8443` lalu `oc secrets link pipeline <secret>`, kemudian jalankan PipelineRun baru.

## Kunci Soal 10

```bash
oc login -u admin -p redhatocp https://api.ocp4.example.com:6443
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge \
  -p '{"spec":{"defaultRoute":true}}'
oc get route default-route -n openshift-image-registry
REG=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
echo $REG       # default-route-openshift-image-registry.apps.ocp4.example.com

oc login -u developer -p developer https://api.ocp4.example.com:6443
oc project registry-lab

podman login -u admin -p redhatocp registry.ocp4.example.com:8443   # untuk base image
podman build -t custom-nginx:1.0 /home/student/ex288-set2/q10/
podman login -u developer -p $(oc whoami -t) $REG --tls-verify=false
podman tag localhost/custom-nginx:1.0 $REG/registry-lab/custom-nginx:1.0
podman push $REG/registry-lab/custom-nginx:1.0 --tls-verify=false

oc get is custom-nginx
oc get istag custom-nginx:1.0

podman rmi $REG/registry-lab/custom-nginx:1.0 localhost/custom-nginx:1.0
podman pull $REG/registry-lab/custom-nginx:1.0 --tls-verify=false

oc new-app --name=custom-nginx --image-stream=custom-nginx:1.0
oc expose service custom-nginx
oc exec deploy/custom-nginx -- printenv APP_TIER   # registry-lab
curl custom-nginx-registry-lab.apps.ocp4.example.com
```

Jalur push: route eksternal (`default-route-...`) dari workstation. Jalur pull di dalam cluster: `image-registry.openshift-image-registry.svc:5000`. Token dari `oc whoami -t` adalah password registry.
