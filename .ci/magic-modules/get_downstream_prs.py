#!/usr/bin/env python
import functools
import os
import re
import sys
from github import Github

def append_github_dependencies_to_list(lst, comment_body):
  list_of_urls = re.findall(r'^depends: (https://github.com/.*)', comment_body, re.MULTILINE)
  return lst + list_of_urls

if __name__ == '__main__':
  g = Github(os.environ.get('GH_TOKEN'))
  assert len(sys.argv) == 2
  pr_number = int(sys.argv[1])
  pull_request = g.get_repo('GoogleCloudPlatform/magic-modules').get_pull(pr_number)
  comment_bodies = [c.body for c in pull_request.get_issue_comments()]
  # "reduce" is "foldl" - apply this function to the result of the previous function and
  # the next value in the iterable.
  all_dependencies = functools.reduce(append_github_dependencies_to_list, comment_bodies, [])
  for downstream_pr in all_dependencies:
    print downstream_pr
