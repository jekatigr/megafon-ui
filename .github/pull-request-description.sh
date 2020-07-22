#!/bin/bash

GITHUB_USERNAME="$1"
GITHUB_AUTH_TOKEN="$2"
REPO_NAME="$3"

BASE_BRANCH="conventional-test"

function generate_pull_request_body () {
    local pull_request=$1
    local versions=$2
    local changelogs=$3

    local pull_request_description;

    pull_request_description=$(echo "${pull_request}" |
        grep body | # get string with body from response
        cut -d ':' -f 2 | # get body value
        cut -d '"' -f 2 | # get body without double quotes
        awk -F'<!-- Autogenerated -->' '{print $1}' # get only original pull request description without autogenerated info
    )

    # compose pull request description
    local BODY="$pull_request_description"'<!-- Autogenerated -->\n\n\n---\n## Upcoming release changes\n> Each branch build will replace this description.\n\n'

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

    echo '{"body":"'"$BODY"'"}'
}

function extract_changelogs() {
    local changelogs;
    changelogs=$(git diff HEAD --unified=0 --no-prefix -- '*CHANGELOG.md' | # get changes from CHANGELOG files
        grep -E "^\+" | # get only additions from git diff
        sed 's/^.//' |  # remove '+' from beginning of each line
        sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' # replace linebreaks with '\n' for curl
    );

    echo "$changelogs";
}

function extract_versions() {
    local versions;
    versions=$(git diff HEAD --unified=0 --no-prefix --relative='packages' '*package.json' | # get changes from package.json files
        grep -E "(\"version\": |\+\+\+)" | # get filenames and "version" change
        sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g' | # replace linebreaks with '\n'
        sed 's/"/\\"/g' # replace '"' with '\"' for curl
    );

    echo "$versions";
}

function update_pull_request_description() {
    local pull_request_number=$1

    git fetch origin pull/"${pull_request_number}"/head
    git checkout FETCH_HEAD

    # generate changelogs and update version
    #lerna version --conventional-commits --no-git-tag-version --no-push --yes

    # extract info from git diff
    #CHANGELOGS_1=$(extract_changelogs)
    #VERSIONS_1=$(extract_versions)

    #NEW_PULL_REQUEST_BODY=$(generate_pull_request_body "$PULL_REQUEST" "$VERSIONS_1" "$CHANGELOGS_1")

    #echo "${NEW_PULL_REQUEST_BODY}"

    # update pull request description
    #curl \
    #  --silent \
    #  -X PATCH \
    #  -H "Accept: application/vnd.github.v3+json" \
    #  -u "${GITHUB_USERNAME}:${GITHUB_AUTH_TOKEN}" \
    #  https://api.github.com/repos/"${GITHUB_USERNAME}"/"${REPO_NAME}"/pulls/"${PULL_REQUEST_ID}" \
    #  -d "${NEW_PULL_REQUEST_BODY}"

    # rollback changes in working tree
    #git reset --hard
}

# get pull request info
PULL_REQUESTS=$(curl -s \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/"${GITHUB_USERNAME}"/"${REPO_NAME}"/pulls?state=open\&base="${BASE_BRANCH}")

for k in $(jq '. | keys | .[]' <<< "$PULL_REQUESTS"); do
    pull_request=$(jq -r ".[$k]" <<< "$PULL_REQUESTS");
    sha=$(jq -r ".head.sha" <<< "$pull_request");
    body=$(jq -r ".body" <<< "$pull_request");

    last_sha=$(sed -n 's/\(.*\)<!-- Autogenerated last_sha:\(.*\) -->\(.*\)/\2/p' <<< "$body")

    if [[ "$last_sha" != "$sha" ]] || [[ -n "$last_sha" ]]
    then
        pr_number=$(jq -r ".number" <<< "$pull_request");
        echo "Pull request #${pr_number} description should be updated";
        update_pull_request_description "$pr_number";
    fi
done

#echo "Pull requests description updated."
