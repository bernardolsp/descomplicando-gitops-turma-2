helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets \
   external-secrets/external-secrets \
    -n external-secrets-system \
    --create-namespace \
   --set installCRDs=true \
   --set serviceAccount.create=false \
   --set serviceAccount.name="external-secrets"