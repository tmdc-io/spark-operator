#
# Copyright 2017 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ARG SPARK_IMAGE=tmdcio/spark:3.5.9-jammy-fips-curated.v2

FROM golang:1.26.6 AS builder

WORKDIR /workspace

ENV GOPROXY=https://proxy.golang.org,direct
ENV GOSUMDB=sum.golang.org
ENV GOCACHE=/root/.cache/go-build

RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.mod,target=go.mod \
    --mount=type=bind,source=go.sum,target=go.sum \
    rm -rf /go/pkg/mod/gopkg.in/yaml.v3@* /go/pkg/mod/cache/download/gopkg.in/yaml.v3 && \
    go mod download

COPY . .

ARG TARGETARCH

RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=cache,target="/root/.cache/go-build" \
    rm -rf /go/pkg/mod/gopkg.in/yaml.v3@* /go/pkg/mod/cache/download/gopkg.in/yaml.v3 && \
    go mod download && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} GO111MODULE=on make build-operator

FROM ${SPARK_IMAGE}

ARG SPARK_UID=185

ARG SPARK_GID=185

USER root

RUN apt-get update \
    && apt-get install -y tini \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/k8s-webhook-server/serving-certs /home/spark && \
    chmod -R g+rw /etc/k8s-webhook-server/serving-certs && \
    chown -R spark /etc/k8s-webhook-server/serving-certs /home/spark

# Spark K8s client (okhttp 4.x) plus CVE remediations for the curated image.
# hive-exec is replaced with the 4.0.1 *core* classifier only (not the fat jar)
# so Spark's remaining Hive 2.3.9 modules stay in place.
COPY jars/kotlin-stdlib-2.2.21.jar \
     jars/okio-jvm-3.4.0.jar \
     jars/logging-interceptor-4.9.2.jar \
     jars/netty-codec-http-4.2.17.Final.jar \
     jars/hive-exec-4.0.1-core.jar \
     /opt/spark/jars/
RUN rm -f \
      /opt/spark/jars/okio-1.17.6.jar \
      /opt/spark/jars/okio-2.8.0.jar \
      /opt/spark/jars/logging-interceptor-3.12.12.jar \
      /opt/spark/jars/jackson-mapper-asl-1.9.13.jar \
      /opt/spark/jars/jackson-core-asl-1.9.13.jar \
      /opt/spark/jars/commons-lang-2.6.jar \
      /opt/spark/jars/netty-codec-http-4.2.16.Final.jar \
      /opt/spark/jars/hive-exec-2.3.9-core.jar

USER ${SPARK_UID}:${SPARK_GID}

COPY --from=builder /workspace/bin/spark-operator /usr/bin/spark-operator

COPY entrypoint.sh /usr/bin/

ENTRYPOINT ["/usr/bin/entrypoint.sh"]
