#!/bin/bash
set -e

echo "Logging to EKS..."
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER

SECRETS_LIST=""
ROUTE_OVERRIDE=""

# Preparing the secret variables defined using the prefix "SECRET_".
SECRETS=$(env | grep ^SECRET_ | sed 's/'SECRET_'//g')
for path in ${SECRETS}
do
  SECRETS_LIST="$SECRETS_LIST --set secrets.$path"
done

# Defining fields according to their release type.
if [[ "$IMAGE_TAG" == preview-app-* ]]; then
  # Release type: Preview Apps
  RELEASE_NAME="$REPOSITORY-$VERSION"
  NAMESPACE="$REPOSITORY-preview-apps"
  VALUES_FILE="chart/values-preview-apps.yaml"
  ROUTE_OVERRIDE="--set ingressRoute.routes[0].match=\"Host(\`$PREVIEW_APP_ROUTE\`)\""

elif [[ "$IMAGE_TAG" == "staging" ]]; then
  # Release type: Staging
  RELEASE_NAME="$REPOSITORY"
  NAMESPACE="$REPOSITORY"
  VALUES_FILE="chart/values-staging.yaml"
  CHART_FILE="chart/"

else
  # Release type: Production
  RELEASE_NAME="$REPOSITORY"
  NAMESPACE="$REPOSITORY"
  VALUES_FILE="chart/values-production.yaml"
fi

COMMON_ARGS="--install --create-namespace --atomic --cleanup-on-fail --debug"

echo "Starting deploy..."
helm upgrade $RELEASE_NAME $CHART_FILE     \
    $COMMON_ARGS                           \
    --namespace $NAMESPACE                 \
    --timeout $TIMEOUT                     \
    --values $VALUES_FILE                  \
    --set image.repository=$REPOSITORY_URI \
    --set image.tag=$IMAGE_TAG             \
    $ROUTE_OVERRIDE                        \
    $SECRETS_LIST

echo "Success!"
