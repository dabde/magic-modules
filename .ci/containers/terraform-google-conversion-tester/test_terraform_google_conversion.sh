#!/bin/bash

set -e

pr_number=$1
mm_commit_sha=$2
build_id=$3
project_id=$4
github_username=modular-magician
gh_repo=terraform-google-conversion
build_step="21"

scratch_path=https://$github_username:$GITHUB_TOKEN@github.com/$github_username/$gh_repo
local_path=$GOPATH/src/github.com/GoogleCloudPlatform/$gh_repo

post_body="{"
post_body+='"context":"terraform-google-conversion-test",'
post_body+='"target_url":"https://console.cloud.google.com/cloud-build/builds;region=global/'"$build_id"';step='"$build_step"'?project='"$project_id"'",'
post_body+='"state":"success"'
post_body+="}"

curl \
  -X POST \
  -u "$github_username:$GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/GoogleCloudPlatform/magic-modules/statuses/$mm_commit_sha" \
  -d "$post_body"

mkdir -p "$(dirname $local_path)"
git clone $scratch_path $local_path --single-branch --branch "auto-pr-$pr_number" --depth 1
pushd $local_path

set +e

make test
exit_code=$?

set -e

if [ $exitCode -ne 0 ]; then
	state="failure"
else
	state="success"
fi

post_body="{"
post_body+='"context":"terraform-google-conversion-test",'
post_body+='"target_url":"https://console.cloud.google.com/cloud-build/builds;region=global/'"$build_id"';step='"$build_step"'?project='"$project_id"'",'
post_body+='"state":"'"$state"'"'
post_body+="}"

curl \
  -X POST \
  -u "$github_username:$GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/GoogleCloudPlatform/magic-modules/statuses/$mm_commit_sha" \
  -d "$post_body"
