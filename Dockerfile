# Container image that runs your code
FROM ghcr.io/templateflow/datalad:main

RUN pip install git+https://github.com/templateflow/python-manager.git@master

# Copies your code file from your action repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# Code file to execute when the docker container starts up (`entrypoint.sh`)
ENTRYPOINT ["/entrypoint.sh"]
