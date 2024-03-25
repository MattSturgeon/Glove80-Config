{
  inputs,
  lib,
  ...
}:
with builtins;
with lib; {
  perSystem = {
    config,
    pkgs,
    system,
    ...
  }: let
    inherit (inputs.poetry2nix.lib.mkPoetry2Nix {inherit pkgs;}) mkPoetryApplication;

    getKeymapFiles = dir:
      mapAttrsToList (name: _: dir + "/${name}") (filterAttrs (name: type: hasSuffix ".keymap" name && type != "directory") (readDir dir));

    # Nix can't import yaml, so use `yj` to convert to JSON 😢
    importYaml = file: let
      jsonFile = pkgs.runCommandNoCC "converted-yaml.json" {} ''
        ${getExe pkgs.yj} < "${file}" > "$out"
      '';
    in
      importJSON jsonFile;

    pkg = config.packages.keymap-drawer;
    exe = getExe pkg;

    parsedPkg = config.packages.keymap-drawer-parsed;

    # List of parsed keyboard configs, complete with various metadata
    parsedCfgs = mapAttrsToList (fname: type:
      assert hasSuffix ".keymap" fname;
      assert type != "directory"; rec {
        file = parsedPkg + "/${fname}";
        name = removeSuffix ".keymap" fname;
        data = importYaml file;
        layers = attrNames data.layers;
      }) (readDir parsedPkg);

    keymapFiles = getKeymapFiles ../config;
    configFile = ../config/keymap_drawer.yaml;
  in {
    packages = {
      keymap-drawer = mkPoetryApplication {
        projectDir = inputs.keymap-drawer;
        preferWheels = true;
        meta = {
          mainProgram = "keymap";
          homepage = "https://github.com/caksoylar/keymap-drawer";
        };
      };

      keymap-drawer-parsed = pkgs.symlinkJoin {
        name = "configs";
        paths = map (file: let
          name = removeSuffix ".keymap" (baseNameOf file);
        in
          pkgs.runCommandNoCC "${name}-parsed" {} ''
            echo "Parsing keymap for ${name}"
            mkdir -p "$out"
            ${exe} --config "${configFile}" \
              parse --zmk-keymap "${file}" \
              > "$out/${name}.yaml"
          '')
        keymapFiles;
      };

      keymap-drawer-svgs = pkgs.symlinkJoin {
        name = "keymap-drawer-svgs";
        paths =
          concatMap (
            {
              name,
              file,
              data,
              layers,
              ...
            }:
              [
                (pkgs.runCommandNoCC "${name}-all" {} ''
                  echo "Drawing all layers for ${name}"
                  mkdir -p "$out"
                  ${exe} --config "${configFile}" \
                    draw ${file}" \
                    > "$out/${name}.svg"
                '')
              ]
              ++ (map (layer:
                pkgs.runCommandNoCC "${name}-${layer}" {} ''
                  echo "Drawing ${layer} layer for ${name}"
                  mkdir -p "$out"
                  ${exe} --config "${configFile}" \
                    draw "${file}" \
                    --select-layers "${layer}" \
                    > "$out/${name}-${layer}.svg"
                '')
              layers)
          )
          parsedCfgs;
      };
    };
  };
}
