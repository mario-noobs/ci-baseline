#!/usr/bin/env bash
set -euo pipefail

# ── Namespace ────────────────────────────────────────────────────────
echo "Creating argocd namespace (if not exists)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# ── Install ArgoCD ───────────────────────────────────────────────────
echo "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side --force-conflicts

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --namespace argocd \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/name=argocd-server \
  --timeout=180s

# ── Patch for insecure mode (local dev without TLS) ─────────────────
echo "Patching argocd-server for insecure mode (no TLS)..."
kubectl patch deployment argocd-server -n argocd \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/command/-","value":"--insecure"}]'

# Wait for the patched deployment to roll out
kubectl rollout status deployment/argocd-server -n argocd --timeout=120s

# ── Get initial admin password ───────────────────────────────────────
echo "Retrieving initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# ── Create Ingress for ArgoCD ────────────────────────────────────────
echo "Creating Ingress for ArgoCD at argocd.local..."
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

# ── Print instructions ───────────────────────────────────────────────
echo ""
echo "============================================="
echo "  ArgoCD is installed and ready!"
echo "============================================="
echo ""
echo "  URL      : http://argocd.local"
echo "  Username : admin"
echo "  Password : ${ARGOCD_PASSWORD}"
echo ""
echo "  Make sure to add '127.0.0.1 argocd.local' to /etc/hosts"
echo ""
echo "  Alternative (port-forward):"
echo "    kubectl port-forward svc/argocd-server -n argocd 8443:443"
echo "    Then open: https://localhost:8443"
echo "============================================="
