#!/usr/bin/env dash

# need to use dash instead of bash, since bash's wait built-in is broken and can lead to 100% CPU lockup

# tailor these directories to your needs
WORK_DIR="./results"
BLOCKSTACK_DIR="$HOME/.blockstack-server/"

ALL_ZONEFILES="$WORK_DIR/all_zonefiles.txt"
ALL_PROFILES="$WORK_DIR/all_profiles/"
ALL_ANALYSIS="$WORK_DIR/all_profiles_analysis/"

ANALYSIS_TOOL="./check_profiles.js"

DB_PATH="$BLOCKSTACK_DIR/blockstack-server.db"
OFFCHAIN_DB_PATH="$BLOCKSTACK_DIR/subdomains.db"

THIS_COMMAND="$0"

# runs in a child process
get_profile_data() {
   local ROW="$1"       # format: <name>|<address>|<value_hash>
   local PROFILE_SUFFIX="$2"

   IFS="|"
   set -- $ROW

   local BLOCKSTACK_ID="$1"
   local ADDRESS="$2"
   local ZFHASH="$3"

   local ZFPATH_PART="$(echo "$ZFHASH" | sed -r 's/^([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]+)$/\/\1\/\2\/\1\2\3.txt/g')"
   local ZFPATH="$BLOCKSTACK_DIR/zonefiles/$ZFPATH_PART"
   local PROFILE_PATH="$ALL_PROFILES/$ZFHASH.$PROFILE_SUFFIX"

   if [ -f "$PROFILE_PATH" ]; then 
      return 0
   fi
   
   if ! [ -f "$ZFPATH" ]; then
      echo >&2 "No zonefile $ZFHASH"
      return 1
   fi


   local PROFILE_URL="$(cat "$ZFPATH" | grep -A 10 "^\$ORIGIN" | egrep -o 'http[s]?://.+' | head -n 1)"
   PROFILE_URL="${PROFILE_URL%%\"}"     # strip trailing "

   if [ -z "$PROFILE_URL" ]; then 
      echo >&2 "No profile URL in $NAME $ZFHASH"
      return 1
   fi

   echo "Get $ZFHASH $PROFILE_URL last-modified..."
   LAST_MODIFIED="$(curl -sLf -D - -X HEAD -m 10 --connect-timeout 5 "$PROFILE_URL" | grep -i 'last-modified' | cut -d ' ' -f 3-100)"
   if [ $? -ne 0 ]; then 
      echo >&2 "Failed to HEAD $NAME $ZFHASH"
      return 1
   fi

   echo "Get $ZFHASH $PROFILE_URL profile..."
   curl -sLf -m 10 --connect-timeout 5 --expect100-timeout 5 "$PROFILE_URL" > "$PROFILE_PATH"
   if [ $? -ne 0 ]; then 
      rm "$PROFILE_PATH"
      echo >&2 "Failed to resolve $NAME $ZFHASH"
      return 1
   fi

   echo "{\"name\": \"$BLOCKSTACK_ID\", \"address\": \"$ADDRESS\", \"last_modified\": \"$LAST_MODIFIED\", \"zonefile\": \"$ZFHASH\", \"profile_url\": \"$PROFILE_URL\", \"profile\": " > "$PROFILE_PATH.tmp"
   cat "$PROFILE_PATH" | jq '.[0].decodedToken.payload.claim' >> "$PROFILE_PATH.tmp" 2>/dev/null
   echo "}" >> "$PROFILE_PATH.tmp"

   # make sure it's JSON 
   cat "$PROFILE_PATH.tmp" | jq >/dev/null 2>/dev/null
   if [ $? -ne 0 ]; then 
      rm "$PROFILE_PATH.tmp" "$PROFILE_PATH"
      echo >&2 "Failed to store data for profile $PROFILE_PATH"
      return 1
   fi

   mv "$PROFILE_PATH.tmp" "$PROFILE_PATH"

   return 0
}

process_profiles() {
   local ALL_ZONEFILES="$1"
   local GROUP="$2"
   local OFFSET="$3"

   local ANALYSIS_PATH="$ALL_ANALYSIS/$GROUP.$OFFSET"
   local ANALYSIS_BUFFER_PATH="$ALL_ANALYSIS/.$GROUP.$OFFSET.tmp"

   # go get the next batch of profiles
   for ROW in $(cat $ALL_ZONEFILES); do
      dash "$THIS_COMMAND" get_profile_data "$ROW" "$GROUP.$OFFSET" &
   done 

   NUM_ZFH="$(wc -l "$ALL_ZONEFILES" | cut -d ' ' -f 1)"
   for JOB in $(seq 1 $NUM_ZFH); do
      wait %${JOB}
   done

   # combine this batch of profiles for subsequent analysis 
   echo "[" > "$ANALYSIS_BUFFER_PATH"
   NEED_TRIM=0
   for PROFILE_PATH in $(ls "$ALL_PROFILES"/*."$GROUP.$OFFSET"); do
      # only concatenate files with non-zero data 
      SIZE="$(stat --printf="%s" "$PROFILE_PATH")"
      if [ $SIZE -gt 0 ]; then 
          cat "$PROFILE_PATH" >> "$ANALYSIS_BUFFER_PATH"
          echo -n "," >> "$ANALYSIS_BUFFER_PATH"
          NEED_TRIM=1
      fi
   done

   if [ $NEED_TRIM -ne 0 ]; then 
      # strip last ','
      truncate -s -1 "$ANALYSIS_BUFFER_PATH"
   fi
   echo "]" >> "$ANALYSIS_BUFFER_PATH"

   # sanity check -- needs to be JSON 
   cat "$ANALYSIS_BUFFER_PATH" | jq >/dev/null 2>&1
   if [ $? -ne 0 ]; then 
      echo >&2 "Resulting analysis buffer $ANALYSIS_BUFFER_PATH is not JSON"
      exit 1
   fi

   # analyze this batch
   if ! [ -f "$ANALYSIS_PATH" ]; then 
      echo "Analyze batch $GROUP.$OFFSET"
      cat "$ANALYSIS_BUFFER_PATH" | "$ANALYSIS_TOOL" > "$ANALYSIS_PATH"
      if [ $? -ne 0 ]; then 
         echo "Failed to analyze $ANALYSIS_BUFFER_PATH"
         exit 1
      fi

      rm "$ANALYSIS_BUFFER_PATH"
   fi

   return 0
}


# run as a subcommand
if [ "$1" = "get_profile_data" ]; then 
   ROW="$2"
   SUFFIX="$3"
   get_profile_data "$ROW" "$SUFFIX"

   exit $?
fi

# run as subcommand 
if [ "$1" = "process_profiles" ]; then 
   ALL_ZONEFILES="$2"
   GROUP="$3"
   OFFSET="$4"

   process_profiles "$ALL_ZONEFILES" "$GROUP" "$OFFSET"
   exit $?
fi

mkdir -p "$ALL_PROFILES"
mkdir -p "$ALL_ANALYSIS"

# loop to run multiple crawls of the profiles in parallel 
run_batches() {
   ZONEFILES_PATH="$1"
   GROUP="$2"
   OFFSET="$3"
   NUM_BATCHES="$4"

   for i in $(seq 1 $NUM_BATCHES); do 
      dash "$THIS_COMMAND" process_profiles "$ZONEFILES_PATH" "$GROUP" "$OFFSET" &
   done

   for i in $(seq 1 $NUM_BATCHES); do
      wait %${i}
   done
}


BATCH_SIZE=50
NUM_CORES=4
COUNT_ONCHAIN="$(sqlite3 "$DB_PATH" 'select count(*) from name_records where value_hash is not null')"
COUNT_OFFCHAIN="$(sqlite3 "$OFFCHAIN_DB_PATH" 'select count(*) from subdomain_records')"
OFFSET=0

# handle off-chain names 
while [[ "$OFFSET" -lt "$COUNT_OFFCHAIN" ]]; do
   for i in $(seq 1 $NUM_CORES); do
       sqlite3 "$OFFCHAIN_DB_PATH" "select fully_qualified_subdomain,owner,zonefile_hash from subdomain_records where zonefile_hash is not null order by zonefile_hash limit $BATCH_SIZE offset $OFFSET" > "$ALL_ZONEFILES.$i"

       dash "$THIS_COMMAND" process_profiles "$ALL_ZONEFILES.$i" "offchain" "$OFFSET" &
       
       OFFSET="$((OFFSET + $BATCH_SIZE))"
   done

   for i in $(seq 1 $NUM_CORES); do
      wait %${i}
   done
done

# handle on-chain names
OFFSET=0
while [[ "$OFFSET" -lt "$COUNT_ONCHAIN" ]]; do
   for i in $(seq 1 $NUM_CORES); do
       sqlite3 "$DB_PATH" "select name,address,value_hash from name_records where value_hash is not null order by value_hash limit $BATCH_SIZE offset $OFFSET" > "$ALL_ZONEFILES.$i"

       dash "$THIS_COMMAND" process_profiles "$ALL_ZONEFILES.$i" "onchain" "$OFFSET" &
       
       OFFSET="$((OFFSET + $BATCH_SIZE))"
   done

   for i in $(seq 1 $NUM_CORES); do
      wait %${i}
   done
done

exit 0

