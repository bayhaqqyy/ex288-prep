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

Kalau `fetch-source` gagal dengan `cp: can't stat '/workspace/basic-auth/.git-credentials'`, berarti kamu mem-bind workspace `basic-auth` ke secret bertipe `kubernetes.io/basic-auth`. Workspace itu harus berisi file `.git-credentials` dan `.gitconfig`. Pilih salah satu:

- Lepas binding `basic-auth` dan pakai secret beranotasi `tekton.dev/git-0` yang di-link ke SA `pipeline` seperti di atas (cara kunci ini).
- Atau buat secret khusus untuk workspace itu, lalu bind sebagai `basic-auth` di task `fetch-source` dan sebagai `secret.secretName` di PipelineRun atau TriggerTemplate:

```bash
oc create secret generic tekton-git-basic-auth \
  --from-literal=.git-credentials='https://developer:d3v3lop3r@git.ocp4.example.com' \
  --from-literal=.gitconfig=$'[credential "https://git.ocp4.example.com"]\n\thelper = store\n'
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

### Trigger dan EventListener

Simpan sebagai `triggers.yaml`:

```yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerBinding
metadata:
  name: tekton-web-binding
spec:
  params:
  - name: git-url
    value: $(body.git_url)
  - name: git-revision
    value: $(body.revision)
---
apiVersion: triggers.tekton.dev/v1beta1
kind: TriggerTemplate
metadata:
  name: tekton-web-template
spec:
  params:
  - name: git-url
  - name: git-revision
    default: main
  resourcetemplates:
  - apiVersion: tekton.dev/v1
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
        value: $(tt.params.git-url)
      - name: GIT_REVISION
        value: $(tt.params.git-revision)
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
---
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: tekton-web-listener
spec:
  serviceAccountName: pipeline
  triggers:
  - name: tekton-web-trigger
    bindings:
    - ref: tekton-web-binding
    template:
      ref: tekton-web-template
```

```bash
oc apply -f triggers.yaml
oc get triggerbinding,triggertemplate,eventlistener
oc get pods -l eventlistener=tekton-web-listener      # pod el-tekton-web-listener-xxx Running
oc get eventlistener tekton-web-listener \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'   # True

oc expose service el-tekton-web-listener
EL=$(oc get route el-tekton-web-listener -o jsonpath='{.spec.host}')

curl -X POST -H 'Content-Type: application/json' \
  -d '{"git_url":"https://git.ocp4.example.com/developer/tekton-web.git","revision":"main"}' \
  "http://$EL"                                          # balasan berisi eventID

tkn pipelinerun list                                  # muncul run baru
oc get pipelinerun -l triggers.tekton.dev/eventlistener=tekton-web-listener
tkn pipelinerun logs -f --last
```

Penting: `$(tt.params.<nama>)` dipakai di dalam TriggerTemplate, bukan `$(params.<nama>)`. Nama service EventListener selalu diawali `el-`.

Kalau pod EventListener `CrashLoopBackOff` karena hak akses (`forbidden`), service account belum punya role triggers. Minta admin menambahkan:

```bash
oc policy add-role-to-user tekton-triggers-eventlistener-roles -z pipeline -n pipeline-lab
oc adm policy add-cluster-role-to-user tekton-triggers-eventlistener-clusterroles -z pipeline -n pipeline-lab
```

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

## Kunci Soal 11

Root cause: `COPY src .` menyalin isi folder `src` (`main/`, `test/`) ke root, sehingga struktur Maven `src/main/java` hilang. Maven tidak menemukan source (`No sources to compile`), runner JAR tidak terbentuk, dan Pod gagal dengan `Unable to access jarfile`.

```bash
oc project docker-app
oc create secret generic myapp1-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret myapp1-git 'build.openshift.io/source-secret-match-uri-1=https://git.ocp4.example.com/*'
oc secrets link builder myapp1-git

oc new-app --name=myapp1-docker --strategy=docker \
  https://git.ocp4.example.com/developer/myapp1-docker.git#main --context-dir=apps/myapp1
oc logs -f bc/myapp1-docker          # cari: No sources to compile
oc get pods
oc logs deploy/myapp1-docker         # Error: Unable to access jarfile target/...-runner.jar

git clone https://git.ocp4.example.com/developer/myapp1-docker.git
cd myapp1-docker/apps/myapp1 && ls -R src | head    # src/main/java/...
```

Perbaiki satu baris di `Dockerfile`:

```dockerfile
COPY src src
```

```bash
git commit -am "fix: preserve Maven source directory" && git push
oc start-build myapp1-docker --follow             # sekarang ada "Compiling ... source files" dan runner JAR
oc rollout status deployment/myapp1-docker
oc get svc myapp1-docker || oc expose deployment myapp1-docker --port=8080
oc expose service myapp1-docker
curl -I http://myapp1-docker-docker-app.apps.ocp4.example.com
```

Dockerfile tanpa `EXPOSE` bisa membuat `oc new-app` tidak membuat Service. Kalau begitu, buat Service dengan `oc expose deployment ... --port=8080` seperti di atas.

## Kunci Soal 12

Tiga masalah di Containerfile: `USER root`, port 80 (privileged, gagal untuk UID non-root), dan `/var/cache` tidak bisa ditulis UID acak. Containerfile yang benar:

```dockerfile
FROM registry.ocp4.example.com:8443/ubi10/nodejs-22-minimal:10.0
ENV PORT=8080
EXPOSE ${PORT}
ADD . $HOME
RUN npm ci --omit=dev && rm -rf .npm
USER root
RUN chgrp -R 0 /var/cache && \
    chmod -R g=u /var/cache
USER 1001
CMD npm start
```

```bash
cd /home/student/ex288-set2/q12
podman login -u developer -p developer registry.ocp4.example.com:8443
podman build -t registry.ocp4.example.com:8443/developer/greetings:1.0.1 .
# uji seperti OpenShift: UID acak, group 0
podman run --rm -d --name gtest --user 12345:0 -p 8080:8080 registry.ocp4.example.com:8443/developer/greetings:1.0.1
curl -s localhost:8080; podman logs gtest; podman rm -f gtest      # File cache OK
podman push registry.ocp4.example.com:8443/developer/greetings:1.0.1

oc project greetings-app
oc create secret docker-registry class-registry \
  --docker-server=registry.ocp4.example.com:8443 \
  --docker-username=developer --docker-password=developer
oc secrets link default class-registry --for=pull

oc import-image greetings:1.0.1 --confirm --reference-policy=local \
  --from=registry.ocp4.example.com:8443/developer/greetings:1.0.1
oc get is greetings -o jsonpath='{.spec.tags[?(@.name=="1.0.1")].referencePolicy.type}{"\n"}'   # Local

oc new-app --name=greetings -i greetings:1.0.1
oc expose service greetings
curl -s http://greetings-greetings-app.apps.ocp4.example.com      # {"greeting":"...","version":"1.0.1"}
```

`oc import-image` otomatis memakai secret registry yang ada di project. `--reference-policy=local` membuat cluster menarik image lewat internal registry, jadi Pod tidak perlu kredensial registry kelas.

## Kunci Soal 13

`assemble` di repo belum executable dan belum membuat `info.html`, dan script `run` belum ada.

```bash
git clone https://git.ocp4.example.com/developer/hello-s2i.git && cd hello-s2i
vi .s2i/bin/assemble
```

Bagian kustomisasi `assemble`:

```bash
######## CUSTOMIZATION STARTS HERE ############
echo "---> Installing application source"
cp -Rf /tmp/src/*.html ./
DATE=`date "+%b %d, %Y @ %H:%M %p"`
echo "---> Creating info page"
echo "Page built on $DATE" >> ./info.html
echo "Proudly served by Apache HTTP Server version $HTTPD_VERSION" >> ./info.html
######## CUSTOMIZATION ENDS HERE ############
```

Buat `.s2i/bin/run`:

```bash
#!/bin/bash
source ${HTTPD_CONTAINER_SCRIPTS_PATH}/common.sh
export HTTPD_RUN_BY_S2I=1
# Make Apache show 'debug' level logs during start up
exec run-httpd -e debug $@
```

```bash
chmod +x .s2i/bin/assemble .s2i/bin/run
git add -A && git commit -m "Customize S2I assemble and run" && git push
git ls-files -s .s2i/bin            # keduanya harus 100755

oc project builds-s2i
oc create secret generic hello-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc new-app --name=hello-web --source-secret=hello-git \
  openshift/httpd:2.4-ubi9~https://git.ocp4.example.com/developer/hello-s2i.git#main
oc logs -f bc/hello-web             # ---> Creating info page
oc expose service hello-web --port=8080
curl http://hello-web-builds-s2i.apps.ocp4.example.com/info.html
oc logs deploy/hello-web | grep ':debug]' | head -3
```

Kalau lupa `chmod +x`, build gagal dengan `permission denied` saat menjalankan `assemble`. Di `run`, `exec` wajib supaya httpd menjadi PID 1 dan menerima sinyal stop dari OpenShift.

## Kunci Soal 14

`parent/Containerfile` yang optimal (satu `RUN`, `ENV` digabung, `ONBUILD` untuk child):

```dockerfile
FROM httpd:2.4-ubi9
LABEL org.opencontainers.image.title="site-base" \
      org.opencontainers.image.vendor="EX288 practice"
RUN echo "<h1>Default site from site-base</h1>" > /var/www/html/index.html && \
    echo "ok" > /var/www/html/health.html && \
    mkdir -p /var/www/html/assets && \
    echo "body { font-family: sans-serif; }" > /var/www/html/assets/site.css
ENV SITE_NAME=default \
    SITE_OWNER=platform-team
EXPOSE 8080
# Dijalankan saat image child di-build
ONBUILD COPY src/ /var/www/html/
CMD ["run-httpd"]
```

```bash
git clone https://git.ocp4.example.com/developer/site-images.git && cd site-images
vi parent/Containerfile
git commit -am "Optimize parent image and add ONBUILD" && git push

oc project production2
oc create secret generic site-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret site-git 'build.openshift.io/source-secret-match-uri-1=https://git.ocp4.example.com/*'
oc secrets link builder site-git

oc new-build openshift/httpd:2.4-ubi9~https://git.ocp4.example.com/developer/site-images.git#main \
  --name=site-base --strategy=docker --context-dir=parent
oc logs -f bc/site-base

oc new-build site-base:latest~https://git.ocp4.example.com/developer/site-images.git#main \
  --name=site-child --strategy=docker --context-dir=child
oc logs -f bc/site-child            # ada langkah ONBUILD COPY src/ ...

oc new-app site-child:latest
oc expose service site-child --port=8080
curl http://site-child-production2.apps.ocp4.example.com       # Child site from ONBUILD
```

Cek jumlah layer: bandingkan `oc get istag site-base:latest -o jsonpath='{.image.dockerImageLayers[*].name}'` dengan `oc get istag httpd:2.4-ubi9 -n openshift -o jsonpath='{.image.dockerImageLayers[*].name}'`. `LABEL`, `ENV`, `EXPOSE`, `CMD`, dan `ONBUILD` tidak menambah layer; hanya `RUN`, `COPY`, dan `ADD` yang menambah.

## Kunci Soal 15

```bash
oc project hooks-lab
oc create configmap smoke-test --from-file=smoke.py=/home/student/ex288-set2/q15/smoke.py

# ConfigMap sebagai build input (masuk ke root source)
oc patch bc/hooks-api --type=merge \
  -p '{"spec":{"source":{"configMaps":[{"configMap":{"name":"smoke-test"}}]}}}'

# Post-commit hook
oc set build-hook bc/hooks-api --post-commit --script="python3 smoke.py"

# Generic webhook
oc set triggers bc/hooks-api --from-webhook
oc describe bc hooks-api | grep -A1 'Webhook Generic'
SECRET=$(oc get bc hooks-api -o jsonpath='{.spec.triggers[?(@.type=="Generic")].generic.secret}')
curl -X POST -k -H "Authorization: Bearer $(oc whoami -t)" \
  "https://api.ocp4.example.com:6443/apis/build.openshift.io/v1/namespaces/hooks-lab/buildconfigs/hooks-api/webhooks/$SECRET/generic"

oc get builds                       # build baru, cause Generic WebHook
oc logs -f bc/hooks-api | grep 'SMOKE TEST PASSED'
curl http://hooks-api-hooks-lab.apps.ocp4.example.com
```

Post-commit hook berjalan di container dari image yang baru di-build, dengan working directory `/opt/app-root/src`. Karena ConfigMap masuk sebagai build input, `smoke.py` ikut ter-copy ke sana. Kalau hook gagal (exit code bukan 0), build dianggap `Failed` dan image tidak di-push.

## Kunci Soal 16

```bash
oc project java-builds
oc create secret generic vertx-git --type=kubernetes.io/basic-auth \
  --from-literal=username=developer --from-literal=password=d3v3lop3r
oc annotate secret vertx-git 'build.openshift.io/source-secret-match-uri-1=https://git.ocp4.example.com/*'
oc secrets link builder vertx-git

oc new-app --name=vertx-site \
  --build-env MAVEN_MIRROR_URL=http://nexus-infra.apps.ocp4.example.com/repository/java \
  --env JAVA_APP_JAR=vertx-site-1.0.0-SNAPSHOT-fat.jar \
  -i redhat-openjdk18-openshift:1.8 \
  https://git.ocp4.example.com/developer/vertx-site.git#main
oc logs -f bc/vertx-site

oc patch bc/vertx-site --type=merge -p '{"spec":{"strategy":{"sourceStrategy":{"incremental":true}}}}'
oc start-build vertx-site --follow  # build kedua memakai artifact dari build sebelumnya
oc get builds                       # minimal 2 Complete

oc expose service vertx-site
curl -I http://vertx-site-java-builds.apps.ocp4.example.com
```

Ingat: `--build-env` (`MAVEN_MIRROR_URL`) hanya ada saat build, sedangkan `--env` (`JAVA_APP_JAR`) masuk ke Deployment. Kalau build gagal mengunduh dependency, cek URL mirror Nexus Maven di lab kelasmu (beberapa materi menulis `http://nexus-infra.apps.ocp4.example.com/java`).
