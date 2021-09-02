# Trybe EKS Deploy
Esta GitHub Action é utilizada para fazer deploy de aplicações em Elastic Kubernetes Service (EKS).

```yaml
- name: Deploy to EKS
  uses: betrybe/trybe-eks-deploy@main
  env:
    SECRET_SENHA: ${{ secrets.SENHA_BANCO }}
    SECRET_SECRETO: ${{ secrets.DADOS_SECRETOS }}
  with:
    clusterName: ${{ secrets.EKS_CLUSTER_STAGING }}  # obrigatório
    awsRegion: ${{ secrets.EKS_REGION }}  # obrigatório
    timeout: 120s  # opcional
    previewAppRoute: $REPOSITORY-preview-app-$VERSION.betrybe.dev # opcional
```
