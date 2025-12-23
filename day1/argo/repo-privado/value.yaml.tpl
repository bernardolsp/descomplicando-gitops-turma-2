apiVersion: v1
kind: Secret
metadata:
  name: argocd-private-repo
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: <repo>
  username: <user>
  password: <token>