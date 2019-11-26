#!/bin/bash
set -euo pipefail

# This script queries the GitHub GraphQLv4 API to aggregate weekly contributions
# into a JSON blob (includes PRs created/reviewed and issues created). Pass the
# year and ISO week number as arguments:
#
# > contributions_query.sh 20 03
#
# Limitations: this script uses an API endpoint that is unable to show private
# contributions. If any restricted contributions exist in the given week, a
# warning will be shown.
# (see: https://github.community/t5/GitHub-API-Development-and/APIv4-feature-request-allow-contributionsCollection-to-include/m-p/39696#M3600)

command -v hub >/dev/null 2>&1 || { echo >&2 "Missing dependency 'hub'"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "Missing dependency 'jq'"; exit 1; }

YEAR="$1"
WEEK="$2"

COLOR_RESET="\033[0m"
COLOR_RED="\033[0;31m"
COLOR_GREEN="\033[0;32m"
COLOR_GREENB="\033[1;32m"
COLOR_PURPLEB="\033[1;35m"
COLOR_CYAN="\033[0;36m"

function action {
    echo -e "\n$COLOR_CYAN<><><><> $COLOR_GREENB${1}$COLOR_CYAN <><><><>$COLOR_RESET\n"
}

function week2date () {
    # Taken from https://stackoverflow.com/a/46002400
    local year=$1
    local week=$2
    local dayofweek=$3
    date -d "$year-01-01 +$(( $week * 7 + 1 - $(date -d "$year-01-04" +%w ) - 3 )) days -2 days + $dayofweek days" +"%Y-%m-%d"
}
export -f week2date

FROM="$(week2date $YEAR $WEEK 1)T00:00:00Z"
TO="$(week2date $YEAR $WEEK 7)T23:59:59Z"

echo -e "Showing contributions in the range $FROM--$TO"

QUERY=$(hub api --paginate graphql -f query="
query(\$endCursor: String) {
  viewer {
    contributionsCollection(from: \"$FROM\", to: \"$TO\") {
      restrictedContributionsCount
      pullRequestContributionsByRepository(maxRepositories: 100) {
        repository {
          nameWithOwner
        }
        contributions(orderBy: {field: OCCURRED_AT, direction: ASC}, first: 100, after: \$endCursor) {
          nodes {
            pullRequest {
              createdAt
              title
              url
            }
          }
        }
      }
      issueContributionsByRepository(maxRepositories: 100) {
        repository {
          nameWithOwner
        }
        contributions(orderBy: {field: OCCURRED_AT, direction: ASC}, first: 100, after: \$endCursor) {
          nodes {
            issue {
              createdAt
              title
              url
            }
          }
        }
      }
      pullRequestReviewContributionsByRepository(maxRepositories: 100) {
        repository {
          nameWithOwner
        }
        contributions(orderBy: {field: OCCURRED_AT, direction: ASC}, first: 100, after: \$endCursor) {
          nodes {
            pullRequest {
              createdAt
              title
              url
            }
          }
        }
      }
    }
  }
}")

action "PRs opened"

echo $QUERY | jq -r '
.data.viewer.contributionsCollection.pullRequestContributionsByRepository |
  map(
    {
      repo: .repository.nameWithOwner,
      contributions: .contributions.nodes | map(.pullRequest)
    }
  )'

action "Issues opened"

echo $QUERY | jq -r '
.data.viewer.contributionsCollection.issueContributionsByRepository |
  map(
    {
      repo: .repository.nameWithOwner,
      contributions: .contributions.nodes | map(.issue)
    }
  )'

action "PRs reviewed"

echo $QUERY | jq -r '
.data.viewer.contributionsCollection.pullRequestReviewContributionsByRepository |
  map(
    {
      repo: .repository.nameWithOwner,
      contributions: .contributions.nodes | map(.pullRequest)
    }
  )'


PRIVATE_CONTRIBUTIONS=$(echo $QUERY | jq -r '.data.viewer.contributionsCollection.restrictedContributionsCount')

if [ "$PRIVATE_CONTRIBUTIONS" != "0" ]; then
    echo -e "\nWARNING: unable to show $PRIVATE_CONTRIBUTIONS private contributions\n"
fi
