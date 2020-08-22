{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      with (import ./lib/directory.nix { inherit pkgs; });
      with (import ./lib/docker.nix { inherit pkgs; });
      let
        kernels = pkgs.callPackag ./kernels { };
        kernelsString = pkgs.lib.concatMapStringsSep ":" (k: "${k.spec}");
        python3 = pkgs.python3Packages;
        defaultDirectory = "${python3.jupyterlab}/share/jupyter/lab";
        defaultKernels = [ (kernels.iPythonWith { }) ];
        defaultExtraPackages = p: [ ];
        defaultExtraInputsFrom = p: [ ];
        jupyterlabWith =
          { directory ? defaultDirectory
          , kernels ? defaultKernels
          , extraPackages ? defaultExtraPackages
          , extraInputsFrom ? defaultExtraInputsFrom
          , extraJupyterPath ? _: ""
          }:
          let
            # PYTHONPATH setup for JupyterLab
            pythonPath = python3.makePythonPath [
              python3.ipykernel
              python3.jupyter_contrib_core
              python3.jupyter_nbextensions_configurator
              python3.tornado
            ];

            # JupyterLab executable wrapped with suitable environment variables.
            jupyterlab = python3.toPythonModule (
              python3.jupyterlab.overridePythonAttrs (oldAttrs: {
                makeWrapperArgs = [
                  "--set JUPYTERLAB_DIR ${directory}"
                  "--set JUPYTER_PATH ${extraJupyterPath pkgs}:${kernelsString kernels}"
                  "--set PYTHONPATH ${extraJupyterPath pkgs}:${pythonPath}"
                ];
              })
            );

            # Shell with the appropriate JupyterLab, launching it at startup.
            env = pkgs.mkShell {
              name = "jupyterlab-shell";
              inputsFrom = extraInputsFrom pkgs;
              buildInputs =
                [ jupyterlab generateDirectory generateLockFile pkgs.nodejs ] ++
                (map (k: k.runtimePackages) kernels) ++
                (extraPackages pkgs);
              shellHook = ''
                export JUPYTER_PATH=${kernelsString kernels}
                export JUPYTERLAB=${jupyterlab}
              '';
            };
          in
          jupyterlab.override (oldAttrs: {
            passthru = oldAttrs.passthru or { } // { inherit env; };
          });
      in
      {
        inherit
          jupyterlabWith
          kernels
          mkBuildExtension
          mkDirectoryWith
          mkDirectoryFromLockFile
          mkDockerImage;
      }
    );
}
