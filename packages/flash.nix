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

        flash() {
          declare -a matches
          readarray -t matches < <(list_keyboards)

          # Assert we found exactly one keyboard
          count="''${#matches[@]}"
          if [[ "$count" -lt 1 ]]; then
            # No matches. Exit
            echo "Error: No Glove80 connected!"
            return 1
          elif [[ "$count" -gt 1 ]]; then
            # Multiple matches. Print them and exit
            echo "Error: $count Glove80s connected. Expected 1!"
            for i in "''${!matches[@]}"; do
              kb="''${matches[$i]}"
              # Print the relevant lines from INFO_UF2
              echo "$((i + 1)). $kb"
              grep --no-filename --color=never Glove80 "$kb"/INFO_UF2.TXT | indent
            done
            return 1
          fi

          # We have a winner!
          kb="''${matches[0]}"
          echo "Flashing keyboard:"
          echo "$kb"
          indent < "$kb"/INFO_UF2.TXT

          # Ask before flashing...
          if gum confirm "Are you sure?" \
              --default="yes" \
              --affirmative="Flash" \
              --negative="Cancel"
          then
            # Flash by copying the firmware package
            gum spin --title "Flashing firmware..." \
              -- cp -Tfr "${config.packages.firmware}" "$kb" \
              && echo "Firmaware flashed!" \
              || echo "Error flashing firmware!"
          else
            echo "Cancelled"
          fi

          echo # blankline
        }

        # Run the script
        flash
        while
          gum confirm \
            --default="no" \
            --affirmative="Run again" \
            --negative="Quit" \
            "Flash another keyboard?"
        do
          echo # blankline
          echo "Running again"
          flash
        done
      '';
    };
  };
}
