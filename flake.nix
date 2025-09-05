# ./flake.nix
{
  description = "Jupyter environment with CUDA, Ollama, and uv2nix.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      uv2nix,
      pyproject-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        inherit (nixpkgs.lib) composeManyExtensions;

        cudaPkgs = with pkgs; [
          cudatoolkit
          linuxPackages.nvidia_x11
        ];

        python = pkgs.python312;
        workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
        overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
        pyprojectOverrides = final: prev: {
          pypika = prev.pypika.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              final.setuptools
              final.wheel
            ];
          });
          langdetect = prev.langdetect.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
              final.setuptools
              final.wheel
            ];
          });
        };
        pythonSet =
          (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
            (composeManyExtensions [
              overlay
              pyprojectOverrides
            ]);
        jupyterEnv = pythonSet.mkVirtualEnv "gemini-rag-env" workspace.deps.default;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            jupyterEnv
            pkgs.uv
            pkgs.zsh
            pkgs.ollama-cuda
          ]
          ++ cudaPkgs;
          shellHook = ''
            export CUDA_PATH=${pkgs.cudatoolkit}
            export LD_LIBRARY_PATH=${pkgs.linuxPackages.nvidia_x11}/lib
            unset PYTHONPATH
            echo "CUDA + Jupyter RAG Environment Ready"
            if [ -z "$ZSH_VERSION" ]; then
              exec zsh
            fi
          '';
        };
      }
    );
}
