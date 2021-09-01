#!/bin/bash

# Setting up #######################################################################
TEMPLATE_ID="$1"

# Pacify git
git config --global user.name "$2"
git config --global user.email "$3"

# Authentication settings
git config --global github.user ${GITHUB_USER}
git config --global github.token ${GIHUB_TOKEN}
git config --global hub.token ${GIHUB_TOKEN}
git config --global hub.oauthtoken ${GIHUB_TOKEN}
git config --global hub.protocol https

# Create ~/.ssh folder
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add github as trusted host
ssh-keyscan -t rsa -H github.com | install -m 600 /dev/stdin /root/.ssh/known_hosts

# Start ssh agent
eval "$(ssh-agent -s)"

# Add key to ssh agent
ssh-add - <<< "${SSH_PRIVATE_KEY}"
####################################################################################

# Prepare intake ###################################################################
tfmgr get ${TEMPLATE_ID}
tfmgr sanitize ${TEMPLATE_ID}

ORIG_FOLDER="$PWD/${TEMPLATE_ID}"
TEMPLATE_DESC=$( cat "${ORIG_FOLDER}/template_description.json" | jq -r ".Name" )

echo "Finishing intake of <${TEMPLATE_ID}> (${TEMPLATE_DESC})"
####################################################################################

# Finish intake ####################################################################

# Install TemplateFlow
mkdir temp
pushd temp/
datalad install -r git@github.com:templateflow/templateflow.git

# Work on a new branch
cd templateflow/
git checkout -b "add/${TEMPLATE_ID}"

# Create a GIN repo under templateflow/ org
# Hopefully handled by datalad after https://github.com/datalad/datalad/issues/5935
curl -v -X POST -H "Authorization: token ${GIN_TOKEN}" \
     https://gin.g-node.org/api/v1/org/templateflow/repos \
     -d name="${TEMPLATE_ID}" -d description="${TEMPLATE_DESC}"

# Initialize the datalad sub-dataset
datalad create -c text2git -d . -D "${TEMPLATE_DESC}" ${TEMPLATE_ID}

# Prepare siblings
pushd ${TEMPLATE_ID}/
datalad siblings add -d . --name gin-update \
 --pushurl git@gin.g-node.org:/templateflow/${TEMPLATE_ID}.git \
 --url https://gin.g-node.org/templateflow/${TEMPLATE_ID} \
 --as-common-datasrc gin
datalad create-sibling-github -d . --github-organization templateflow -s github ${TEMPLATE_ID}
git config --unset-all remote.gin-update.annex-ignore
git annex initremote public-s3 type=S3 encryption=none public=yes bucket=templateflow exporttree=yes versioning=yes fileprefix="${TEMPLATE_ID}/" autoenable=true
datalad siblings configure -d . -s github --publish-by-default github
datalad save -d . -m "chore: setup GitHub sibling and public-s3 annex-remote"

cp -r ${ORIG_FOLDER}/* .
datalad save -m "add: populate template contents"
datalad push --to gin-update .

# Ready!
popd
datalad save -m "add(${TEMPLATE_ID}): new template"

# Fixup submodule URL
sed -i -e "s+url = ./${TEMPLATE_ID}+url = https://github.com/templateflow/${TEMPLATE_ID}+g" .gitmodules
datalad save -m "fix(submodules): set the github repo url for new template ``${TEMPLATE_ID}``"

# Conclude
datalad push -r --to github .

# Send PR
hub pull-request -b templateflow:master -h "templateflow:add/${TEMPLATE_ID}"