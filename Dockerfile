# The BNK host installer as a runner image. The same image runs in three places:
#   - CI jobs (GitHub Actions or Gitea Actions) that use a container
#   - BNK Forge, as a container-runner module (forge/), one Forge step per install phase
#   - a laptop: docker run --rm -v $PWD/work:/work ghcr.io/iracic82/bnk-host-deploy:<tag> plan
#
# BNK Forge refuses images that run as root (including images that never declare USER), and needs
# a numeric uid. 1000 matches the owner of Forge's workspace volume.
FROM debian:bookworm-slim

ARG KUBECTL_VERSION
ARG HELM_VERSION
ARG YQ_VERSION
ARG TARGETARCH=amd64
# The commit this image was built from, for the provenance stamp (the image carries no .git).
ARG GIT_COMMIT=unknown

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends bash ca-certificates curl openssl make python3 tar gzip git jq \
 && rm -rf /var/lib/apt/lists/*

# Pinned tools, each verified against the checksum its project publishes.
RUN set -eux; cd /tmp; \
    curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl"; \
    echo "$(curl -fsSL https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256)  kubectl" | sha256sum -c -; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    curl -fsSLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; \
    echo "$(curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum | cut -d' ' -f1)  helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" | sha256sum -c -; \
    tar xzf "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; install -m 0755 "linux-${TARGETARCH}/helm" /usr/local/bin/helm; \
    curl -fsSLO "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${TARGETARCH}"; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums-bsd" \
      | sed -n "s/^SHA256 (yq_linux_${TARGETARCH}) = \(.*\)$/\1  yq_linux_${TARGETARCH}/p" | sha256sum -c -; \
    install -m 0755 "yq_linux_${TARGETARCH}" /usr/local/bin/yq; \
    rm -rf /tmp/*

COPY --chown=1000:1000 . /opt/bnk-host-deploy
RUN ln -s /opt/bnk-host-deploy/bin/bnk-host /usr/local/bin/bnk-host \
 && mkdir -p /work && chown 1000:1000 /work

ENV BNK_HOST_HOME=/opt/bnk-host-deploy WORK=/work BNK_HOST_COMMIT=${GIT_COMMIT}
WORKDIR /work
USER 1000
ENTRYPOINT ["bnk-host"]
CMD ["help"]
