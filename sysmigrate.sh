#!/bin/bash -e

RUNTIME_DIR="$SYSMIGRATE_PREFIX/usr/local/var/lib/sysmigrate"
CONFIG_DIR="$SYSMIGRATE_PREFIX/usr/local/etc/sysmigrate"

MIGRATIONS_DIR="$CONFIG_DIR/migrations"
TRACKED_FILES_PATH="$RUNTIME_DIR/tracked-files"
MIRROR_DIR="$RUNTIME_DIR/mirror"
PERFORMED_MIGRATIONS_DIR="$RUNTIME_DIR/performed-migrations"

GIT=(git -C "$MIRROR_DIR")

print_help() {
  echo "Reproducible migrations for GNU/Linux systems"
  echo ""
  echo "USAGE:"
  echo "    $0 [SUBCOMMAND]"
  echo ""
  echo "SUBCOMMANDS:"
  echo "    run        Runs all available migrations"
  echo "    reset      Resets all state (performed migrations, mirror, list of tracked files)"
  echo "    help       Prints help information"
}

print_status() {
  echo "$(tput bold)==> $1...$(tput sgr0)"
}

perform_migration() {
  local migration="$1"
  local patch="$MIGRATIONS_DIR/$migration/migration.patch"
  local script="$MIGRATIONS_DIR/$migration/migration.sh"
  local files_dir="$MIGRATIONS_DIR/$migration/files"

  if [ -f "$patch" ]
  then
    ${GIT[@]} apply $patch
    ${GIT[@]} add --all
    ${GIT[@]} commit -m "Apply patch for migration $migration"
  fi

  if [ -d "$files_dir" ]
  then
    cp -R -- "$files_dir/." "$MIRROR_DIR/"
    ${GIT[@]} add --all
    ${GIT[@]} commit -m "Add files for migration $migration"
  fi

  if [ -d "$files_dir" ] || [ -f "$patch" ]
  then
    while IFS= read -r -d '' filename
    do
      rm -- "$SYSMIGRATE_PREFIX/$filename"
    done < $TRACKED_FILES_PATH

    ${GIT[@]} ls-files -z > $TRACKED_FILES_PATH

    while IFS= read -r -d '' filename
    do
      mkdir -p "$(dirname "$SYSMIGRATE_PREFIX/$filename")"
      cp -- "$MIRROR_DIR/$filename" "$SYSMIGRATE_PREFIX/$filename"
    done < $TRACKED_FILES_PATH
  fi
  
  if [ -f "$script" ]
  then
    bash $script
  fi
}

perform_migrations() {
  run_checks

  trap cleanup EXIT

  find "$MIGRATIONS_DIR" -type d -maxdepth 1 -print0 | while IFS= read -r -d '' filename
  do
    local migration=$(basename "$filename")

    print_status "Performing migration $migration"

    if [ -f "$PERFORMED_MIGRATIONS_DIR/$migration" ]
    then
      echo "Migration already performed. Skipping."
      continue
    fi

    perform_migration "$migration"

    touch "$PERFORMED_MIGRATIONS_DIR/$migration"
  done
}

reset() {
  echo "Are you sure you want to reset all state?"
  printf "type y or yes to confirm> "
  read answer

  if [[ "$answer" == "y" ]] || [[ "$answer" == "yes" ]]
  then
    print_status "Removing state"
    rm -rf "$RUNTIME_DIR"
  fi
}

run_checks() {
  mkdir -p "$RUNTIME_DIR"
  mkdir -p "$MIRROR_DIR"
  mkdir -p "$MIGRATIONS_DIR"
  mkdir -p "$PERFORMED_MIGRATIONS_DIR"

  if [ ! -f "$TRACKED_FILES_PATH" ]
  then
    touch "$TRACKED_FILES_PATH"
  fi

  if [ ! -d "$MIRROR_DIR/.git" ]
  then
    print_status "Initializing mirror git instance"

    ${GIT[@]} init
    ${GIT[@]} config user.name "$USER"
    ${GIT[@]} config user.email "$USER@$HOSTNAME"
    ${GIT[@]} config commit.gpgsign "false"
    ${GIT[@]} commit --allow-empty -m "Initial commit"
  fi
}

cleanup() {
  ${GIT[@]} clean -xfd > /dev/null
  ${GIT[@]} reset --hard > /dev/null
}

if [ $# -lt 1 ]
then
  print_help
  exit 2
fi

case "$1" in
  run)
    perform_migrations
    ;;
  help)
    print_help
    ;;
  reset)
    reset
    ;;
  *)
    echo "Unknown subcommand $1."
    echo "Run $0 help to list available commands."
    exit 2
esac
