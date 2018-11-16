#!/bin/bash

function usage() {
  echo "
Usage wync [ options ] dir1|file1 [dir2|file2] [ ... ] -- args
Options:

  -s|--size         The maximum size to wath files (-1 no limit, default).
  -a|--addr         Server address to use.
  -e|--exclude      Files to exclude.
  -l|--log          Log file (default to /tmp/wync_log).
  -f|--filexclude   A file with one line per file to exclude in syncing
                    like in a .wyncignore file but all for all wathced directories.
  -o|--once         Just sync once, no watching of files.
  -v|--verbose      Verbose output.
  -d|--dry-run      Just output commands, not actually sync.

  Size is specified as the find command would understand.
  If a .wyncignore file is found in any watched directory or subdirectory it will
  be read and all files inside it (one per line) will be ignored from syncing.
  If a .wyncdirignore file is found in any watched directory or subdirectory it
  will be completely ignored from syncing.
  -- is used to pass more arguments to rsync.
"
}

size="-1"
addr=""
args=""
once=0
verbose=0
dry_run=0
log_file="stdout"
# exclusion that are always ignored, used for all watched files/dirs
static_excludes=()
# dynamically constructed exclusion list, used for all watched files/dirs
excludes=()
# same but in rsync prepared exclusion string
rsync_excludes=""
# dynamically constructed exclusion list on a per watched files/dirs basis
file_excludes=()
# same but in rsync prepared exclusion string, used for the current file
rsync_file_excludes=""
# files to watch
files=()
# r: recursive, z: compression, P: progress, c: no checksum, v: verbose
rsync_opts="-rzcvP --delete-before"

syncer=$(which rsync)
watcher=$(which inotifywait)
syncing=0

while (( "$#" )); do
  case "$1" in
    -s|--size)
      size=$2
      shift 2
      ;;
    -a|--addr)
      addr=$2
      shift 2
      ;;
    -e|--exclude)
      static_excludes+=($2)
      shift 2
      ;;
    -l|--log)
      if [[ "$2" == "-" ]]; then
        log_file="stdout"
      else
        log_file=$2
      fi
      shift 2
      ;;
    -f|--filexclude)
      for excl in $(cat $(readlink -f $2)); do
        static_excludes+=( $excl )
      done
      shift 2
      ;;
    -o|--once)
      once=1
      shift
      ;;
    -v|--verbose)
      verbose=1
      shift
      ;;
    -d|--dry-run)
      dry_run=1
      shift
      ;;
    --) # end argument parsing
      shift
      args=$@
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      usage
      exit 1
      ;;
    *) # preserve positional arguments
      files+=("$(readlink -f $1)")
      shift
      ;;
  esac
done

if [[ "${#files[@]}" == "" ]]; then
  echo "You must specify files to watch!"
  usage
  exit 2
elif [[ "$addr" == "" ]]; then
  echo "You must specify an address to sync against!"
  usage
  exit 3
fi

function setup_logfile() {
  if [[ "${log_file^^}" != "STDOUT" ]]; then
    local incr=1
    if [[ -f "$log_file" ]]; then
      while [[ -f "${log_file}_${incr}" ]]; do
        incr=$(( $incr + 1 ))
      done
      log_file="${log_file}_${incr}"
    fi
    static_excludes+=( "$log_file" )
  fi
}

function reset_excludes() {
  excludes=("${static_excludes[@]}")
  rsync_excludes=""
}

function exclude_size() {
  local size=$1; shift
  local f=$1; shift
  local excl file prunes=""
  for excl in "${excludes[@]}"; do
    prunes="$prunes -name $excl -prune -o"
  done
  for file in $(find "$f" $prunes -type f -size "$size" 2>/dev/null); do
    excludes+=( $(readlink -f "$file") )
  done
}

function setup_filter(){
  reset_excludes
  local file excl
  for file in "${files[@]}"; do
    if [[ "$size" != "-1" ]]; then
      exclude_size "$size" "$files"
    fi
  done
  # setup the rsync exclude string
  for excl in "${excludes[@]}"; do
    # get the name and add to the list
    rsync_excludes="$rsync_excludes --exclude=$(basename $excl)"
  done
}

function construct_file_excludes() {
  local file=$1; shift
  local ignore excl dir name
  rsync_file_excludes=""
  # wyncignore files
  for ignore in $(find "$file" -iname ".wync*" -type f 2>/dev/null); do
    if [[ "$ignore" == *".wyncignore" ]]; then
      for excl in $(cat "$ignore"); do
        rsync_file_excludes+="--exclude=$excl "
      done
    else
      dir=$(dirname "$ignore")
      name=$(basename "$dir")
      rsync_file_excludes+="--exclude=$name "
    fi
  done
}

function sync(){
  local local_file=$1; shift
  local remote_file=$1; shift
  echo -e "Syncing \"$local_file\"..."
  construct_file_excludes "$local_file"
  if [[ "$verbose" -gt 0 ]]; then
    echo ""
    echo " ${syncer} $rsync_opts --exclude=\".*\" $rsync_excludes $rsync_file_excludes $args $local_file $remote_file"
  fi
  if [[ "$dry_run" -eq 0 ]]; then
    if [[ "${log_file^^}" == "STDOUT" ]]; then
      ${syncer} $rsync_opts --exclude='.*' $rsync_excludes $rsync_file_excludes $args $local_file $remote_file
    else
      ${syncer} $rsync_opts --exclude='.*' $rsync_excludes $rsync_file_excludes $args $local_file $remote_file &>"$log_file"
    fi
   fi
  echo " done"

  if [[ "$?" -ne 0 ]]; then
    echo ""
    echo "Could not perform sync"
    exit 4
  fi
}

echo "Logging to $log_file"

setup_logfile
setup_filter
for file in "${files[@]}"; do
  sync "$file" "$addr"
done

if [[ "$once" -eq 1 ]]; then
  exit 0
fi

${watcher} --exclude "\(\.\*.git\)" -mr --format '%w %f %:e' \
  -e create -e close_write -e delete ${files[@]} \
| while read dir file event; do
  # avoid editor extra files
  if [[ -f "$dir/$file" ]]; then
    if [[ "$verbose" -gt 0 ]]; then
      echo "notify: dir $dir file $file event $event"
    fi
    if [[ "$event" != "CREATE:ISDIR" && "$event" != "DELETE:ISDIR" ]]; then
      if [[ ! "${excludes[@]}" =~ "$(readlink -f $file)" && \
            ! "${excludes[@]}" =~ "$file" ]]; then
        if [[ "$syncing" -eq 0 ]]; then
          # find the matching watched file,
          # if the prefix from dir (who has triggered the event)
          # and a watched file is common, then it was that file
          for watched_file in "${files[@]}"; do
            if [[ "${dir#$watched_file}" == "$dir" ]]; then
              continue
            fi
            prefix="${dir#$watched_file}"
            base="$(basename $watched_file)"
            if [[ "$prefix" != "" ]]; then
              if [[ "$verbose" -gt 0 ]]; then
                echo "send $dir/$file -> $addr/$base/$prefix"
              fi
              syncing=1
              setup_filter
              sync "$dir/$file" "$addr/$base/$prefix"
              syncing=0
            fi
          done
        fi
      else
        echo "Ignoring \"$file\""
      fi
    fi
  fi
done
