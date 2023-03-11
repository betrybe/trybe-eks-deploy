#!/bin/bash
set -e

# If the repository is a monorepo then the envvar `$PIPELINE_MODE` must
# be set to "monorepo" in order to the pipeline work properly.
sub_dir="."
if [[ "$PIPELINE_MODE" == "monorepo" ]]; then
  sub_dir="$REPOSITORY_PATH$REPOSITORY"
fi

echo "Logging to EKS..."
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER

# Preparing the custom variables defined using the prefix "VALUES_".
custom_values=$(env | awk -F = '/^VALUES_/ {print $1}')
custom_values_list=""
for data in ${custom_values}
do
  NAME=$(echo $data | sed 's/'^VALUES_'//g')
  custom_values_list="$custom_values_list --set $NAME=\"\${$data}\""
done

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
values_file="values.yaml"
# Defining fields according to their release type.
if [[ "$ENVIRONMENT" == "preview-app" ]]; then
  # Release type: Preview Apps
  release_name="$REPOSITORY-$VERSION"
  namespace=${NAMESPACE:-"$REPOSITORY-preview-apps"}
  values_file="values-preview-apps.yaml"

  override_preview_app_route

  # Reset env variable for post-deploy use.
  PREVIEW_APP_HOSTNAME=`echo $PREVIEW_APP_HOSTNAME | envsubst`
  echo "PREVIEW_APP_HOSTNAME=$PREVIEW_APP_HOSTNAME" >> $GITHUB_ENV

  # Cleanup any preview-app in progress
  helm uninstall $release_name --wait --namespace $namespace || true

elif [[ "$ENVIRONMENT" == "staging" ]]; then
  # Release type: Staging
  values_file="values-staging.yaml"

elif [[ "$ENVIRONMENT" == "homologation" ]]; then
  # Release type: Homologation
  namespace=${NAMESPACE:-"$REPOSITORY"}
  values_file="values-homologation.yaml"

else
  # Release type: Production
  values_file="values-production.yaml"
fi

# is_in_argocd=$(curl -s "https://x-access-token:$BOOTSTRAP_TOKEN@raw.githubusercontent.com/betrybe/argocd-app-updater/main/.argo_cd_projects" | grep $REPOSITORY)
# if [[ ! -z "$is_in_argocd" ]]; then
#   argocd_script=$(curl -s "https://x-access-token:$BOOTSTRAP_TOKEN@raw.githubusercontent.com/betrybe/infrastructure-projects/main/$REPOSITORY/values.yaml")
#   echo "$values_file_content" > ./update_params.sh

#   export ARGOCD_AUTH_TOKEN=$(curl -s "https://x-access-token:$BOOTSTRAP_TOKEN@raw.githubusercontent.com/betrybe/argo-app-credential/main/.token")

#   ./update_params.sh
# else
  if [[ "$REPOSITORY" == "sorry-cypress" ]] || [[ "$REPOSITORY" == "projects-service" ]] || [[ "$REPOSITORY" == "keycloak" ]]
  then
    echo "Values file: $sub_dir/chart/$values_file"
  else
    echo "Values file: $values_file"

    values_file_content=$(curl -s "https://x-access-token:$BOOTSTRAP_TOKEN@raw.githubusercontent.com/betrybe/infrastructure-projects/main/$REPOSITORY/values.yaml")
    if [[ "$values_file_content" == *"404: Not Found"* ]]; then
      echo "values.yaml não foi encontrado no em https://github.com/betrybe/infrastructure-projects/tree/main/$REPOSITORY"
      exit 1
    fi
    echo "$values_file_content" > "$sub_dir/chart/values.yaml"

    values_file_content=$(curl -s "https://x-access-token:$BOOTSTRAP_TOKEN@raw.githubusercontent.com/betrybe/infrastructure-projects/main/$REPOSITORY/$values_file")
    if [[ "$values_file_content" == *"404: Not Found"* ]]; then
      echo "$values_file não foi encontrado no em https://github.com/betrybe/infrastructure-projects/tree/main/$REPOSITORY"
      exit 1
    fi
    echo "$values_file_content" > "$sub_dir/chart/$values_file"
  fi

  common_args="--install --create-namespace --atomic --cleanup-on-fail --debug"
  echo "Starting deploy..."
  bash -c "\
      helm upgrade $release_name $CHART_FILE \
      $common_args                           \
      --namespace $namespace                 \
      --timeout $TIMEOUT                     \
      --values $sub_dir/chart/$values_file   \
      --set image.repository=$REPOSITORY_URI \
      --set image.tag=$IMAGE_TAG             \
      $route_override                        \
      $custom_values_list                    \
      $secrets_list                          \
  "
  echo "Success!"
# fi
