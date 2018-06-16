#!/bin/bash -e

RUNTIME_DIR="$SYSMIGRATE_PREFIX/var/lib/sysmigrate"
CONFIG_DIR="$SYSMIGRATE_PREFIX/etc/sysmigrate"

MIGRATIONS_DIR="$CONFIG_DIR/migrations"
TRACKED_FILES_PATH="$RUNTIME_DIR/tracked-files"
MIRROR_DIR="$RUNTIME_DIR/mirror"
PERFORMED_MIGRATIONS_DIR="$RUNTIME_DIR/performed-migrations"

GIT=(git -C "$MIRROR_DIR")

print_status() {
  echo "$(tput bold)==> $1...$(tput sgr0)"
}

perform_migration() {
  local migration="$1"
  local patch="$MIGRATIONS_DIR/$migration/migration.patch"
  local script="$MIGRATIONS_DIR/$migration/migration.sh"

  if [ -f "$patch" ]
  then
    ${GIT[@]} apply $patch
    ${GIT[@]} add --all
    ${GIT[@]} commit -m "Apply migration $migration"

    while read file
    do
      rm "$SYSMIGRATE_PREFIX/$file"
    done < $TRACKED_FILES_PATH

    ${GIT[@]} ls-files > $TRACKED_FILES_PATH

    while read file
    do
      mkdir -p "$(dirname "$SYSMIGRATE_PREFIX/$file")"
      cp "$MIRROR_DIR/$file" "$SYSMIGRATE_PREFIX/$file"
    done < $TRACKED_FILES_PATH
  fi
  
  if [ -f "$script" ]
  then
    bash $script
  fi
}

cleanup() {
  ${GIT[@]} clean -xfd > /dev/null
  ${GIT[@]} reset --hard > /dev/null
}

trap cleanup EXIT

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

for migration in $(ls -1 $MIGRATIONS_DIR)
do
  print_status "Performing migration $migration"

  if [ -f "$PERFORMED_MIGRATIONS_DIR/$migration" ]
  then
    echo "Migration already performed. Skipping."
    continue
  fi

  perform_migration "$migration"

  touch "$PERFORMED_MIGRATIONS_DIR/$migration"
done