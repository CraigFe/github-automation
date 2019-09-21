#!/bin/bash
set -euo pipefail

# This script clones all non-fork repositories owned by a particular user into
# the current directory.

hub api --paginate graphql -f query="
query(\$endCursor: String) {
    repositoryOwner(login: \"$1\") {
      repositories(fork: false, first: 100, after: \$endCursor) {
        nodes {
          url
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }
  }" |\
	  jq -r '.data.repositoryOwner.repositories.nodes | map(.url) | .[]' |\
	  sort |\
	  xargs --max-args=1 --max-procs=0 git clone --no-checkout --origin upstream
