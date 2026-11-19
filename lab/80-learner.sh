#!/usr/bin/env bash
# The learner's shell: the lab command, kubeconfig, a prompt that says where you are.
source "$(dirname "$0")/lib.sh"
rm -rf /opt/lab && cp -r "$(dirname "$0")" /opt/lab && ln -sf /opt/lab/lab /usr/local/bin/lab
cat > /etc/profile.d/bnk-lab.sh <<PROFILE
export KUBECONFIG=/root/.kube/config
export WORKSPACE=${WORKSPACE}
alias k=kubectl
source <(kubectl completion bash) 2>/dev/null; complete -o default -F __start_kubectl k 2>/dev/null
cd ${WORKSPACE} 2>/dev/null || true
PROFILE
grep -q bnk-lab.sh /root/.bashrc || echo '[ -f /etc/profile.d/bnk-lab.sh ] && . /etc/profile.d/bnk-lab.sh' >> /root/.bashrc
ok "lab command installed: $(command -v lab)"
# the AI Inference tab (challenge 12): installed here too, so a running sandbox gets it with `lab update`
bash "$(dirname "$0")/75-inference.sh"
