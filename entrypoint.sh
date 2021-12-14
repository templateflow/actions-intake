#!/bin/bash

# Setting up #######################################################################
export GIT_EDITOR=/usr/bin/vim
export HUB_CONFIG=/root/.hub/config
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
GH_SUBMITTER=$( python -c "import toml; from pathlib import Path; print(toml.loads((Path('${TEMPLATE_ID}.toml').read_text())['github']['user'])" )
pushd $HOME
datalad install -g https://github.com/${GH_SUBMITTER}/${TEMPLATE_ID}
datalad export-archive -d ${TEMPLATE_ID} $HOME/${TEMPLATE_ID}.tar.gz
popd

# Install TemplateFlow
datalad install git@github.com:templateflow/templateflow.git
cd templateflow/
# Work on a new branch
git checkout -b "add/${TEMPLATE_ID}"

####################################################################################

# Prepare intake ###################################################################
tar xzvf $HOME/${TEMPLATE_ID}.tar.gz
find ${TEMPLATE_ID}/ -name "\.*" -exec rm -rf {} +

TEMPLATE_DESC=$( cat "${TEMPLATE_ID}/template_description.json" | jq -r ".Name" )
echo "Sanitizing <${TEMPLATE_ID}> (${TEMPLATE_DESC})"
tfmgr sanitize ${TEMPLATE_ID}

# Initialize the datalad sub-dataset
datalad create --force -c text2git -d . -D "${TEMPLATE_DESC}" ${TEMPLATE_ID}
datalad save -d ./${TEMPLATE_ID} -m "add: populate template contents"

mkdir -p ./${TEMPLATE_ID}/.github/workflows
curl -sSL https://raw.githubusercontent.com/templateflow/gha-workflow-superdataset/main/update.yml \
     -o ./${TEMPLATE_ID}/.github/workflows/update-superdataset.yml
datalad save -d ./${TEMPLATE_ID} -m "add: update superdataset action"
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
datalad push --to gin
datalad siblings configure --name gin --as-common-datasrc gin-src
datalad push --to gin

datalad create-sibling-github -d . --github-organization templateflow --access-protocol ssh --publish-depends gin -s github ${TEMPLATE_ID}
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

datalad push --to gin .
datalad push --to github .

# Ready!
popd
datalad save -m "add(${TEMPLATE_ID}): new template"

# Fixup submodule URL
sed -i -e "s+url = ./${TEMPLATE_ID}+url = https://github.com/templateflow/${TEMPLATE_ID}.git+g" .gitmodules
datalad save -m "fix(submodules): set the github repo url for new template ``${TEMPLATE_ID}``"

# Conclude
datalad push --to github .

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
