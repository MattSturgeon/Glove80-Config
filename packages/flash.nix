{
  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: {
    # Builds the firmware and copies it to the plugged-in keyboard half
    packages.flash = pkgs.writeShellApplication {
      name = "flash";
      runtimeInputs = [
        # Use Charm Gum for fancy interactivity
        pkgs.gum
      ];
      text = ''
        set +e

        # Disable -u because empty arrays are treated as "unbound"
        set +u

        # Enable nullglob so that non-matching globs have no output
        shopt -s nullglob

        # Style
        export GUM_SPIN_SPINNER="minidot"

        # Indent piped input 4 spaces
        indent() {
          sed -e 's/^/    /'
        }

        # Prints a list of connected glove80s
        list_keyboards() {
          # Platform specific disk candidates
          declare -a disks
          if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            # Linux/GNU
            # - /run/media/<user>/<disk>
            disks=(/run/media/"$(whoami)"/GLV80*)
          elif [[ "$OSTYPE" == "darwin"* ]]; then
            # Mac OSX
            # - /Volumes/<disk>
            disks=(/Volumes/GLV80*)
          elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
            # Cygwin or Msys2
            # - /<drive letter>
            disks=(/?)
          elif grep -sq Microsoft /proc/version; then
            # WSL
            # - /mnt/<drive letter>
            disks=(/mnt/?)
          else
            echo "Error: Unable to detect platform!" >&2
            echo "OSTYPE=$OSTYPE" >&2
            echo "/proc/version" >&2
            indent < /proc/version >&2
          fi

          # Print disks that have a matching INFO_UF2
          for disk in "''${disks[@]}"; do
            if (grep -sq Glove80 "$disk"/INFO_UF2.TXT); then
              echo "$disk"
            fi
          done
        }

        # Flash all keyboards found by `list_keyboards`
        flash_keyboards() {
          declare -a matches
          readarray -t matches < <(list_keyboards)
          count="''${#matches[@]}"

          # Print a summary of what `list_keyboards` has found
          echo "Found $count keyboards connected."
          for i in "''${!matches[@]}"; do
            kb="''${matches[$i]}"
            # Print the relevant lines from INFO_UF2
            echo "$((i + 1)). $kb"
            indent < "$kb"/INFO_UF2.TXT
          done
          echo # blankline

          for i in "''${!matches[@]}"; do
            flash_keyboard "$((i + 1))" "''${matches[$i]}"
          done
        }

        # Flash the given keyboard
        flash_keyboard() {
          i="$1"
          kb="$2"

          # Ask before flashing...
          if gum confirm "$i. $kb" \
              --default="yes" \
              --affirmative="Flash" \
              --negative="Cancel"
          then
            # Flash by copying the firmware package
            gum spin --title "Flashing $kb" \
              -- cp -Tfr "${config.packages.firmware}" "$kb" \
              && echo "$i. Flashed $kb" \
              || echo "$i. Error flashing $kb!"
          else
            echo "$i. Skipped $kb"
          fi
        }

        # Run the script
        flash_keyboards
        while
          gum confirm "Done" \
            --default="no" \
            --affirmative="Run again" \
            --negative="Quit"
        do
          echo # blankline
          echo "Running again"
          flash_keyboards
        done
      '';
    };
  };
}
