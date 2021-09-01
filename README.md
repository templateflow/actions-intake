# Intake pipeline action

This action finalizes the intake process

## Inputs

The action takes environment variables as inputs (`GITHUB_REPOSITORY`) and a secret access token (with write permissions to `templateflow/templateflow`)

## Example usage

```YAML
uses: actions/actions-intake@master
env:
  SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
  GITHUB_USER: nipreps-bot
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  OSF_PASSWORD: ${{ secrets.OSF_PASSWORD }}
  OSF_USERNAME: ${{ secrets.OSF_USERNAME }}
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  GIN_TOKEN: ${{ secrets.GIN_TOKEN }}
with:
  name: NiPreps Bot
  email: nipreps@gmail.com
```
