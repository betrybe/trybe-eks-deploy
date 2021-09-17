#!/bin/bash
set -e
set -x

echo "Logging to EKS..."
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER

SECRETS_LIST=""
ROUTE_OVERRIDE=""

# Preparing the secret variables defined using the prefix "SECRET_".
SECRETS=$(env | awk -F = '/^SECRET_/ {print $1}')
for data in ${SECRETS}
do
  NAME=$(echo $data | sed 's/'^SECRET_'//g')
  SECRETS_LIST="$SECRETS_LIST --set secrets.$NAME=\"\${$data}\""
done

# Defining fields according to their release type.
if [[ "$IMAGE_TAG" == preview-app-* ]]; then
  # Release type: Preview Apps
  RELEASE_NAME="$REPOSITORY-$VERSION"
  NAMESPACE="$REPOSITORY-preview-apps"
  VALUES_FILE="chart/values-preview-apps.yaml"

  # Use value from ENV or from user input.
  PREVIEW_APP_HOSTNAME=${PREVIEW_APP_HOSTNAME:-$PREVIEW_APP_ROUTE}
  index=0
  for route in ${PREVIEW_APP_HOSTNAME}
  do
    host=`echo $route | envsubst` # Resolve environment variables on string
    ROUTE_OVERRIDE="$ROUTE_OVERRIDE --set ingressRoute.routes[$index].match=\"Host(\\\`$host\\\`)\" "
    index=`expr $index + 1`
  done

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
bash -c "\
    helm upgrade $RELEASE_NAME $CHART_FILE \
    $COMMON_ARGS                           \
    --namespace $NAMESPACE                 \
    --timeout $TIMEOUT                     \
    --values $VALUES_FILE                  \
    --set image.repository=$REPOSITORY_URI \
    --set image.tag=$IMAGE_TAG             \
    $ROUTE_OVERRIDE                        \
    $SECRETS_LIST                          \
"
echo "Success!"
