#!/bin/bash

# Setting up #######################################################################
export GIT_EDITOR=/usr/bin/vim
export HUB_CONFIG=/root/.hub/config
export DATALAD_CREDENTIAL_GITHUB_TOKEN=${GITHUB_TOKEN}

mkdir -p /root/.hub
chmod 700 /root/.hub
echo -e "github.com:\n- user: ${GITHUB_USER}\n  oauth_token: ${GITHUB_TOKEN}\n  protocol: https\n" | install -m 600 /dev/stdin $HUB_CONFIG

# Pacify git
git config --global user.name "$1"
git config --global user.email "$2"

# Authentication settings
git config --global hub.token ${GIHUB_TOKEN}

unset GITHUB_USER
unset GITHUB_TOKEN

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

# Pull down template
CFG_FILE=$( find $PWD -type f -name "${TEMPLATE_ID}.toml" )
GH_SUBMITTER=$( python -c "import toml; from pathlib import Path; print(toml.loads((Path('${CFG_FILE}')).read_text())['github']['user']);" )

if [[ "$GH_SUBMITTER" == "" ]]; then
    echo "Could not find submitter's GH username"
    exit 1
fi
pushd $HOME
datalad install -g https://github.com/${GH_SUBMITTER}/${TEMPLATE_ID}
datalad export-archive -d ${TEMPLATE_ID} $HOME/${TEMPLATE_ID}.tar.gz
popd

# Install TemplateFlow
datalad install git@github.com:templateflow/templateflow.git
pushd templateflow/
# Work on a new branch
git checkout -b "add/${TEMPLATE_ID}" origin/master
popd

####################################################################################
# Prepare intake ###################################################################
mkdir -p $HOME/tmp

pushd $HOME/tmp
tar xzvf $HOME/${TEMPLATE_ID}.tar.gz
find ${TEMPLATE_ID}/ -name "\.*" -exec rm -rf {} +

TEMPLATE_DESC=$( cat "${TEMPLATE_ID}/template_description.json" | jq -r ".Name" )
echo "Sanitizing <${TEMPLATE_ID}> (${TEMPLATE_DESC})"
tfmgr sanitize ${TEMPLATE_ID}
popd

pushd templateflow/
# Initialize the datalad sub-dataset
datalad create -c text2git -d . -D "${TEMPLATE_DESC}" ${TEMPLATE_ID}
cp .gitattributes ${TEMPLATE_ID}/.gitattributes

mkdir -p ./${TEMPLATE_ID}/.github/workflows
curl -sSL https://raw.githubusercontent.com/templateflow/gha-workflow-superdataset/main/update.yml \
     -o ./${TEMPLATE_ID}/.github/workflows/update-superdataset.yml
datalad save -d ./${TEMPLATE_ID} -m "chore: procedure + update superdataset action"

# Finally populate contents
mv $HOME/tmp/${TEMPLATE_ID}/* ./${TEMPLATE_ID}/
datalad save -d ./${TEMPLATE_ID} -m "chore: populate template contents"

####################################################################################

# Finish intake ####################################################################
echo "Publishing new template..."

# Create a GIN repo under templateflow/ org
# Hopefully handled by datalad after https://github.com/datalad/datalad/issues/5935
curl -v -H "Authorization: token ${GIN_TOKEN}" \
     https://gin.g-node.org/api/v1/org/templateflow/repos \
     -d name="${TEMPLATE_ID}" -d description="${TEMPLATE_DESC}"

# Prepare siblings
pushd ${TEMPLATE_ID}/
datalad siblings add -d . --name gin \
                 --pushurl git@gin.g-node.org:/templateflow/${TEMPLATE_ID}.git \
                 --url https://gin.g-node.org/templateflow/${TEMPLATE_ID}
git config --unset-all remote.gin.annex-ignore
datalad save -d . -m "chore: setup GIN sibling"
datalad push --to gin .
datalad siblings configure --name gin --as-common-datasrc gin-src
datalad push --to gin .

datalad create-sibling-github -d . --github-organization templateflow --access-protocol ssh --publish-depends gin -s origin ${TEMPLATE_ID}
datalad save -d . -m "chore: setup GH sibling"
datalad push --to origin .

# Enable Amazon S3 public remote
git annex initremote s3 \
                     type=S3 \
                     encryption=none \
                     public=yes \
                     bucket=templateflow \
                     exporttree=yes \
                     versioning=yes \
                     "fileprefix=${TEMPLATE_ID}/" \
                     autoenable=true \
                     "publicurl=https://templateflow.s3.amazonaws.com/"
datalad save -d . -m "chore: setup s3 annex-remote"
git annex export master --to s3

datalad push --to gin .
datalad push --to origin .

# Ready!
popd
datalad save -m "add(${TEMPLATE_ID}): new template"

# Fixup submodule URL
sed -i -e "s+url = ./${TEMPLATE_ID}+url = https://github.com/templateflow/${TEMPLATE_ID}.git+g" .gitmodules
datalad save -m "fix(submodules): set the github repo url for new template ``${TEMPLATE_ID}``"

# Conclude
datalad push --to origin .

echo -e "MRG: \`\`${TEMPLATE_ID}\`\`\n\n" >> $HOME/pr-message.md
echo "" >> $HOME/pr-message.txt
echo "Name: ${TEMPLATE_DESC}" >> $HOME/pr-message.md
echo "" >> $HOME/pr-message.txt
echo "## Template description" >> $HOME/pr-message.md
echo "\`\`\`JSON" >> $HOME/pr-message.md
cat ${TEMPLATE_ID}/template_description.json >> $HOME/pr-message.md
echo '\`\`\`'  >> $HOME/pr-message.md

# Send PR
hub pull-request -b templateflow:master -h "templateflow:add/${TEMPLATE_ID}" -F $HOME/pr-message.md
