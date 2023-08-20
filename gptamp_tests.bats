#!/usr/bin/env bats

@test "-h switch" {
  run ./gptamp.sh -h
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Usage: ./gptamp.sh [" ]]
}

@test "-a switch with verbose" {
  run ./gptamp.sh -a -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Options chosen: Install Apache" ]]
}

@test "-f switch with verbose" {
  run ./gptamp.sh -f -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Options chosen: Install Apache with FPM" ]]
}

@test "-m switch with default version and verbose" {
  run ./gptamp.sh -m -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Assuming default MOODLE_VERSION is "3.10" for this example.
  [[ "$output" =~ "Options chosen: Install Moodle version 3.10" ]]
}

@test "-m switch with specific version and verbose" {
  run ./gptamp.sh -m 3.11 -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Options chosen: Install Moodle version 3.11" ]]
}

@test "-n switch with verbose" {
  run ./gptamp.sh -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Options chosen: DRY RUN" ]]
}

@test "-p switch with default version and verbose" {
  run ./gptamp.sh -p -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Assuming default PHP_VERSION is "7.4" for this example.
  [[ "$output" =~ "Options chosen: Install PHP version 7.4" ]]
}

@test "-p switch with specific version and verbose" {
  run ./gptamp.sh -p 8.0 -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Options chosen: Install PHP version 8.0" ]]
}

@test "-v switch alone" {
  run ./gptamp.sh -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # This might just echo an empty "Options chosen:" since no other option is selected. Adjust as needed.
  [[ "$output" =~ "Options chosen:" ]]
}
