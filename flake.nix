{
  description = "Local ESP-IDF dev shell for flashing Chroninkle/Followup (not committed to the project)";

  inputs.esp-dev.url = "github:mirrexagon/nixpkgs-esp-dev";

  outputs = { self, esp-dev }: {
    devShells.x86_64-linux.default = esp-dev.devShells.x86_64-linux.esp-idf-full;
  };
}
