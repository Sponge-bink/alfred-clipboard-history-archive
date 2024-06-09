#!/usr/bin/env bash
# This is a script that provides infinite history to get around Alfred's 3-month limit.
# It works by regularly backing up and appending the items in the alfred db to a
# sqlite database in the user's home folder. It also provides search functionality.

# https://www.alfredforum.com/topic/10969-keep-clipboard-history-forever/?tab=comments#comment-68859
# https://www.reddit.com/r/Alfred/comments/cde29x/script_to_manage_searching_backing_up_and/

# Example Usage:
#    alfred-clipboard.sh backup
#    alfred-clipboard.sh status
#    alfred-clipboard.sh shell
#    alfred-clipboard.sh dump > ~/Desktop/clipboard_db.sqlite3
#    alfred-clipboard.sh search 'some_string' --separator=, --limit=2 --fields=ts,item,app

shopt -s extglob
set +o pipefail

# *************************************************************************
# --------------------------- Why this exists -----------------------------
# *************************************************************************

# I'd be willing to pay >another $30 on top of my existing Legendary license for 
# unlimited clipboard history, and I fully accept any CPU/Memory hit necessary to get it.
#
# I use Clipboard History as a general buffer for everything in my life, 
# and losing everything beyond 3 months is a frequent source of headache.  
# Here's a small sample of a few recent things I've lost due to history expiring:
#
#  - flight confirmation details
#  - commit summaries with commit ids (detached commits that are hard to find due to deleted branches)
#  - important UUIDs
#  - ssh public keys
#  - many many many file paths (lots of obscure config file paths that I never bother to remember)
#  - entire config files 
#  - blog post drafts
#  - comments on social media
#  - form fields on websites
#
# It's always stuff that I don't realize at the time would be important later
# so it would be pointless to try and use snippets to solve this issue.
#
# Having a massive index of every meaningful string that's passed through my 
# brain is incredibly useful. In fact I rely on it so much that I'd even 
# willing to manage an entire separate server with Elasticsearch/Redis 
# full-text search to handle storage and indexing beyond 3 months (if 
# that's really what it takes to keep history indefinitely).
#
# If needed you could hide "6 months" "12 months" and "unlimited" behind an 
# "Advanced settings" pane and display a big warning about potential performance 
# downsides.
#
# For now I just periodically back up `~/Library/Application Support/Alfred/Databases/clipboard.alfdb` 
# to a separate folder, and merge the rows in it with a main database.  This at 
# least allows me to query further back by querying the merged database directly.
#  Maybe I'll build a workflow to do that if I have time, but no promises.
#
# I've created a script that handles the backup of the db, merging it with an
# infinite-history sqlite db in my home folder, and searching functionality.
# https://gist.github.com/pirate/6551e1c00a7c4b0c607762930e22804c
#
# I also tried hacking around the limit by changing the Alfred binary directly
# but unfortunately I was only able to find the limit in the .nib file (which
# is useless as it's just the GUI definition).
# I'd have to properly decompile Alfred it to find the actual limit logic...
# $ ggrep --byte-offset --only-matching --text '3 Months' \
#       '/Applications/Alfred.app/Contents/Frameworks/Alfred Framework.framework/Versions/A/Resources/AlfredFeatureClipboard.nib'
# 12590:3 Months
#
# (Now I just have to convince the Google Chrome team to also allow storing 
# browser history longer than 3 months... then the two biggest sources of 
# data-loss pain in my life will be eliminated).


# *************************************************************************
# --------------------------- Config Options ------------------------------
# *************************************************************************

# init definition altered later
BACKUP_DATA_DIR="${BACKUP_DATA_DIR:-$HOME/Clipboard}"
ALFRED_DATA_DIR="${ALFRED_DATA_DIR:-$HOME/Library/Application Support/Alfred/Databases}"
ALFRED_DB_NAME="${ALFRED_DB_NAME:-clipboard.alfdb}"
BACKUP_DB_NAME="${BACKUP_DB_NAME:-$(date +'%Y-%m-%d_%H:%M:%S').sqlite3}"
MERGED_DB_NAME="${MERGED_DB_NAME:-all.sqlite3}"
# init definition ends

# uncomment the second option if you also to store the duplicate item history
# entries for whenever the same value was copied again at a different time
# This wouldn't be affective since this UNIQUE_FILTER variable is no longer 
# in use
UNIQUE_FILTER="${UNIQUE_FILTER:-'latest.item = item'}"
# UNIQUE_FILTER="${UNIQUE_FILTER:-'latest.item = item AND latest.ts = ts'}"


# *************************************************************************
# -------------------------------------------------------------------------
# *************************************************************************


# init definition altered later
ALFRED_DB="$ALFRED_DATA_DIR/$ALFRED_DB_NAME"
BACKUP_DB="$BACKUP_DATA_DIR/$BACKUP_DB_NAME"
MERGED_DB="$BACKUP_DATA_DIR/$MERGED_DB_NAME"
# init definition ends
MERGE_QUERY="
    /* Delete any items that are the same in both databases */
    DELETE FROM merged_db.clipboard
    WHERE item IN (SELECT item FROM latest_db.clipboard);

    /* Insert all items from the latest_db backup  */
    INSERT INTO merged_db.clipboard
    SELECT * FROM latest_db.clipboard;
"

# clipboard timestamps are in Mac epoch format (Mac epoch started on 1/1/2001, not 1/1/1970)
# to convert them to standard UTC UNIX timestamps, add 978307200
# 2 months = 60 days * 24 hr * 60 min * 60 sec = 5184000 seconds
# for all rows WHERE ts <(current_timestamp - 5184000) aka older than 2 months ago, set ts = ts + (60 * 60 * 24 * 30) aka one month ago
BUMP_QUERY="
    UPDATE
        ts = ts + 2592000
    WHERE
        ts < (current_timestamp - 5184000)

    TODO finish this
"



number_of_backed_up_rows=0
existing_rows=0
merged_rows=0

number_of_original_rows=$(sqlite3 "$ALFRED_DB" 'select count(*) from clipboard;')


function backup_alfred_db {
    echo "[+] Backing up Alfred Clipboard History DB..."
    cp "$ALFRED_DB" "$BACKUP_DB"
    number_of_backed_up_rows=$(sqlite3 "$BACKUP_DB" 'select count(*) from clipboard;')
    echo "    √ Read     $number_of_original_rows items from $ALFRED_DB_NAME"
    echo "    √ Wrote    $number_of_backed_up_rows items to $BACKUP_DB_NAME"
}

function init_master_db {
    echo -e "\n[+] Initializing new clipboard database with $number_of_backed_up_rows items..."
    cp "$BACKUP_DB" "$MERGED_DB"
    echo "    √ Copied new db $MERGED_DB"
    echo
    sqlite3 "$MERGED_DB" ".schema" | sed 's/^/    /'
}

function update_master_db {
    echo -e "\n[*] Updating Master Clipboard History DB..."
    existing_rows=$(sqlite3 "$MERGED_DB" 'select count(*) from clipboard;')

    echo "    √ Read     $existing_rows existing items from "$(basename "$MERGED_DB")
    sqlite3 "$MERGED_DB" "
        attach '$MERGED_DB' as merged_db;
        attach '$BACKUP_DB' as latest_db;
        BEGIN;
        $MERGE_QUERY
        COMMIT;
        detach latest_db;
        detach merged_db;
    "
    merged_rows=$(sqlite3 "$MERGED_DB" 'select count(*) from clipboard;')
    new_rows=$(( merged_rows - existing_rows ))
    echo "    √ Incoming $number_of_backed_up_rows items from backup you just created to $MERGED_DB_NAME"
    echo "    √ Merged   $new_rows new items to Master DB"
    # echo "    √ Wrote    $merged_rows total items to $MERGED_DB_NAME"
}

function bump_alfred_db_timestamps {
    echo -e "\n[+] Bumping timestamps in clipboard database so that older items don't expire..."
    echo "NOT YET IMPLEMENTED"
    exit 4
    # TODO
    sqlite3 "$ALFRED_DB" "
        BEGIN;
        $BUMP_QUERY
        COMMIT;
    "
}

# *************************************************************************
# -------------------------------------------------------------------------
# *************************************************************************

function summary {
    number_of_backed_up_rows=$(sqlite3 "$BACKUP_DB" 'select count(*) from clipboard;')
    existing_rows=$(sqlite3 "$MERGED_DB" 'select count(*) from clipboard;')
    merged_rows=$(sqlite3 "$MERGED_DB" 'select count(*) from clipboard;')
    echo "    Original   $ALFRED_DB ($number_of_original_rows items)"
    echo "    Backup     $BACKUP_DB ($number_of_backed_up_rows items)"
    echo "    Master     $MERGED_DB ($merged_rows items)"
}

function status {
    merged_rows=$(sqlite3 "$MERGED_DB" 'select count(*) from clipboard;')
    echo "Alfred: $ALFRED_DB ($number_of_original_rows items)"
    echo "Master: $MERGED_DB ($merged_rows items)"
}

function backup {
    backup_alfred_db
    [[ -f "$MERGED_DB" ]] || init_master_db
    update_master_db

    echo -e "\n[√] Done backing up clipboard history."
    summary
}

function bump {
    backup_alfred_db
    bump_alfred_db_timestamps
    echo -e "\n[√] Done bumping clipboard history timestamps."
    summary
}

function print_help {
    echo "Usage: TODO"
}

function unrecognized {
    echo "Error: Unrecognized argument $1" >&2
    print_help
    exit 2
}

# *************************************************************************
# -------------------------------------------------------------------------
# *************************************************************************

function main {
    COMMAND=''
    declare -a ARGS=()
    declare -A KWARGS=( [style]='csv' [separator]="|" [fields]='item' [verbose]='' [limit]=10)

    # mkdir -p "$BACKUP_DATA_DIR"

    while (( "$#" )); do
        case "$1" in
            help|-h|--help)
                COMMAND='help'
                print_help
                exit 0;;

            -v|--verbose)
                KWARGS[verbose]='yes'
                shift;;

            -j|--json)
                KWARGS[style]='json'
                shift;;

            --separator|--separator=*)
                if [[ "$1" == *'='* ]]; then
                    KWARGS[separator]="${1#*=}"
                else
                    shift
                    KWARGS[separator]="$1"
                fi
                shift;;

            -s|--style|-s=*|--style=*)
                if [[ "$1" == *'='* ]]; then
                    KWARGS[style]="${1#*=}"
                else
                    shift
                    KWARGS[style]="$1"
                fi
                shift;;

            -l|--limit|-l=*|--limit=*)
                if [[ "$1" == *'='* ]]; then
                    KWARGS[limit]="${1#*=}"
                else
                    shift
                    KWARGS[limit]="$1"
                fi
                shift;;

            -f|--fields|-f=*|--fields=*)
                if [[ "$1" == *'='* ]]; then
                    KWARGS[fields]="${1#*=}"
                else
                    shift
                    KWARGS[fields]="$1"
                fi
                shift;;

            -d|--directory|-d=*|--directory=*)
                if [[ "$1" == *'='* ]]; then
                    KWARGS[directory]="${1#*=}"
                else
                    shift
                    KWARGS[directory]="$1"
                fi
                shift;;

            +([a-z]))
                if [[ "$COMMAND" ]]; then
                    ARGS+=("$1")
                else
                    COMMAND="$1"
                fi
                shift;;

            --)
                shift;
                ARGS+=("$@")
                break;;
            *)
                [[ "$COMMAND" != "search" ]] && unrecognized "$1"
                ARGS+=("$1")
                shift;;
        esac
    done

    # echo "COMMAND=$COMMAND"
    # echo "ARGS=${ARGS[*]}"
    # for key in "${!KWARGS[@]}"; do
    #     echo "$key=${KWARGS[$key]}"
    # done

    BACKUP_DATA_DIR="${KWARGS[directory]}"

    if [ ! -d "$BACKUP_DATA_DIR" ]; then
        echo "The path '$BACKUP_DATA_DIR' does not exist."
        exit 0
    fi


    ALFRED_DATA_DIR="${ALFRED_DATA_DIR:-$HOME/Library/Application Support/Alfred/Databases}"
    ALFRED_DB_NAME="${ALFRED_DB_NAME:-clipboard.alfdb}"
    BACKUP_DB_NAME="${BACKUP_DB_NAME:-$(date +'%Y-%m-%d_%H:%M:%S').sqlite3}"
    MERGED_DB_NAME="${MERGED_DB_NAME:-all.sqlite3}"


    ALFRED_DB="$ALFRED_DATA_DIR/$ALFRED_DB_NAME"
    BACKUP_DB="$BACKUP_DATA_DIR/$BACKUP_DB_NAME"
    MERGED_DB="$BACKUP_DATA_DIR/$MERGED_DB_NAME"


    if [[ "$COMMAND" == "status" ]]; then
        status
    elif [[ "$COMMAND" == "backup" ]]; then
        backup
    elif [[ "$COMMAND" == "shell" ]]; then
        sqlite3 "$MERGED_DB"
    elif [[ "$COMMAND" == "dump" ]]; then
        sqlite3 "$MERGED_DB" ".dump"
    # elif [[ "$COMMAND" == "bump" ]]; then
    #     bump_alfred_db_timestamps
    elif [[ "$COMMAND" == "search" ]]; then
        if [[ "${KWARGS[style]}" == "json" ]]; then
            sqlite3 "$MERGED_DB" "
                SELECT '{\"items\": [' || group_concat(match) || ']}'
                FROM (
                    SELECT json_object(
                        'valid', 1,
                        'uuid', ts,
                        'title', substr(item, 1, 120),
                        'arg', item
                    ) as match
                    FROM clipboard
                    WHERE item LIKE '%${ARGS[*]}%'
                    ORDER BY ts DESC
                    LIMIT ${KWARGS[limit]}
                );
            "
        else
            sqlite3 -separator "${KWARGS[separator]}" "$MERGED_DB" "
                SELECT ${KWARGS[fields]}
                FROM clipboard
                WHERE item LIKE '%${ARGS[*]}%'
                ORDER BY ts DESC
                LIMIT ${KWARGS[limit]};
            "
        fi

    else
        unrecognized "$COMMAND"
    fi
}

main "$@"