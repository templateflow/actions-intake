#!/bin/bash

# Setting up #######################################################################

# Pacify git
git config --global user.name "$2"
git config --global user.email "$3"

# Authentication settings
git config --global github.user ${GITHUB_USER}
git config --global github.token ${GIHUB_TOKEN}
git config --global hub.token ${GIHUB_TOKEN}
git config --global hub.oauthtoken ${GIHUB_TOKEN}
git config --global hub.protocol https
git config --global gin.user nipreps-admin
git config --global gin.token ${GIN_TOKEN}

# Create ~/.ssh folder
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Add trusted hosts
ssh-keyscan -t rsa -H github.com | install -m 600 /dev/stdin /root/.ssh/known_hosts
ssh-keyscan -t rsa -H gin.g-node.org >> /root/.ssh/known_hosts

# Start ssh agent
eval "$(ssh-agent -s)"

# Add key to ssh agent
ssh-add - <<< "${SSH_PRIVATE_KEY}"

# Install TemplateFlow
datalad install -r git@github.com:templateflow/templateflow.git
cd templateflow/
# Work on a new branch
git checkout -b "add/${TEMPLATE_ID}"

####################################################################################

# Prepare intake ###################################################################
tfmgr get ${TEMPLATE_ID}
TEMPLATE_DESC=$( cat "${TEMPLATE_ID}/template_description.json" | jq -r ".Name" )
echo "Sanitizing <${TEMPLATE_ID}> (${TEMPLATE_DESC})"
tfmgr sanitize ${TEMPLATE_ID}

# Initialize the datalad sub-dataset
datalad create --force -c text2git -d . -D "${TEMPLATE_DESC}" ${TEMPLATE_ID}
datalad save -m "add: populate template contents"
####################################################################################

# Finish intake ####################################################################
echo "Publishing new template..."

# Create a GIN repo under templateflow/ org
# Hopefully handled by datalad after https://github.com/datalad/datalad/issues/5935
curl -v -X POST -H "Authorization: token ${GIN_TOKEN}" \
     https://gin.g-node.org/api/v1/org/templateflow/repos \
     -d name="${TEMPLATE_ID}" -d description="${TEMPLATE_DESC}"

# Prepare siblings
pushd ${TEMPLATE_ID}/
datalad siblings add -d . --name gin-update \
                 --pushurl git@gin.g-node.org:/templateflow/${TEMPLATE_ID}.git \
                 --url https://gin.g-node.org/templateflow/${TEMPLATE_ID} \
                 --as-common-datasrc gin
git config --unset-all remote.gin-update.annex-ignore
datalad save -d . -m "chore: setup GIN sibling"

datalad create-sibling-github -d . --github-organization templateflow --publish-depends gin-update -s github ${TEMPLATE_ID}
datalad save -d . -m "chore: setup GH sibling"

# Enable Amazon S3 public remote
git annex initremote public-s3 \
                     type=S3 \
                     encryption=none \
                     public=yes \
                     bucket=templateflow \
                     exporttree=yes \
                     versioning=yes \
                     fileprefix="${TEMPLATE_ID}/" \
                     autoenable=true
datalad save -d . -m "chore: setup public-s3 annex-remote"

datalad push --to gin-update .
datalad push --to github .

# Ready!
popd
datalad save -m "add(${TEMPLATE_ID}): new template"

# Fixup submodule URL
sed -i -e "s+url = ./${TEMPLATE_ID}+url = https://github.com/templateflow/${TEMPLATE_ID}.git+g" .gitmodules
datalad save -m "fix(submodules): set the github repo url for new template ``${TEMPLATE_ID}``"

# Conclude
datalad push --to origin .

# Send PR
hub pull-request -b templateflow:master -h "templateflow:add/${TEMPLATE_ID}"
