#!/bin/bash

# This script configures the git submodule under magic-modules so that it is
# ready to create a new pull request.  It is cloned in a detached-head state,
# but its branch is relevant to the PR creation process, so we want to make
# sure that it's on a branch, and most importantly that that branch tracks
# a branch upstream.

set -e
set -x

shopt -s dotglob
cp -r magic-modules/* magic-modules-with-comment

PR_ID="$(cat ./mm-initial-pr/.git/id)"
ORIGINAL_PR_BRANCH="codegen-pr-$PR_ID"
set +e
ORIGINAL_PR_USER=$(curl "https://api.github.com/repos/GoogleCloudPlatform/magic-modules/issues/$PR_ID" | jq -r ".user.login")
set -e
pushd magic-modules-with-comment
echo "$ORIGINAL_PR_BRANCH" > ./original_pr_branch_name

# Check out the magic-modules branch with the same name as the current tracked
# branch of the terraform submodule.  All the submodules will be on the the same
# branch name - we pick terraform because it's the first one the magician supported.
BRANCH_NAME="$(git config -f .gitmodules --get submodule.build/terraform.branch)"
IFS="," read -ra PUPPET_PRODUCTS <<< "$PUPPET_MODULES"
IFS="," read -ra CHEF_PRODUCTS <<< "$CHEF_MODULES"
IFS="," read -ra TERRAFORM_VERSIONS <<< "$TERRAFORM_VERSIONS"

git checkout -b "$BRANCH_NAME"

if [ "$BRANCH_NAME" = "$ORIGINAL_PR_BRANCH" ]; then
  DEPENDENCIES=""
  NEWLINE=$'\n'
  # There is no existing PR - this is the first pass through the pipeline and
  # we will need to create a PR using 'hub'.
  if [ -n "$TERRAFORM_REPO_USER" ]; then
    for VERSION in "${TERRAFORM_VERSIONS[@]}"; do
      if [ -n "$VERSION" ]; then
        PROVIDER_NAME="terraform-provider-google-$VERSION"
        SUBMODULE_DIR="terraform-$VERSION"
      else
        PROVIDER_NAME="terraform-provider-google"
        SUBMODULE_DIR="terraform"
      fi

      pushd build/$SUBMODULE_DIR

      git log -1 --pretty=%B > ./downstream_body
      echo "" >> ./downstream_body
      echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
      if [ -n "$ORIGINAL_PR_USER" ]; then
        echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
      fi

      git checkout -b "$BRANCH_NAME"
      if TF_PR=$(hub pull-request -b "$TERRAFORM_REPO_USER/$PROVIDER_NAME:2.0.0" -F ./downstream_body); then
        DEPENDENCIES="${DEPENDENCIES}depends: $TF_PR ${NEWLINE}"
      else
        echo "$SUBMODULE_DIR - did not generate a PR."
      fi
      popd
    done
  fi

  if [ -n "$ANSIBLE_REPO_USER" ]; then
    pushd build/ansible

    git log -1 --pretty=%B > ./downstream_body
    echo "" >> ./downstream_body
    echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
    if [ -n "$ORIGINAL_PR_USER" ]; then
      echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
    fi

    git checkout -b "$BRANCH_NAME"
    if ANSIBLE_PR=$(hub pull-request -b "$ANSIBLE_REPO_USER/ansible:devel" -F ./downstream_body); then
      DEPENDENCIES="${DEPENDENCIES}depends: $ANSIBLE_PR ${NEWLINE}"
    else
      echo "Ansible - did not generate a PR."
    fi
    popd
  fi

    if [ -n "$INSPEC_REPO_USER" ]; then
    pushd build/inspec

    git log -1 --pretty=%B > ./downstream_body
    echo "" >> ./downstream_body
    echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
    if [ -n "$ORIGINAL_PR_USER" ]; then
      echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
    fi

    git checkout -b "$BRANCH_NAME"
    if INSPEC_PR=$(hub pull-request -b "$INSPEC_REPO_USER/inspec-gcp:master" -F ./downstream_body); then
      DEPENDENCIES="${DEPENDENCIES}depends: $INSPEC_PR ${NEWLINE}"
    else
      echo "InSpec - did not generate a PR."
    fi
    popd
  fi

  for PRD in "${PUPPET_PRODUCTS[@]}"; do

    pushd "build/puppet/$PRD"

    git log -1 --pretty=%B > ./downstream_body
    echo "" >> ./downstream_body
    echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
    if [ -n "$ORIGINAL_PR_USER" ]; then
      echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
    fi

    git checkout -b "$BRANCH_NAME"
    if [[ $PRD == *"_bundle"* ]]; then
      repo="puppet-google"
    else
      repo="puppet-google-$PRD"
    fi
    if PUP_PR=$(hub pull-request -b "$PUPPET_REPO_USER/$repo:master" -F ./downstream_body); then
      DEPENDENCIES="${DEPENDENCIES}depends: $PUP_PR ${NEWLINE}"
    else
      echo "Puppet $PRD - did not generate a PR."
    fi
    popd
  done

  for PRD in "${CHEF_PRODUCTS[@]}"; do

    pushd "build/chef/$PRD"

    git log -1 --pretty=%B > ./downstream_body
    echo "" >> ./downstream_body
    echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
    if [ -n "$ORIGINAL_PR_USER" ]; then
      echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
    fi

    git checkout -b "$BRANCH_NAME"
    if [[ $PRD == *"_bundle"* ]]; then
      repo="chef-google"
    else
      repo="chef-google-$PRD"
    fi
    if CHEF_PR=$(hub pull-request -b "$CHEF_REPO_USER/$repo:master" -F ./downstream_body); then
      DEPENDENCIES="${DEPENDENCIES}depends: $CHEF_PR ${NEWLINE}"
    else
      echo "Chef $PRD - did not generate a PR."
    fi
    popd
  done

  if [ -z "$DEPENDENCIES" ]; then
    cat << EOF > ./pr_comment 
I am a robot that works on MagicModules PRs!
I checked the downstream repositories (see README.md for which ones I can write to), and none of them seem to have any changes.

Once this PR is approved, you can feel free to merge it without taking any further steps.
EOF
  else
    cat << EOF > ./pr_comment 
I am a robot that works on MagicModules PRs!

I built this PR into one or more PRs on other repositories, and when those are closed, this PR will also be merged and closed.
$DEPENDENCIES
EOF
  fi

else
  # This is the second-or-more pass through the pipeline - we need to overwrite
  # the codegen-pr-* branch with the new updated code to update the existing
  # PR, rather than create a new one.
  git branch -f "$ORIGINAL_PR_BRANCH"

  if [ -n "$TERRAFORM_REPO_USER" ]; then
    for VERSION in "${TERRAFORM_VERSIONS[@]}"; do
      if [ -n "$VERSION" ]; then
        pushd "build/terraform-$VERSION"
      else
        pushd build/terraform
      fi
      git branch -f "$ORIGINAL_PR_BRANCH"
      popd
    done
  fi

  for PRD in "${PUPPET_PRODUCTS[@]}"; do
    pushd "build/puppet/$PRD"
    git branch -f "$ORIGINAL_PR_BRANCH"
    popd
  done
  for PRD in "${CHEF_PRODUCTS[@]}"; do
    pushd "build/chef/$PRD"
    git branch -f "$ORIGINAL_PR_BRANCH"
    popd
  done
  # Note - we're interested in HEAD~1 here, not HEAD, because HEAD is the
  # generated code commit.  :)
  cat << EOF > ./pr_comment
I am (still) a robot that works on MagicModules PRs!

I just wanted to let you know that your changes (as of commit $(git rev-parse --short HEAD~1)) have been included in your existing downstream PRs.
EOF

fi
