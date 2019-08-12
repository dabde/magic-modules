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
IFS="," read -ra TERRAFORM_VERSIONS <<< "$TERRAFORM_VERSIONS"

git checkout -b "$BRANCH_NAME"
NEWLINE=$'\n'
MESSAGE="Hi!  I'm the modular magician, I work on Magic Modules.$NEWLINE"
LAST_USER_COMMIT="$(git rev-parse HEAD~1^2)"
# Check if handwritten Terraform changes need to be made in third_party/validator as well.

if [ "$BRANCH_NAME" = "$ORIGINAL_PR_BRANCH" ]; then
  MESSAGE="${MESSAGE}This PR seems not to have generated downstream PRs before, as of $LAST_USER_COMMIT. "
else
  MESSAGE="${MESSAGE}I see that this PR has already had some downstream PRs generated. "
  MESSAGE="${MESSAGE}Any open downstreams are already updated to your most recent commit, $LAST_USER_COMMIT. "
fi

MESSAGE="${MESSAGE}${NEWLINE}## Pull request statuses"
DEPENDENCIES=""
LABELS=""

# There is no existing PR - this is the first pass through the pipeline and
# we will need to create a PR using 'hub'.

# Check the files between this commit and HEAD
# If they're only contained in third_party, add the third_party label.
if [ ! git diff --name-only HEAD^1 | grep -v "third_party" | grep -v ".gitmodules" | grep -r "build/" ]; then
  LABELS="${LABELS}only_third_party,"
fi

# Terraform
if [ -n "$TERRAFORM_VERSIONS" ]; then
  for VERSION in "${TERRAFORM_VERSIONS[@]}"; do
    IFS=":" read -ra TERRAFORM_DATA <<< "$VERSION"
    PROVIDER_NAME="${TERRAFORM_DATA[0]}"
    SUBMODULE_DIR="${TERRAFORM_DATA[1]}"
    TERRAFORM_REPO_USER="${TERRAFORM_DATA[2]}"

    pushd "build/$SUBMODULE_DIR"

    git log -1 --pretty=%s > ./downstream_body
    echo "" >> ./downstream_body
    echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
    if [ -n "$ORIGINAL_PR_USER" ]; then
      echo "Original Author: @$ORIGINAL_PR_USER" >> ./downstream_body
    fi

    git checkout -b "$BRANCH_NAME"
    if hub pull-request -b "$TERRAFORM_REPO_USER/$PROVIDER_NAME:master" -h "$ORIGINAL_PR_BRANCH" -F ./downstream_body > ./tf_pr 2> ./tf_pr_err ; then
      DEPENDENCIES="${DEPENDENCIES}depends: $(cat ./tf_pr) ${NEWLINE}"
      LABELS="${LABELS}${PROVIDER_NAME},"
    else
      echo "$SUBMODULE_DIR - did not generate a PR."
      if grep "No commits between" ./tf_pr_err; then
        echo "There were no diffs in $SUBMODULE_DIR."
        MESSAGE="$MESSAGE${NEWLINE}No diff detected in $PROVIDER_NAME."
      elif grep "A pull request already exists" ./tf_pr_err; then
        echo "Already have a PR for $SUBMODULE_DIR."
        MESSAGE="$MESSAGE${NEWLINE}$PROVIDER_NAME already has an open PR."
      fi

    fi
    popd
  done
fi

if [ -n "$ANSIBLE_REPO_USER" ]; then
  pushd build/ansible

  git log -1 --pretty=%s > ./downstream_body
  echo "" >> ./downstream_body
  echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
  if [ -n "$ORIGINAL_PR_USER" ]; then
    echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
  fi

  git checkout -b "$BRANCH_NAME"
  if hub pull-request -b "$ANSIBLE_REPO_USER/ansible:devel" -h "$ORIGINAL_PR_BRANCH" -F ./downstream_body > ./ansible_pr 2> ./ansible_pr_err ; then
    DEPENDENCIES="${DEPENDENCIES}depends: $(cat ./ansible_pr) ${NEWLINE}"
    LABELS="${LABELS}ansible,"
  else
    echo "Ansible - did not generate a PR."
    if grep "No commits between" ./ansible_pr_err; then
      echo "There were no diffs in Ansible."
      MESSAGE="$MESSAGE${NEWLINE}No diff detected in Ansible."
    elif grep "A pull request already exists" ./ansible_pr_err; then
      MESSAGE="$MESSAGE${NEWLINE}Ansible already has an open PR."
    fi
  fi
  popd

  pwd

  # If there is now a difference in the ansible_version_added files, those
  # should be pushed back up to the user's MM branch to be reviewed.
  if git diff --name-only HEAD^1 | grep "ansible_version_added.yaml"; then
    # Setup git config.
    git config --global user.email "magic-modules@google.com"
    git config --global user.name "Modular Magician"

    BRANCH=$(git config --get pullrequest.branch)
    REPO=$(git config --get pullrequest.repo)
    # Add user's branch + get latest copy.
    git remote add non-gcp-push-target "git@github.com:$REPO"
    git fetch non-gcp-push-target $BRANCH

    # Make a commit to the current branch and track that commit's SHA1.
    git add products/**/ansible_version_added.yaml
    git commit -m "Ansible version_added changes"
    CHERRY_PICKED_COMMIT=$(git rev-parse HEAD)

    # Checkout the user's branch + add the new cherry-picked commit.
    git checkout non-gcp-push-target/$BRANCH
    git cherry-pick $CHERRY_PICKED_COMMIT

    # Create commit + push (no force flag to avoid overwrites).
    # If the push doesn't work, it's not problematic because a commit
    # down the line will pick up the changes.
    ssh-agent bash -c "ssh-add ~/github_private_key; git push non-gcp-push-target \"HEAD:$BRANCH\"" || true

    # Check out the branch we were on to ensure that the downstream commits don't change.
    git checkout $CHERRY_PICKED_COMMIT
  fi
fi

  if [ -n "$INSPEC_REPO_USER" ]; then
  pushd build/inspec

  git log -1 --pretty=%s > ./downstream_body
  echo "" >> ./downstream_body
  echo "<!-- This change is generated by MagicModules. -->" >> ./downstream_body
  if [ -n "$ORIGINAL_PR_USER" ]; then
    echo "/cc @$ORIGINAL_PR_USER" >> ./downstream_body
  fi

  git checkout -b "$BRANCH_NAME"
  if hub pull-request -b "$INSPEC_REPO_USER/inspec-gcp:master" -h "$ORIGINAL_PR_BRANCH" -F ./downstream_body > ./inspec_pr 2> ./inspec_pr_err ; then
    DEPENDENCIES="${DEPENDENCIES}depends: $(cat ./inspec_pr) ${NEWLINE}"
    LABELS="${LABELS}inspec,"
  else
    echo "InSpec - did not generate a PR."
    if grep "No commits between" ./inspec_pr_err; then
      echo "There were no diffs in Inspec."
      MESSAGE="$MESSAGE${NEWLINE}No diff detected in Inspec."
    elif grep "A pull request already exists" ./inspec_pr_err; then
      MESSAGE="$MESSAGE${NEWLINE}InSpec already has an open PR."
    fi
  fi
  popd
fi

MESSAGE="${MESSAGE}${NEWLINE}## New Pull Requests"

# Create PR comment with the list of dependencies.
if [ -z "$DEPENDENCIES" ]; then
  MESSAGE="${MESSAGE}${NEWLINE}I didn't open any new pull requests because of this PR."
else
  MESSAGE="${MESSAGE}${NEWLINE}I built this PR into one or more new PRs on other repositories, "
  MESSAGE="${MESSAGE}and when those are closed, this PR will also be merged and closed."
  MESSAGE="${MESSAGE}${NEWLINE}${DEPENDENCIES}"
fi

## Some files may need non-generatable changes added to alternative Terraform repos
VALIDATOR_WARN_FILES=$(git diff --name-only HEAD^1 | grep -Ff ".ci/magic-modules/vars/validator_handwritten_files.txt" | sed 's/^/* /')
if [ -n "${VALIDATOR_WARN_FILES}" ]; then
  MESSAGE="${MESSAGE}${NEWLINE}**WARNING**: The following files may need corresponding changes in third_party/validator:"
  MESSAGE="${MESSAGE}${NEWLINE}${VALIDATOR_WARN_FILES}${NEWLINE}"
fi

echo "$MESSAGE" > ./pr_comment

# Create Labels list with the comma-separated list of labels for this PR
if [ -z "$LABELS" ]; then
  touch ./label_file
else
  printf "%s" "$LABELS" > ./label_file
fi
