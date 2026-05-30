#!/bin/sh

set -e

handle_error() {
    if echo "$1" | jq -e 'has("error")' >/dev/null; then
        echo "$1" | jq -r '"\nError: \(.error): \(.message)"' >&2
        exit 1
    fi
}

frontmatter() {
    awk '
        /^---$/ { delim++; next }
        delim == 1 { print }
        delim == 2 { exit }
    ' "$1"
}

normalise_datetime() {
    dt=$1

    case "$dt" in
        *Z|*[+-][0-9][0-9]:[0-9][0-9])
            ;;
        *)
            dt="${dt}Z"
            ;;
    esac

    date -u -d "$dt" '+%Y-%m-%dT%H:%M:%S.000Z'
}

if [ -z "$ATPROTO_DID" ]; then
    echo "ATPROTO_DID is not set"
    exit 1
fi

if [ -z "$ATPROTO_PWD" ]; then
    echo "ATPROTO_PWD is not set"
    exit 1
fi

if [ -z "$SITE_KEY" ]; then
    echo "SITE_KEY is not set"
    exit 1
fi

if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
    echo "SOURCE_DIR is not set or does not exist"
    exit 1
fi

if [ -z "$ROOT_DIR" ] || [ ! -d "$ROOT_DIR" ]; then
    echo "ROOT_DIR is not set or does not exist"
    exit 1
fi

if [ -z "$CONTENT_DIR" ] || [ ! -d "$CONTENT_DIR" ]; then
    echo "CONTENT_DIR is not set or does not exist"
    exit 1
fi

if [ -z "$BUILD_DIR" ] || [ ! -d "$BUILD_DIR" ]; then
    echo "BUILD_DIR is not set or does not exist"
    exit 1
fi

echo "did=$ATPROTO_DID"

DOC=$(curl -s "https://plc.directory/$ATPROTO_DID")
PDS=$(echo "$DOC" | jq -r '.service[0].serviceEndpoint')

echo "pds=$PDS"

if [ -z "$PDS" ]; then
    echo "PDS service endpoint not set"
    exit 1
fi

SESSION=$(curl -s "$PDS/xrpc/com.atproto.server.createSession" \
            -H "Content-Type: application/json" \
            -d "{\"identifier\":\"$ATPROTO_DID\",\"password\":\"$ATPROTO_PWD\"}")
handle_error "$SESSION"

ACCESS_JWT=$(echo "$SESSION" | jq -r '.accessJwt')
REFRESH_JWT=$(echo "$SESSION" | jq -r '.refreshJwt')

if [ ! -z "$ACCESS_JWT" ] && [ ! -z "$REFRESH_JWT" ]; then
    echo "auth success"
fi

SOURCES=$(find "$SOURCE_DIR" -type f -name '*.md' | sed 's|^\./||')

printf '%s\n' "$SOURCES" | while IFS= read -r SOURCE; do
    key=$(printf "$SOURCE" | sha1sum | awk '{print $1}')
    checksum=$(sha1sum "$SOURCE" | awk '{print $1}')
    printf "checking: $SOURCE ($checksum) ..."

    post_rec=$(curl -sG "$PDS/xrpc/com.atproto.repo.getRecord" \
                --data-urlencode "repo=$ATPROTO_DID" \
                --data-urlencode "collection=net.ngill.post" \
                --data-urlencode "rkey=$key")

    do_refresh=""
    if echo "$post_rec" | jq -e 'has("value")' >/dev/null && [ -n "$REFRESH" ]; then
        if echo "$post_rec" | jq -e '.value.document != null and .value.document != ""' >/dev/null; then
            uri=$(echo "$post_rec" | jq -r ".value.document")
            rkey=$(echo "$uri" | awk -F/ '{print $NF}')

            del_doc_req=$(jq -n \
              --arg repo "$ATPROTO_DID" \
              --arg rkey "$rkey" '
            {
              repo: $repo,
              collection: "site.standard.document",
              rkey: $rkey
            }
            ')

            resp=$(curl -s "$PDS/xrpc/com.atproto.repo.deleteRecord" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $ACCESS_JWT" \
                    -d "$del_doc_req")
            handle_error "$resp"
        fi

        del_post_req=$(jq -n \
          --arg repo "$ATPROTO_DID" \
          --arg checksum "$checksum" '
        {
          repo: $repo,
          collection: "net.ngill.post",
          rkey: $checksum
        }
        ')

        resp=$(curl -s "$PDS/xrpc/com.atproto.repo.deleteRecord" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $ACCESS_JWT" \
                -d "$del_post_req")
        handle_error "$resp"

        do_refresh="1"
    fi

                    
    if echo "$post_rec" | jq -e ".error == \"RecordNotFound\" or .value.sha1 != \"$checksum\"" >/dev/null || [ -n "$do_refresh" ]; then
        fm=$(frontmatter "$SOURCE")
        title=$(printf '%s\n' "$fm" | yq -r '.title // ""')
        summary=$(printf '%s\n' "$fm" | yq -r '.summary // ""')
        date=$(printf '%s\n' "$fm" | yq -r '.date // ""')

        if [ -z "$date" ]; then
            echo "\nno date set!"
            exit 1
        fi

        date=$(normalise_datetime "$date")
        slug="/$(realpath --relative-to="$ROOT_DIR" "$SOURCE" | sed 's/\.md$/.html/')"

        doc_rec=$(jq -n \
          --arg did "$ATPROTO_DID" \
          --arg site_key "$SITE_KEY" \
          --arg slug "$slug" \
          --arg title "$title" \
          --arg summary "$summary" \
          --arg date "$date" '
        {
          repo: $did,
          collection: "site.standard.document",
          record: {
            "$type": "site.standard.document",
            site: ("at://" + $did + "/site.standard.publication/" + $site_key),
            path: $slug,
            title: $title,
            description: $summary,
            publishedAt: $date
          }
        }
        ')

        printf "updating..."

        if [ ! -n "$DRY" ]; then
            resp=$(curl -s "$PDS/xrpc/com.atproto.repo.createRecord" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $ACCESS_JWT" \
                    -d "$doc_rec")
            handle_error "$resp"

            doc_target=$(echo "$resp" | jq -r '.uri')
        fi

        build_out="$BUILD_DIR/$(realpath --relative-to="$CONTENT_DIR" "$SOURCE" | sed 's|\./||' | sed 's/\.md$/.html/')"
        sed -i "s|%STANDARD_SITE_DOCUMENT%|$doc_target|" "$build_out"

        npost_rec=$(jq -n \
          --arg did "$ATPROTO_DID" \
          --arg key "$key" \
          --arg checksum "$checksum" \
          --arg doc_target "$doc_target" \
          --arg slug "$slug" '
        {
          repo: $did,
          collection: "net.ngill.post",
          rkey: $key,
          record: {
            "$type": "net.ngill.post",
            sha1: $checksum,
            document: $doc_target,
            final: $slug
          }
        }
        ')

        if [ ! -n "$DRY" ]; then
            resp=$(curl -s "$PDS/xrpc/com.atproto.repo.createRecord" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $ACCESS_JWT" \
                    -d "$npost_rec")
            handle_error "$resp"
        fi

        echo "updated"
    elif echo "$post_rec" | jq -e ".value.sha1 == \"$checksum\"" > /dev/null; then
        doc_target=$(echo "$post_rec" | jq -r ".value.document")
        build_out="$BUILD_DIR/$(realpath --relative-to="$CONTENT_DIR" "$SOURCE" | sed 's|\./||' | sed 's/\.md$/.html/')"
        sed -i "s|%STANDARD_SITE_DOCUMENT%|$doc_target|" "$build_out"
        
        echo "up to date"
    else
        printf "\n"
        handle_error "$post_rec"
    fi

done
