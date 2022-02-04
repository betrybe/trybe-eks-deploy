#!/bin/bash
set -e

echo "Logging to EKS..."
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER

# If the repository is a monorepo the envvar `$REPOSITORY` is the application subdir
sub_dir="./"
if [[ ! "${GITHUB_REPOSITORY#betrybe\/}" == "$REPOSITORY" ]]; then
  sub_dir="$REPOSITORY"
fi

# Preparing the secret variables defined using the prefix "SECRET_".
secrets=$(env | awk -F = '/^SECRET_/ {print $1}')
secrets_list=""
for data in ${secrets}
do
  NAME=$(echo $data | sed 's/'^SECRET_'//g')
  secrets_list="$secrets_list --set secrets.$NAME=\"\${$data}\""
done

route_override=""
# Use value from ENV or from user input.
PREVIEW_APP_HOSTNAME=${PREVIEW_APP_HOSTNAME:-$PREVIEW_APP_ROUTE}
override_preview_app_route () {
  index=0
  for route in ${PREVIEW_APP_HOSTNAME}
  do
    host=`echo $route | envsubst` # Resolve environment variables on string
    route_override="$route_override --set ingressRoute.routes[$index].match=\"Host(\\\`$host\\\`)\" "
    index=`expr $index + 1`
  done
  route_override="$route_override --set appHost=$host "
}

CHART_FILE=${CHART_FILE:-"$sub_dir/chart/"}
release_name="$REPOSITORY"
namespace=${NAMESPACE:-$REPOSITORY}
values_file="$sub_dir/chart/values.yaml"
# Defining fields according to their release type.
if [[ "$IMAGE_TAG" == preview-app-* ]]; then
  # Release type: Preview Apps
  release_name="$REPOSITORY-$VERSION"
  namespace=${NAMESPACE:-"$REPOSITORY-preview-apps"}
  values_file="$sub_dir/chart/values-preview-apps.yaml"

  override_preview_app_route

  # Reset env variable for post-deploy use.
  PREVIEW_APP_HOSTNAME=`echo $PREVIEW_APP_HOSTNAME | envsubst`
  echo "PREVIEW_APP_HOSTNAME=$PREVIEW_APP_HOSTNAME" >> $GITHUB_ENV

  # Cleanup any preview-app in progress
  helm uninstall $release_name --wait --namespace $namespace || true

elif [[ "$IMAGE_TAG" == "staging" ]]; then
  # Release type: Staging
  values_file="$sub_dir/chart/values-staging.yaml"

elif [[ "$IMAGE_TAG" == "homologation" ]]; then
  # Release type: Homologation
  namespace=${NAMESPACE:-"$REPOSITORY-homologation"}
  values_file="$sub_dir/chart/values-homologation.yaml"

else
  # Release type: Production
  values_file="$sub_dir/chart/values-production.yaml"
fi

common_args="--install --create-namespace --atomic --cleanup-on-fail --debug"
echo "Starting deploy..."
bash -c "\
    helm upgrade $release_name $CHART_FILE \
    $common_args                           \
    --namespace $namespace                 \
    --timeout $TIMEOUT                     \
    --values $values_file                  \
    --set image.repository=$REPOSITORY_URI \
    --set image.tag=$IMAGE_TAG             \
    $route_override                        \
    $secrets_list                          \
"
echo "Success!"
