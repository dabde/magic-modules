#!/bin/bash

# This script takes in 'magic-modules-branched', a git repo tracking the head of a PR against magic-modules.
# It outputs "terraform-generated", a non-submodule git repo containing the generated terraform code.

set -x
set -e
source "$(dirname "$0")/helpers.sh"
PATCH_DIR="$(pwd)/patches"

# Create $GOPATH structure - in order to successfully run Terraform codegen, we need to run
# it with a correctly-set-up $GOPATH.  It calls out to `goimports`, which means that
# we need to have all the dependencies correctly downloaded.
export GOPATH="${PWD}/go"
mkdir -p "${GOPATH}/src/github.com/$GITHUB_ORG"

pushd magic-modules-branched
ln -s "${PWD}/build/$SHORT_NAME/" "${GOPATH}/src/github.com/$GITHUB_ORG/$PROVIDER_NAME"
popd

pushd "${GOPATH}/src/github.com/$GITHUB_ORG/$PROVIDER_NAME"

# Other orgs are not fully-generated.  This may be transitional - if this causes pain,
# try vendoring into third-party, as with TPG and TPGB.
if [ "$GITHUB_ORG" = "terraform-providers" ]; then
    # This line removes every file which is not specified here.
    # If you add files to Terraform which are not generated, you have to add them here.
    # It uses the somewhat obtuse 'find' command.  To explain:
    # "find .": all files and directories recursively under the current directory, subject to matchers.
    # "-type f": all regular real files, i.e. not directories.
    # "-not": do the opposite of the next thing, always used with another matcher.
    # "-wholename": entire relative path - including directory names - matches following wildcard.
    # "-name": filename alone matches following string.  e.g. -name README.md matches ./README.md *and* ./foo/bar/README.md
    # "-exec": for each file found, execute the command following until the literal ';'
    find . -type f -not -wholename "./.git*" -not -wholename "./vendor*" -not -name ".travis.yml" -not -name ".golangci.yml" -not -name "CHANGELOG.md" -not -name GNUmakefile -not -name LICENSE -not -name README.md -not -wholename "./examples*" -not -name "go.mod" -not -name "go.sum" -not -name "staticcheck.conf"  -exec git rm {} \;
fi

popd

pushd magic-modules-branched
LAST_COMMIT_AUTHOR="$(git log --pretty="%an <%ae>" -n1 HEAD)"
bundle install

# Build all terraform products
if [ -n "$OVERRIDE_PROVIDER" ] && [ "$OVERRIDE_PROVIDER" != "null" ]; then
  bundle exec compiler -a -e terraform -f "$OVERRIDE_PROVIDER" -o "${GOPATH}/src/github.com/$GITHUB_ORG/$PROVIDER_NAME/"
else
  bundle exec compiler -a -e terraform -o "${GOPATH}/src/github.com/$GITHUB_ORG/$PROVIDER_NAME/" -v "$VERSION"
fi

# This command can crash - if that happens, the script should not fail.
set +e
TERRAFORM_COMMIT_MSG="$(python .ci/magic-modules/extract_from_pr_description.py --tag "$SHORT_NAME" < .git/body)"
set -e
if [ -z "$TERRAFORM_COMMIT_MSG" ]; then
  TERRAFORM_COMMIT_MSG="$(cat .git/title)"
fi

pushd "build/$SHORT_NAME"

# Begin building our commit; we need to set the committer details, and add our modified files.
#
# Note that we need to perform `go mod vendor` _after_ adding the files because we're skipping
# the vendor step if Terraform has no changes. Ideally it would happen before, but because we
# deleted all of the existing files earlier in this script we'll see changes until we've staged
# our generated changes.

git config --global user.email "magic-modules@google.com"
git config --global user.name "Modular Magician"

git add -A

# This is useful for human debugging, but not necessary for the Magician.
git status

# Only run `go mod vendor` if we see changes in this downstream repo, since it takes a while to run
if [[ ! -z $(git status -s) ]]; then
  GO111MODULE=on go mod vendor
  git add -A
fi

# Set the "author" to the commit's real author.
git commit -m "$TERRAFORM_COMMIT_MSG" --author="$LAST_COMMIT_AUTHOR" || true  # don't crash if no changes
git checkout -B "$(cat ../../branchname)"

apply_patches "$PATCH_DIR/$GITHUB_ORG/$PROVIDER_NAME" "$TERRAFORM_COMMIT_MSG" "$LAST_COMMIT_AUTHOR" "master"

popd
popd

git clone "magic-modules-branched/build/$SHORT_NAME" "./terraform-generated/$VERSION"
