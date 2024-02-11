#!/bin/sh
set -e

gum confirm 'Are you ready to start?' || exit 0

echo "
## You will need following tools installed:
|Name            |Required             |More info                                          |
|----------------|---------------------|---------------------------------------------------|
|git CLI         |Yes                  |'https://git-scm.com/downloads'                    |
|civo CLI        |If setup created a Civo cluster|'https://civo.com/docs/overview/civo-cli#installation'|
|Civo account    |If setup created a Civo cluster|'https://dashboard.civo.com/signup'      |

If you are running this script from **Nix shell**, most of the requirements are already set with the exception of a **Kubernetes cluster** (unless you chose to create it through the setup script).
" | gum format

gum confirm "
Do you have those tools installed?
" || exit 0

rm -f .env

###########
# Cluster #
###########

echo '## Open https://app.perfectscale.io in a browser, select `Settings` of the cluster, and disconnect it' \
    | gum format

if [[ "$CLUSTER" == "civo" ]]; then

    civo kubernetes remove dot --region NYC1 --yes

    rm -f $KUBECONFIG

    sleep 10

    civo firewall ls --region NYC1 --output custom --fields "name" | grep dot \
        | while read FIREWALL; do
        civo firewall rm $FIREWALL --region NYC1 --yes
    done

    civo volume ls --region NYC1 --dangling --output custom --fields "name" \
        | while read VOLUME; do
        civo volume rm $VOLUME --region NYC1 --yes
    done

else

    echo "## Destroy the Kubernetes cluster" | gum format

fi
