#!/bin/bash

printf "provided envs:\n\tGITHUB_REPOSITORY: '%s',\n\tBASE_BRANCH: '%s'\n" "$GITHUB_REPOSITORY" "$BASE_BRANCH"

if [[ -z "$GITHUB_REPOSITORY" ]] || [[ -z "$GITHUB_AUTH_TOKEN" ]] || [[ -z "$BASE_BRANCH" ]]
then
    echo "Not enough info to make checks.";
    exit 1;
fi

GITHUB_USERNAME=$(sed 's/\/.*//' <<< "$GITHUB_REPOSITORY");
REPO_NAME=$(sed 's/.*\///' <<< "$GITHUB_REPOSITORY");
echo "Extracted user and repository name from env variable.";

function compose_new_body() {
    local pull_request_body=$1;
    local versions=$2;
    local changelogs=$3;
    local pull_request_last_sha=$4;

    local pull_request_description;

    # get only original pull request description without autogenerated info
    pull_request_description=$(
        sed -e "s/\r//g" <<< "$pull_request_body" | # remove windows carriage return symbols (github adds this in body field omg)
        sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | # replace linebreaks with '\n' (just in case)
        awk -F'<!-- Autogenerated last_sha:(.*) -->' '{print $1}'
    );

    # compose pull request description
    local BODY="${pull_request_description}<!-- Autogenerated last_sha:${pull_request_last_sha} -->\n\n\n---\n## Upcoming release changes\n> Each branch build will replace this description.\n\n"

    if [ -n "$versions" ]
    then
        BODY+='### Version updates:\n'"\`\`\`"'\n'"$versions"'\n'"\`\`\`"'\n'
    else
        BODY+='### Version updates:\nNo version changes detected.\n'
    fi

    if [ -n "$changelogs" ]
    then
        BODY+='### Change logs:\n'"$changelogs"
    else
        BODY+='### Change logs:\nNo updates detected.\n'
    fi

    BODY=$(
        echo "$BODY" |
        sed -e "s/\r//g" | # remove windows carriage return symbols (github adds this in body field omg)
        sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | # replace linebreaks with '\n'
        sed 's/"/\\"/g' # replace '"' with '\"' for curl
    )

    echo '{"body":"'"$BODY"'"}';
}

function extract_changelogs() {
    local __changelogs;
    __changelogs=$(git diff HEAD --unified=0 --no-prefix -- '*CHANGELOG.md' | # get changes from CHANGELOG files
        grep -E "^\+" | # get only additions from git diff
        sed 's/^.//'  # remove '+' from beginning of each line
    );

    echo "$__changelogs";
}

function extract_versions() {
    local __versions;
    __versions=$(git diff HEAD --unified=0 --no-prefix --relative='packages' '*package.json' | # get changes from package.json files
        grep -E "(\"version\": |\+\+\+)" # get filenames and "version" change
    );

    echo "$__versions";
}

function update_pull_request_description() {
    local pull_request_number=$1
    local pull_request_body=$2
    local pull_request_last_sha=$3

    git fetch origin pull/"${pull_request_number}"/head:pr-"${pull_request_number}"
    git checkout pr-"${pull_request_number}"

    # generate changelogs and update version
    yarn exec lerna version --allow-branch=* --conventional-commits --no-git-tag-version --no-push --yes

    local versions;
    local changelogs;
    # extract info from git diff
    versions=$(extract_versions)
    changelogs=$(extract_changelogs)

    local new_pull_request_body;
    new_pull_request_body=$(compose_new_body "$pull_request_body" "$versions" "$changelogs" "$pull_request_last_sha")

    # update pull request description
    curl \
      -X PATCH \
      -H "Accept: application/vnd.github.v3+json" \
      -u "${GITHUB_USERNAME}:${GITHUB_AUTH_TOKEN}" \
      https://api.github.com/repos/"${GITHUB_USERNAME}"/"${REPO_NAME}"/pulls/"${pull_request_number}" \
      -d "${new_pull_request_body}"

    # rollback changes in working tree
    git reset --hard
}

fetch_url="https://api.github.com/repos/${GITHUB_USERNAME}/${REPO_NAME}/pulls?state=open&base=${BASE_BRANCH}"
echo "Fetching open pull requests for base branch with url: ${fetch_url}";
# get pull requests info
PULL_REQUESTS=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  "${fetch_url}")
echo "Fetched.";

for k in $(jq '. | keys | .[]' <<< "$PULL_REQUESTS"); do
    pull_request=$(jq -r ".[$k]" <<< "$PULL_REQUESTS");
    pr_number=$(jq -r ".number" <<< "$pull_request");
    sha=$(jq -r ".head.sha" <<< "$pull_request");
    body=$(jq -r ".body" <<< "$pull_request");

    echo "Check pull request #${pr_number}...";

    last_sha=$(sed -n 's/\(.*\)<!-- Autogenerated last_sha:\(.*\) -->\(.*\)/\2/p' <<< "$body")

    if [[ "$last_sha" != "$sha" ]] || [[ -z "$last_sha" ]]
    then
        echo "Updating pull request #${pr_number} description...";
        update_pull_request_description "$pr_number" "$body" "$sha";
        echo "Pull request #${pr_number} description updated.";
    else
        echo "Pull request #${pr_number} doesn't need to be updated.";
    fi
done

echo "Check done.";
