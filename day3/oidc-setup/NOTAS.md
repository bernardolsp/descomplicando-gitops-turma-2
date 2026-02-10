# Notas de Instalação:
1. Criar GitHub OAuth App em: https://github.com/organizations/<org>/settings/applications/new
2. Authorization callback URL: https://argocd.example.com/api/dex/callback
3. Criar secret com as credenciais:
   kubectl create secret generic argocd-secret \
     --from-literal=dex.clientSecret=$(openssl rand -base64 32) \
     --from-literal=oidc.github.clientID=<client-id> \
     --from-literal=oidc.github.clientSecret=<client-secret> \
     -n argocd
4. Instalar: helm upgrade --install argocd argo/argo-cd -f values.yaml
5. Verificar login: kubectl -n argocd logs deployment/argocd-dex-server


6. Testar: https://argocd.example.com e fazer login com GitHub